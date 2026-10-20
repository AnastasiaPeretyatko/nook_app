import 'package:todo_app/database/app_database.dart';

/// The first day of the week [day] falls in, for a week that starts on
/// [firstWeekday] ([DateTime.monday] or [DateTime.sunday]). Date only.
DateTime startOfWeek(DateTime day, int firstWeekday) {
  final back = (day.weekday - firstWeekday + 7) % 7;
  return DateTime(day.year, day.month, day.day - back);
}

/// The days of [logs] (this task's) that were ticked later than the task's own
/// time plus [graceMinutes].
///
/// Only a task with a time can be late, and only a tick that knows its moment:
/// a mark made before schema v17 carries no `completedAt` and is simply "done".
/// A tick made today for a day already gone is late too — it was made after the
/// time — which is what "when did you actually do it" asks.
Set<DateTime> lateDays(Task task, Iterable<TaskLog> logs, int graceMinutes) {
  final planned = task.scheduledTimeMinutes;
  if (planned == null) return const {};
  final late = <DateTime>{};
  for (final log in logs) {
    final at = log.completedAt;
    if (!log.completed || at == null || log.taskId != task.id) continue;
    final day = DateTime(log.date.year, log.date.month, log.date.day);
    final due = DateTime(
      day.year,
      day.month,
      day.day,
      0,
      planned + graceMinutes,
    );
    if (at.isAfter(due)) late.add(day);
  }
  return late;
}
