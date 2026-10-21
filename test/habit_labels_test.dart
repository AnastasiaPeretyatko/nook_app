import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/habit_labels.dart';
import 'package:todo_app/utils/recurrence.dart';

/// The line under a habit's title.
void main() {
  setUpAll(() => initializeDateFormatting('ru_RU', null));

  // A Friday, so a weekly habit with no mask falls back to "Пт".
  final friday = DateTime(2026, 10, 16);

  Task habit({
    RepeatType? repeat = RepeatType.daily,
    int? interval,
    Set<int>? days,
    int? time,
    TrackingMode mode = TrackingMode.checkbox,
    int? minutes,
  }) => Task(
    dirty: false,
    id: 1,
    title: 'x',
    status: TaskStatus.active,
    repeatType: repeat,
    repeatInterval: interval,
    repeatDaysMask: days == null ? null : daysToMask(days),
    scheduledTimeMinutes: time,
    trackingMode: mode,
    targetDurationMinutes: minutes,
    startDate: friday,
    createdAt: friday,
    updatedAt: friday,
  );

  test('the rule, in a few words', () {
    expect(habitRuleLabel(habit()), 'Каждый день');
    expect(
      habitRuleLabel(habit(repeat: RepeatType.custom, interval: 4)),
      'Каждые 4 дня',
    );
    expect(
      habitRuleLabel(habit(repeat: RepeatType.custom, interval: 5)),
      'Каждые 5 дней',
    );
    expect(
      habitRuleLabel(habit(repeat: RepeatType.weekly, days: {5, 1, 3})),
      'Пн, Ср, Пт',
    );
    expect(habitRuleLabel(habit(repeat: RepeatType.weekly)), 'Пт');
    expect(
      habitRuleLabel(
        habit(repeat: RepeatType.weekly, days: {1, 2, 3, 4, 5, 6, 7}),
      ),
      'Каждый день',
    );
    expect(
      habitRuleLabel(habit(repeat: RepeatType.weekly, interval: 2, days: {1})),
      'Каждые 2 недели: Пн',
    );
    expect(
      habitRuleLabel(habit(repeat: RepeatType.monthly, days: {15, 1})),
      'Каждый месяц: 1, 15',
    );
    expect(
      habitRuleLabel(habit(repeat: RepeatType.monthly)),
      'Каждый месяц: 16',
    );
  });

  test('time and a timer\'s length follow the rule', () {
    expect(habitSubtitle(habit(time: 7 * 60 + 30)), 'Каждый день · 07:30');
    expect(
      habitSubtitle(
        habit(
          repeat: RepeatType.weekly,
          days: {1, 3, 5},
          mode: TrackingMode.timer,
          minutes: 30,
        ),
      ),
      'Пн, Ср, Пт · 30 мин',
    );
  });

  test('a value task says when it was last done', () {
    final value = habit(repeat: null, mode: TrackingMode.value);
    expect(habitSubtitle(value), startsWith('Слежу с 16'));
    expect(
      habitSubtitle(value, lastDone: DateTime(2026, 10, 3)),
      startsWith('3 '),
    );
  });
}
