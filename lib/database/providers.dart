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

final diaryDaoProvider = Provider<DiaryDao>((ref) {
  return ref.watch(databaseProvider).diaryDao;
});

/// Every diary entry, newest touched first. The diary's four tabs filter this
/// one list rather than opening a query each.
final diaryEntriesProvider = StreamProvider<List<DiaryEntry>>((ref) {
  return ref.watch(diaryDaoProvider).watchEntries();
});

/// One entry. Null after it has been deleted, which is how the view screen
/// knows to close itself.
final diaryEntryProvider = StreamProvider.family<DiaryEntry?, int>((ref, id) {
  return ref.watch(diaryDaoProvider).watchEntry(id);
});

/// The mood catalogue — every mood there is, oldest first, so the eight the app
/// seeded keep the order the design lists them in. Watched by the picker, and by
/// nothing else: a note's own moods come from [entryMoodsProvider].
final noteMoodsProvider = StreamProvider<List<NoteMood>>((ref) {
  return ref.watch(diaryDaoProvider).watchMoods();
});

/// The tag catalogue. Same shape as [noteMoodsProvider].
final noteTagsProvider = StreamProvider<List<NoteTag>>((ref) {
  return ref.watch(diaryDaoProvider).watchTags();
});

/// The moods of one note, live. A family and not a filter over the whole join
/// table: only the screen showing a note ever asks, and it asks about one.
final entryMoodsProvider = StreamProvider.family<List<NoteMood>, int>((
  ref,
  entryId,
) {
  return ref.watch(diaryDaoProvider).watchMoodsForEntry(entryId);
});

/// Every note's moods and tags in one map each, keyed by note id.
///
/// What the diary's list watches: the family providers above are for **one**
/// note on screen, and a list of cards asking for them would open a query per
/// card and never close it. These are two queries for any number of notes.
final moodsByEntryProvider = StreamProvider<Map<int, List<NoteMood>>>((ref) {
  return ref.watch(diaryDaoProvider).watchMoodsByEntry();
});

final tagsByEntryProvider = StreamProvider<Map<int, List<NoteTag>>>((ref) {
  return ref.watch(diaryDaoProvider).watchTagsByEntry();
});

/// The tags of one note, live.
final entryTagsProvider = StreamProvider.family<List<NoteTag>, int>((
  ref,
  entryId,
) {
  return ref.watch(diaryDaoProvider).watchTagsForEntry(entryId);
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
