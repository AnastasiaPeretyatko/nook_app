import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/tracking.dart';
import 'package:todo_app/widgets/habits/habits_grid.dart';

/// Any moment at all: these tests never read a log's edit time. It exists
/// because the sync needs one and the column is therefore not nullable.
final _fixtureStamp = DateTime(2026, 1, 1);

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);
final _monday = _today.subtract(Duration(days: _today.weekday - 1 + 7));
final _days = List.generate(14, (i) => _monday.add(Duration(days: i)));

Task _counterHabit({double? target}) => Task(dirty: false, 
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

TaskLog _log({required double count, bool completed = false}) => TaskLog(dirty: false, updatedAt: _fixtureStamp, 
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
                width: 164,
                child: HabitCard(
                  task: _counterHabit(target: target),
                  days: _days,
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

  group('the counter button', () {
    testWidgets('counts up to the target instead of finishing at once', (
      tester,
    ) async {
      await _pumpCard(tester, target: 3);
      expect(find.text('Отметить'), findsOneWidget);

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
      expect(find.text('Выполнено'), findsOneWidget);
    });

    testWidgets('opens on "Отметить" when the target rounds to zero', (
      tester,
    ) async {
      // A target below half a tap used to read 0 and satisfy "count >= target"
      // with nothing counted at all, so the card opened on "Выполнено".
      await _pumpCard(tester, target: 0.4);
      expect(find.text('Выполнено'), findsNothing);
      expect(find.text('Отметить'), findsOneWidget);
    });

    testWidgets('a counter with no target still counts, not ticks', (
      tester,
    ) async {
      // Without a target the card used to fall back to the plain mark button,
      // so a "Счётчик" habit behaved exactly like a checkbox.
      var increments = 0;
      await _pumpCard(tester, onCounterInc: () => increments++);
      await tester.tap(find.text('Отметить'));
      expect(increments, 1);
    });
  });
}
