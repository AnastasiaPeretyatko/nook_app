import 'package:todo_app/database/app_database.dart';

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

/// A member's name for the screens; someone who never published one is still
/// somebody.
String memberName(GroupMember? member) {
  final name = member?.displayName?.trim();
  return name == null || name.isEmpty ? 'Участник' : name;
}
