import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/user_profile.dart';
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

  /// Not attempted — no account, no client, a run already going, or the last
  /// failure is still being waited out.
  skipped,

  /// The network was not there. The ordinary case, and not a fault.
  offline,

  /// The server was reachable and said no.
  failed,
}

/// Sends what this device wrote and takes what the others did.
///
/// Shaped after `AppNotifications`, and for the same reason: everything here
/// talks to something outside the app that is entitled to fail, and none of
/// those failures may reach the diary. A refused request is a note that has not
/// been sent **yet** — the local database is untouched, the mark stays on, and
/// the next attempt carries it.
///
/// ## The order, and why it is not negotiable
///
/// Push first, then pull. Sending before receiving means a disagreement is
/// settled once, on the server, instead of twice.
///
/// Inside the push: catalogues, then notes, then links, then deletions.
/// Postgres — unlike the SQLite underneath this app, which never turns
/// `PRAGMA foreign_keys` on — actually enforces its keys, so a link sent before
/// the note it points at is rejected outright.
///
/// ## Connectivity
///
/// There is none to ask about. `supabase_flutter` v2 dropped its dependency on
/// `connectivity_plus`, and this app never added one — deliberately: a
/// connectivity answer describes the *interface*, not the internet, and says
/// "connected" on a café Wi-Fi that resolves nothing. The request is the
/// question, and a thrown exception is the answer.
class SyncService {
  // `this._client` is what the lint asks for and what Dart forbids: a named
  // parameter may not begin with an underscore. The field stays private
  // because nothing outside this class should reach the network directly, the
  // way nothing outside a DAO reaches the database.
  SyncService({
    required this.dao,
    required this.tasksDao,
    required this.cycleDao,
    required SupabaseClient? client,
    bool Function()? syncDiary,
    bool Function()? syncCycle,
  })
    // ignore: prefer_initializing_formals
    : _client = client,
       _syncDiary = syncDiary ?? (() => true),
       _syncCycle = syncCycle ?? (() => false);

  final DiaryDao dao;
  final TasksDao tasksDao;
  final CycleDao cycleDao;

  /// Null when Supabase never came up — which is every widget test, and any
  /// launch where the keys were wrong or the platform refused. [sync] then does
  /// nothing at all, which is the correct amount.
  final SupabaseClient? _client;

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

  /// Runs one push-and-pull. Never throws.
  Future<SyncOutcome> sync() async {
    final client = _client;
    if (client == null) return SyncOutcome.skipped;
    if (client.auth.currentUser == null) return SyncOutcome.skipped;
    if (_running) return SyncOutcome.skipped;

    // A run that failed a moment ago will fail again; hammering a server that
    // is down is how an app gets rate-limited.
    final retryAfter = _retryAfter;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      return SyncOutcome.skipped;
    }

