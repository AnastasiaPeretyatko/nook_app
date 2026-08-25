import 'package:drift/drift.dart';
import '../app_database.dart';

part 'tasks_dao.g.dart';

@DriftAccessor(tables: [Tasks, TaskLogs, TaskSessions])
class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
  TasksDao(super.db);

  Stream<List<Task>> watchAllTasks() => select(tasks).watch();

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

  Future<int> insertTask(TasksCompanion task) => into(tasks).insert(task);

  Future<bool> updateTask(TasksCompanion task) => update(tasks).replace(task);

  /// Updates only the provided columns of the task with [id]. Unlike
  /// [updateTask], absent values are left untouched, while explicit
  /// `Value(null)` clears the corresponding nullable column.
  Future<int> updateTaskById(int id, TasksCompanion task) =>
      (update(tasks)..where((t) => t.id.equals(id))).write(task);

  /// Moves a task in or out of the archive. Only the status is written, so the
  /// logs, sessions and subtasks of an archived habit all survive to be
  /// restored — unlike [deleteTaskCascade], which is the destructive one.
  Future<int> setTaskStatus(int id, TaskStatus status) => updateTaskById(
    id,
    TasksCompanion(status: Value(status), updatedAt: Value(DateTime.now())),
  );

  Future<int> deleteTask(int id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  /// Deletes the task and everything attached to it: its direct subtasks and
  /// all logs/sessions of both the task and those subtasks.
  Future<void> deleteTaskCascade(int id) async {
    await transaction(() async {
      final subtaskIds =
          await (selectOnly(tasks)
                ..addColumns([tasks.id])
                ..where(tasks.parentId.equals(id)))
              .map((row) => row.read(tasks.id)!)
              .get();
      final affectedIds = [id, ...subtaskIds];

      await (delete(taskLogs)..where((l) => l.taskId.isIn(affectedIds))).go();
      await (delete(
        taskSessions,
      )..where((s) => s.taskId.isIn(affectedIds))).go();
      await (delete(tasks)..where((t) => t.parentId.equals(id))).go();
      await (delete(tasks)..where((t) => t.id.equals(id))).go();
    });
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
      await into(tasks).insert(
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

  Future<int> upsertLog(TaskLogsCompanion log) =>
      into(taskLogs).insertOnConflictUpdate(log);

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

  Future<TaskLog?> getLogForDate(int taskId, DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
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
  Future<void> setLog(
    int taskId,
    DateTime date, {
    double? value,
    bool? completed,
  }) async {
    final existing = await getLogForDate(taskId, date);
    if (existing == null) {
      await into(taskLogs).insert(
        TaskLogsCompanion.insert(
          taskId: taskId,
          date: date,
          completed: Value(completed ?? false),
          value: value != null ? Value(value) : const Value.absent(),
        ),
      );
    } else {
      await (update(taskLogs)..where((l) => l.id.equals(existing.id))).write(
        TaskLogsCompanion(
          value: value != null ? Value(value) : const Value.absent(),
          completed: completed != null
              ? Value(completed)
              : const Value.absent(),
        ),
      );
    }
  }

  /// Adds 1 to the counter log for [taskId] on [date], marking it completed
  /// once the running count reaches [target].
  Future<void> incrementCounter(
    int taskId,
    DateTime date,
    double target,
  ) async {
    final existing = await getLogForDate(taskId, date);
    final next = (existing?.value ?? 0) + 1;
    final completed = target > 0 && next >= target;
    await setLog(taskId, date, value: next, completed: completed);
  }

  Future<void> toggleCompletion(int taskId, DateTime date) async {
    final existing = await getLogForDate(taskId, date);
    if (existing == null) {
      await into(taskLogs).insert(
        TaskLogsCompanion.insert(
          taskId: taskId,
          date: date,
          completed: const Value(true),
        ),
      );
    } else {
      await (update(taskLogs)..where((l) => l.id.equals(existing.id))).write(
        TaskLogsCompanion(completed: Value(!existing.completed)),
      );
    }
  }
}
