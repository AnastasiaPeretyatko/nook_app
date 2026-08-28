import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';

/// Monday, 3 August 2026 — the anchor for every case below.
final _monday = DateTime(2026, 8, 3);

Task _task({
  RepeatType? repeatType,
  int? repeatInterval,
  int? repeatDaysMask,
  DateTime? startDate,
}) {
  return Task(
    dirty: false,
    id: 1,
    title: 'Задача',
    status: TaskStatus.active,
    repeatType: repeatType,
    repeatInterval: repeatInterval,
    repeatDaysMask: repeatDaysMask,
    trackingMode: TrackingMode.checkbox,
    startDate: startDate ?? _monday,
    createdAt: _monday,
    updatedAt: _monday,
  );
}

void main() {
  group('mask helpers', () {
    test('round-trip a selection', () {
      expect(daysToMask({1, 3, 5}), 0x15);
      expect(daysFromMask(0x15, maxDay: 7), {1, 3, 5});
    });

    test('empty selection stays null, all seven days survive', () {
      expect(daysToMask({}), isNull);
      expect(daysFromMask(null, maxDay: 7), isEmpty);
      expect(daysFromMask(0, maxDay: 7), isEmpty);
      expect(daysFromMask(daysToMask({1, 2, 3, 4, 5, 6, 7}), maxDay: 7), {
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      });
    });

    test('days past maxDay are dropped when unpacking', () {
      final mask = daysToMask({3, 15, 31});
      expect(daysFromMask(mask, maxDay: 7), {3});
      expect(daysFromMask(mask, maxDay: 31), {3, 15, 31});
    });

    test('out-of-range days are ignored when packing', () {
      expect(daysToMask({0, 32, 3}), daysToMask({3}));
    });

    test('a full month mask stays inside 32 bits', () {
      final mask = daysToMask({for (var d = 1; d <= 31; d++) d});
      expect(mask, 0x7FFFFFFF);
      expect(daysFromMask(mask, maxDay: 31).length, 31);
    });
  });

  group('weekly with a weekday selection', () {
    test('lands on every selected day of the anchor week', () {
      final task = _task(
        repeatType: RepeatType.weekly,
        repeatDaysMask: daysToMask({1, 3, 5}),
      );

      expect(isTaskScheduledOn(task, _monday), isTrue); // пн
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 1))),
        isFalse,
      ); // вт
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 2))),
        isTrue,
      ); // ср
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 4))),
        isTrue,
      ); // пт
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 6))),
        isFalse,
      ); // вс
    });

    test('all seven days selected behaves like daily', () {
      final task = _task(
        repeatType: RepeatType.weekly,
        repeatDaysMask: daysToMask({1, 2, 3, 4, 5, 6, 7}),
      );

      for (var i = 0; i < 14; i++) {
        expect(isTaskScheduledOn(task, _monday.add(Duration(days: i))), isTrue);
      }
    });

    test('interval skips whole weeks, not days', () {
      final task = _task(
        repeatType: RepeatType.weekly,
        repeatInterval: 2,
        repeatDaysMask: daysToMask({1, 4}),
      );

      expect(isTaskScheduledOn(task, _monday), isTrue);
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 3))),
        isTrue,
      );
      // Next week is skipped entirely.
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 7))),
        isFalse,
      );
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 10))),
        isFalse,
      );
      // The week after is on again.
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 14))),
        isTrue,
      );
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 17))),
        isTrue,
      );
    });

    test('a selected day earlier in the anchor week is not scheduled', () {
      // Anchored on Wednesday, but Monday is selected too.
      final wednesday = _monday.add(const Duration(days: 2));
      final task = _task(
        repeatType: RepeatType.weekly,
        repeatDaysMask: daysToMask({1, 3}),
        startDate: wednesday,
      );

      expect(isTaskScheduledOn(task, _monday), isFalse);
      expect(isTaskScheduledOn(task, wednesday), isTrue);
      // The following Monday is fine — it is after the start date.
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 7))),
        isTrue,
      );
    });
  });

  group('weekly without a selection', () {
    test('falls back to the anchor weekday', () {
      final task = _task(repeatType: RepeatType.weekly);

      expect(isTaskScheduledOn(task, _monday), isTrue);
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 2))),
        isFalse,
      );
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 7))),
        isTrue,
      );
    });

    test('honours the week interval', () {
      final task = _task(repeatType: RepeatType.weekly, repeatInterval: 3);

      expect(isTaskScheduledOn(task, _monday), isTrue);
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 7))),
        isFalse,
      );
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 21))),
        isTrue,
      );
    });
  });

  group('monthly with a day selection', () {
    test('lands on every selected day of the month', () {
      final task = _task(
        repeatType: RepeatType.monthly,
        repeatDaysMask: daysToMask({1, 15}),
        startDate: DateTime(2026, 8, 1),
      );

      expect(isTaskScheduledOn(task, DateTime(2026, 8, 1)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 8, 15)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 8, 2)), isFalse);
      expect(isTaskScheduledOn(task, DateTime(2026, 9, 1)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 9, 15)), isTrue);
    });

    test('the 31st falls back to the last day of a short month', () {
      final task = _task(
        repeatType: RepeatType.monthly,
        repeatDaysMask: daysToMask({31}),
        startDate: DateTime(2026, 1, 31),
      );

      expect(isTaskScheduledOn(task, DateTime(2026, 1, 31)), isTrue);
      // February has no 31st: the task lands on the 28th instead of vanishing.
      expect(isTaskScheduledOn(task, DateTime(2026, 2, 28)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 2, 27)), isFalse);
      expect(isTaskScheduledOn(task, DateTime(2026, 3, 31)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 4, 30)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 4, 29)), isFalse);
    });

    test('the 29th reaches 29 February in a leap year', () {
      final task = _task(
        repeatType: RepeatType.monthly,
        repeatDaysMask: daysToMask({29}),
        startDate: DateTime(2024, 1, 29),
      );

      expect(isTaskScheduledOn(task, DateTime(2024, 2, 29)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2024, 2, 28)), isFalse);
    });

    test('days collapsing onto the same clamped date fire once', () {
      final task = _task(
        repeatType: RepeatType.monthly,
        repeatDaysMask: daysToMask({29, 30, 31}),
        startDate: DateTime(2026, 1, 29),
      );

      expect(isTaskScheduledOn(task, DateTime(2026, 2, 28)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 1, 29)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 1, 30)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 1, 31)), isTrue);
    });

    test('interval skips whole months', () {
      final task = _task(
        repeatType: RepeatType.monthly,
        repeatInterval: 3,
        repeatDaysMask: daysToMask({10}),
        startDate: DateTime(2026, 1, 10),
      );

      expect(isTaskScheduledOn(task, DateTime(2026, 1, 10)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 2, 10)), isFalse);
      expect(isTaskScheduledOn(task, DateTime(2026, 4, 10)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2027, 1, 10)), isTrue);
    });
  });

  group('monthly without a selection', () {
    test('falls back to the anchor day of month', () {
      final task = _task(
        repeatType: RepeatType.monthly,
        startDate: DateTime(2026, 8, 17),
      );

      expect(isTaskScheduledOn(task, DateTime(2026, 8, 17)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 9, 17)), isTrue);
      expect(isTaskScheduledOn(task, DateTime(2026, 9, 18)), isFalse);
    });

    test('an anchor on the 31st no longer skips February', () {
      final task = _task(
        repeatType: RepeatType.monthly,
        startDate: DateTime(2026, 1, 31),
      );

      expect(isTaskScheduledOn(task, DateTime(2026, 2, 28)), isTrue);
    });
  });

  group('other repeat types are unaffected', () {
    test('daily ignores the mask', () {
      final task = _task(
        repeatType: RepeatType.daily,
        repeatDaysMask: daysToMask({1}),
      );

      for (var i = 0; i < 5; i++) {
        expect(isTaskScheduledOn(task, _monday.add(Duration(days: i))), isTrue);
      }
    });

    test('one-off task shows only on its start date', () {
      final task = _task();

      expect(isTaskScheduledOn(task, _monday), isTrue);
      expect(
        isTaskScheduledOn(task, _monday.add(const Duration(days: 1))),
        isFalse,
      );
    });
  });
}
