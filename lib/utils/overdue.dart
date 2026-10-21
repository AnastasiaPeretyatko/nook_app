import 'package:todo_app/database/app_database.dart';

/// Whether [task] is a one-off task whose day has gone by with it still unticked.
///
/// Derived and never stored, and split out here because the number is read in
/// two places — the "Просроченные" section of the tasks tab and the badge on the
/// nav bar — and two places counting for themselves is two places that can
/// disagree.
///
/// What is **not** overdue:
///
/// * a habit (`repeatType != null`) — a day a habit was not marked is a `missed`
///   square in its own grid, not a task running late, and a daily habit would
///   otherwise put every past day it missed into the count;
/// * a "Значение" task — its start date is when the watching began, not a due
///   day, so it can never be late;
/// * a subtask (`parentId != null`) — its parent's tile reports it, and counting
///   both would count the same work twice;
/// * a task with no date — that is the backlog ("Без даты"); a task nobody ever
///   put a day on cannot have missed one;
/// * a ticked one — a task completed after its day moves to "Выполненные" the
///   moment it is ticked, so it is not late in the tab;
/// * today's, and everything still ahead.
///
/// [completed] is the tick for the day the task logs against — its start date —
/// which the caller looks up, the log living in another table.
bool isTaskOverdue(
  Task task, {
  required bool completed,
  required DateTime today,
}) {
  if (task.repeatType != null || task.parentId != null) return false;
  if (task.trackingMode == TrackingMode.value) return false;
  if (task.status != TaskStatus.active) return false;
  if (completed) return false;

  final startDate = task.startDate;
  if (startDate == null) return false;

  final start = DateTime(startDate.year, startDate.month, startDate.day);
  return start.isBefore(DateTime(today.year, today.month, today.day));
}
