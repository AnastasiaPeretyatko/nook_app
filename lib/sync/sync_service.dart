import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/api/sync_api.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/sync/merge.dart';
import 'package:todo_app/sync/payload.dart';

/// How a run ended.
///
/// Four answers rather than a bool, because the screen has to say different
/// things about them: "no connection" is a state to wait out, a refusal is
/// something to look at, and "there was nothing to do" is not worth mentioning
/// at all.
enum SyncOutcome {
  /// Everything went up and came down.
  done,

  /// Not attempted — no account, a run already going, or the last failure is
  /// still being waited out.
  skipped,

  /// The network was not there. The ordinary case, and not a fault.
  offline,

  /// The server was reachable and said no.
  failed,
}

/// Takes what the other devices did and sends what this one wrote.
///
/// Shaped after `AppNotifications`, and for the same reason: everything here
/// talks to something outside the app that is entitled to fail, and none of
/// those failures may reach the local database. A refused request is a row that
/// has not been sent **yet** — the local data is untouched, the mark stays on,
/// and the next attempt carries it.
///
/// ## The order, and why it is not negotiable
///
/// **Pull first, then push.** The server does not compare the time of an edit:
/// it takes whatever arrives last. A device that pushed a stale edit before
/// hearing about a newer one would overwrite the newer one for everybody. After
/// a pull, [pullAction] has already thrown away the stale local copy (or kept it
/// because it really is newer), so what is still marked "unsent" is safe to send.
///
/// ## What is in it so far
///
/// Tasks and their day marks, the diary (notes, moods, tags) and the cycle's
/// days. The groups return with their own stage; until then what the user
/// writes there stays marked as unsent, and nothing is lost.
///
/// ## Connectivity
///
/// There is none to ask about. A connectivity answer describes the *interface*,
/// not the internet, and says "connected" on a café Wi-Fi that resolves nothing.
/// The request is the question, and an [ApiException] is the answer.
class SyncService {
  SyncService({
    required this.dao,
    required this.tasksDao,
    required this.cycleDao,
    required SyncApi api,
    required String? Function() userId,
    bool Function()? syncDiary,
    bool Function()? syncCycle,
  }) // The lint wants `this._api`, and Dart forbids a private named parameter.
    // ignore: prefer_initializing_formals
    : _api = api,
       // ignore: prefer_initializing_formals
       _userId = userId,
       _syncDiary = syncDiary ?? (() => true),
       _syncCycle = syncCycle ?? (() => false);

  /// For the deletions waiting to be reported (one table holds them all).
  final DiaryDao dao;
  final TasksDao tasksDao;
  final CycleDao cycleDao;
  final SyncApi _api;

  /// Who is signed in, asked each run; null means nobody.
  final String? Function() _userId;

  /// Whether the notes take part in this run — asked each time, so the setting
  /// can change between runs. Off, the diary is neither sent nor read, and what
  /// was written meanwhile stays marked as unsent.
  final bool Function() _syncDiary;

  /// Whether the cycle's days take part — asked each time, like [_syncDiary].
  /// Off by default: it is health data, and the user opts in.
  final bool Function() _syncCycle;

  /// Set while a run is in flight, so a second trigger does not start one over
  /// the top of it — the same guard the habit timer uses for its ticker.
  bool _running = false;

  /// What a failed run waits before the next one is worth attempting.
  /// Doubles on each failure and resets the moment anything succeeds.
  Duration _backoff = Duration.zero;
  DateTime? _retryAfter;

  static const _firstBackoff = Duration(seconds: 5);
  static const _maxBackoff = Duration(minutes: 5);

  /// Enough for a server waking from sleep (a minute) plus the work itself. A
  /// request has its own timeout in [ApiClient]; this is the cap on the whole
  /// run, so that one that never ends cannot keep [_running] set until the app
  /// restarts — every later run, the button's too, would be turned away.
  static const _runLimit = Duration(minutes: 3);

