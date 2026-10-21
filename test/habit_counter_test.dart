import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/tracking.dart';
import 'package:todo_app/widgets/habits/habits_today.dart';

/// Any moment at all: these tests never read a log's edit time. It exists
/// because the sync needs one and the column is therefore not nullable.
final _fixtureStamp = DateTime(2026, 1, 1);

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

Task _counterHabit({double? target}) => Task(
  dirty: false,
  id: 1,
  title: 'Вода',
  status: TaskStatus.active,
  repeatType: RepeatType.daily,
  trackingMode: TrackingMode.counter,
  targetValue: target,
  colorValue: 0xFFE998A1,
  startDate: _today.subtract(const Duration(days: 30)),
  createdAt: _today,
  updatedAt: _today,
);

TaskLog _log({required double count, bool completed = false}) => TaskLog(
  dirty: false,
  updatedAt: _fixtureStamp,
  id: 1,
  taskId: 1,
  date: _today,
  completed: completed,
  value: count,
);

Future<void> _pumpCard(
  WidgetTester tester, {
  double? target,
  TaskLog? todayLog,
  Set<DateTime> completedDays = const {},
  VoidCallback? onCounterInc,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 390,
                child: HabitRow(
                  task: _counterHabit(target: target),
                  today: _today,
                  completedDays: completedDays,
                  todayLog: todayLog,
                  timerRunningSince: null,
                  onTap: () {},
                  onMark: () {},
                  onTimerStart: () {},
                  onTimerStop: () {},
                  onCounterInc: onCounterInc ?? () {},
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('counterTarget', () {
    test('a missing target counts once', () {
      expect(counterTarget(_counterHabit()), 1);
    });

    test('a fraction never rounds down to zero taps', () {
      expect(counterTarget(_counterHabit(target: 0.4)), 1);
      expect(counterTarget(_counterHabit(target: 0.5)), 1);
      expect(counterTarget(_counterHabit(target: 2.5)), 3);
    });

    test('a whole target is itself', () {
      expect(counterTarget(_counterHabit(target: 3)), 3);
    });
  });

  group('the counter control', () {
    testWidgets('counts up to the target instead of finishing at once', (
      tester,
    ) async {
      await _pumpCard(tester, target: 3);
      expect(find.text('0/3'), findsOneWidget);
      expect(find.byTooltip('Добавить'), findsOneWidget);

      await _pumpCard(tester, target: 3, todayLog: _log(count: 1));
      expect(find.text('1/3'), findsOneWidget);

      await _pumpCard(tester, target: 3, todayLog: _log(count: 2));
      expect(find.text('2/3'), findsOneWidget);

      await _pumpCard(
        tester,
        target: 3,
        todayLog: _log(count: 3, completed: true),
        completedDays: {_today},
      );
      expect(find.byTooltip('Выполнено'), findsOneWidget);
      expect(find.byTooltip('Добавить'), findsNothing);
    });

    testWidgets('opens open when the target rounds to zero', (tester) async {
      // A target below half a tap used to read 0 and satisfy "count >= target"
      // with nothing counted at all, so the card opened on "Выполнено".
      await _pumpCard(tester, target: 0.4);
      expect(find.byTooltip('Выполнено'), findsNothing);
      expect(find.byTooltip('Добавить'), findsOneWidget);
    });

    testWidgets('a counter with no target still counts, not ticks', (
      tester,
    ) async {
      // Without a target the card used to fall back to the plain mark button,
      // so a "Счётчик" habit behaved exactly like a checkbox.
      var increments = 0;
      await _pumpCard(tester, onCounterInc: () => increments++);
      await tester.tap(find.byTooltip('Добавить'));
      expect(increments, 1);
    });

    testWidgets('the progress track spans the row, not just the fill', (
      tester,
    ) async {
      // The track sat in a box as wide as the fill, so it was always hidden
      // under it — and at zero it had no width at all.
      await _pumpCard(tester, target: 4, todayLog: _log(count: 1));

      final bars = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(HabitRow),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      final sizes = [
        for (final bar in bars) tester.getSize(find.byWidget(bar)).width,
      ];
      // Track first, fill second: the fill is a quarter of the track.
      expect(sizes, hasLength(2));
      expect(sizes[0], greaterThan(100));
      expect(sizes[1], closeTo(sizes[0] / 4, 0.5));
    });
  });
}
