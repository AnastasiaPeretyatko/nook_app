import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/home_widget/habits_payload.dart';
import 'package:todo_app/home_widget/today_payload.dart';
import 'package:todo_app/main.dart' show buildAppTheme;

final _stamp = DateTime(2026, 1, 1);

/// A Thursday; the week (Monday first) is 24–30 August.
final _today = DateTime(2026, 8, 27);
final _now = DateTime(2026, 8, 27, 9, 30);

Task _habit({
  int id = 1,
  String title = 'Медитация',
  RepeatType repeatType = RepeatType.daily,
  int? repeatDaysMask,
  TrackingMode mode = TrackingMode.checkbox,
  TaskStatus status = TaskStatus.active,
  DateTime? startDate,
}) => Task(
  dirty: false,
  id: id,
  title: title,
  status: status,
  repeatType: repeatType,
  repeatDaysMask: repeatDaysMask,
  trackingMode: mode,
  startDate: startDate ?? DateTime(2026, 8, 1),
  createdAt: _stamp,
  updatedAt: _stamp,
);

TaskLog _log(int taskId, DateTime day, {int id = 1}) => TaskLog(
  dirty: false,
  updatedAt: _stamp,
  id: id,
  taskId: taskId,
  date: day,
  completed: true,
);

final _light = WidgetPalette.fromScheme(
  buildAppTheme(const Color(0xFF8B7CF6), Brightness.light).colorScheme,
);
final _dark = WidgetPalette.fromScheme(
  buildAppTheme(const Color(0xFF8B7CF6), Brightness.dark).colorScheme,
);

HabitsWidgetPayload _payload(
  List<Task> tasks, [
  List<TaskLog> logs = const [],
]) => buildHabitsWidgetPayload(
  tasks: tasks,
  logs: logs,
  now: _now,
  light: _light,
  dark: _dark,
  mode: 'system',
  weekStart: DateTime.monday,
  graceMinutes: 15,
  todayStaysOpen: true,
);

void main() {
  test('the week reads Mon–Sun: done, missed, today open, days ahead', () {
    final payload = _payload(
      [_habit()],
      [_log(1, DateTime(2026, 8, 24)), _log(1, DateTime(2026, 8, 26), id: 2)],
    );

    final habit = payload.days.first.habits.single;
    // Mon done, Tue missed, Wed done, Thu (today) open, Fri–Sun ahead.
    expect(habit.week, 'dmdtfff');
    expect(habit.due, isTrue);
    expect(habit.done, isFalse);
  });

  test('ticking today marks it done and shows the streak', () {
    final payload = _payload(
      [_habit()],
      [
        _log(1, DateTime(2026, 8, 25)),
        _log(1, DateTime(2026, 8, 26), id: 2),
        _log(1, _today, id: 3),
      ],
    );

    final habit = payload.days.first.habits.single;
    expect(habit.done, isTrue);
    expect(habit.week[3], 'd');
    expect(habit.subtitle, 'серия 3 дня');
    expect(habit.streak, 3);
    expect(habit.streakWord, 'дня');
    // The 2×2 widget reads these two straight from the JSON.
    final json = jsonDecode(payload.encode()) as Map<String, dynamic>;
    final first = (json['days'] as List).first['habits'].first as Map;
    expect(first['streak'], 3);
    expect(first['streakWord'], 'дня');
  });

  test('a done circle is filled with the darker tone of its colour', () {
    // No colour stored → the palette's first family, a real swatch.
    final habit = _payload([_habit()]).days.first.habits.single;

    // The fill is the family's `strong` tone, not the bare accent, and the
    // glyph on it differs from it in both themes.
    expect(habit.fill, isNot(habit.color));
    expect(habit.fillInk, isNot(habit.fill));
    expect(habit.fillInkDark, isNot(habit.fillDark));
    final json = jsonDecode(_payload([_habit()]).encode()) as Map;
    final first = (json['days'] as List).first['habits'].first as Map;
    expect(
      first.keys,
      containsAll(['fill', 'fillDark', 'fillInk', 'fillInkDark']),
    );
  });

  test('the streak word follows the Russian rule', () {
    String wordFor(int days) {
      final logs = [
        for (var i = 0; i < days; i++)
          _log(1, _today.subtract(Duration(days: i)), id: i + 1),
      ];
      return _payload([
        _habit(startDate: _today.subtract(Duration(days: days))),
      ], logs).days.first.habits.single.streakWord;
    }

    expect(wordFor(1), 'день');
    expect(wordFor(4), 'дня');
    expect(wordFor(11), 'дней');
    expect(wordFor(21), 'день');
  });

  test('a longer best streak is named next to the current one', () {
    final logs = [
      for (var d = 1; d <= 10; d++) _log(1, DateTime(2026, 8, d), id: d),
      _log(1, DateTime(2026, 8, 26), id: 20),
      _log(1, _today, id: 21),
    ];

    expect(
      _payload([_habit()], logs).days.first.habits.single.subtitle,
      'серия 2 дня · лучшая 10',
    );
  });

  test('a habit with no marks has no streak to name', () {
    expect(
      _payload([_habit()]).days.first.habits.single.subtitle,
      'пока без серии',
    );
    expect(_payload([_habit()]).days.first.habits.single.streak, 0);
  });

  test('a habit the rule skips today is kept, but not due', () {
    // Monday only.
    final payload = _payload([
      _habit(repeatType: RepeatType.weekly, repeatDaysMask: 1),
    ]);

    final habits = payload.days.first.habits;
    expect(habits, hasLength(1));
    expect(habits.single.due, isFalse);
    // Next Monday is inside the window.
    expect(payload.days[4].habits.single.due, isTrue);
  });

  test('archived habits stay out; each habit carries its tracking kind', () {
    final payload = _payload([
      _habit(),
      _habit(id: 2, status: TaskStatus.archived),
      _habit(id: 3, mode: TrackingMode.counter),
    ]);

    final habits = payload.days.first.habits;
    expect(habits.map((h) => h.id), unorderedEquals([1, 3]));
    expect(habits.firstWhere((h) => h.id == 3).kind, 'counter');
    expect(habits.firstWhere((h) => h.id == 1).kind, 'checkbox');
  });

  test('a week starting on Sunday shifts the strip', () {
    final payload = buildHabitsWidgetPayload(
      tasks: [_habit()],
      logs: const [],
      now: _now,
      light: _light,
      dark: _dark,
      mode: 'system',
      weekStart: DateTime.sunday,
      graceMinutes: 15,
      todayStaysOpen: true,
    );

    // Sun 23 … Sat 29: Thursday is the fifth.
    expect(payload.days.first.habits.single.week, 'mmmmtff');
  });

  test('a counter carries its tally today and its target', () {
    final counter = _habit(
      mode: TrackingMode.counter,
    ).copyWith(targetValue: const Value(5));
    final payload = _payload(
      [counter],
      [
        TaskLog(
          dirty: false,
          updatedAt: _stamp,
          id: 1,
          taskId: 1,
          date: _today,
          completed: false,
          value: 3,
        ),
      ],
    );

    final habit = payload.days.first.habits.single;
    expect(habit.count, 3);
    expect(habit.target, 5);
    expect(habit.done, isFalse);
  });

  test('the payload covers the window and encodes the version', () {
    final json = jsonDecode(_payload([_habit()]).encode()) as Map;

    expect(json['version'], HabitsWidgetPayload.payloadVersion);
    expect(json['weekStart'], DateTime.monday);
    expect((json['days'] as List), hasLength(todayWidgetHorizonDays));
    expect(((json['days'] as List).first as Map)['date'], '2026-08-27');
  });
}
