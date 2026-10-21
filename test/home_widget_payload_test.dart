import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/home_widget/today_payload.dart';
import 'package:todo_app/main.dart' show buildAppTheme;
import 'package:todo_app/widgets/color_picker_row.dart';

/// Any moment at all: nothing here reads a log's edit time. It exists because
/// the sync needs one and the column is therefore not nullable.
final _fixtureStamp = DateTime(2026, 1, 1);

/// A Thursday, so a weekly rule can be told apart from a daily one.
final _today = DateTime(2026, 8, 27);
final _now = DateTime(2026, 8, 27, 9, 30);

Task _task({
  int id = 1,
  String title = 'Выпить чай',
  int? scheduledTimeMinutes = 9 * 60,
  int? endTimeMinutes,
  RepeatType? repeatType,
  int? repeatDaysMask,
  TaskStatus status = TaskStatus.active,
  int? parentId,
  int? colorValue,
  DateTime? startDate,
}) => Task(
  dirty: false,
  id: id,
  title: title,
  parentId: parentId,
  status: status,
  repeatType: repeatType,
  repeatDaysMask: repeatDaysMask,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: scheduledTimeMinutes,
  endTimeMinutes: endTimeMinutes,
  colorValue: colorValue,
  startDate: startDate ?? _today,
  createdAt: startDate ?? _today,
  updatedAt: startDate ?? _today,
);

TaskLog _log({
  int id = 1,
  int taskId = 1,
  DateTime? date,
  bool completed = true,
}) => TaskLog(
  dirty: false,
  updatedAt: _fixtureStamp,
  id: id,
  taskId: taskId,
  date: date ?? _today,
  completed: completed,
);

final _light = WidgetPalette.fromScheme(
  buildAppTheme(const Color(0xFF8B7CF6), Brightness.light).colorScheme,
);
final _dark = WidgetPalette.fromScheme(
  buildAppTheme(const Color(0xFF8B7CF6), Brightness.dark).colorScheme,
);

TodayWidgetPayload _payload({
  List<Task>? tasks,
  List<TaskLog> logs = const [],
  DateTime? now,
  String mode = 'system',
  int maxTasks = todayWidgetMaxTasks,
}) => buildTodayWidgetPayload(
  tasks: tasks ?? [_task()],
  logs: logs,
  now: now ?? _now,
  light: _light,
  dark: _dark,
  mode: mode,
  maxTasks: maxTasks,
);

