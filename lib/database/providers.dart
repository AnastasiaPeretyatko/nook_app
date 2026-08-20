import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final tasksDaoProvider = Provider<TasksDao>((ref) {
  return ref.watch(databaseProvider).tasksDao;
});

final eventsDaoProvider = Provider<EventsDao>((ref) {
  return ref.watch(databaseProvider).eventsDao;
});

final rootTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(tasksDaoProvider).watchRootTasks();
});

/// Every task, subtasks included. For screens that need both a task and its
/// children in one pass, so they do not open a stream per row.
final allTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(tasksDaoProvider).watchAllTasks();
});

final subtasksProvider = StreamProvider.family<List<Task>, int>((
  ref,
  parentId,
) {
  return ref.watch(tasksDaoProvider).watchSubtasks(parentId);
});

final logsForTaskProvider = StreamProvider.family<List<TaskLog>, int>((
  ref,
  taskId,
) {
  return ref.watch(tasksDaoProvider).watchLogsForTask(taskId);
});

final logsForDateProvider = StreamProvider.family<List<TaskLog>, DateTime>((
  ref,
  date,
) {
  return ref.watch(tasksDaoProvider).watchLogsForDate(date);
});

final allLogsProvider = StreamProvider<List<TaskLog>>((ref) {
  return ref.watch(tasksDaoProvider).watchAllLogs();
});

/// Timer runs going right now — a session that was started and never closed.
/// Screens turn it into "this task has been running since X" and recompute the
/// elapsed time from the clock, so a backgrounded or restarted app picks the
/// run back up where it really is.
final openSessionsProvider = StreamProvider<List<TaskSession>>((ref) {
  return ref.watch(tasksDaoProvider).watchOpenSessions();
});

class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

final logsBetweenProvider = StreamProvider.family<List<TaskLog>, DateRange>((
  ref,
  range,
) {
  return ref.watch(tasksDaoProvider).watchLogsBetween(range.start, range.end);
});
