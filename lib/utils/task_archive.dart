import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';

/// Whether a one-off task has moved out of the "Задачи" tab and into the
/// archive.
///
/// Nothing is written when that happens — there is no "archived on" column and
/// no status change — so the rule is read, not stored, and both screens have to
/// read it the same way: the tab hides what this returns true for, the archive
/// page shows exactly those. Keeping it derived is what makes the archive
/// harmless: the task row and its logs are untouched, so the timeline still
/// draws the task on its day. Deleting is the destructive counterpart.
///
/// A task archives once the day its tick is logged against — [taskAnchorDate],
/// the day it was scheduled for — is behind [today]:
///
/// * ticked for today, it stays in the tab for the rest of the day and turns up
///   in the archive tomorrow;
/// * ticked for a day already gone (an overdue task, completed late) it moves
///   there the moment it is ticked, because that day is already behind us;
/// * ticked for a day still ahead, it waits in the tab until that day passes.
///
/// Habits never archive: a repeating task has no last occurrence to be done
/// with. Neither does a "Значение" task, which is ticked again and again by
/// design — only the user's own "Архив" puts one away.
bool isTaskArchived(
  Task task, {
  required bool completed,
  required DateTime today,
}) {
  if (!completed || task.repeatType != null) return false;
  if (task.trackingMode == TrackingMode.value) return false;
  final day = DateTime(today.year, today.month, today.day);
  return taskAnchorDate(task).isBefore(day);
}
