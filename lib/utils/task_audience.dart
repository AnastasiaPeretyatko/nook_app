import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';

/// Whose a task is, from where [me] stands — the one rule every screen asks.
///
/// Derived, never stored, and kept apart for the reason [isTaskOverdue] is: the
/// day screen, the reminders, the overdue badge and the home-screen widget all
/// read it, and each must give the same answer.
enum TaskAudience {
  /// On my day: personal, handed to me, or a group task "for everyone".
  mine,

  /// One I wrote and handed to another member. On my timeline, to see whether
  /// it got done, but not mine to tick, be reminded of or be overdue on.
  delegated,

  /// Someone else's task in a group I am in. Only the group's own screen.
  hidden,
}

/// [me] is null when nobody is signed in: then only what is plainly mine — a
/// personal task, or one for everyone — shows.
TaskAudience taskAudience(Task task, String? me) {
  if (task.groupUid == null) return TaskAudience.mine;
  final assignee = task.assigneeUid;
  if (assignee == null || assignee == me) return TaskAudience.mine;
  if (me != null && task.authorUid == me) return TaskAudience.delegated;
  return TaskAudience.hidden;
}

bool isMyTask(Task task, String? me) =>
    taskAudience(task, me) == TaskAudience.mine;

/// Whether [me] may edit or delete [task]: any personal task; a group task only
/// as its author or as the owner of its group, [groupOwnerUid]. The server
/// enforces the same — see `supabase/005_groups.sql`.
bool canEditTaskAs(Task task, String? me, {String? groupOwnerUid}) {
  if (task.groupUid == null) return true;
  if (me == null) return false;
  return task.authorUid == me || groupOwnerUid == me;
}

/// A group task "for everyone" is one shared task, not one copy per member: the
/// first member to tick it closes it for all.
bool isForEveryone(Task task) =>
    task.groupUid != null && task.assigneeUid == null;

/// [logs] with other members' ticks on shared tasks counted as done.
///
/// A shared task is one-off, so its tick sits on its anchor date. Where another
/// member ticked it and this account has no tick of its own, a stand-in log
/// (`id` -1, never stored or sent) says "done" — which is how every screen that
/// reads logs learns it without a rule of its own. [includes] keeps the stand-ins
/// inside the days the caller asked for.
List<TaskLog> withSharedTicks(
  List<TaskLog> logs,
  Iterable<Task> tasks,
  Iterable<GroupMark> marks, {
  bool Function(DateTime day)? includes,
}) {
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final anchors = {
    for (final t in tasks)
      if (isForEveryone(t)) t.id: day(taskAnchorDate(t)),
  };
  final doneByOthers = <(int, DateTime)>{
    for (final m in marks)
      if (m.completed &&
          anchors[m.taskId] == day(m.date) &&
          (includes?.call(day(m.date)) ?? true))
        (m.taskId, day(m.date)),
  };
  if (doneByOthers.isEmpty) return logs;

  final own = {for (final l in logs) (l.taskId, day(l.date)): l};
  return [
    for (final l in logs)
      if (l.completed || !doneByOthers.contains((l.taskId, day(l.date)))) l,
    for (final (taskId, date) in doneByOthers)
      if (!(own[(taskId, date)]?.completed ?? false))
        TaskLog(
          id: -1,
          taskId: taskId,
          date: date,
          completed: true,
          dirty: false,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
  ];
}

/// Who has done a group task on [day]: the members whose mark there is ticked.
///
/// [doneByMe] comes from this account's own `task_logs`, [marks] from everyone
/// else's — the two tables the device keeps them in.
Set<String> groupTaskDoneBy(
  Task task,
  DateTime day, {
  required String? me,
  required bool doneByMe,
  required Iterable<GroupMark> marks,
}) => {
  if (doneByMe && me != null) me,
  for (final mark in marks)
    if (mark.taskId == task.id &&
        mark.completed &&
        mark.date.year == day.year &&
        mark.date.month == day.month &&
        mark.date.day == day.day)
      mark.userUid,
};

/// What the screens say about a shared task ([isForEveryone]): who closed it, or
/// that it still waits. [done] is the account's own view, shared ticks included.
String sharedTaskStatus(
  Task task,
  DateTime day, {
  required String? me,
  required bool done,
  required Iterable<GroupMark> marks,
  required Iterable<GroupMember> members,
}) {
  final others = groupTaskDoneBy(
    task,
    day,
    me: me,
    doneByMe: false,
    marks: marks,
  );
  if (others.isNotEmpty) {
    final who = members
        .where((m) => m.groupUid == task.groupUid && m.userUid == others.first)
        .firstOrNull;
    return 'выполнено: ${memberName(who)}';
  }
  return done ? 'выполнено: вы' : 'ждёт';
}

/// A member's name for the screens; someone who never published one is still
/// somebody.
String memberName(GroupMember? member) {
  final name = member?.displayName?.trim();
  return name == null || name.isEmpty ? 'Участник' : name;
}
