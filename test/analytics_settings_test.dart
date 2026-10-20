import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/week.dart';
import 'package:todo_app/widgets/habits/habit_day_state.dart';
import 'package:todo_app/widgets/settings/analytics_section.dart';

final _stamp = DateTime(2026, 1, 1);

/// A habit at 09:00 every day.
Task _habit({int? time = 9 * 60}) => Task(
  dirty: false,
  id: 1,
  title: 'Зарядка',
  status: TaskStatus.active,
  repeatType: RepeatType.daily,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: time,
  startDate: DateTime(2026, 1, 1),
  createdAt: _stamp,
  updatedAt: _stamp,
);

TaskLog _log(DateTime day, {DateTime? at, bool completed = true}) => TaskLog(
  dirty: false,
  updatedAt: _stamp,
  id: day.day,
  taskId: 1,
  date: day,
  completed: completed,
  completedAt: at,
);

void main() {
  group('startOfWeek', () {
    // 2026-10-21 is a Wednesday, 2026-10-18 a Sunday.
    test('Monday-first', () {
      expect(
        startOfWeek(DateTime(2026, 10, 21), DateTime.monday),
        DateTime(2026, 10, 19),
      );
      expect(
        startOfWeek(DateTime(2026, 10, 18), DateTime.monday),
        DateTime(2026, 10, 12),
      );
    });

    test('Sunday-first', () {
      expect(
        startOfWeek(DateTime(2026, 10, 21), DateTime.sunday),
        DateTime(2026, 10, 18),
      );
      expect(
        startOfWeek(DateTime(2026, 10, 18), DateTime.sunday),
        DateTime(2026, 10, 18),
      );
    });
  });

  group('lateDays', () {
    final day = DateTime(2026, 10, 19);

    test('a tick within the grace is on time, one past it is late', () {
      final logs = [
        _log(day, at: DateTime(2026, 10, 19, 9, 15)),
        _log(
          day.add(const Duration(days: 1)),
          at: DateTime(2026, 10, 20, 9, 16),
        ),
      ];
      expect(lateDays(_habit(), logs, 15), {DateTime(2026, 10, 20)});
      // With no grace the first one is late too.
      expect(lateDays(_habit(), logs, 0), {day, DateTime(2026, 10, 20)});
    });

    test('a tick made on a later day is late', () {
      expect(
        lateDays(_habit(), [_log(day, at: DateTime(2026, 10, 21, 8))], 60),
        {day},
      );
    });

    test('no time, no moment or no tick means never late', () {
      final at = DateTime(2026, 10, 19, 23);
      expect(lateDays(_habit(time: null), [_log(day, at: at)], 15), isEmpty);
      expect(lateDays(_habit(), [_log(day)], 15), isEmpty);
      expect(
        lateDays(_habit(), [_log(day, at: at, completed: false)], 15),
        isEmpty,
      );
    });
  });

  group('habitDayState', () {
    final today = DateTime(2026, 10, 19);

    test('a late tick is its own state, still a done day', () {
      expect(
        habitDayState(
          _habit(),
          today,
          today: today,
          completedDays: {today},
          lateDays: {today},
        ),
        HabitDayState.late,
      );
    });

    test('an open day today is spared unless the switch is off', () {
      expect(
        habitDayState(_habit(), today, today: today, completedDays: {}),
        HabitDayState.today,
      );
      expect(
        habitDayState(
          _habit(),
          today,
          today: today,
          completedDays: {},
          todayStaysOpen: false,
        ),
        HabitDayState.missed,
      );
    });
  });

  group('the stored settings', () {
    Future<ProviderContainer> container([Map<String, Object>? stored]) async {
      SharedPreferences.setMockInitialValues(stored ?? {});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('defaults: Monday, 15 minutes, today spared', () async {
      final c = await container();
      expect(c.read(weekStartProvider), DateTime.monday);
      expect(c.read(lateGraceMinutesProvider), 15);
      expect(c.read(todayStaysOpenProvider), isTrue);
    });

    test('they are written down and read back', () async {
      final c = await container();
      await c.read(weekStartProvider.notifier).setDay(DateTime.sunday);
      await c.read(lateGraceMinutesProvider.notifier).setMinutes(60);
      await c.read(todayStaysOpenProvider.notifier).setEnabled(false);
      final prefs = c.read(sharedPreferencesProvider);

      final again = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(again.dispose);
      expect(again.read(weekStartProvider), DateTime.sunday);
      expect(again.read(lateGraceMinutesProvider), 60);
      expect(again.read(todayStaysOpenProvider), isFalse);
    });

    test('a grace nothing offers any more reads as the default', () async {
      final c = await container({'late_grace_minutes': 7});
      expect(c.read(lateGraceMinutesProvider), 15);
    });
  });

  group('the settings block', () {
    late ProviderContainer c;

    Future<void> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildAppTheme(const Color(0xFF5B6DCB), Brightness.light),
            home: Scaffold(
              body: ListView(children: const [AnalyticsSection()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a chip sets the grace', (tester) async {
      await pump(tester);
      await tester.tap(find.text('30 мин'));
      await tester.pumpAndSettle();
      expect(c.read(lateGraceMinutesProvider), 30);
    });

    testWidgets('the grace chips share one row even on a narrow phone', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.reset);
      await pump(tester);

      final tops = [
        for (final t in ['Сразу', '15 мин', '30 мин', '1 ч'])
          tester.getTopLeft(find.text(t)).dy,
      ];
      expect(tops.toSet(), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the switch turns "today" off and says what that means', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(c.read(todayStaysOpenProvider), isFalse);
      expect(find.text(todayStaysOpenLabel(false)), findsOneWidget);
    });

    testWidgets('the week start is picked from a sheet', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Начало недели'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Воскресенье'));
      await tester.pumpAndSettle();
      expect(c.read(weekStartProvider), DateTime.sunday);
    });
  });

  group('the switch look', () {
    // An off switch must not read as a disabled one: no outline ring, a white
    // thumb, and in the dark theme a soft white on the palette's off track.
    for (final brightness in Brightness.values) {
      test('off, $brightness', () {
        final theme = buildAppTheme(const Color(0xFF5B6DCB), brightness);
        final p = AppPalette.of(theme);
        final sw = theme.switchTheme;
        const off = <WidgetState>{};
        expect(
          sw.thumbColor!.resolve(off),
          brightness == Brightness.light ? Colors.white : p.textPrimary,
        );
        expect(sw.trackColor!.resolve(off), p.switchOff);
        expect(sw.trackOutlineColor!.resolve(off), Colors.transparent);
        // Disabled is still dimmer than the live one.
        expect(
          sw.thumbColor!.resolve({WidgetState.disabled}),
          isNot(sw.thumbColor!.resolve(off)),
        );
      });
    }
  });
}
