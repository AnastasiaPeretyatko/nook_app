import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/last_done.dart';
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

  /// The instant it should fire — the occurrence's own time less the lead the
  /// user asked for, so it may fall on the day before an early-morning task.
  final DateTime at;

  /// "Медитация в 22:00" — the task's name and the time it is for.
  final String title;

  /// The second line: a habit's streak ("Серия 4 дня — не прерывай её"). Null
  /// for a one-off task and for a habit with no streak worth naming.
  final String? body;

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
///
/// [leadMinutes] moves every reminder that far ahead of the time its task
/// carries. The task's own time still names the occurrence and still is what the
/// title says; only the firing instant moves.
///
/// [logs] should be the whole history, not just the window: a streak is counted
/// back from the occurrence for as far as the marks go.
List<TaskReminder> taskRemindersFor({
  required List<Task> tasks,
  required List<TaskLog> logs,
  required DateTime now,
  int horizonDays = defaultReminderHorizonDays,
  int limit = maxScheduledReminders,
  int leadMinutes = 0,
}) {
  final completedDays = <(int, DateTime)>{
    for (final log in logs)
      if (log.completed) (log.taskId, _dateOnly(log.date)),
  };

  final today = _dateOnly(now);
  final lead = leadMinutes < 0 ? 0 : leadMinutes;
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

      final at = day.add(Duration(minutes: startMinutes - lead));
      // Whatever is behind the clock is gone; firing it now would be noise.
      // Judged on the firing instant and not on the task's own time, so a lead
      // that has already elapsed drops the reminder rather than pulling it
      // forward to this moment — the list is recomputed on every task edit and
      // every tick, and a reminder pinned to "now" would fire again on each of
      // them.
      if (!at.isAfter(now)) continue;

      reminders.add(
        TaskReminder(
          taskId: task.id,
          day: day,
          at: at,
          title: _title(task.title, startMinutes, task.endTimeMinutes),
          body: task.repeatType == null
              ? null
              : _streakBody(_streakBefore(task, day, completedDays)),
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

String _title(String name, int startMinutes, int? endMinutes) {
  final start = _fmtTime(startMinutes);
  return endMinutes == null || endMinutes <= startMinutes
      ? '$name в $start'
      : '$name с $start до ${_fmtTime(endMinutes)}';
}

/// How many scheduled occurrences of [task] in a row were marked, counting back
/// from the one before [day]. Days the rule skips neither add nor break it.
///
/// Counted from what is marked **now**: an occurrence between today and [day]
/// that is not marked yet ends the streak, so a reminder scheduled for later in
/// the week names no streak until the days before it are done — better silent
/// than promising a streak that may not survive. The list is recomputed on
/// every tick, which is when it fills in.
int _streakBefore(Task task, DateTime day, Set<(int, DateTime)> done) {
  final first = taskAnchorDate(task);
  var count = 0;
  var d = DateTime(day.year, day.month, day.day - 1);
  // The ceiling keeps a habit that is hardly ever scheduled from walking years.
  for (var i = 0; i < 400 && !d.isBefore(first); i++) {
    if (isTaskScheduledOn(task, d)) {
      if (!done.contains((task.id, d))) break;
      count++;
    }
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return count;
}

/// Only a streak of two or more is worth a line: "Серия 1 день" says nothing.
String? _streakBody(int streak) => streak < 2
    ? null
    : 'Серия $streak ${pluralRu(streak, 'день', 'дня', 'дней')} — не прерывай её';

String _fmtTime(int minutes) {
  final normalized = minutes % (24 * 60);
  final h = (normalized ~/ 60).toString().padLeft(2, '0');
  final m = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