  /// The server's clock is not the phone's, and two rows written in the same
  /// moment may be stamped out of order of their commit. Reading from a little
  /// before the watermark costs a few rows read twice; merging is harmless to
  /// repeat. Subtracted **once, at the start of a run** — inside the loop over
  /// pages the server's own `next` is used as it is, or a page of more than
  /// `limit` rows written in one moment would start from the same rows again.
  static const _overlap = Duration(seconds: 5);

  /// The server refuses more than this many rows of one kind in one request...
  static const _pushChunk = 500;

  /// ...and a body over 5 MB. A note may be a megabyte of text, so 500 of them
  /// would not fit; requests are cut by size as well, with room to spare.
  static const _pushBytes = 4 * 1024 * 1024;

  /// Whether a run is in flight right now.
  bool get isRunning => _running;

  /// The furthest point in the server's own clock this device has seen.
  ///
  /// Held in memory and handed in by the caller, so the service itself owns no
  /// storage. Null means "everything" — a first sync.
  DateTime? watermark;

  /// What went wrong last, as the server or the platform put it.
  ///
  /// Handed up to the status the same way [watermark] is handed down: the
  /// service owns no storage and no screen, it only knows the answer. Null once
  /// anything succeeds.
  String? lastError;

  /// Whether anything is waiting to be sent. Lets a run that was only set off by
  /// a local edit stay out of the way when the "edit" was the pull's own write.
  Future<bool> hasPending() async {
    if ((await tasksDao.pendingTasks()).isNotEmpty ||
        (await tasksDao.pendingLogs()).isNotEmpty ||
        (await _pendingGraves('tasks')).isNotEmpty) {
      return true;
    }
    if (_syncCycle() && (await cycleDao.pending()).isNotEmpty) return true;
    if (!_syncDiary()) return false;
    return (await dao.pendingEntries()).isNotEmpty ||
        (await dao.pendingMoods()).isNotEmpty ||
        (await dao.pendingTags()).isNotEmpty ||
        (await _pendingGraves('diary_entries')).isNotEmpty;
  }

  /// Runs one pull-and-push. Never throws.
  ///
  /// [force] skips the wait after a failure: the user pressed the button, or the
  /// network just came back, and either is a better reason to try than a timer.
  Future<SyncOutcome> sync({bool force = false}) async {
    final me = _userId();
    if (me == null) {
      lastError = 'Нет активной сессии — войдите в аккаунт заново';
      return SyncOutcome.skipped;
    }
    if (_running) return SyncOutcome.skipped;

    // A run that failed a moment ago will fail again; hammering a server that
    // is down is how an app gets rate-limited.
    final retryAfter = _retryAfter;
    if (!force && retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      return SyncOutcome.skipped;
    }

    _running = true;
    try {
      // shortcut: the limit cuts the wait, not the requests — a run that
      // outlives it keeps going in the background beside the next one. Fine,
      // since every write is idempotent; move it into the HTTP client if that
      // ever hurts.
      await Future<void>(() async {
        await _pull(me);
        await _push(me);
      }).timeout(_runLimit);
      _backoff = Duration.zero;
      _retryAfter = null;
      lastError = null;
      return SyncOutcome.done;
    } catch (error, stack) {
      _noteFailure(error, stack);
      return isOfflineError(error) ? SyncOutcome.offline : SyncOutcome.failed;
    } finally {
      _running = false;
    }
  }

  void _noteFailure(Object error, StackTrace stack) {
    lastError = error is ApiException
        ? (error.message ?? error.code ?? error.toString())
        : error.toString();
    _backoff = _backoff == Duration.zero
        ? _firstBackoff
        : Duration(
            seconds: (_backoff.inSeconds * 2).clamp(1, _maxBackoff.inSeconds),
          );
    _retryAfter = DateTime.now().add(_backoff);

    // Offline is the ordinary case, not a fault, and it must not fill the log.
    if (!isOfflineError(error)) {
      debugPrint('Sync failed: $error\n$stack');
    }
  }

  /// Whether the failure is "no connection" rather than "something is wrong".
  @visibleForTesting
  static bool isOfflineError(Object error) => error is ApiException
      ? error.isOffline
      : ApiException.isNetworkError(error);

