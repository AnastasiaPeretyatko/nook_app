import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/widgets/habits/habit_week_stats.dart';

final _stamp = DateTime(2026, 1, 1);

// 2026-10-12 is a Monday; today is that week's Friday.
final _days = [for (var i = 0; i < 7; i++) DateTime(2026, 10, 12 + i)];
final _today = _days[4];

Task _task(
  int id, {
  RepeatType type = RepeatType.daily,
  Set<int> weekdays = const {},
  TrackingMode mode = TrackingMode.checkbox,
  int? time,
}) => Task(
  dirty: false,
  id: id,
  title: 'Привычка $id',
  status: TaskStatus.active,
  repeatType: type,
  repeatDaysMask: daysToMask(weekdays),
  trackingMode: mode,
  scheduledTimeMinutes: time,
  startDate: DateTime(2026, 1, 1),
  createdAt: _stamp,
  updatedAt: _stamp,
);

TaskLog _log(
  int taskId,
  int day, {
  bool completed = true,
  DateTime? at,
  double? value,
}) => TaskLog(
  dirty: false,
  updatedAt: _stamp,
  id: taskId * 100 + day,
  taskId: taskId,
  date: _days[day],
  completed: completed,
  completedAt: at,
  value: value,
);

DateTime _at(int day, int h, int m) => DateTime(2026, 10, 12 + day, h, m);

HabitWeek _week(
  Task task,
  List<TaskLog> logs, {
  int grace = 15,
  bool todayStaysOpen = true,
}) => habitWeek(
  task: task,
  days: _days,
  logs: logs,
  today: _today,
  graceMinutes: grace,
  todayStaysOpen: todayStaysOpen,
);

void main() {
  // A: every day at 07:30. B: a counter. C: Monday, Wednesday, Friday.
  final a = _task(1, time: 7 * 60 + 30);
  final b = _task(2, mode: TrackingMode.counter);
  final c = _task(3, type: RepeatType.weekly, weekdays: {1, 3, 5});

  final logsA = [
    _log(1, 0, at: _at(0, 7, 35)), // within the 15 minutes
    _log(1, 1, at: _at(1, 8, 10)), // 40 minutes past
    _log(1, 3, at: _at(3, 7, 30)),
    _log(1, 4, at: _at(4, 7, 0)),
  ];
  final logsB = [
    _log(2, 0),
    _log(2, 1, completed: false, value: 3),
    _log(2, 2),
    _log(2, 3),
    _log(2, 4, completed: false, value: 5),
  ];
  final logsC = [_log(3, 0), _log(3, 2)];

  group('one habit across the week', () {
    test('a tick is on time, late, or missing', () {
      final w = _week(a, logsA);
      expect(w.cells, [
        WeekCell.onTime,
        WeekCell.late,
        WeekCell.missed,
        WeekCell.onTime,
        WeekCell.onTime,
        WeekCell.future,
        WeekCell.future,
      ]);
      expect([w.done, w.planned], [4, 5]);
      expect(w.lateMinutes, [40]);
    });

    test('the grace decides what is late', () {
      expect(_week(a, logsA, grace: 60).late, 0);
      expect(_week(a, logsA, grace: 0).late, 2);
    });

    test('progress short of the target is partial, today included', () {
      final w = _week(b, logsB);
      expect(w.cells[1], WeekCell.partial);
      expect(w.cells[4], WeekCell.partial);
      expect([w.done, w.planned], [3, 5]);
    });

    test(
      'days off the rule are not planned, and today open is not counted',
      () {
        final w = _week(c, logsC);
        expect(w.cells, [
          WeekCell.onTime,
          WeekCell.off,
          WeekCell.onTime,
          WeekCell.off,
          WeekCell.pending,
          WeekCell.off,
          WeekCell.off,
        ]);
        expect([w.done, w.planned], [2, 2]);
      },
    );

    test('with "today stays open" off, an open today is a miss', () {
      final w = _week(c, logsC, todayStaysOpen: false);
      expect(w.cells[4], WeekCell.missed);
      expect([w.done, w.planned], [2, 3]);
    });

    test('a mark on a day the rule skips shows, but is nobody\'s plan', () {
      final w = _week(c, [...logsC, _log(3, 1)]);
      expect(w.cells[1], WeekCell.onTime);
      expect([w.done, w.planned], [2, 2]);
    });
  });

  group('the summary', () {
    final habits = [_week(a, logsA), _week(b, logsB), _week(c, logsC)];
    final s = weekSummary(habits, _days, today: _today);

    test('percentages are over what was planned and settled', () {
      expect([s.done, s.planned, s.onTime], [9, 12, 8]);
      expect(s.donePercent, 75);
      expect(s.onTimePercent, 67);
    });

    test('the average lateness is over the late marks', () {
      expect(s.averageLateMinutes, 40);
      expect(lateAverageLabel(40), '+40 мин');
      expect(lateAverageLabel(70), '+1 ч 10 мин');
      expect(lateAverageLabel(120), '+2 ч');
      expect(lateAverageLabel(null), '—');
    });

    test('a bar is the share of that day\'s habits', () {
      expect(s.bars[0].onTime, 1.0); // all three on time
      expect(s.bars[1].late, 0.5); // A late, B partial: two due
      expect(s.bars[1].onTime, 0);
      expect(s.bars[4].onTime, closeTo(1 / 3, 0.001));
      expect(s.bars[4].open, isTrue);
      // Nothing yet for a day ahead.
      expect([s.bars[5].onTime, s.bars[5].late], [0, 0]);
    });

    test('a week with nothing planned has no percentage', () {
      final empty = weekSummary(const [], _days, today: _today);
      expect(empty.donePercent, isNull);
      expect(empty.averageLateMinutes, isNull);
    });
  });
}
