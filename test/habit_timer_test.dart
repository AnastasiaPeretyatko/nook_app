import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/widgets/habits/habits_today.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Any moment at all: these tests never read a log's edit time. It exists
/// because the sync needs one and the column is therefore not nullable.
final _fixtureStamp = DateTime(2026, 1, 1);

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

/// Ten minutes, the target every habit here is set to.
const _targetMinutes = 10;

Task _timerHabit() => Task(
  dirty: false,
  id: 1,
  title: 'Медитация',
  status: TaskStatus.active,
  repeatType: RepeatType.daily,
  trackingMode: TrackingMode.timer,
  targetDurationMinutes: _targetMinutes,
  colorValue: 0xFFFFC1CC,
  startDate: _today.subtract(const Duration(days: 30)),
  createdAt: _today,
  updatedAt: _today,
);

TaskLog _log({required double seconds, bool completed = false}) => TaskLog(
  dirty: false,
  updatedAt: _fixtureStamp,
  id: 1,
  taskId: 1,
  date: _today,
  completed: completed,
  value: seconds,
);

Future<void> _pumpCard(
  WidgetTester tester, {
  TaskLog? todayLog,
  DateTime? runningSince,
  Set<DateTime> completedDays = const {},
  VoidCallback? onStart,
  VoidCallback? onStop,
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
                  task: _timerHabit(),
                  today: _today,
                  completedDays: completedDays,
                  todayLog: todayLog,
                  timerRunningSince: runningSince,
                  onTap: () {},
                  onMark: () {},
                  onTimerStart: onStart ?? () {},
                  onTimerStop: onStop ?? () {},
                  onCounterInc: () {},
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
  testWidgets('an untouched timer invites a start', (tester) async {
    await _pumpCard(tester);

    // The readout counts down: an untouched run has all of it left.
    expect(find.text('10:00'), findsOneWidget);
    expect(find.byTooltip('Запустить таймер'), findsOneWidget);
  });

  testWidgets('a paused timer counts what is banked off the target', (
    tester,
  ) async {
    await _pumpCard(tester, todayLog: _log(seconds: 90));

    expect(find.text('08:30'), findsOneWidget);
    expect(find.byIcon(LucideIcons.play), findsOneWidget);
  });

  testWidgets('a running timer counts from when it started', (tester) async {
    // The run began 65 seconds ago — the readout is derived from the clock, not
    // from anything the widget has been counting.
    await _pumpCard(
      tester,
      runningSince: DateTime.now().subtract(const Duration(seconds: 65)),
    );

    expect(find.text('08:55'), findsOneWidget);
    expect(find.byIcon(LucideIcons.pause), findsOneWidget);
  });

  testWidgets('a run resumed after a break adds to what was banked', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      todayLog: _log(seconds: 120),
      runningSince: DateTime.now().subtract(const Duration(seconds: 30)),
    );

    expect(find.text('07:30'), findsOneWidget);
  });

  testWidgets('a run that outlived the app picks up where the clock is', (
    tester,
  ) async {
    // Backgrounded for four minutes: the old ticker would have shown 00:00.
    await _pumpCard(
      tester,
      runningSince: DateTime.now().subtract(const Duration(minutes: 4)),
    );

    expect(find.text('06:00'), findsOneWidget);
  });

  testWidgets('a running timer does not leak its ticker', (tester) async {
    await _pumpCard(
      tester,
      runningSince: DateTime.now().subtract(const Duration(seconds: 10)),
    );

    // Replacing the tree disposes the button; a surviving ticker would make the
    // test fail with a pending-timer error.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
  });

  testWidgets('an idle timer runs no ticker at all', (tester) async {
    await _pumpCard(tester, todayLog: _log(seconds: 90));

    // Nothing to advance: a paused readout cannot change on its own.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('08:30'), findsOneWidget);
  });

  testWidgets('a finished habit reads as done, not as a timer', (tester) async {
    await _pumpCard(
      tester,
      todayLog: _log(seconds: _targetMinutes * 60, completed: true),
      completedDays: {_today},
    );

    expect(find.byTooltip('Выполнено'), findsOneWidget);
    expect(find.byTooltip('Запустить таймер'), findsNothing);
  });

  testWidgets('tapping an idle timer asks to start it', (tester) async {
    var started = 0, stopped = 0;
    await _pumpCard(tester, onStart: () => started++, onStop: () => stopped++);

    await tester.tap(find.byTooltip('Запустить таймер'));
    await tester.pump();

    expect(started, 1);
    expect(stopped, 0);
  });

  testWidgets('tapping a running timer asks to stop it', (tester) async {
    var started = 0, stopped = 0;
    await _pumpCard(
      tester,
      runningSince: DateTime.now().subtract(const Duration(seconds: 5)),
      onStart: () => started++,
      onStop: () => stopped++,
    );

    await tester.tap(find.byTooltip('Остановить таймер'));
    await tester.pump();

    expect(started, 0);
    expect(stopped, 1);
  });

  testWidgets('a done habit ignores taps', (tester) async {
    var started = 0, stopped = 0;
    await _pumpCard(
      tester,
      todayLog: _log(seconds: _targetMinutes * 60, completed: true),
      completedDays: {_today},
      onStart: () => started++,
      onStop: () => stopped++,
    );

    await tester.tap(find.byTooltip('Выполнено'));
    await tester.pump();

    expect(started, 0);
    expect(stopped, 0);
  });

  group('reaching the target', () {
    testWidgets('closes the run once, not once per second', (tester) async {
      var stopped = 0;
      await _pumpCard(
        tester,
        runningSince: DateTime.now().subtract(
          const Duration(minutes: _targetMinutes),
        ),
        onStop: () => stopped++,
      );

      // The post-frame check settles it as soon as the card is on screen.
      await tester.pump();
      expect(stopped, 1);

      // Three more ticks with the database not yet caught up.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(stopped, 1, reason: 'the finish must not replay while it settles');
    });

    testWidgets('the readout stops at the target, it does not run past', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        runningSince: DateTime.now().subtract(const Duration(minutes: 15)),
      );

      expect(find.text('00:00'), findsOneWidget);
    });
  });
}
