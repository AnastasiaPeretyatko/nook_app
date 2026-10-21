import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/home_widget/today_payload.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/tracking.dart';
import 'package:todo_app/utils/week.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/habit_history_stats.dart';
import 'package:todo_app/widgets/habits/habit_week_stats.dart';

/// What the two habit widgets draw — "привычка с неделей" and the row of habit
/// circles — as plain data, in the same shape and for the same reasons as
/// [TodayWidgetPayload]: a week of days keyed by date (so midnight costs
/// nothing), both palettes, a version.
///
/// One payload for both widgets, because they show the same thing — a habit, its
/// state today, and its week — and differ only in how much of it they draw.
class HabitsWidgetPayload {
  const HabitsWidgetPayload({
    required this.days,
    required this.light,
    required this.dark,
    required this.mode,
    required this.weekStart,
  });

  final List<HabitsDay> days;

  /// The weekday the strips start on ([DateTime.monday] or [DateTime.sunday]),
  /// so the widget can letter the columns "Пн … Вс" or "Вс … Сб".
  final int weekStart;
  final WidgetPalette light;
  final WidgetPalette dark;
  final String mode;

  String encode() => jsonEncode({
    'version': payloadVersion,
    'mode': mode,
    'weekStart': weekStart,
    'palettes': {'light': light.toJson(), 'dark': dark.toJson()},
    'days': [for (final day in days) day.toJson()],
  });

  /// Read by `HabitWeekWidgetProvider` and `HabitStripWidgetProvider`.
  static const payloadVersion = 1;
}

class HabitsDay {
  const HabitsDay({required this.date, required this.habits});

  final DateTime date;

  /// Every active habit, due today or not, in the order the lists draw them.
  /// The strip keeps the `due` ones; the week widget cycles through all.
  final List<WidgetHabit> habits;

  Map<String, Object?> toJson() => {
    'date': DateFormat('yyyy-MM-dd').format(date),
    'habits': [for (final habit in habits) habit.toJson()],
  };
}

class WidgetHabit {
  const WidgetHabit({
    required this.id,
    required this.title,
    required this.color,
    required this.checkInk,
    required this.due,
    required this.done,
    required this.kind,
    required this.count,
    required this.target,
    required this.subtitle,
    required this.week,
  });

  final int id;
  final String title;
  final int color;
  final int checkInk;

  /// The rule lands on this day.
  final bool due;
  final bool done;

  /// `checkbox`, `counter` or `timer`. A press ticks the first, adds one to the
  /// second and — for now — opens the app for the third: a run needs the
  /// app's own notification, which a background isolate cannot post.
  final String kind;

  /// A counter's tally today and its target, null for any other kind.
  final int? count;
  final int? target;

  /// "серия 4 дня · лучшая 23" — worded here, where Russian plurals are cheap.
  final String subtitle;

  /// Seven letters, one per day of the week the day falls in, in the order the
  /// app draws it: `d` done (on time or late), `m` missed, `t` today still open,
  /// `p` partial progress, `f` a day ahead, `o` nothing planned.
  final String week;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'color': color,
    'checkInk': checkInk,
    'due': due,
    'done': done,
    'kind': kind,
    if (count != null) 'count': count,
    if (target != null) 'target': target,
    'sub': subtitle,
    'week': week,
  };
}