  // ---------------------------------------------------------------------------
  // Down
  // ---------------------------------------------------------------------------

  Future<Set<String>> _pendingGraves(String table) async => {
    for (final grave in await dao.pendingTombstones())
      if (grave.sourceTable == table) grave.uid,
  };

  Future<void> _pull(String me) async {
    final diary = _syncDiary();
    final cycle = _syncCycle();
    // Deleted here, not yet reported: the overlap may well hand the row back,
    // and inserting it again would raise a task or a note the user threw away.
    final graves = await _pendingGraves('tasks');
    final entryGraves = diary
        ? await _pendingGraves('diary_entries')
        : <String>{};

    var since = watermark?.subtract(_overlap);
    DateTime? furthest;
    // Marks that came before their task. The two lists are cut into pages
    // independently, so a mark can land a page ahead of the task it belongs to.
    final early = <Map<String, dynamic>>[];
    // The labels of each note that was taken, by uid; the last copy wins. Applied
    // after the last page, for the same reason as above: a note can arrive a page
    // ahead of the mood or tag it names.
    final links = <String, ({List<String> moods, List<String> tags})>{};

    var first = true;
    while (true) {
      final page = await _firstCallRetried(
        first,
        () => _api.pull(
          since: since?.toUtc().toIso8601String(),
          include: {if (diary) 'diary', if (cycle) 'cycle'},
        ),
      );
      first = false;

      // Before the tasks: whether a group task may be edited is read off its
      // group's owner, and a group that is gone takes its tasks off the phone.
      await _applyGroups(page['groups']);

      if (diary) {
        // Catalogues before notes, so a note's labels have something to point at.
        for (final row in _rows(page['moods'])) {
          await _applyMood(row);
        }
        for (final row in _rows(page['tags'])) {
          await _applyTag(row);
        }
        for (final row in _rows(page['entries'])) {
          await _applyEntry(row, entryGraves, links);
        }
      }
      for (final row in _rows(page['tasks'])) {
        await _applyTask(row, graves);
      }
      for (final row in _rows(page['logs'])) {
        if (!await _applyLog(row, me, graves)) early.add(row);
      }

      if (cycle) {
        for (final row in _rows(page['cycle_days'])) {
          await _applyCycleDay(row);
        }
      }

      final next = DateTime.tryParse(page['next'] as String? ?? '');
      if (next != null) {
        since = next;
        furthest = next;
      }
      if (page['has_more'] != true || next == null) break;
    }

    // A mark still without its task now has nothing to attach to; if the task is
    // merely late, the mark comes down again whenever the server next hears of it.
    for (final row in early) {
      await _applyLog(row, me, graves);
    }
    for (final entry in links.entries) {
      await _applyLinks(entry.key, entry.value.moods, entry.value.tags);
    }

    // Moved only after everything above has landed, and never backwards: with
    // nothing new the server answers with the `since` it was given, which is the
    // watermark minus the overlap.
    if (furthest != null &&
        (watermark == null || furthest.isAfter(watermark!))) {
      watermark = furthest;
    }
  }

  /// The server lists every group this account is in, with its members, in
  /// every answer — whole, so that a group missing from it is how the phone
  /// learns it was left, removed from or deleted. An answer without the key is
  /// not "no groups" and leaves the mirror alone.
  Future<void> _applyGroups(Object? snapshot) async {
    if (snapshot is! Map<String, dynamic>) return;
    await tasksDao.replaceGroups(
      [for (final row in _rows(snapshot['groups'])) groupFromRow(row)],
      [for (final row in _rows(snapshot['members'])) memberFromRow(row)],
    );
  }

