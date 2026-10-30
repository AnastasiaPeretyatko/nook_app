import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../sync/merge.dart' show storedSeconds;
import '../../utils/task_audience.dart' show canEditTaskAs;
import '../app_database.dart';

part 'tasks_dao.g.dart';

/// Reads and writes tasks, habits and their day marks.
///
/// ## The sync marks
///
/// The same three ideas the diary got, and the same asymmetry running through
/// every method: a write **the user made** is dirty, a write **the server sent**
/// is not. That is what the `applyRemote*` methods below are for, and getting it
/// wrong does not fail loudly — it makes a row bounce between two devices
/// forever.
///
/// Where this differs from [DiaryDao] is the logs, and the difference is worth
/// stating because it saved a table's worth of machinery. A log has a **natural
/// key** — its task and its day — so it needs no `uid`: with random uuids, two
/// phones that ticked today's habit independently would arrive with two rows for
/// one day and something would have to merge them. It needs no tombstone either,
/// because the one statement in the app that deletes a log deletes every log of
/// one task, so its disappearance is always already told by its task's.
///
/// ## What a day is
///
/// [TaskLogs.date] is a calendar day at local midnight, and [dayOf] is the only
/// thing that decides so. It used to be midnight by convention alone, which held
/// right up until the unique index over the pair made it load-bearing — see the
/// comment on [TaskLogs].
///
/// ## What does *not* leave the device
///
/// [TaskSessions], entirely. An open session is one phone's live state, and a
/// closed one is a row nothing reads: every lasting trace of a run is folded
/// into that day's log by [_closeRun] before the session is closed. Restore the
/// logs and every screen in the app draws what it drew.
/// Everything [TasksDao.deleteTaskCascade] removed, kept so that
/// [TasksDao.restoreDeleted] can put it back: the task, its subtasks, and the
/// logs, other members' marks and timer runs of either.
class DeletedTask {
  const DeletedTask({
    required this.tasks,
    required this.logs,
    required this.marks,
    required this.sessions,
  });

  /// The task and its direct subtasks, the parent first.
  final List<Task> tasks;
  final List<TaskLog> logs;
  final List<GroupMark> marks;
  final List<TaskSession> sessions;
}