/// Builds the payload for the coming [horizonDays] days.
///
/// Every number goes through [habitWeek] / [HabitHistory], the same code the
/// habits tab and the habit's page run, so the widget cannot disagree with them
/// about a day. [logs] are every log there is: a streak reaches back to the
/// habit's first day.
HabitsWidgetPayload buildHabitsWidgetPayload({
  required List<Task> tasks,
  required List<TaskLog> logs,
  required DateTime now,
  required WidgetPalette light,
  required WidgetPalette dark,
  required String mode,
  required int weekStart,
  required int graceMinutes,
  required bool todayStaysOpen,
  int horizonDays = todayWidgetHorizonDays,
}) {
  final habits = [
    for (final task in tasks)
      if (task.parentId == null &&
          task.status == TaskStatus.active &&
          task.repeatType != null)
        task,
  ]..sort(byTimeThenTitle);

  final logsByTask = <int, List<TaskLog>>{};
  for (final log in logs) {
    logsByTask.putIfAbsent(log.taskId, () => []).add(log);
  }

  final today = DateTime(now.year, now.month, now.day);
  final days = <HabitsDay>[];
  for (var offset = 0; offset < horizonDays; offset++) {
    final day = DateTime(today.year, today.month, today.day + offset);
    final first = startOfWeek(day, weekStart);
    final week = [
      for (var i = 0; i < 7; i++)
        DateTime(first.year, first.month, first.day + i),
    ];

    days.add(
      HabitsDay(
        date: day,
        habits: [
          for (final task in habits)
            _habitFor(
              task,
              logsByTask[task.id] ?? const [],
              day: day,
              week: week,
              graceMinutes: graceMinutes,
              todayStaysOpen: todayStaysOpen,
            ),
        ],
      ),
    );
  }
  return HabitsWidgetPayload(
    days: days,
    light: light,
    dark: dark,
    mode: mode,
    weekStart: weekStart,
  );
}

WidgetHabit _habitFor(
  Task task,
  List<TaskLog> logs, {
  required DateTime day,
  required List<DateTime> week,
  required int graceMinutes,
  required bool todayStaysOpen,
}) {
  final weekCells = habitWeek(
    task: task,
    days: week,
    logs: logs,
    today: day,
    graceMinutes: graceMinutes,
    todayStaysOpen: todayStaysOpen,
  );
  final streaks = HabitHistory.of(
    task: task,
    logs: logs,
    today: day,
    graceMinutes: graceMinutes,
    todayStaysOpen: todayStaysOpen,
  ).streaks;
  final color = task.colorValue != null
      ? Color(task.colorValue!)
      : ColorPickerRow.colors.first;
  final todayIndex = week.indexOf(day);

  return WidgetHabit(
    id: task.id,
    title: task.title,
    color: color.toARGB32(),
    checkInk: onBrandFill(color).toARGB32(),
    due: isTaskScheduledOn(task, day),
    done: switch (weekCells.cells[todayIndex]) {
      WeekCell.onTime || WeekCell.late => true,
      _ => false,
    },
    kind: task.trackingMode.name,
    count: task.trackingMode == TrackingMode.counter
        ? _countOn(logs, day)
        : null,
    target: task.trackingMode == TrackingMode.counter
        ? counterTarget(task)
        : null,
    subtitle: _subtitle(streaks.current, streaks.best),
    week: weekCells.cells.map(_letter).join(),
  );
}

int _countOn(List<TaskLog> logs, DateTime day) {
  for (final log in logs) {
    if (DateTime(log.date.year, log.date.month, log.date.day) == day) {
      return log.value?.round() ?? 0;
    }
  }
  return 0;
}

String _letter(WeekCell cell) => switch (cell) {
  WeekCell.onTime || WeekCell.late => 'd',
  WeekCell.missed => 'm',
  WeekCell.pending => 't',
  WeekCell.partial => 'p',
  WeekCell.future => 'f',
  WeekCell.off => 'o',
};

String _subtitle(int streak, int best) {
  if (best == 0) return 'пока без серии';
  if (streak == 0) return 'лучшая серия $best';
  final current = 'серия ${_days(streak)}';
  return best > streak ? '$current · лучшая $best' : current;
}

/// "1 день", "4 дня", "11 дней".
String _days(int n) {
  final mod100 = n % 100, mod10 = n % 10;
  final word = mod100 >= 11 && mod100 <= 14
      ? 'дней'
      : mod10 == 1
      ? 'день'
      : mod10 >= 2 && mod10 <= 4
      ? 'дня'
      : 'дней';
  return '$n $word';
}
