import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/widgets/habits/habit_actions_sheet.dart';

/// Any moment at all: these tests never read a log's edit time. It exists
/// because the sync needs one and the column is therefore not nullable.
final _fixtureStamp = DateTime(2026, 1, 1);

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

const _habitColor = Color(0xFFFFC1CC);

Task _habit({
  required int id,
  required String title,
  RepeatType repeatType = RepeatType.daily,
  Set<int> weekdays = const {},
}) => Task(
  dirty: false,
  id: id,
  title: title,
  status: TaskStatus.active,
  repeatType: repeatType,
  repeatDaysMask: daysToMask(weekdays),
  trackingMode: TrackingMode.checkbox,
  colorValue: _habitColor.toARGB32(),
  startDate: _today.subtract(const Duration(days: 30)),
  createdAt: _today,
  updatedAt: _today,
);

TaskLog _log({
  required int id,
  required int taskId,
  required int daysAgo,
  bool completed = true,
}) => TaskLog(
  dirty: false,
  updatedAt: _fixtureStamp,
  id: id,
  taskId: taskId,
  date: _today.subtract(Duration(days: daysAgo)),
  completed: completed,
);

/// Day squares painted in the habit's full-strength colour, i.e. the completed
/// ones. Unmarked days use the same colour at low alpha.
int _completedSquares(WidgetTester tester) => tester
    .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
    .where((c) => (c.decoration as BoxDecoration?)?.color == _habitColor)
    .length;

/// Every scheduled day, drawn as a rounded square. Days outside the schedule are
/// drawn as dots instead, so this counts the scheduled ones.
int _squares(WidgetTester tester) =>
    find.byType(AnimatedContainer).evaluate().length;

/// Days outside the schedule, drawn as a small circle inside an empty slot. The
/// search is scoped to the day slots so the legend's own swatch is not counted.
int _dots(WidgetTester tester) => find
    .descendant(of: find.byType(AspectRatio), matching: find.byType(Container))
    .evaluate()
    .where(
      (e) =>
          ((e.widget as Container).decoration as BoxDecoration?)?.shape ==
          BoxShape.circle,
    )
    .length;

/// Missed days: outlined with no fill.
int _hollowSquares(WidgetTester tester) => tester
    .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
    .map((c) => c.decoration as BoxDecoration?)
    .where((d) => d?.color == Colors.transparent && d?.border != null)
    .length;

/// Day slots that accept a tap. The day squares are the only [AspectRatio]s in
/// the sheet, so a [GestureDetector] above one belongs to a markable day.
int _tappableDays(WidgetTester tester) => find
    .ancestor(
      of: find.byType(AspectRatio),
      matching: find.byType(GestureDetector),
    )
    .evaluate()
    .length;

Widget _sheet(Task task, List<TaskLog> logs) => ProviderScope(
  overrides: [
    logsBetweenProvider.overrideWith((ref, range) => Stream.value(logs)),
  ],
  child: MaterialApp(
    home: Scaffold(body: HabitActionsSheet(task: task)),
  ),
);

void main() {
  testWidgets('marks only the days logged for this habit', (tester) async {
    final logs = [
      // This habit: two completed days.
      _log(id: 1, taskId: 1, daysAgo: 0),
      _log(id: 2, taskId: 1, daysAgo: 1),
      // Another habit in the same two-week window: must not show up here.
      _log(id: 3, taskId: 2, daysAgo: 2),
      _log(id: 4, taskId: 2, daysAgo: 3),
      _log(id: 5, taskId: 2, daysAgo: 4),
    ];

    await tester.pumpWidget(_sheet(_habit(id: 1, title: 'Зарядка'), logs));
    await tester.pumpAndSettle();

    expect(_completedSquares(tester), 2);
  });

  testWidgets('a habit with no logs of its own shows nothing marked', (
    tester,
  ) async {
    final logs = [
      _log(id: 1, taskId: 2, daysAgo: 0),
      _log(id: 2, taskId: 2, daysAgo: 1),
    ];

    await tester.pumpWidget(_sheet(_habit(id: 1, title: 'Чтение'), logs));
    await tester.pumpAndSettle();

    expect(_completedSquares(tester), 0);
  });

  testWidgets('incomplete logs are not counted as done', (tester) async {
    final logs = [
      _log(id: 1, taskId: 1, daysAgo: 0, completed: false),
      _log(id: 2, taskId: 1, daysAgo: 1),
    ];

    await tester.pumpWidget(_sheet(_habit(id: 1, title: 'Вода'), logs));
    await tester.pumpAndSettle();

    expect(_completedSquares(tester), 1);
  });

  group('days outside the schedule', () {
    // Weekly on today's weekday only, so the window holds exactly two scheduled
    // days — today and the same weekday a week ago — whenever the suite runs.
    Task weeklyToday() => _habit(
      id: 1,
      title: 'Зал',
      repeatType: RepeatType.weekly,
      weekdays: {_today.weekday},
    );

    testWidgets('are drawn as dots, not as empty squares', (tester) async {
      await tester.pumpWidget(_sheet(weeklyToday(), const []));
      await tester.pumpAndSettle();

      expect(_dots(tester), 12);
      expect(_squares(tester), 2);
    });

    testWidgets('are still tappable — only the future is inert', (
      tester,
    ) async {
      await tester.pumpWidget(_sheet(weeklyToday(), const []));
      await tester.pumpAndSettle();

      // Every day that has arrived accepts a tap, scheduled or not: the full
      // previous week plus this week up to today. Days ahead do not.
      expect(_tappableDays(tester), 7 + _today.weekday);
    });

    testWidgets('a missed day is hollow', (tester) async {
      await tester.pumpWidget(_sheet(weeklyToday(), const []));
      await tester.pumpAndSettle();

      // Last week's occurrence went unmarked, today is still open.
      expect(_hollowSquares(tester), 1);
    });

    testWidgets('a daily habit has no off days', (tester) async {
      await tester.pumpWidget(_sheet(_habit(id: 1, title: 'Вода'), const []));
      await tester.pumpAndSettle();

      expect(_dots(tester), 0);
      expect(_squares(tester), 14);
    });
  });
}
