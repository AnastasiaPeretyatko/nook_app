import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/widgets/habits/habit_history_stats.dart';
import 'package:todo_app/widgets/habits/habit_week_stats.dart';

final _stamp = DateTime(2026, 1, 1);
// A Friday.
final _today = DateTime(2026, 10, 16);

Task _habit({
  DateTime? start,
  RepeatType type = RepeatType.daily,
  Set<int> weekdays = const {},
  int? time = 22 * 60,
}) => Task(
  dirty: false,
  id: 1,
  title: 'Медитация',
  status: TaskStatus.active,
  repeatType: type,
  repeatDaysMask: daysToMask(weekdays),
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: time,
  startDate: start ?? DateTime(2026, 10, 5),
  createdAt: _stamp,
  updatedAt: _stamp,
);

/// A tick on the given October day, [offset] minutes after 22:00 that day.
TaskLog _tick(int day, int offset) => TaskLog(
  dirty: false,
  updatedAt: _stamp,
  id: day,
  taskId: 1,
  date: DateTime(2026, 10, day),
  completed: true,
  completedAt: DateTime(2026, 10, day, 22).add(Duration(minutes: offset)),
);

HabitHistory _history(Task t, List<TaskLog> logs, {int grace = 15}) =>
    HabitHistory.of(
      task: t,
      logs: logs,
      today: _today,
      graceMinutes: grace,
      todayStaysOpen: true,
    );

void main() {
  // Oct 5 (Mon) .. 16 (Fri, today): done 5,6,7 | miss 8 | done 9,10,11,12,13 |
  // miss 14 | done 15 (30 min late) | today open.
  final logs = [
    _tick(5, 0),
    _tick(6, 5),
    _tick(7, -10),
    _tick(9, 40),
    _tick(10, 0),
    _tick(11, 0),
    _tick(12, 0),
    _tick(13, 0),
    _tick(15, 30),
  ];
  final h = _history(_habit(), logs);

  test('the history runs from the first day to today', () {
    expect(h.days.first, DateTime(2026, 10, 5));
    expect(h.days.last, _today);
    expect(h.days, hasLength(12));
  });

  test('counts leave today and the days ahead out', () {
    final c = h.counts();
    // 11 settled days; 9 done, two missed. 15 and 9 are late (past 15 minutes).
    expect([c.done, c.missed, c.planned], [9, 2, 11]);
    expect([c.onTime, c.late], [7, 2]);
    expect(c.donePercent, 82);
  });

  test('a period narrows what is counted', () {
    final c = h.counts((d) => d.day >= 12);
    expect([c.done, c.missed], [3, 1]);
  });

  test('the current streak ends at the last miss, the best is the longest', () {
    expect(h.streaks, (current: 1, best: 5));
  });

  test('a day off the rule does not break a streak', () {
    // Mondays and Wednesdays, both done; the days between are not planned.
    final w = _history(_habit(type: RepeatType.weekly, weekdays: {1, 3}), [
      _tick(5, 0),
      _tick(7, 0),
      _tick(12, 0),
      _tick(14, 0),
    ]);
    expect(w.streaks.best, 4);
    expect(w.streaks.current, 4);
  });

  test('weekday rates are the share done, null where nothing is planned', () {
    // Mondays 5 (done) and 12 (missed); Wednesdays 7 (done) and 14 (missed).
    final w = _history(_habit(type: RepeatType.weekly, weekdays: {1, 3}), [
      _tick(5, 0),
      _tick(7, 0),
    ]);
    final rates = w.weekdayRates;
    expect(rates[0], 0.5);
    expect(rates[2], 0.5);
    expect(rates[1], isNull);
    expect(rates[6], isNull);
  });

  test('months carry counts and the average offset', () {
    final m = h.months.single;
    expect([m.year, m.month], [2026, 10]);
    expect(m.counts.done, 9);
    // (0 + 5 − 10 + 40 + 0 + 0 + 0 + 0 + 30) / 9
    expect(m.averageOffset, closeTo(65 / 9, 0.001));
  });

  test('the recent points are settled days before today, oldest first', () {
    final p = h.recentPoints(_today, n: 3);
    expect(p.map((e) => e.day.day), [13, 14, 15]);
    expect(p[1].cell, WeekCell.missed);
    expect(p[1].offset, isNull);
    expect(p[2].offset, 30);
  });

  test('the average offset can be taken over a stretch', () {
    expect(h.averageOffset((d) => d.day >= 14), 30);
    expect(h.averageOffset((d) => d.day == 8), isNull);
  });

  test('a habit with no time has no offsets', () {
    final n = _history(_habit(time: null), logs);
    expect(n.averageOffset(), isNull);
    expect(n.counts().late, 0);
  });

  test('weeks run from the first day\'s week to this one', () {
    final w = h.weeks(DateTime.monday);
    expect(w.map((e) => e.start.day), [5, 12]);
    // 5–11: done 5, 6, 7, 9, 10, 11; missed 8. 12–15 (today, the 16th, is open):
    // done 12, 13, 15; missed 14.
    expect([w[0].counts.done, w[0].counts.missed], [6, 1]);
    expect([w[1].counts.done, w[1].counts.missed], [3, 1]);
  });

  test('a Sunday start moves the week, not the days counted', () {
    final w = h.weeks(DateTime.sunday);
    // The week of Sunday the 4th is cut short by the habit's start on the 5th.
    expect(w.map((e) => e.start.day), [4, 11]);
    expect(w[0].counts.planned, 6); // 5–10
    expect(w.fold<int>(0, (a, e) => a + e.counts.planned), 11);
  });
}
