import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/recurrence.dart';

/// Monday-first short weekday names, `DateTime.weekday - 1` indexed.
const weekdayShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// The repeat rule in a few words, as a habit row prints it under the title:
/// "Каждый день", "Пн, Ср, Пт", "Каждые 4 дня", "Каждый месяц: 1, 15".
///
/// Short on purpose — the form's own summary spells the rule out in full; this
/// one has a 12px line to fit on. Reads the same fields [matchesRepeatRule]
/// does, including its fallbacks: no mask means the anchor's weekday or day.
String habitRuleLabel(Task task) {
  final n = (task.repeatInterval ?? 1) < 1 ? 1 : (task.repeatInterval ?? 1);
  final anchor = taskAnchorDate(task);
  switch (task.repeatType) {
    case null:
      return '';
    case RepeatType.daily:
      return 'Каждый день';
    case RepeatType.custom:
      return n == 1
          ? 'Каждый день'
          : 'Каждые $n ${pluralRu(n, 'день', 'дня', 'дней')}';
    case RepeatType.weekly:
      final days = daysFromMask(task.repeatDaysMask, maxDay: 7);
      final picked = days.isEmpty ? {anchor.weekday} : days;
      final names = (picked.toList()..sort())
          .map((d) => weekdayShort[d - 1])
          .join(', ');
      if (n == 1) return picked.length == 7 ? 'Каждый день' : names;
      return 'Каждые $n ${pluralRu(n, 'неделю', 'недели', 'недель')}: $names';
    case RepeatType.monthly:
      final days = daysFromMask(task.repeatDaysMask, maxDay: 31);
      final picked = (days.isEmpty ? {anchor.day} : days).toList()..sort();
      final every = n == 1
          ? 'Каждый месяц'
          : 'Каждые $n ${pluralRu(n, 'месяц', 'месяца', 'месяцев')}';
      return '$every: ${picked.join(', ')}';
  }
}

/// "07:30" from minutes past midnight.
String clockLabel(int minutes) {
  final m = minutes % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// The line under a habit's title: the rule, then its time, then — for a timer —
/// how long it runs. "Пн, Ср, Пт · 30 мин", "Каждый день · 07:30".
///
/// A "Значение" task has no rule; its line is when it was last done, or since
/// when it is watched if it never was.
String habitSubtitle(Task task, {DateTime? lastDone}) {
  if (isValueTask(task)) {
    final date = DateFormat('d MMM', 'ru_RU');
    return lastDone == null
        ? 'Слежу с ${date.format(taskAnchorDate(task))}'
        : date.format(lastDone);
  }
  final duration = task.targetDurationMinutes;
  return [
    habitRuleLabel(task),
    if (task.scheduledTimeMinutes != null)
      clockLabel(task.scheduledTimeMinutes!),
    if (task.trackingMode == TrackingMode.timer &&
        duration != null &&
        duration > 0)
      '$duration мин',
  ].where((part) => part.isNotEmpty).join(' · ');
}
