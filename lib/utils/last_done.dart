import 'package:todo_app/database/app_database.dart';

/// Whether [task] is a "Значение" task: no schedule, no time, no reminder — just
/// a record of when the thing was last done.
///
/// A mode and not a column of its own, so it rides on `tracking_mode`, which the
/// server already accepts and the sync already carries.
bool isValueTask(Task task) => task.trackingMode == TrackingMode.value;

/// The most recent day each task was marked done on, by task id.
///
/// A task with no completed log is simply absent. Only `completed` rows count: a
/// mark that was taken back stays in the table as `completed = false` (a log is
/// never deleted on its own — the server would send it straight back), and it
/// must not read as a day the thing was done.
Map<int, DateTime> lastDoneByTask(Iterable<TaskLog> logs) {
  final latest = <int, DateTime>{};
  for (final log in logs) {
    if (!log.completed) continue;
    final day = DateTime(log.date.year, log.date.month, log.date.day);
    final seen = latest[log.taskId];
    if (seen == null || day.isAfter(seen)) latest[log.taskId] = day;
  }
  return latest;
}

/// Whole calendar days from [from] to [today], never negative.
///
/// Counted between UTC dates and not with `difference(...).inDays` on local
/// midnights: across a daylight-saving change the gap between two local
/// midnights is 23 or 25 hours, and `inDays` rounds that down to a day short.
int daysSince(DateTime from, DateTime today) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(today.year, today.month, today.day);
  final days = b.difference(a).inDays;
  return days < 0 ? 0 : days;
}

/// How long ago a "Значение" task was last done, as the card prints it.
///
/// [lastDone] is null for a task that was never marked; there is no honest
/// number for it — the start date says when tracking began, not when the thing
/// was last done — so it reads as "no marks" rather than as a count of days.
String lastDoneLabel(DateTime? lastDone, {required DateTime today}) {
  if (lastDone == null) return 'Нет отметок';
  final days = daysSince(lastDone, today);
  return switch (days) {
    0 => 'Сегодня',
    1 => 'Вчера',
    _ => '$days ${pluralRu(days, 'день', 'дня', 'дней')} назад',
  };
}

/// The marked days of one task, newest first. What the sheet lists so a wrong
/// tap can be taken back.
List<DateTime> markedDaysNewestFirst(Iterable<TaskLog> logs, int taskId) {
  final days = <DateTime>{
    for (final log in logs)
      if (log.taskId == taskId && log.completed)
        DateTime(log.date.year, log.date.month, log.date.day),
  }.toList()..sort((a, b) => b.compareTo(a));
  return days;
}

/// Russian plural form for [n]: 1 день, 2 дня, 5 дней.
String pluralRu(int n, String one, String few, String many) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  final mod10 = n % 10;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}