@DriftAccessor(
  tables: [
    Tasks,
    TaskLogs,
    TaskSessions,
    SyncTombstones,
    TaskGroups,
    GroupMembers,
    GroupMarks,
  ],
)
class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
  TasksDao(super.db);

  static const _uuid = Uuid();

  /// The calendar day [moment] falls on, as local midnight.
  ///
  /// Every write to [TaskLogs.date] goes through here, which is what makes the
  /// unique index over `(taskId, date)` describe what it claims to. The callers
  /// mostly pass a day already — but not all of them: `HomePage` opens on
  /// `DateTime.now()`, so the timeline can hand over an instant, and before this
  /// existed that instant went into the column as it was.
  static DateTime dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  Stream<List<Task>> watchAllTasks() => select(tasks).watch();

  Stream<List<TaskGroup>> watchGroups() =>
      (select(taskGroups)..orderBy([(g) => OrderingTerm.asc(g.name)])).watch();

  Stream<List<GroupMember>> watchGroupMembers() => (select(
    groupMembers,
  )..orderBy([(m) => OrderingTerm.asc(m.displayName)])).watch();

  Stream<List<GroupMark>> watchGroupMarks() => select(groupMarks).watch();

  /// One-shot reads of the mirror, for the task form.
  Future<List<TaskGroup>> getGroups() =>
      (select(taskGroups)..orderBy([(g) => OrderingTerm.asc(g.name)])).get();

  Future<List<GroupMember>> getGroupMembers() => select(groupMembers).get();

  Stream<List<Task>> watchRootTasks() =>
      (select(tasks)..where((t) => t.parentId.isNull())).watch();

  Stream<List<Task>> watchSubtasks(int parentId) =>
      (select(tasks)..where((t) => t.parentId.equals(parentId))).watch();

  /// One-shot read of the direct subtasks, for forms that seed editable copies
  /// rather than following the live stream.
  Future<List<Task>> getSubtasks(int parentId) =>
      (select(tasks)..where((t) => t.parentId.equals(parentId))).get();

  Future<Task?> getTaskById(int id) =>
      (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// One-shot read of the root tasks, for the isolate that redraws the
  /// home-screen widget.
  ///
  /// A `watch` would be wrong there rather than merely wasteful: that isolate is
  /// woken to answer one tap and is killed straight after, so a stream has
  /// nobody to deliver its second event to. Every screen in the app keeps using
  /// [watchRootTasks].
  Future<List<Task>> getRootTasks() =>
      (select(tasks)..where((t) => t.parentId.isNull())).get();

  /// One-shot read of the day marks between [start] and [end], `end` excluded.
  /// The twin of [watchLogsBetween], for the same isolate and the same reason.
  Future<List<TaskLog>> getLogsBetween(DateTime start, DateTime end) {
    final from = dayOf(start);
    final to = dayOf(end);
    return (select(taskLogs)..where(
          (l) =>
              l.date.isBiggerOrEqualValue(from) & l.date.isSmallerThanValue(to),
        ))
        .get();
  }

  /// Writes a new task, giving it the identity the server will know it by.
  ///
  /// The uid is minted here rather than by the caller: a row without one is
  /// invisible to the sync, and a screen should not have to remember that.
  /// `dirty` needs no mention — the column defaults to true, which is exactly
  /// what a task nobody has sent yet is.
  Future<int> insertTask(TasksCompanion task) => into(
    tasks,
  ).insert(task.uid.present ? task : task.copyWith(uid: Value(_uuid.v4())));

  /// Updates only the provided columns of the task with [id]: absent values are
  /// left untouched, while an explicit `Value(null)` clears the corresponding
  /// nullable column.
  ///
  /// The one funnel every edit goes through — [setTaskStatus] lands here too —
  /// which is why it is the single place that has to mark the task as changed.
  /// `dirty` is forced rather than defaulted, so a caller cannot leave an edit
  /// unsent by passing a companion of its own.
  ///
  /// `updatedAt` is forced as well, and forced to be **strictly greater than it
  /// was**, for the reason spelled out on [stampAfter]: the task form already
  /// passed a stamp of its own, but two edits inside one second would otherwise
  /// be stored as the same instant and [clearTaskDirty] would drop the second.
  Future<int> updateTaskById(int id, TasksCompanion task) {
    return transaction(() async {
      final current = await getTaskById(id);
      return (update(tasks)..where((t) => t.id.equals(id))).write(
        task.copyWith(
          updatedAt: Value(stampAfter(current?.updatedAt)),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// A moment strictly later than [previous], as the database stores moments.
  ///
  /// Drift keeps a `DateTime` as whole seconds, so two writes inside one second
  /// land on the same instant — and `clear*Dirty` decides whether an edit
  /// happened *during* a send by comparing exactly that. Equal stamps would make
  /// it clear a mark that covers an edit nobody has sent, and nothing would ever
  /// send it again. Stepping a second forward when the clock has not moved keeps
  /// every version of a row orderable.
  ///
  /// The cost is that a burst of writes inside one second pushes the stamp a
  /// little ahead of the wall clock. Ticking a day is user-paced, so the burst
  /// that would make that visible does not happen.
  ///
  /// The twin of the rule inside `DiaryDao.updateEntryById`, and it compares
  /// **as stored** rather than with `isAfter`: `now` is always a fraction later
  /// than a value read back from the database, so `isAfter` would say yes and
  /// then write the very same second.
  static DateTime stampAfter(DateTime? previous) {
    final now = DateTime.now();
    if (previous == null) return now;
    return storedSeconds(now) > storedSeconds(previous)
        ? now
        : previous.add(const Duration(seconds: 1));
  }

  /// What a write sets [TaskLogs.completedAt] to: now on the tick, null on the
  /// untick, and untouched when [completed] is not being written or the day was
  /// already ticked — a counter re-ticks on every step past its target.
  static Value<DateTime?> _completedAtFor(bool? completed, TaskLog? existing) {
    if (completed == null) return const Value.absent();
    if (!completed) return const Value(null);
    if (existing != null && existing.completed) return const Value.absent();
    return Value(DateTime.now());
  }

  /// Moves a one-off task to [day] — "На завтра". Only the start date changes
  /// (and so the task is marked unsent), but its subtasks log their ticks against
  /// the parent's start date, so the ones ticked there are re-ticked on the new
  /// day and unticked on the old, the way the task form's save does it. The old
  /// mark is set to not-done rather than deleted: a deleted log would be brought
  /// back by the next sync.
  Future<void> moveTaskToDay(Task task, DateTime day) => transaction(() async {
    final from = dayOf(task.startDate ?? task.createdAt);
    final to = dayOf(day);
    await updateTaskById(
      task.id,
      TasksCompanion(startDate: Value(to), updatedAt: Value(DateTime.now())),
    );
    if (from == to) return;
    for (final subtask in await getSubtasks(task.id)) {
      final log = await getLogForDate(subtask.id, from);
      if (log?.completed ?? false) {
        await setLog(subtask.id, to, completed: true);
        await setLog(subtask.id, from, completed: false);
      }
    }
  });

  /// Moves a task in or out of the archive. Only the status is written, so the
  /// logs, sessions and subtasks of an archived habit all survive to be
  /// restored — unlike [deleteTaskCascade], which is the destructive one.
  Future<int> setTaskStatus(int id, TaskStatus status) => updateTaskById(
    id,
    TasksCompanion(status: Value(status), updatedAt: Value(DateTime.now())),
  );

  /// Deletes the task and everything attached to it: its direct subtasks and
  /// all logs/sessions of both the task and those subtasks.
  ///
  /// A tombstone is written for the task **and for every subtask**, in the same
  /// transaction, and that is the only trace the deletion leaves. Every other
  /// edit can be found by comparing the row against the server's copy; a deleted
  /// task is simply gone, and "gone" reads exactly like "the other device has
  /// not sent it yet" — so without this the task would come straight back on the
  /// next pull.
  ///
  /// One per row and not one for the parent, because a subtask is a row of its
  /// own on the server with an identity of its own: the server would never learn
  /// about the children from a note about the parent. The logs need none — the
  /// only statement in the app that deletes one is right here, by task, and on
  /// the server a foreign key says the same thing.
  ///
  /// Returns what was removed, for [restoreDeleted]; null when there was no such
  /// task.
  Future<DeletedTask?> deleteTaskCascade(int id) => transaction(() async {
    final family =
        await (select(tasks)
              ..where((t) => t.id.equals(id) | t.parentId.equals(id))
              ..orderBy([(t) => OrderingTerm.asc(t.parentId)]))
            .get();
    if (family.isEmpty) return null;
    final ids = [for (final t in family) t.id];
    final deleted = DeletedTask(
      tasks: family,
      logs: await (select(taskLogs)..where((l) => l.taskId.isIn(ids))).get(),
      marks: await (select(groupMarks)..where((m) => m.taskId.isIn(ids))).get(),
      sessions: await (select(
        taskSessions,
      )..where((s) => s.taskId.isIn(ids))).get(),
    );
    for (final uid in await _deleteCascade(id)) {
      await _writeTombstone(uid);
    }
    return deleted;
  });

  /// Undoes [deleteTaskCascade]: the rows come back with the **ids** they had,
  /// but as new tasks to the server — each gets a fresh uid, and the tombstones
  /// of the old ones stay.
  ///
  /// Not the old uids, although that looks like the honest undo. By the time the
  /// user taps "Отменить" the deletion may already have reached the server
  /// (`deleted_at` set there), and a deletion **wins** in [pullAction]: the
  /// restored task would be deleted again by the next pull, a second after it
  /// reappeared. A fresh uid has no such history, and the old tombstone, sent or
  /// not, settles the old identity the same way on every device.
  ///
  /// Every restored task and log is dirty and the tasks are stamped now, so they
  /// are sent as the news they are.
  Future<void> restoreDeleted(DeletedTask deleted) => transaction(() async {
    final now = DateTime.now();
    for (final t in deleted.tasks) {
      await into(tasks).insert(
        t.copyWith(uid: Value(_uuid.v4()), dirty: true, updatedAt: now),
        mode: InsertMode.insertOrReplace,
      );
    }
    for (final l in deleted.logs) {
      await into(taskLogs).insert(
        l.copyWith(dirty: true, updatedAt: now),
        mode: InsertMode.insertOrReplace,
      );
    }
    for (final m in deleted.marks) {
      await into(groupMarks).insert(m, mode: InsertMode.insertOrReplace);
    }
    for (final s in deleted.sessions) {
      await into(taskSessions).insert(s, mode: InsertMode.insertOrReplace);
    }
  });

  /// Takes the task, its direct subtasks and every log and session of either
  /// out of the database, and reports the uids of the rows that went.
  ///
  /// No tombstones: whether the deletion is news depends on who asked for it,
  /// and only the callers know. [deleteTaskCascade] writes them, [deleteTaskByUid]
  /// deliberately does not.
  ///
  /// A uid is read **before** the row goes, which is why this is not a
  /// three-line delete.
  Future<List<String>> _deleteCascade(int id) async {
    final family = await (select(
      tasks,
    )..where((t) => t.id.equals(id) | t.parentId.equals(id))).get();
    if (family.isEmpty) return const [];

    final affectedIds = [for (final task in family) task.id];
    await (delete(taskLogs)..where((l) => l.taskId.isIn(affectedIds))).go();
    await (delete(groupMarks)..where((g) => g.taskId.isIn(affectedIds))).go();
    await (delete(taskSessions)..where((s) => s.taskId.isIn(affectedIds))).go();
    await (delete(tasks)..where((t) => t.parentId.equals(id))).go();
    await (delete(tasks)..where((t) => t.id.equals(id))).go();

    // A row with no uid predates the sync schema and the server has never heard
    // of it — there is nobody to tell.
    return [for (final task in family) ?task.uid];
  }

  /// Records that [uid] is gone, replacing any earlier note of the same.
  ///
  /// `insertOrReplace` because the key is the pair `(sourceTable, uid)`: a
  /// deletion re-recorded after a failed send is the same fact, not a second
  /// one, and a plain insert would throw the second time.
  ///
  /// A twin of the private helper in [DiaryDao] rather than something shared,
  /// because each DAO reaches only the tables its own accessor lists.
  Future<void> _writeTombstone(String uid) async {
    await into(syncTombstones).insert(
      SyncTombstonesCompanion.insert(
        // From the schema rather than a string literal, so a renamed table
        // cannot leave the tombstones pointing at one that no longer exists.
        sourceTable: tasks.actualTableName,
        uid: uid,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// Copies every direct subtask of [fromTaskId] under [toTaskId], without any
  /// completion history.
  ///
  /// The task form no longer calls this: duplicating a task now goes through its
  /// own editable subtask rows, so the copy can be adjusted before saving. Kept
  /// as a DAO-level way to clone children in one step.
  Future<void> copySubtasks({
    required int fromTaskId,
    required int toTaskId,
  }) async {
    final subtasks = await (select(
      tasks,
    )..where((t) => t.parentId.equals(fromTaskId))).get();
    for (final subtask in subtasks) {
      // Through [insertTask] rather than straight into the table: a copy is a
      // new row and needs an identity of its own, and this is the only other
      // place that inserts one.
      await insertTask(
        TasksCompanion.insert(
          parentId: Value(toTaskId),
          title: subtask.title,
          description: Value(subtask.description),
          status: Value(subtask.status),
          repeatType: Value(subtask.repeatType),
          repeatInterval: Value(subtask.repeatInterval),
          repeatDaysMask: Value(subtask.repeatDaysMask),
          trackingMode: Value(subtask.trackingMode),
          targetDurationMinutes: Value(subtask.targetDurationMinutes),
          targetValue: Value(subtask.targetValue),
          iconKey: Value(subtask.iconKey),
          colorValue: Value(subtask.colorValue),
          scheduledTimeMinutes: Value(subtask.scheduledTimeMinutes),
          endTimeMinutes: Value(subtask.endTimeMinutes),
          startDate: Value(subtask.startDate),
        ),
      );
    }
  }

  // TaskLogs

  Stream<List<TaskLog>> watchAllLogs() => select(taskLogs).watch();

  Stream<List<TaskLog>> watchLogsForTask(int taskId) =>
      (select(taskLogs)..where((l) => l.taskId.equals(taskId))).watch();

  Stream<List<TaskLog>> watchLogsForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return (select(taskLogs)..where(
          (l) =>
              l.date.isBiggerOrEqualValue(start) &
              l.date.isSmallerThanValue(end),
        ))
        .watch();
  }

  Stream<List<TaskLog>> watchLogsBetween(DateTime start, DateTime end) {
    final from = DateTime(start.year, start.month, start.day);
    final to = DateTime(end.year, end.month, end.day);
    return (select(taskLogs)..where(
          (l) =>
              l.date.isBiggerOrEqualValue(from) & l.date.isSmallerThanValue(to),
        ))
        .watch();
  }

  // TaskSessions

  Stream<List<TaskSession>> watchSessionsForTask(int taskId) =>
      (select(taskSessions)..where((s) => s.taskId.equals(taskId))).watch();

  Future<int> insertSession(TaskSessionsCompanion session) =>
      into(taskSessions).insert(session);

  Future<bool> updateSession(TaskSessionsCompanion session) =>
      update(taskSessions).replace(session);

  // Timer runs
  //
  // A running timer is a session with no `endedAt`. Keeping the start instant in
  // the database rather than the elapsed count is what lets the timer survive
  // the app being backgrounded or killed: elapsed time is always recomputed from
  // the wall clock, never accumulated frame by frame.

  /// Runs that were started and never closed. At most one per task.
  Stream<List<TaskSession>> watchOpenSessions() =>
      (select(taskSessions)..where((s) => s.endedAt.isNull())).watch();

  /// The run [taskId] has going, if any. Ordered so that a stray older run left
  /// behind by a crash cannot shadow the current one.
  Future<TaskSession?> getOpenSession(int taskId) =>
      (select(taskSessions)
            ..where((s) => s.taskId.equals(taskId) & s.endedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.startedAt)])
            ..limit(1))
          .getSingleOrNull();

  /// Starts a run for [taskId] at [now]. A run left open — the app was killed
  /// while the timer went — is closed first, so its time is neither lost nor
  /// counted twice.
  Future<void> startTimer(
    int taskId,
    DateTime now, {
    required int targetSeconds,
  }) {
    return transaction(() async {
      await _closeRun(taskId, now, targetSeconds: targetSeconds);
      await into(
        taskSessions,
      ).insert(TaskSessionsCompanion.insert(taskId: taskId, startedAt: now));
    });
  }

  /// Closes [taskId]'s run at [now] and folds its seconds into the day's log.
  /// A no-op when nothing is running.
  Future<void> stopTimer(
    int taskId,
    DateTime now, {
    required int targetSeconds,
  }) {
    return transaction(
      () => _closeRun(taskId, now, targetSeconds: targetSeconds),
    );
  }

  Future<void> _closeRun(
    int taskId,
    DateTime now, {
    required int targetSeconds,
  }) async {
    final open = await getOpenSession(taskId);
    if (open == null) return;

    // A clock that moved backwards must not subtract time already worked.
    final ran = now.difference(open.startedAt).inSeconds;
    final seconds = ran < 0 ? 0 : ran;

    await (update(taskSessions)..where((s) => s.id.equals(open.id))).write(
      TaskSessionsCompanion(
        endedAt: Value(now),
        durationSeconds: Value(seconds),
      ),
    );

    // The run belongs to the day it began on, even when it ends after midnight.
    final day = DateTime(
      open.startedAt.year,
      open.startedAt.month,
      open.startedAt.day,
    );
    final log = await getLogForDate(taskId, day);
    final total = (log?.value ?? 0) + seconds;
    final reached = targetSeconds > 0 && total >= targetSeconds;
    await setLog(
      taskId,
      day,
      value: reached ? targetSeconds.toDouble() : total,
      // Only ever ticks the day, never clears it: pausing a timer must not undo
      // a day the user marked done by hand.
      completed: reached ? true : null,
    );
  }

  // Completion toggling

  /// The log for [taskId] on the day [date] falls on, if there is one.
  ///
  /// Still asked as a range rather than an equality, even though the column now
  /// only ever holds a day: a device upgraded from before v14 has had its rows
  /// folded onto their days, but reading by range costs nothing and cannot be
  /// wrong. `getSingleOrNull()` **throws** on a second row, which is what the
  /// unique index over the pair exists to make impossible.
  Future<TaskLog?> getLogForDate(int taskId, DateTime date) {
    final start = dayOf(date);
    final end = start.add(const Duration(days: 1));
    return (select(taskLogs)..where(
          (l) =>
              l.taskId.equals(taskId) &
              l.date.isBiggerOrEqualValue(start) &
              l.date.isSmallerThanValue(end),
        ))
        .getSingleOrNull();
  }

  /// Upserts the log for [taskId] on [date], updating only the provided fields.
  ///
  /// In a transaction, unlike before: this reads, decides and writes, and it is
  /// no longer the case that the app is the only writer — a pull writes logs too.
  /// [date] is folded onto its day on the way in, so the unique index over the
  /// pair keeps describing what it claims to.
  Future<void> setLog(
    int taskId,
    DateTime date, {
    double? value,
    bool? completed,
  }) {
    return transaction(() async {
      final day = dayOf(date);
      final existing = await getLogForDate(taskId, day);
      if (existing == null) {
        // `dirty` is left to the column default, which is true — exactly what a
        // mark nobody has sent yet is.
        await into(taskLogs).insert(
          TaskLogsCompanion.insert(
            taskId: taskId,
            date: day,
            completed: Value(completed ?? false),
            value: value != null ? Value(value) : const Value.absent(),
            completedAt: _completedAtFor(completed, null),
            updatedAt: Value(stampAfter(null)),
          ),
        );
      } else {
        await (update(taskLogs)..where((l) => l.id.equals(existing.id))).write(
          TaskLogsCompanion(
            value: value != null ? Value(value) : const Value.absent(),
            completed: completed != null
                ? Value(completed)
                : const Value.absent(),
            completedAt: _completedAtFor(completed, existing),
            dirty: const Value(true),
            updatedAt: Value(stampAfter(existing.updatedAt)),
          ),
        );
      }
    });
  }

  /// Adds 1 to the counter log for [taskId] on [date], marking it completed
  /// once the running count reaches [target].
  Future<void> incrementCounter(int taskId, DateTime date, double target) {
    return transaction(() async {
      final existing = await getLogForDate(taskId, date);
      final next = (existing?.value ?? 0) + 1;
      final completed = target > 0 && next >= target;
      await setLog(taskId, date, value: next, completed: completed);
    });
  }

  Future<void> toggleCompletion(int taskId, DateTime date) {
    return transaction(() async {
      final day = dayOf(date);
      final existing = await getLogForDate(taskId, day);
      // A group task "for everyone" is shared: once another member has ticked
      // it, it is done for all and this account has nothing to tick.
      if (!(existing?.completed ?? false) && await _doneByOthers(taskId, day)) {
        return;
      }
      if (existing == null) {
        await into(taskLogs).insert(
          TaskLogsCompanion.insert(
            taskId: taskId,
            date: day,
            completed: const Value(true),
            completedAt: _completedAtFor(true, null),
            updatedAt: Value(stampAfter(null)),
          ),
        );
      } else {
        await (update(taskLogs)..where((l) => l.id.equals(existing.id))).write(
          TaskLogsCompanion(
            completed: Value(!existing.completed),
            completedAt: _completedAtFor(!existing.completed, existing),
            dirty: const Value(true),
            updatedAt: Value(stampAfter(existing.updatedAt)),
          ),
        );
      }
    });
  }

  Future<bool> _doneByOthers(int taskId, DateTime day) async {
    final task = await getTaskById(taskId);
    if (task == null || task.groupUid == null || task.assigneeUid != null) {
      return false;
    }
    final marks = await (select(
      groupMarks,
    )..where((m) => m.taskId.equals(taskId) & m.completed.equals(true))).get();
    return marks.any((m) => dayOf(m.date) == day);
  }

  // ---------------------------------------------------------------------------
  // The surface the sync engine works through.
  //
  // Nothing here reaches the network. What separates these methods from the ones
  // above is *who* the write is on behalf of: a `pending*` read is this device
  // saying what it has to offer, and an `applyRemote*` write must **not** mark
  // the row — a row written as if the user had touched it would be sent straight
  // back, and the two devices would hand it to each other forever.
  // ---------------------------------------------------------------------------

  /// The tasks changed here and not sent yet — subtasks included, since each is
  /// a row of its own on the server.
  Future<List<Task>> pendingTasks() =>
      (select(tasks)..where((t) => t.dirty.equals(true))).get();

  /// The day marks changed here and not sent yet.
  Future<List<TaskLog>> pendingLogs() =>
      (select(taskLogs)..where((l) => l.dirty.equals(true))).get();

  /// How many tasks are waiting to be sent, for the "there are N here, upload
  /// them?" question.
  ///
  /// Root tasks only. Subtasks are unsent too and do go up, but they are never
  /// rows of their own on any screen, so counting them would make the number in
  /// the dialog disagree with what the user can see.
  Future<int> unsentTaskCount() async {
    final count = tasks.id.count();
    final row =
        await (selectOnly(tasks)
              ..addColumns([count])
              ..where(
                tasks.dirty.equals(true) &
                    tasks.parentId.isNull() &
                    tasks.groupUid.isNull(),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// How many tasks are on the device at all, sent or not.
  ///
  /// Not [unsentTaskCount], and the difference is the whole point. That one
  /// counts what is waiting to go up, which is the right question the first
  /// time an account is involved — everything here is unsent, because nothing
  /// can be sent before the question is answered. It is the **wrong** question
  /// when the device changes hands: the previous account's tasks went up under
  /// that account and carry no mark at all, so counting the unsent would find
  /// none of them and the dialog would never appear over the data it exists to
  /// protect.
  ///
  /// Root tasks only, for the same reason [unsentTaskCount] counts roots: a
  /// subtask is never a row on any screen, and a number the user cannot see is
  /// a number they cannot check.
  Future<int> taskCount() async {
    final count = tasks.id.count();
    final row =
        await (selectOnly(tasks)
              ..addColumns([count])
              ..where(tasks.parentId.isNull() & tasks.groupUid.isNull()))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Answers "no" to that question: everything here stays here.
  ///
  /// The marks are cleared without anything being sent, so the rows are simply
  /// never offered to the server. Editing one later marks it again and it does
  /// go up — which is worth saying out loud in the dialog, because otherwise the
  /// behaviour looks like the answer was ignored.
  ///
  /// The tombstones go too, and dropping **all** of them rather than only the
  /// tasks' is deliberate: this runs together with its diary twin, which does
  /// the same, and a deletion of something that is staying here is nobody
  /// else's news either way.
  Future<void> keepExistingTasksLocal() {
    return transaction(() async {
      await update(tasks).write(const TasksCompanion(dirty: Value(false)));
      await update(
        taskLogs,
      ).write(const TaskLogsCompanion(dirty: Value(false)));
      await delete(syncTombstones).go();
    });
  }

  /// Every task, day mark and timer run on this device, gone.
  ///
  /// What a phone needs when a **different** account signs in: the local
  /// database has no notion of who owns a row — there is no `user_id` column
  /// here and there never was — so the previous account's tasks are simply
  /// still on the screen, editable, and confusingly half-connected to a server
  /// that will not take them. Nothing but removing them makes the app tell the
  /// truth about whose data it is showing.
  ///
  /// Only this account's *tasks*: the tombstones of notes are the diary twin's
  /// to drop, and the two run together.
  ///
  /// Sessions go too. An open one is a timer running right now, and a timer
  /// belonging to a task that no longer exists would keep ticking against
  /// nothing — [startTimer] banks a run left open by a crash, and there would be
  /// no row left to bank it into.
  Future<void> wipeAllTasks() {
    return transaction(() async {
      await delete(taskLogs).go();
      await delete(groupMarks).go();
      await delete(taskSessions).go();
      await delete(tasks).go();
      await delete(groupMembers).go();
      await delete(taskGroups).go();
      await (delete(
        syncTombstones,
      )..where((t) => t.sourceTable.equals(tasks.actualTableName))).go();
    });
  }

  /// Gives every task a fresh identity and marks the lot to be sent again.
  ///
  /// For the one case where data stays on the device and changes hands: the
  /// user signs in as somebody else and answers "upload" to the question about
  /// what is already here. Without this the answer cannot be honoured at all.
  ///
  /// Two reasons, and either alone would be enough. A task that went up under
  /// the previous account carries `dirty = false`, so nothing would ever offer
  /// it to the new one. And its uid is the **primary key of a row the previous
  /// account owns** on the server, so an upsert under the new account is
  /// refused — the row cannot be inserted, and cannot be updated either, since
  /// the policies show a client only its own rows. A new uuid is what makes it
  /// this account's task rather than a claim on someone else's.
  ///
  /// The day marks keep their `(task, date)` identity and are re-keyed for free
  /// by their task's new uid; they need the mark, and nothing else.
  ///
  /// The tombstones go: they name uids belonging to the other account, and
  /// sending them would ask the server to delete that account's rows.
  ///
  /// One statement per task, because each needs its own uuid and SQLite has no
  /// function that would generate one — the same bargain `_backfillUids` makes
  /// in the migrations.
  ///
  /// Group tasks are not taken over: they belong to the groups the previous
  /// account was in, and re-minted they would go up as this account's personal
  /// copies of someone else's tasks. They go, with the groups; this account's
  /// own groups arrive on its first pull.
  Future<void> remintTaskUids() {
    return transaction(() async {
      await replaceGroups(const [], const []);
      for (final task in await select(tasks).get()) {
        await (update(tasks)..where((t) => t.id.equals(task.id))).write(
          TasksCompanion(uid: Value(_uuid.v4()), dirty: const Value(true)),
        );
      }
      await update(taskLogs).write(const TaskLogsCompanion(dirty: Value(true)));
      await (delete(
        syncTombstones,
      )..where((t) => t.sourceTable.equals(tasks.actualTableName))).go();
    });
  }

  /// The uid of every task that has one, by local id.
  ///
  /// What a push needs to turn a local reference into one the server
  /// understands: a subtask names its parent and a day mark names its task, and
  /// both are integers here and uuids there. One query for the lot rather than a
  /// lookup per row — a task list is small, and the alternative is a read per
  /// logged day.
  Future<Map<int, String>> taskUidsById() async {
    final rows =
        await (selectOnly(tasks)
              ..addColumns([tasks.id, tasks.uid])
              ..where(tasks.uid.isNotNull()))
            .get();
    return {for (final row in rows) row.read(tasks.id)!: row.read(tasks.uid)!};
  }

  /// Finds a task by the identity the server knows it by.
  Future<Task?> taskByUid(String uid) =>
      (select(tasks)..where((t) => t.uid.equals(uid))).getSingleOrNull();

  /// Writes a task as the server has it, by [uid].
  ///
  /// Not through [updateTaskById]: this must **not** set `dirty`, and it must
  /// not move `updatedAt` either — the timestamp is part of what came down, and
  /// overwriting it with the local clock would make the row look newer than the
  /// copy it was just taken from.
  ///
  /// Returns whether a row was there to update. False means the task is new to
  /// this device and the caller should insert it instead — that is the caller's
  /// decision because only it knows how to translate a parent's uid into a
  /// local id.
  Future<bool> applyRemoteTask(String uid, TasksCompanion task) async {
    final changed = await (update(tasks)..where((t) => t.uid.equals(uid)))
        .write(task.copyWith(uid: Value(uid), dirty: const Value(false)));
    return changed > 0;
  }

  /// Takes a task the server has and this device has not.
  ///
  /// Separate from [insertTask] because that one mints a uid and leaves the row
  /// dirty — right for a task the user just made, wrong for one that came down
  /// the wire already carrying both answers.
  Future<int> insertRemoteTask(String uid, TasksCompanion task) => into(
    tasks,
  ).insert(task.copyWith(uid: Value(uid), dirty: const Value(false)));

  /// Writes a day mark as the server has it, keyed by the pair that identifies
  /// it rather than by any id.
  ///
  /// One statement, and it is the unique index from v14 that makes it correct:
  /// the conflict target is `(task_id, date)`, so a mark this device already has
  /// is updated instead of duplicated. Spelled out rather than left to
  /// `insertOnConflictUpdate`, which resolves on the primary key — `id` — and
  /// would therefore have inserted a second row for the same day every time.
  Future<void> applyRemoteLog(int taskId, TaskLogsCompanion log) async {
    final row = log.copyWith(
      taskId: Value(taskId),
      date: Value(dayOf(log.date.value)),
      dirty: const Value(false),
    );
    await into(taskLogs).insert(
      row,
      onConflict: DoUpdate(
        (_) => row,
        target: [taskLogs.taskId, taskLogs.date],
      ),
    );
  }

  /// Marks the listed tasks as sent. Called **after** the server has taken
  /// them, never before — a row cleared optimistically is an edit thrown away.
  ///
  /// Matched by uid rather than id, and only where the row is still the one that
  /// was sent: an edit made while the send was in flight has moved `updatedAt`
  /// on, and clearing that would lose it.
  Future<void> clearTaskDirty(Map<String, DateTime> sentAt) async {
    for (final entry in sentAt.entries) {
      await (update(tasks)..where(
            (t) =>
                t.uid.equals(entry.key) &
                t.updatedAt.isSmallerOrEqualValue(entry.value),
          ))
          .write(const TasksCompanion(dirty: Value(false)));
    }
  }

  /// The same for the day marks, keyed by the pair instead of by a uid — which
  /// is why it takes the rows that were sent rather than a map: the key is two
  /// columns and the guard is a third.
  Future<void> clearLogDirty(Iterable<TaskLog> sent) async {
    for (final log in sent) {
      await (update(taskLogs)..where(
            (l) =>
                l.taskId.equals(log.taskId) &
                l.date.equals(log.date) &
                l.updatedAt.isSmallerOrEqualValue(log.updatedAt),
          ))
          .write(const TaskLogsCompanion(dirty: Value(false)));
    }
  }

  /// Takes back marks the server refused to keep (a group task handed to
  /// someone else), so the phone does not show a tick that exists nowhere else.
  Future<void> deleteLogs(Iterable<TaskLog> refused) async {
    for (final log in refused) {
      await (delete(taskLogs)..where(
            (l) => l.taskId.equals(log.taskId) & l.date.equals(log.date),
          ))
          .go();
    }
  }

  /// Mirrors the server's answer to "which groups am I in, and with whom".
  ///
  /// Whole, not merged: the lists are small and the server is the only writer.
  /// A group missing from [groups] is one this account left, was removed from,
  /// or that was deleted — the server tells all three the same way, by no
  /// longer showing it — so its tasks come off the device, with no tombstones:
  /// the deletion is not news to anyone.
  Future<void> replaceGroups(
    List<TaskGroupsCompanion> groups,
    List<GroupMembersCompanion> members,
  ) {
    return transaction(() async {
      // Every pull brings the snapshot, nearly always the one already held.
      // Rewriting it would make every screen watching the groups repaint for
      // nothing, so the tables are touched only when something differs.
      final sameGroups = _sameSet(
        [for (final g in await getGroups()) (g.uid, g.name, g.ownerUid)],
        [for (final g in groups) (g.uid.value, g.name.value, g.ownerUid.value)],
      );
      final sameMembers = _sameSet(
        [
          for (final m in await getGroupMembers())
            (m.groupUid, m.userUid, m.displayName, m.avatarUrl),
        ],
        [
          for (final m in members)
            (
              m.groupUid.value,
              m.userUid.value,
              m.displayName.value,
              m.avatarUrl.value,
            ),
        ],
      );
      if (!sameGroups || !sameMembers) {
        await delete(groupMembers).go();
        await delete(taskGroups).go();
        for (final group in groups) {
          await into(taskGroups).insert(group);
        }
        for (final member in members) {
          await into(groupMembers).insert(member);
        }
      }

      final kept = [for (final group in groups) group.uid.value];
      final gone = await (select(
        tasks,
      )..where((t) => t.groupUid.isNotNull() & t.groupUid.isNotIn(kept))).get();
      for (final task in gone) {
        await _deleteCascade(task.id);
      }
    });
  }

  static bool _sameSet<T>(List<T> a, List<T> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  /// The group of a task, or null when this device has no such group.
  Future<TaskGroup?> groupByUid(String uid) =>
      (select(taskGroups)..where((g) => g.uid.equals(uid))).getSingleOrNull();

  /// Whether [userUid] may edit [task]: any personal task, and a group task
  /// only as its author or the group's owner — what the server allows, see
  /// BACKEND_PLAN.md §4.3.
  Future<bool> canEditTask(Task task, String userUid) async {
    final groupUid = task.groupUid;
    return canEditTaskAs(
      task,
      userUid,
      groupOwnerUid: groupUid == null
          ? null
          : (await groupByUid(groupUid))?.ownerUid,
    );
  }

  /// Another member's mark on a group task, as the server has it.
  Future<void> applyGroupMark({
    required int taskId,
    required String userUid,
    required DateTime date,
    required bool completed,
  }) => into(groupMarks).insertOnConflictUpdate(
    GroupMarksCompanion.insert(
      taskId: taskId,
      userUid: userUid,
      date: dayOf(date),
      completed: Value(completed),
    ),
  );

  /// Removes a task the server says is gone, subtasks and logs and all.
  ///
  /// Not [deleteTaskCascade]: that one writes tombstones, and a tombstone for a
  /// deletion this device is merely *learning about* would be sent back as news.
  /// Returns whether there was anything to remove.
  Future<bool> deleteTaskByUid(String uid) {
    return transaction(() async {
      final task = await taskByUid(uid);
      if (task == null) return false;
      await _deleteCascade(task.id);
      return true;
    });
  }
}