  /// A server that was asleep can take longer than one request is allowed to, and
  /// the first request of a run is the one that wakes it. Offline on the first
  /// try is therefore tried twice more before it counts; the run's own limit
  /// still bounds the whole.
  Future<T> _firstCallRetried<T>(bool first, Future<T> Function() call) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await call();
      } on ApiException catch (e) {
        if (!first || !e.isOffline || attempt >= 2) rethrow;
      }
    }
  }

  static Iterable<Map<String, dynamic>> _rows(Object? list) =>
      (list as List? ?? const []).cast<Map<String, dynamic>>();

  /// No path deletes a mood or a tag in the app, so a deleted one is never news.
  Future<void> _applyMood(Map<String, dynamic> row) async {
    final uid = uidOf(row);
    if (uid == null || isDeleted(row)) return;
    if (await dao.moodByUid(uid) == null) {
      await dao.insertRemoteMood(uid, moodFromRow(row));
    } else {
      await dao.applyRemoteMood(uid, moodFromRow(row));
    }
  }

  Future<void> _applyTag(Map<String, dynamic> row) async {
    final uid = uidOf(row);
    if (uid == null || isDeleted(row)) return;
    if (await dao.tagByUid(uid) == null) {
      await dao.insertRemoteTag(uid, tagFromRow(row));
    } else {
      await dao.applyRemoteTag(uid, tagFromRow(row));
    }
  }

  Future<void> _applyEntry(
    Map<String, dynamic> row,
    Set<String> graves,
    Map<String, ({List<String> moods, List<String> tags})> links,
  ) async {
    final uid = uidOf(row);
    if (uid == null || graves.contains(uid)) return;

    final local = await dao.entryByUid(uid);
    final action = pullAction(
      remoteDeleted: isDeleted(row),
      localUpdatedAt: local?.updatedAt,
      localDirty: local?.dirty ?? false,
      remoteUpdatedAt: clientUpdatedAt(row) ?? DateTime.now(),
      localUid: local?.uid ?? '',
      remoteUid: uid,
    );

    switch (action) {
      case PullAction.skip:
      case PullAction.keepLocal:
        return;
      case PullAction.delete:
        await dao.deleteEntryByUid(uid);
        links.remove(uid);
      case PullAction.insert:
        await dao.insertRemoteEntry(uid, entryFromRow(row));
        links[uid] = _labelsOf(row);
      case PullAction.overwrite:
        await dao.applyRemoteEntry(uid, entryFromRow(row));
        links[uid] = _labelsOf(row);
    }
  }

  static ({List<String> moods, List<String> tags}) _labelsOf(
    Map<String, dynamic> row,
  ) => (
    moods: [...?(row['mood_ids'] as List?)?.cast<String>()],
    tags: [...?(row['tag_ids'] as List?)?.cast<String>()],
  );

  /// Sets a note's labels to the server's. A label this device does not have is
  /// left out, and the note is **not** marked as changed — sending the same set
  /// straight back would make two phones trade it for ever (see
  /// [DiaryDao.applyRemoteEntryMoods]).
  Future<void> _applyLinks(
    String entryUid,
    List<String> moodUids,
    List<String> tagUids,
  ) async {
    final entry = await dao.entryByUid(entryUid);
    if (entry == null) return;
    await dao.applyRemoteEntryMoods(entry.id, [
      for (final uid in moodUids) ?(await dao.moodByUid(uid))?.id,
    ]);
    await dao.applyRemoteEntryTags(entry.id, [
      for (final uid in tagUids) ?(await dao.tagByUid(uid))?.id,
    ]);
  }

  Future<void> _applyTask(Map<String, dynamic> row, Set<String> graves) async {
    final uid = uidOf(row);
    if (uid == null || graves.contains(uid)) return;

    final local = await tasksDao.taskByUid(uid);
    final action = pullAction(
      remoteDeleted: isDeleted(row),
      localUpdatedAt: local?.updatedAt,
      localDirty: local?.dirty ?? false,
      remoteUpdatedAt: clientUpdatedAt(row) ?? DateTime.now(),
      localUid: local?.uid ?? '',
      remoteUid: uid,
    );

    switch (action) {
      case PullAction.skip:
      case PullAction.keepLocal:
        return;
      case PullAction.delete:
        await tasksDao.deleteTaskByUid(uid);
      case PullAction.insert:
        await tasksDao.insertRemoteTask(uid, await _withParent(row));
      case PullAction.overwrite:
        await tasksDao.applyRemoteTask(uid, await _withParent(row));
    }
  }

  /// The row as a companion, with its parent translated from a uid into the
  /// local id this device knows the parent by.
  ///
  /// Written explicitly as `Value(null)` when there is no parent, never left
  /// absent: an overwrite has to be able to *un*-parent a task, and an absent
  /// value would leave the old link in place.
  ///
  /// A parent this device has not been sent yet leaves the task at the top level
  /// rather than not arriving at all. Self-healing, because the rows come
  /// ordered by the server's clock and a parent is created before its child, so
  /// the ordinary case never hits this; and if it does, the next edit to the
  /// child puts it back where it belongs.
  Future<TasksCompanion> _withParent(Map<String, dynamic> row) async {
    final task = taskFromRow(row);
    final parentUid = row['parent_id'] as String?;
    if (parentUid == null) return task.copyWith(parentId: const Value(null));
    final parent = await tasksDao.taskByUid(parentUid);
    return task.copyWith(parentId: Value(parent?.id));
  }

  /// Takes one day mark. False when its task is not here (yet).
  ///
  /// `remoteDeleted` is always false, and that is a fact about the data rather
  /// than a shortcut: nothing deletes a single mark. A mark's disappearance
  /// arrives as its task's deletion, which [_applyTask] has acted on.
  Future<bool> _applyLog(
    Map<String, dynamic> row,
    String me,
    Set<String> graves,
  ) async {
    final taskUid = taskUidOf(row);
    if (taskUid == null) return true;
    // The task is being deleted here: its marks go with it.
    if (graves.contains(taskUid)) return true;

    final task = await tasksDao.taskByUid(taskUid);
    if (task == null) return false;

    final incoming = logFromRow(row);

    // Another member's mark on a group task. Theirs alone to change, so the
    // server's copy is simply taken — no merge, and never into `task_logs`,
    // which holds this account's one answer per day.
    final author = markAuthorOf(row);
    if (author != null && author != me) {
      await tasksDao.applyGroupMark(
        taskId: task.id,
        userUid: author,
        date: incoming.date.value,
        completed: incoming.completed.value,
      );
      return true;
    }
    final day = incoming.date.value;
    final local = await tasksDao.getLogForDate(task.id, day);

    // The identity handed to the tie-break is the natural key, and it is the
    // **same string on both sides** — which for a log is right rather than a
    // degenerate case. A tie can only matter while this copy is still unsent,
    // and "keep mine for now" is settled by the push that follows: once a row
    // is clean, anything arriving overwrites it without consulting a clock.
    final identity = '$taskUid|${_calendarDay(day)}';
    final action = pullAction(
      remoteDeleted: false,
      localUpdatedAt: local?.updatedAt,
      localDirty: local?.dirty ?? false,
      remoteUpdatedAt: clientUpdatedAt(row) ?? DateTime.now(),
      localUid: identity,
      remoteUid: identity,
    );

    switch (action) {
      case PullAction.skip:
      case PullAction.keepLocal:
      case PullAction.delete:
        break;
      // One statement covers both: the upsert resolves on the pair, so a mark
      // this device already has is updated and a new one is inserted.
      case PullAction.insert:
      case PullAction.overwrite:
        await tasksDao.applyRemoteLog(task.id, incoming);
    }
    return true;
  }

  /// Takes one cycle day. Nothing is ever deleted: a mark taken back arrives as
  /// an empty day, which is applied like any other.
  Future<void> _applyCycleDay(Map<String, dynamic> row) async {
    final incoming = cycleDayFromRow(row);
    final day = incoming.date.value;
    final local = await cycleDao.getDay(day);

    // The identity is the same string on both sides, as for a task log: a tie
    // can only matter while this copy is unsent, and the push that follows
    // settles it.
    final identity = _calendarDay(day);
    final action = pullAction(
      remoteDeleted: false,
      localUpdatedAt: local?.updatedAt,
      localDirty: local?.dirty ?? false,
      remoteUpdatedAt: clientUpdatedAt(row) ?? DateTime.now(),
      localUid: identity,
      remoteUid: identity,
    );

    switch (action) {
      case PullAction.skip:
      case PullAction.keepLocal:
      case PullAction.delete:
        return;
      case PullAction.insert:
      case PullAction.overwrite:
        await cycleDao.applyRemote(incoming);
    }
  }

  /// `YYYY-MM-DD`, only ever used to spell a log's identity for the tie-break.
  static String _calendarDay(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}'
      '-${day.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Up
  // ---------------------------------------------------------------------------

  Future<void> _push(String me) async {
    final diary = _syncDiary();
    final rows = <_Row>[];

    // The order the server writes in, and so the order of sending: labels before
    // the notes that name them, tasks before the marks that point at them.
    if (diary) {
      for (final mood in await dao.pendingMoods()) {
        final uid = mood.uid;
        if (uid != null) rows.add(_Row(_Kind.moods, moodToRow(mood), uid: uid));
      }
      for (final tag in await dao.pendingTags()) {
        final uid = tag.uid;
        if (uid != null) rows.add(_Row(_Kind.tags, tagToRow(tag), uid: uid));
      }
      for (final entry in await dao.pendingEntries()) {
        final uid = entry.uid;
        if (uid == null) continue;
        // The note owns its whole set of labels and sends all of it; an empty
        // list is how the server learns that the last one was taken off.
        rows.add(
          _Row(
            _Kind.entries,
            {
              ...entryToRow(entry),
              'mood_ids': await dao.moodUidsForEntry(entry.id),
              'tag_ids': await dao.tagUidsForEntry(entry.id),
            },
            uid: uid,
            at: entry.updatedAt,
          ),
        );
      }
    }

    final uidsById = await tasksDao.taskUidsById();
    // Parents need no ordering here: the server checks the link at the end of
    // the transaction, so a child may precede its parent in one request.
    for (final task in await tasksDao.pendingTasks()) {
      final uid = task.uid;
      // Nothing to address the row by, so skipping beats inventing — but not in
      // silence. This should be impossible: v14 mints a uid for every task on
      // the device and v15 re-checks unconditionally.
      if (uid == null) {
        debugPrint('Sync: task ${task.id} has no uid, not sent');
        continue;
      }
      // A group task goes up only from its author or the group's owner, the
      // two the server lets edit it. Anyone else's copy is only a mirror.
      if (task.groupUid != null && !await tasksDao.canEditTask(task, me)) {
        continue;
      }
      rows.add(
        _Row(
          _Kind.tasks,
          taskToRow(task, parentUid: uidsById[task.parentId]),
          uid: uid,
          at: task.updatedAt,
        ),
      );
    }
    // A mark whose task carries no uid is skipped rather than dropped: it keeps
    // its mark and goes up once the task has an identity.
    for (final log in await tasksDao.pendingLogs()) {
      final uid = uidsById[log.taskId];
      if (uid != null) {
        rows.add(_Row(_Kind.logs, logToRow(log, taskUid: uid), log: log));
      }
    }
    if (_syncCycle()) {
      for (final day in await cycleDao.pending()) {
        rows.add(_Row(_Kind.cycle, cycleDayToRow(day), cycleDay: day));
      }
    }
    for (final uid in await _pendingGraves('tasks')) {
      rows.add(_Row(_Kind.deleted, {'table': 'tasks', 'id': uid}, uid: uid));
    }
    if (diary) {
      for (final uid in await _pendingGraves('diary_entries')) {
        rows.add(
          _Row(_Kind.deleted, {'table': 'diary_entries', 'id': uid}, uid: uid),
        );
      }
    }
    if (rows.isEmpty) return;

    // One request when it all fits, which is nearly always.
    final counts = <_Kind, int>{};
    for (final row in rows) {
      counts[row.kind] = (counts[row.kind] ?? 0) + 1;
    }
    if (counts.values.every((n) => n <= _pushChunk) &&
        rows.fold<int>(0, (sum, row) => sum + row.bytes) <= _pushBytes) {
      await _send(rows);
      return;
    }

    // A big queue (a first upload) goes in pieces, kind by kind in the order
    // above, so that a link or a mark never reaches the server ahead of what it
    // points at. Each piece holds at most 500 rows and about 4 MB.
    for (final kind in _Kind.values) {
      var chunk = <_Row>[];
      var bytes = 0;
      for (final row in rows.where((row) => row.kind == kind)) {
        if (chunk.isNotEmpty &&
            (chunk.length >= _pushChunk || bytes + row.bytes > _pushBytes)) {
          await _send(chunk);
          chunk = [];
          bytes = 0;
        }
        chunk.add(row);
        bytes += row.bytes;
      }
      if (chunk.isNotEmpty) await _send(chunk);
    }
  }

  /// One `POST /sync/push`, then the marks cleared for what it carried.
  ///
  /// **All** of it, refused rows too: a row the server will never take (a
  /// reason is in `rejected`) must not be offered again on every run, or one bad
  /// row would hold up the sync for ever. The refusals are written to the log. A
  /// note with `unknown_label` is saved, only one of its labels was not. A
  /// failure — no network, a 5xx — throws before any mark is touched, so the
  /// next run sends the same rows again; every write is by id, so repeating is
  /// harmless.
  Future<void> _send(List<_Row> rows) async {
    List<Map<String, dynamic>> of(_Kind kind) => [
      for (final row in rows)
        if (row.kind == kind) row.json,
    ];
    Iterable<_Row> kind(_Kind k) => rows.where((row) => row.kind == k);

    final answer = await _api.push({
      for (final k in _Kind.values)
        if (of(k).isNotEmpty) k.key: of(k),
    });

    for (final r in _rows(answer['rejected'])) {
      debugPrint(
        'Sync: server refused ${r['table']} ${r['id']}: ${r['reason']}',
      );
    }

    // Refusals are final (see above), and for a mark there is one more thing to
    // undo: `not_allowed` means the task is handed to someone else, so the tick
    // is not this account's to keep. The refusal names the task, not the day.
    final refusedTasks = {
      for (final r in _rows(answer['rejected']))
        if (r['table'] == 'task_logs' && r['reason'] == 'not_allowed') r['id'],
    };
    if (refusedTasks.isNotEmpty) {
      await tasksDao.deleteLogs([
        for (final r in kind(_Kind.logs))
          if (refusedTasks.contains(r.json['task_id'])) r.log!,
      ]);
    }

    await dao.clearMoodDirty([for (final r in kind(_Kind.moods)) r.uid!]);
    await dao.clearTagDirty([for (final r in kind(_Kind.tags)) r.uid!]);
    await dao.clearEntryDirty({
      for (final r in kind(_Kind.entries)) r.uid!: r.at!,
    });
    await tasksDao.clearTaskDirty({
      for (final r in kind(_Kind.tasks)) r.uid!: r.at!,
    });
    await tasksDao.clearLogDirty([for (final r in kind(_Kind.logs)) r.log!]);
    await cycleDao.clearDirty([for (final r in kind(_Kind.cycle)) r.cycleDay!]);
    await dao.clearTombstones([for (final r in kind(_Kind.deleted)) r.uid!]);
  }
}

/// What a row of a push is: also the order of sending, and the key it travels
/// under in the request.
enum _Kind {
  moods('moods'),
  tags('tags'),
  entries('entries'),
  tasks('tasks'),
  logs('logs'),
  cycle('cycle_days'),
  deleted('deleted');

  const _Kind(this.key);
  final String key;
}

/// One row waiting to go up, with what is needed to clear its mark afterwards.
class _Row {
  _Row(this.kind, this.json, {this.uid, this.at, this.log, this.cycleDay})
    : bytes = utf8.encode(jsonEncode(json)).length;

  final _Kind kind;
  final Map<String, dynamic> json;

  /// The row's identity (a deletion's too), for clearing its mark.
  final String? uid;

  /// When it was last edited as read — a mark is cleared only if this still
  /// holds, so an edit made during the send is not lost.
  final DateTime? at;
  final TaskLog? log;
  final CycleDay? cycleDay;

  /// Its size on the wire, for cutting a queue to fit a request.
  final int bytes;
}
