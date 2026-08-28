import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/widgets/habits/habit_day_state.dart';

/// Monday, 10 August 2026. "Today" in these cases is Monday the 17th, so the
/// window has one full past week and one current week.
final _monday = DateTime(2026, 8, 10);
final _today = DateTime(2026, 8, 17);

Task _habit({
  RepeatType repeatType = RepeatType.weekly,
  Set<int> days = const {},
  DateTime? startDate,
}) => Task(
  dirty: false,
  id: 1,
  title: 'Привычка',
  status: TaskStatus.active,
  repeatType: repeatType,
  repeatDaysMask: daysToMask(days),
  trackingMode: TrackingMode.checkbox,
  startDate: startDate ?? _monday,
  createdAt: _monday,
  updatedAt: _monday,
);

HabitDayState _state(
  Task task,
  DateTime day, {
  Set<DateTime> completed = const {},
}) => habitDayState(task, day, today: _today, completedDays: completed);

void main() {
  group('days outside the schedule', () {
    test('are off, not missed', () {
      // Tuesday and Wednesday only.
      final task = _habit(days: {2, 3});

      // Monday of the past week: scheduled? no -> off, even though it is past.
      expect(_state(task, _monday), HabitDayState.off);
      expect(
        _state(task, _monday.add(const Duration(days: 4))), // пт
        HabitDayState.off,
      );
      // Today is a Monday, so it is off too — nothing to mark.
      expect(_state(task, _today), HabitDayState.off);
    });

    test('a marked day still reads as done', () {
      final task = _habit(days: {2, 3});
      // The schedule no longer covers Friday, but it was ticked back then.
      final friday = _monday.add(const Duration(days: 4));

      expect(_state(task, friday, completed: {friday}), HabitDayState.done);
    });
  });

  group('scheduled days', () {
    test('past and unmarked is a miss', () {
      final task = _habit(days: {2, 3});
      final pastTuesday = _monday.add(const Duration(days: 1));

      expect(_state(task, pastTuesday), HabitDayState.missed);
    });

    test('past and marked is done', () {
      final task = _habit(days: {2, 3});
      final pastTuesday = _monday.add(const Duration(days: 1));

      expect(
        _state(task, pastTuesday, completed: {pastTuesday}),
        HabitDayState.done,
      );
    });

    test('today is its own state, not a miss', () {
      // Monday only, which is what today is.
      final task = _habit(days: {1});

      expect(_state(task, _today), HabitDayState.today);
    });

    test('later this window is upcoming', () {
      final task = _habit(days: {2, 3});
      final comingTuesday = _today.add(const Duration(days: 1));

      expect(_state(task, comingTuesday), HabitDayState.upcoming);
    });
  });

  group('other repeat types', () {
    test('a daily habit has no off days', () {
      final task = _habit(repeatType: RepeatType.daily);

      for (var i = 0; i < 14; i++) {
        expect(
          _state(task, _monday.add(Duration(days: i))),
          isNot(HabitDayState.off),
        );
      }
    });

    test('a daily habit ignores a stale interval', () {
      // Rows saved before "Ежедневно" and "Другое" were split can still carry an
      // interval. Daily means every day, so no weekday may come out as off.
      final task = Task(
        dirty: false,
        id: 1,
        title: 'Зарядка',
        status: TaskStatus.active,
        repeatType: RepeatType.daily,
        repeatInterval: 2,
        trackingMode: TrackingMode.checkbox,
        startDate: _monday,
        createdAt: _monday,
        updatedAt: _monday,
      );

      for (var i = 0; i < 14; i++) {
        expect(
          _state(task, _monday.add(Duration(days: i))),
          isNot(HabitDayState.off),
          reason: 'day $i of a daily habit',
        );
      }
    });

    test('custom still repeats every N days', () {
      final task = Task(
        dirty: false,
        id: 1,
        title: 'Пробежка',
        status: TaskStatus.active,
        repeatType: RepeatType.custom,
        repeatInterval: 2,
        trackingMode: TrackingMode.checkbox,
        startDate: _monday,
        createdAt: _monday,
        updatedAt: _monday,
      );

      expect(_state(task, _monday), HabitDayState.missed);
      expect(
        _state(task, _monday.add(const Duration(days: 1))),
        HabitDayState.off,
      );
      expect(
        _state(task, _monday.add(const Duration(days: 2))),
        HabitDayState.missed,
      );
    });

    test('days before the start date are their own state, not off', () {
      final task = _habit(
        repeatType: RepeatType.daily,
        startDate: _today.subtract(const Duration(days: 2)),
      );

      // The habit did not exist yet — that is not "skipped by the rule".
      expect(_state(task, _monday), HabitDayState.beforeStart);
      expect(
        _state(task, _today.subtract(const Duration(days: 2))),
        HabitDayState.missed,
      );
    });

    test('a habit created today leaves last week fillable, not blank', () {
      // Exactly the reported case: created today, daily, so every day of the
      // previous week is pre-history rather than an empty slot.
      final task = _habit(repeatType: RepeatType.daily, startDate: _today);

      for (var i = 0; i < 7; i++) {
        expect(
          _state(task, _monday.add(Duration(days: i))),
          HabitDayState.beforeStart,
          reason: 'day $i of the previous week',
        );
      }
      expect(_state(task, _today), HabitDayState.today);
    });

    test('the repeat rule still wins over pre-history', () {
      // Weekly on Tue/Wed, created today: last week's Tuesday is fillable
      // pre-history, but last week's Monday is simply not one of its days.
      final task = _habit(days: {2, 3}, startDate: _today);

      expect(_state(task, _monday), HabitDayState.off);
      expect(
        _state(task, _monday.add(const Duration(days: 1))),
        HabitDayState.beforeStart,
      );
      expect(
        _state(task, _monday.add(const Duration(days: 2))),
        HabitDayState.beforeStart,
      );
    });

    test('a start date in the future does not read as pre-history ahead', () {
      final task = _habit(
        repeatType: RepeatType.daily,
        startDate: _today.add(const Duration(days: 3)),
      );

      expect(
        _state(task, _today.add(const Duration(days: 1))),
        HabitDayState.upcoming,
      );
      expect(_state(task, _monday), HabitDayState.beforeStart);
    });

    test('a day marked before the start still reads as done', () {
      final task = _habit(
        repeatType: RepeatType.daily,
        startDate: _today.subtract(const Duration(days: 2)),
      );

      expect(_state(task, _monday, completed: {_monday}), HabitDayState.done);
    });

    test('a monthly habit marks only its own day of month', () {
      final task = _habit(
        repeatType: RepeatType.monthly,
        days: {17},
        startDate: DateTime(2026, 7, 17),
      );

      expect(_state(task, _today), HabitDayState.today);
      expect(_state(task, _monday), HabitDayState.off);
    });
  });

  group('markability', () {
    test('any day that has arrived can be toggled', () {
      expect(isHabitDayMarkable(_monday, today: _today), isTrue);
      expect(isHabitDayMarkable(_today, today: _today), isTrue);
    });

    test('days still ahead are inert', () {
      expect(
        isHabitDayMarkable(_today.add(const Duration(days: 1)), today: _today),
        isFalse,
      );
    });

    test('a day outside the schedule stays toggleable both ways', () {
      // Tuesday/Wednesday habit; the past Friday is off but must remain
      // markable, otherwise unmarking it would be a one-way door.
      final task = _habit(days: {2, 3});
      final friday = _monday.add(const Duration(days: 4));

      expect(_state(task, friday), HabitDayState.off);
      expect(isHabitDayMarkable(friday, today: _today), isTrue);

      // Once marked it reads as done, and it is still markable — so the mark can
      // be taken back off again.
      expect(_state(task, friday, completed: {friday}), HabitDayState.done);
      expect(isHabitDayMarkable(friday, today: _today), isTrue);
    });
  });
}