    _running = true;
    try {
      // Groups first, ahead of the push: a task waiting to go up into a group
      // this account has since left would be refused, and a refusal fails the
      // whole run — every run after it too. Learning about the departure first
      // takes that task off the device instead.
      await _syncGroups(client);
      await _push(client);
      await _pull(client);
      _backoff = Duration.zero;
      _retryAfter = null;
      lastError = null;
      return SyncOutcome.done;
    } catch (error, stack) {
      _noteFailure(error, stack);
      return _isOffline(error) ? SyncOutcome.offline : SyncOutcome.failed;
    } finally {
      _running = false;
    }
  }

  void _noteFailure(Object error, StackTrace stack) {
    lastError = error.toString();
    _backoff = _backoff == Duration.zero
        ? _firstBackoff
        : Duration(
            seconds: (_backoff.inSeconds * 2).clamp(1, _maxBackoff.inSeconds),
          );
    _retryAfter = DateTime.now().add(_backoff);

    // Offline is the ordinary case, not a fault, and it must not fill the log.
    if (!_isOffline(error)) {
      debugPrint('Sync failed: $error\n$stack');
    }
  }

  /// Whether the failure is "no connection" rather than "something is wrong".
  static bool _isOffline(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      error is AuthRetryableFetchException;

  // ---------------------------------------------------------------------------
  // Groups
  // ---------------------------------------------------------------------------

  /// Mirrors the groups this account is in, their members and their names.
  ///
  /// Read whole every run rather than "changed since": the lists are a handful
  /// of rows, and only a whole list can say that a group is **gone** — left,
  /// removed from, or deleted all look the same from here, as a group the
  /// server no longer shows.
  ///
  /// Publishes this account's own name first, but only once it is in a group:
  /// nobody else can read it before then.
  Future<void> _syncGroups(SupabaseClient client) async {
    final user = client.auth.currentUser!;

    final groups =
        (await client
                .from('groups')
                .select('id, name, owner_id')
                .isFilter('deleted_at', null))
            .cast<Map<String, dynamic>>();

    final List<Map<String, dynamic>> members;
    final Map<String, Map<String, dynamic>> profiles;
    if (groups.isEmpty) {
      members = const [];
      profiles = const {};
    } else {
      await client.from('profiles').upsert({
        'display_name': user.displayName ?? user.email?.split('@').first,
        'avatar_url': user.avatarUrl,
      }, onConflict: 'user_id');

      final inGroups = {for (final group in groups) group['id']};
      members = [
        for (final row
            in (await client
                    .from('group_members')
                    .select('group_id, user_id')
                    .isFilter('deleted_at', null))
                .cast<Map<String, dynamic>>())
          if (inGroups.contains(row['group_id'])) row,
      ];
      profiles = {
        for (final row
            in (await client
                    .from('profiles')
                    .select('user_id, display_name, avatar_url'))
                .cast<Map<String, dynamic>>())
          row['user_id'] as String: row,
      };
    }

    await tasksDao.replaceGroups(
      [for (final row in groups) groupFromRow(row)],
      [
        for (final row in members)
          memberFromRow(row, profile: profiles[row['user_id']]),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Up
  // ---------------------------------------------------------------------------

  Future<void> _push(SupabaseClient client) async {
    final diary = _syncDiary();
    // Catalogues first: a note's links point at them, and Postgres checks.
    final moods = diary ? await dao.pendingMoods() : const <NoteMood>[];
    if (moods.isNotEmpty) {
      await client.from('note_moods').upsert([
        for (final mood in moods) moodToRow(mood),
      ]);
      await dao.clearMoodDirty([for (final mood in moods) ?mood.uid]);
    }

    final tags = diary ? await dao.pendingTags() : const <NoteTag>[];
    if (tags.isNotEmpty) {
      await client.from('note_tags').upsert([
        for (final tag in tags) tagToRow(tag),
      ]);
      await dao.clearTagDirty([for (final tag in tags) ?tag.uid]);
    }

    final entries = diary ? await dao.pendingEntries() : const <DiaryEntry>[];
    if (entries.isNotEmpty) {
      await client.from('diary_entries').upsert([
        for (final entry in entries) entryToRow(entry),
      ]);
      // The links of a changed note are replaced wholesale, exactly as the app
      // does locally: the note owns its whole set, and working out which one
      // moved would be more code than sending three rows.
      for (final entry in entries) {
        await _pushLinks(client, entry);
      }
      // Cleared only after the links, and only for notes untouched since they
      // were read — an edit made during the send keeps its mark and goes next
      // time.
      await dao.clearEntryDirty({
        for (final entry in entries) ?entry.uid: entry.updatedAt,
      });
    }

    // Tasks before their day marks, for the same reason catalogues come before
    // notes: a mark points at a task and Postgres checks.
    await _pushTasks(client);
    await _pushLogs(client);
    if (_syncCycle()) await _pushCycle(client);

    // Deletions last: everything above may have been about a row this is
    // about to remove, and the server should hear the story in order.
    //
    // One leg for both halves of the app. A tombstone carries the name of the
    // table it belongs to, and that name is the server's as well as the
    // device's, so `tasks` and `diary_entries` need no separate handling here.
    final graves = [
      for (final grave in await dao.pendingTombstones())
        // A deleted note is part of the diary's story: it waits with the rest.
        if (diary || grave.sourceTable != 'diary_entries') grave,
    ];
    if (graves.isNotEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final grave in graves) {
        await client
            .from(grave.sourceTable)
            .update({'deleted_at': now})
            .eq('id', grave.uid);
      }
      await dao.clearTombstones([for (final grave in graves) grave.uid]);
    }
  }

  /// Sends the tasks this device changed, **parents before children**.
  ///
  /// `parent_id` points into the same table and Postgres checks its keys row by
  /// row, so a child that turns up in the batch ahead of its parent is rejected
  /// outright. [_generations] is what stops that, and it handles any depth
  /// rather than the two the app currently produces: nesting is one level deep
  /// in the UI, but nothing in the schema forbids more and
  /// `deleteTaskCascade` already only reaches one.
  ///
  /// The marks are cleared once, at the end. A generation that lands and is then
  /// followed by one that fails leaves everything unsent, and the next run sends
  /// it all again — an upsert, so re-sending costs nothing and is never wrong.
  Future<void> _pushTasks(SupabaseClient client) async {
    final batch = await tasksDao.pendingTasks();
    if (batch.isEmpty) return;

    final uidsById = await tasksDao.taskUidsById();
    final me = client.auth.currentUser!.id;
    final sent = <String, DateTime>{};

    for (final generation in _generations(batch)) {
      final rows = <Map<String, dynamic>>[];
      for (final task in generation) {
        final uid = task.uid;
        // A group task this account may not edit. The screens never offer the
        // edit, so this is a slip somewhere — and the server refusing it would
        // fail every run from now on. Not sent, and the mark cleared with the
        // rest, so the server's copy wins the next time it changes.
        if (uid != null && !await tasksDao.canEditTask(task, me)) {
          debugPrint(
            'Sync: group task ${task.id} is not ours to edit, not sent',
          );
          sent[uid] = task.updatedAt;
          continue;
        }
        // Nothing to address the row by, so skipping beats inventing — but not
        // in silence. This should be impossible: v14 mints a uid for every task
        // on the device and v15 re-checks unconditionally. If it happens
        // anyway, the task is being dropped from every sync forever with
        // nothing on screen to say so, which is precisely the shape of bug that
        // takes a week to find.
        if (uid == null) {
          debugPrint('Sync: task ${task.id} has no uid, not sent');
          continue;
        }
        rows.add(taskToRow(task, parentUid: uidsById[task.parentId]));
        sent[uid] = task.updatedAt;
      }
      if (rows.isNotEmpty) await client.from('tasks').upsert(rows);
    }

    await tasksDao.clearTaskDirty(sent);
  }

  /// The batch in layers, each one safe to send once the ones before it have
  /// landed: a task is held back while its parent is still waiting.
  static List<List<Task>> _generations(List<Task> batch) {
    final layers = <List<Task>>[];
    var waiting = batch;

    while (waiting.isNotEmpty) {
      final held = {for (final task in waiting) task.id};
      // `contains(null)` is false, so a root task is always ready.
      final ready = [
        for (final task in waiting)
          if (!held.contains(task.parentId)) task,
      ];

      if (ready.isEmpty) {
        // A parent loop, which the app cannot produce. Send the rest in one go
        // rather than spin here forever: the server will refuse it and the run
        // fails loudly, which is the right outcome for data that cannot exist.
        layers.add(waiting);
        break;
      }

      layers.add(ready);
      final done = {for (final task in ready) task.id};
      waiting = [
        for (final task in waiting)
          if (!done.contains(task.id)) task,
      ];
    }

    return layers;
  }

  /// Sends the day marks this device changed.
  ///
  /// A mark whose task carries no uid is **skipped rather than dropped**: it
  /// keeps its own mark and goes up on a later run, once the task it belongs to
  /// has an identity. There is nothing to point at until then, and inventing a
  /// reference is how an orphan row is made.
  ///
  /// One statement for the lot, resolved on `(task_id, date)` — the pair *is*
  /// the row, here and on the server, which is exactly what lets two devices
  /// that ticked the same day converge without anything having to merge them.
  Future<void> _pushLogs(SupabaseClient client) async {
    final batch = await tasksDao.pendingLogs();
    if (batch.isEmpty) return;

    final uidsById = await tasksDao.taskUidsById();
    final rows = <Map<String, dynamic>>[];
    final sent = <TaskLog>[];

    for (final log in batch) {
      final uid = uidsById[log.taskId];
      if (uid == null) continue;
      rows.add(logToRow(log, taskUid: uid));
      sent.add(log);
    }
    if (rows.isEmpty) return;

    // `user_id` is not sent; the server fills it from the session before the
    // conflict is resolved.
    await client
        .from('task_logs')
        .upsert(rows, onConflict: 'task_id,user_id,date');
    await tasksDao.clearLogDirty(sent);
  }

  /// Sends the cycle days this device changed, as one upsert resolved on
  /// `(user_id, date)` — the pair is the row, so two phones that marked the same
  /// day converge on their own.
  Future<void> _pushCycle(SupabaseClient client) async {
    final batch = await cycleDao.pending();
    if (batch.isEmpty) return;

    final me = client.auth.currentUser!.id;
    await client.from('cycle_days').upsert([
      for (final day in batch) cycleDayToRow(day, userId: me),
    ], onConflict: 'user_id,date');
    await cycleDao.clearDirty(batch);
  }

  Future<void> _pushLinks(SupabaseClient client, DiaryEntry entry) async {
    final uid = entry.uid;
    if (uid == null) return;

    final moodUids = await dao.moodUidsForEntry(entry.id);
    await client.from('diary_entry_moods').delete().eq('entry_id', uid);
    if (moodUids.isNotEmpty) {
      await client.from('diary_entry_moods').insert([
        for (final moodUid in moodUids) {'entry_id': uid, 'mood_id': moodUid},
      ]);
    }

    final tagUids = await dao.tagUidsForEntry(entry.id);
    await client.from('diary_entry_tags').delete().eq('entry_id', uid);
    if (tagUids.isNotEmpty) {
      await client.from('diary_entry_tags').insert([
        for (final tagUid in tagUids) {'entry_id': uid, 'tag_id': tagUid},
      ]);
    }
  }

  // ---------------------------------------------------------------------------
  // Down
  // ---------------------------------------------------------------------------

  Future<void> _pull(SupabaseClient client) async {
    // Catalogues before notes, so a note's labels have something to point at,
    // and tasks before their day marks, so a mark can find the task it belongs
    // to by uid.
    var furthest = watermark;
    // The watermark is one position for every table, so skipping the diary here
    // would move it past notes never read. Switching the diary back on puts it
    // back to the start — see `setSyncDiary`.
    if (_syncDiary()) {
      furthest = _later(furthest, await _pullMoods(client));
      furthest = _later(furthest, await _pullTags(client));
      furthest = _later(furthest, await _pullEntries(client));
    }
    furthest = _later(furthest, await _pullTasks(client));
    furthest = _later(furthest, await _pullLogs(client));
    // Same reasoning as the diary: with this off the watermark must not be
    // moved by a table that was not read — `syncCycleSetterProvider` puts it
    // back to the start when the switch comes on.
    if (_syncCycle()) furthest = _later(furthest, await _pullCycle(client));

    // Moved only after everything above has landed. A watermark advanced
    // early, over a pull that then failed halfway, silently skips whatever the
    // second half held — forever, because nothing would ever ask for it again.
    watermark = furthest;
  }

  Future<List<Map<String, dynamic>>> _changedSince(
    SupabaseClient client,
    String table,
  ) {
    final query = client.from(table).select();
    final since = watermark;
    return (since == null
            ? query
            : query.gt('updated_at', since.toUtc().toIso8601String()))
        .order('updated_at')
        .then((rows) => rows.cast<Map<String, dynamic>>());
  }

  Future<DateTime?> _pullMoods(SupabaseClient client) async {
    DateTime? furthest;
    for (final row in await _changedSince(client, 'note_moods')) {
      furthest = _later(furthest, serverUpdatedAt(row));
      final uid = uidOf(row);
      if (uid == null) continue;

      final local = await dao.moodByUid(uid);
      if (isDeleted(row)) continue; // No path deletes a mood; nothing to do.
      if (local == null) {
        await dao.insertRemoteMood(uid, moodFromRow(row));
      } else {
        await dao.applyRemoteMood(uid, moodFromRow(row));
      }
    }
    return furthest;
  }

  Future<DateTime?> _pullTags(SupabaseClient client) async {
    DateTime? furthest;
    for (final row in await _changedSince(client, 'note_tags')) {
      furthest = _later(furthest, serverUpdatedAt(row));
      final uid = uidOf(row);
      if (uid == null) continue;

      final local = await dao.tagByUid(uid);
      if (isDeleted(row)) continue;
      if (local == null) {
        await dao.insertRemoteTag(uid, tagFromRow(row));
      } else {
        await dao.applyRemoteTag(uid, tagFromRow(row));
      }
    }
    return furthest;
  }

  Future<DateTime?> _pullEntries(SupabaseClient client) async {
    DateTime? furthest;
    for (final row in await _changedSince(client, 'diary_entries')) {
      furthest = _later(furthest, serverUpdatedAt(row));
      final uid = uidOf(row);
      if (uid == null) continue;

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
          continue;
        case PullAction.delete:
          await dao.deleteEntryByUid(uid);
        case PullAction.insert:
          await dao.insertRemoteEntry(uid, entryFromRow(row));
          await _pullLinks(client, uid);
        case PullAction.overwrite:
          await dao.applyRemoteEntry(uid, entryFromRow(row));
          await _pullLinks(client, uid);
      }
    }
    return furthest;
  }

  Future<DateTime?> _pullTasks(SupabaseClient client) async {
    DateTime? furthest;
    for (final row in await _changedSince(client, 'tasks')) {
      furthest = _later(furthest, serverUpdatedAt(row));
      final uid = uidOf(row);
      if (uid == null) continue;

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
          continue;
        case PullAction.delete:
          await tasksDao.deleteTaskByUid(uid);
        case PullAction.insert:
          await tasksDao.insertRemoteTask(uid, await _withParent(row));
        case PullAction.overwrite:
          await tasksDao.applyRemoteTask(uid, await _withParent(row));
      }
    }
    return furthest;
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

  /// Takes the day marks the other devices made.
  ///
  /// `remoteDeleted` is always false, and that is a fact about the data rather
  /// than a shortcut: nothing deletes a single mark. The only statement in the
  /// app that removes one removes every mark of a task, and on the server the
  /// same thing is a foreign key — so a mark's disappearance always arrives as
  /// its task's deletion, which [_pullTasks] has already acted on by the time
  /// this runs.
  ///
  /// A mark whose task is not here is dropped rather than kept anywhere: with
  /// the task gone this device has nothing to attach it to, and if the task is
  /// merely late, the mark comes down again the next time the server hears about
  /// it.
  Future<DateTime?> _pullLogs(SupabaseClient client) async {
    final me = client.auth.currentUser!.id;
    DateTime? furthest;
    for (final row in await _changedSince(client, 'task_logs')) {
      furthest = _later(furthest, serverUpdatedAt(row));
      final taskUid = taskUidOf(row);
      if (taskUid == null) continue;

      final task = await tasksDao.taskByUid(taskUid);
      if (task == null) continue;

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
        continue;
      }
      final day = incoming.date.value;
      final local = await tasksDao.getLogForDate(task.id, day);

      // The identity handed to the tie-break is the natural key, and it is the
      // **same string on both sides** — which for a log is right rather than a
      // degenerate case. A tie can only matter while this copy is still unsent,
      // and "keep mine for now" is settled by the push that follows: once a row
      // is clean, anything arriving overwrites it without consulting a clock, so
      // the two devices converge on whichever pushed last either way.
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
          continue;
        // One statement covers both: the upsert resolves on the pair, so a mark
        // this device already has is updated and a new one is inserted.
        case PullAction.insert:
        case PullAction.overwrite:
          await tasksDao.applyRemoteLog(task.id, incoming);
      }
    }
    return furthest;
  }

  /// Takes the cycle days the other devices marked. Nothing is ever deleted, so
  /// there is no deletion to hear about — a day taken back arrives as an empty
  /// day.
  Future<DateTime?> _pullCycle(SupabaseClient client) async {
    DateTime? furthest;
    for (final row in await _changedSince(client, 'cycle_days')) {
      furthest = _later(furthest, serverUpdatedAt(row));
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
          continue;
        case PullAction.insert:
        case PullAction.overwrite:
          await cycleDao.applyRemote(incoming);
      }
    }
    return furthest;
  }

  /// `YYYY-MM-DD`, only ever used to spell a log's identity for the tie-break.
  static String _calendarDay(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}'
      '-${day.day.toString().padLeft(2, '0')}';

  /// Replaces one note's labels with the server's set.
  ///
  /// Fetched per note rather than in one sweep because the link tables carry no
  /// timestamp to sweep by — a link has no identity of its own, so there is
  /// nothing for a watermark to compare. What marks it as changed is the note,
  /// which is why this only ever runs for a note that just arrived.
  Future<void> _pullLinks(SupabaseClient client, String entryUid) async {
    final entry = await dao.entryByUid(entryUid);
    if (entry == null) return;

    final moodRows = await client
        .from('diary_entry_moods')
        .select('mood_id')
        .eq('entry_id', entryUid);
    final moodIds = <int>[];
    for (final row in moodRows) {
      final mood = await dao.moodByUid(row['mood_id'] as String);
      // A label this device has not been sent yet: skipped rather than
      // invented, and picked up whenever the catalogue catches up.
      if (mood != null) moodIds.add(mood.id);
    }
    await dao.applyRemoteEntryMoods(entry.id, moodIds);

    final tagRows = await client
        .from('diary_entry_tags')
        .select('tag_id')
        .eq('entry_id', entryUid);
    final tagIds = <int>[];
    for (final row in tagRows) {
      final tag = await dao.tagByUid(row['tag_id'] as String);
      if (tag != null) tagIds.add(tag.id);
    }
    await dao.applyRemoteEntryTags(entry.id, tagIds);
  }

  static DateTime? _later(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return b.isAfter(a) ? b : a;
  }
}