WidgetDay _day(TodayWidgetPayload payload, [int offset = 0]) =>
    payload.days[offset];

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU', null));

  group('which tasks a day shows', () {
    test('a task scheduled for today', () {
      final tasks = _day(_payload()).tasks;

      expect(tasks, hasLength(1));
      expect(tasks.single.id, 1);
      expect(tasks.single.title, 'Выпить чай');
      expect(tasks.single.time, '09:00');
      expect(tasks.single.done, isFalse);
    });

    test('a one-off task on another day is not on this one', () {
      final payload = _payload(
        tasks: [_task(startDate: DateTime(2026, 8, 25))],
      );

      expect(_day(payload).tasks, isEmpty);
    });

    test('a daily habit is on every day of the window', () {
      final payload = _payload(tasks: [_task(repeatType: RepeatType.daily)]);

      expect(payload.days.map((day) => day.tasks.length), everyElement(1));
    });

    test('a weekly habit only lands on the weekdays of its rule', () {
      // Thursday (bit 3) and Saturday (bit 5) — today, and two days on.
      final payload = _payload(
        tasks: [
          _task(repeatType: RepeatType.weekly, repeatDaysMask: 1 << 3 | 1 << 5),
        ],
      );

      expect(payload.days.map((day) => day.tasks.length), [
        1,
        0,
        1,
        0,
        0,
        0,
        0,
      ]);
    });

    test('an archived task is not shown', () {
      expect(
        _day(_payload(tasks: [_task(status: TaskStatus.archived)])).tasks,
        isEmpty,
      );
    });

    test('a paused habit is not shown', () {
      expect(
        _day(_payload(tasks: [_task(status: TaskStatus.paused)])).tasks,
        isEmpty,
      );
    });

    test('a subtask is reported through its parent, never on its own', () {
      final payload = _payload(
        tasks: [
          _task(),
          _task(id: 2, title: 'Заварить', parentId: 1),
        ],
      );

      expect(_day(payload).tasks.map((task) => task.id), [1]);
    });
  });

  group('the order the rows read in', () {
    test('by the clock', () {
      final payload = _payload(
        tasks: [
          _task(id: 1, title: 'Обед', scheduledTimeMinutes: 15 * 60),
          _task(id: 2, title: 'Чай', scheduledTimeMinutes: 9 * 60),
          _task(id: 3, title: 'Встреча', scheduledTimeMinutes: 11 * 60 + 30),
        ],
      );

      expect(_day(payload).tasks.map((task) => task.time), [
        '09:00',
        '11:30',
        '15:00',
      ]);
    });

    test('a task with no time comes after every task that has one', () {
      final payload = _payload(
        tasks: [
          _task(id: 1, title: 'Без времени', scheduledTimeMinutes: null),
          _task(id: 2, title: 'Чай', scheduledTimeMinutes: 9 * 60),
        ],
      );

      expect(_day(payload).tasks.map((task) => task.title), [
        'Чай',
        'Без времени',
      ]);
      expect(_day(payload).tasks.last.time, isNull);
    });

    test('two tasks at the same minute are ordered by title', () {
      final payload = _payload(
        tasks: [
          _task(id: 1, title: 'Бег'),
          _task(id: 2, title: 'Аптека'),
        ],
      );

      expect(_day(payload).tasks.map((task) => task.title), ['Аптека', 'Бег']);
    });

    test('a done task keeps its place in the day', () {
      final payload = _payload(
        tasks: [
          _task(id: 1, title: 'Чай', scheduledTimeMinutes: 9 * 60),
          _task(id: 2, title: 'Встреча', scheduledTimeMinutes: 11 * 60),
        ],
        logs: [_log(taskId: 1)],
      );

      expect(_day(payload).tasks.map((task) => task.title), ['Чай', 'Встреча']);
      expect(_day(payload).tasks.first.done, isTrue);
    });
  });

  group('the counter', () {
    test('counts the ticks of the day', () {
      final payload = _payload(
        tasks: [
          _task(id: 1),
          _task(id: 2, scheduledTimeMinutes: 11 * 60),
          _task(id: 3, scheduledTimeMinutes: 15 * 60),
        ],
        logs: [_log(taskId: 1), _log(taskId: 3)],
      );

      expect(_day(payload).done, 2);
      expect(_day(payload).total, 3);
    });

    test('an unfinished log is not a tick', () {
      final payload = _payload(logs: [_log(completed: false)]);

      expect(_day(payload).done, 0);
      expect(_day(payload).tasks.single.done, isFalse);
    });

    test("another day's tick does not count for this one", () {
      final payload = _payload(
        tasks: [_task(repeatType: RepeatType.daily)],
        logs: [_log(date: _today.add(const Duration(days: 1)))],
      );

      expect(_day(payload).done, 0);
      expect(_day(payload, 1).done, 1);
    });

    test('the total is the whole day, not the rows that fit', () {
      final payload = _payload(
        tasks: [
          for (var id = 1; id <= 6; id++)
            _task(id: id, scheduledTimeMinutes: id * 60),
        ],
        logs: [_log(taskId: 1), _log(id: 2, taskId: 2)],
        maxTasks: 3,
      );

      expect(_day(payload).tasks, hasLength(3));
      expect(_day(payload).total, 6);
      expect(_day(payload).done, 2);
    });
  });

  group('the window', () {
    test('is a week starting today', () {
      final payload = _payload();

      expect(payload.days, hasLength(todayWidgetHorizonDays));
      expect(_day(payload).date, _today);
      expect(payload.days.last.date, DateTime(2026, 9, 2));
    });

    test('the date is a day and not the moment it was built', () {
      expect(_day(_payload(now: DateTime(2026, 8, 27, 23, 59))).date, _today);
    });

    test('the label is the Russian short date the header prints', () {
      expect(_day(_payload()).label, '27 авг.');
    });
  });

  group('a row carries its own colour', () {
    test("the task's colour when it has one", () {
      final payload = _payload(
        tasks: [_task(colorValue: const Color(0xFFF4C95D).toARGB32())],
      );

      expect(_day(payload).tasks.single.color, 0xFFF4C95D);
    });

    test('the palette default when it has none', () {
      expect(
        _day(_payload()).tasks.single.color,
        ColorPickerRow.colors.first.toARGB32(),
      );
    });

    test('the tick drawn on it is opaque', () {
      expect(_day(_payload()).tasks.single.checkInk >> 24, 0xFF);
    });
  });

  group('what the widget store receives', () {
    test('a version, the mode, both palettes and the days', () {
      final json =
          jsonDecode(_payload(mode: 'dark').encode()) as Map<String, Object?>;

      expect(json['version'], TodayWidgetPayload.payloadVersion);
      expect(json['mode'], 'dark');
      expect(
        (json['palettes'] as Map<String, Object?>).keys,
        containsAll(['light', 'dark']),
      );
      expect(json['days'], hasLength(todayWidgetHorizonDays));
    });

    test('a day is keyed by its date, in the spelling Kotlin looks up', () {
      final json = jsonDecode(_payload().encode()) as Map<String, Object?>;
      final day = (json['days'] as List).first as Map<String, Object?>;

      expect(day['date'], '2026-08-27');
      expect(day['label'], '27 авг.');
      expect(day['total'], 1);
      expect(day['done'], 0);
    });

    test('a task with no time carries no time key at all', () {
      final json = jsonDecode(
        _payload(tasks: [_task(scheduledTimeMinutes: null)]).encode(),
      );
      final day = (json['days'] as List).first as Map<String, Object?>;
      final task = (day['tasks'] as List).single as Map<String, Object?>;

      expect(task.containsKey('time'), isFalse);
      expect(task['id'], 1);
      expect(task['done'], false);
    });

    test('two payloads of the same state encode identically', () {
      // What the change detection in `HomeWidgetBridge` rests on: an unchanged
      // app must not produce a new string, or every rebuild would broadcast a
      // redraw.
      expect(_payload().encode(), _payload().encode());
    });
  });

  group('the palettes', () {
    test('are opaque, both of them', () {
      for (final palette in [_light, _dark]) {
        for (final colour in [
          palette.card,
          palette.title,
          palette.muted,
          palette.outline,
          palette.accent,
          palette.ring,
        ]) {
          expect(colour >> 24, 0xFF);
        }
      }
    });

    test(
      'the dark card is a surface above the background, not the background',
      () {
        final theme = buildAppTheme(const Color(0xFF8B7CF6), Brightness.dark);

        expect(_dark.card, theme.colorScheme.surface.toARGB32());
        expect(_dark.card, isNot(theme.scaffoldBackgroundColor.toARGB32()));
      },
    );

    test('the light card is the app surface itself', () {
      final scheme = buildAppTheme(
        const Color(0xFF8B7CF6),
        Brightness.light,
      ).colorScheme;

      expect(_light.card, scheme.surface.toARGB32());
    });

    test('the accent follows the app accent', () {
      final green = WidgetPalette.fromScheme(
        buildAppTheme(const Color(0xFF76B894), Brightness.light).colorScheme,
      );

      expect(green.accent, isNot(_light.accent));
    });

    test('a graphite accent is not left invisible on a dark card', () {
      // The palette's neutral option is #1A1A1A, which is all but the dark
      // card's own colour. `buildAppTheme` already turns it white for the dark
      // theme; this is the guard that the widget inherits that.
      final graphite = WidgetPalette.fromScheme(
        buildAppTheme(const Color(0xFF1A1A1A), Brightness.dark).colorScheme,
      );

      expect(graphite.accent, isNot(graphite.card));
    });
  });
}
