import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/utils/overdue.dart';
import 'package:todo_app/utils/task_audience.dart';
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

final cycleDaoProvider = Provider<CycleDao>((ref) {
  return ref.watch(databaseProvider).cycleDao;
});

/// Every day of the cycle that has a row — marked or taken back. The Cycle tab
/// and the sync nudge watch this one list.
final cycleDaysProvider = StreamProvider<List<CycleDay>>((ref) {
  return ref.watch(cycleDaoProvider).watchAll();
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

/// The signed-in account's id — the `me` of [taskAudience]. A provider of its
/// own so a test can be someone without signing in.
final myUidProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);

/// The root tasks that are **mine** — see [TaskAudience.mine]. What the habits
/// grid, the calendar, the reminders and the home-screen widget read, so none
/// of them shows, reminds of or counts another member's task. A task handed to
/// someone else is on [delegatedTasksProvider] instead.
final rootTasksProvider = StreamProvider<List<Task>>((ref) {
  final me = ref.watch(myUidProvider);
  return ref
      .watch(tasksDaoProvider)
      .watchRootTasks()
      .map(
        (tasks) => [
          for (final t in tasks)
            if (isMyTask(t, me)) t,
        ],
      );
});

/// Group tasks I wrote and handed to another member. Derived from
/// [allTasksProvider] rather than a query of its own, so a screen that is handed
/// its tasks gets these from the same place.
final delegatedTasksProvider = Provider<List<Task>>((ref) {
  final me = ref.watch(myUidProvider);
  return [
    for (final t in ref.watch(allTasksProvider).valueOrNull ?? const <Task>[])
      if (t.parentId == null && taskAudience(t, me) == TaskAudience.delegated)
        t,
  ];
});

/// The groups this account is in, as the last sync mirrored them.
final groupsProvider = StreamProvider<List<TaskGroup>>((ref) {
  return ref.watch(tasksDaoProvider).watchGroups();
});

/// Every member of every group, me included.
final groupMembersProvider = StreamProvider<List<GroupMember>>((ref) {
  return ref.watch(tasksDaoProvider).watchGroupMembers();
});

/// The other members' marks on group tasks.
final groupMarksProvider = StreamProvider<List<GroupMark>>((ref) {
  return ref.watch(tasksDaoProvider).watchGroupMarks();
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

/// The one-off tasks whose day has passed with them still unticked — the rule is
/// [isTaskOverdue] and lives there, not here.
///
/// Derived rather than queried: whether a task is done is a row in `task_logs`,
/// so the answer needs both streams — and both are already open for the screens
/// that show the tasks themselves, so this costs no query of its own.
///
/// Empty until **both** streams have a value. Treating "no logs yet" as "nothing
/// is ticked" would count a task that is in fact done, and the badge reading
/// this would flash a number for one frame and then drop it on every launch.
///
/// **Today is read while this is computed.** Nothing recomputes it when the
/// clock passes midnight: an app left open overnight keeps yesterday's answer
/// until something else rebuilds this. `TasksList` has always worked that way —
/// it takes `DateTime.now()` in `build` — and the badge inherits it rather than
/// growing a timer of its own.
final overdueTasksProvider = Provider<List<Task>>((ref) {
  final tasksAsync = ref.watch(allTasksProvider);
  final logsAsync = ref.watch(allLogsProvider);
  if (!tasksAsync.hasValue || !logsAsync.hasValue) return const [];

  final today = DateTime.now();
  // Every (task, day) that carries a tick, so the tasks below are one set lookup
  // each rather than a scan of the whole log table.
  final completedOn = <(int, DateTime)>{
    for (final log in logsAsync.requireValue)
      if (log.completed)
        (log.taskId, DateTime(log.date.year, log.date.month, log.date.day)),
  };

  // The tick sits on the day the task is scheduled for — its start date, the
  // same key `TasksList` reads. A task without one is never overdue, so there is
  // nothing to look up for it.
  bool isCompleted(Task task) {
    final startDate = task.startDate;
    if (startDate == null) return false;
    return completedOn.contains((
      task.id,
      DateTime(startDate.year, startDate.month, startDate.day),
    ));
  }

  final me = ref.watch(myUidProvider);
  return tasksAsync.requireValue
      .where(
        (task) =>
            isMyTask(task, me) &&
            isTaskOverdue(task, completed: isCompleted(task), today: today),
      )
      .toList();
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
