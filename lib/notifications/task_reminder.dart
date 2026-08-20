import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';

/// A reminder the shade should fire for one occurrence of a task.
///
/// One per task *per day*: a repeating habit at 07:00 earns a separate reminder
/// for every day it lands on inside the window.
class TaskReminder {
  const TaskReminder({
    required this.taskId,
    required this.day,
    required this.at,
    required this.title,
    required this.body,
  });

  final int taskId;

  /// The calendar day this occurrence belongs to, time stripped. Together with
  /// [taskId] it identifies the reminder.
  final DateTime day;

  /// The instant it should fire.
  final DateTime at;
  final String title;
  final String body;

  /// What the reminder would say and when. Compared against an already
  /// scheduled one so a renamed or re-timed task is rescheduled rather than
  /// left showing the old text.
  String get fingerprint => '${at.millisecondsSinceEpoch}|$title|$body';

  @override
  bool operator ==(Object other) =>
      other is TaskReminder &&
      other.taskId == taskId &&
      other.day == day &&
      other.at == at &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(taskId, day, at, title, body);

  @override
  String toString() => 'TaskReminder(task: $taskId, "$title", at: $at)';
}

/// How far ahead reminders are scheduled. Repeating habits have no end, so the
/// window is refreshed whenever anything changes rather than filled once.
const defaultReminderHorizonDays = 7;

/// Ceiling on how many reminders may be pending at once. Android throttles an
/// app that queues alarms without limit, and a handful of daily habits over a
/// week is already dozens. The nearest ones win.
const maxScheduledReminders = 64;

/// The reminders that should be scheduled for the tasks that carry a time.
///
/// Ordered by when they fire. An occurrence is skipped when it has already
/// passed, when its day is marked done, or when the task cannot be acted on —
/// archived, or a subtask, which is reported through its parent and never
/// stands on its own.
List<TaskReminder> taskRemindersFor({
  required List<Task> tasks,
  required List<TaskLog> logs,
  required DateTime now,
  int horizonDays = defaultReminderHorizonDays,
  int limit = maxScheduledReminders,
}) {
  final completedDays = <(int, DateTime)>{
    for (final log in logs)
      if (log.completed) (log.taskId, _dateOnly(log.date)),
  };

  final today = _dateOnly(now);
  final reminders = <TaskReminder>[];

  for (final task in tasks) {
    if (task.parentId != null) continue;
    if (task.status != TaskStatus.active) continue;

    final startMinutes = task.scheduledTimeMinutes;
    if (startMinutes == null) continue;

    for (var offset = 0; offset < horizonDays; offset++) {
      final day = DateTime(today.year, today.month, today.day + offset);
      if (!isTaskScheduledOn(task, day)) continue;
      if (completedDays.contains((task.id, day))) continue;

      final at = day.add(Duration(minutes: startMinutes));
      // Today's earlier occurrences are gone; firing them now would be noise.
      if (!at.isAfter(now)) continue;

      reminders.add(
        TaskReminder(
          taskId: task.id,
          day: day,
          at: at,
          title: task.title,
          body: _body(startMinutes, task.endTimeMinutes),
        ),
      );
    }
  }

  reminders.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.taskId.compareTo(b.taskId);
  });

  return reminders.length <= limit ? reminders : reminders.sublist(0, limit);
}

String _body(int startMinutes, int? endMinutes) {
  final start = _fmtTime(startMinutes);
  if (endMinutes == null || endMinutes <= startMinutes) return start;
  return '$start – ${_fmtTime(endMinutes)}';
}

String _fmtTime(int minutes) {
  final normalized = minutes % (24 * 60);
  final h = (normalized ~/ 60).toString().padLeft(2, '0');
  final m = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
