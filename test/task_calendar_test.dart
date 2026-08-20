import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/home/task_calendar.dart';

/// Mid-month, so every task lands on a day the month view actually renders.
final _day = DateTime(2026, 8, 18);

const _taskColor = Color(0xFFFFC1CC);

/// What a dot in [_taskColor] is actually painted in: the task's colour brought
/// to at least 3:1 against the surface under it, so a pale swatch stays visible.
/// Read from the tree rather than hard-coded, since it follows the theme.
Color _dotColor(WidgetTester tester) => inkOn(
  Theme.of(tester.element(find.byType(TaskCalendar))).colorScheme.surface,
  _taskColor,
  minContrast: 3,
);

/// One-off tasks only, so each one puts a dot on exactly one day and the whole
/// calendar contains no dots but the ones under test.
Task _task({
  required int id,
  required String title,
  int? scheduledTimeMinutes,
  TaskStatus status = TaskStatus.active,
}) => Task(
  id: id,
  title: title,
  status: status,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: scheduledTimeMinutes,
  colorValue: 0xFFFFC1CC, // == _taskColor
  startDate: _day,
  createdAt: _day,
  updatedAt: _day,
);

Widget _calendar(List<Task> tasks) => ProviderScope(
  overrides: [rootTasksProvider.overrideWith((ref) => Stream.value(tasks))],
  child: MaterialApp(
    locale: const Locale('ru', 'RU'),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ru', 'RU')],
    home: Scaffold(
      body: TaskCalendar(
        focusedDay: _day,
        selectedDay: _day,
        calendarFormat: CalendarFormat.month,
        onDaySelected: (_, _) {},
        onPageChanged: (_) {},
      ),
    ),
  ),
);

/// Marker dots, picked out by their 5px size — day cells are circles too, and
/// matching on colour would be brittle for the neutral overflow dot.
Iterable<BoxDecoration> _dotDecorations(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .where((c) => c.constraints?.maxWidth == 5)
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .where((d) => d.shape == BoxShape.circle);

int _colouredDots(WidgetTester tester) =>
    _dotDecorations(tester).where((d) => d.color == _dotColor(tester)).length;

int _moreDots(WidgetTester tester) =>
    _dotDecorations(tester).where((d) => d.color != _dotColor(tester)).length;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
  });

  testWidgets('counts tasks without a time as well', (tester) async {
    await tester.pumpWidget(
      _calendar([
        _task(id: 1, title: 'Со временем', scheduledTimeMinutes: 10 * 60),
        _task(id: 2, title: 'Тоже со временем', scheduledTimeMinutes: 18 * 60),
        _task(id: 3, title: 'Без времени'),
        _task(id: 4, title: 'Тоже без времени'),
      ]),
    );
    await tester.pumpAndSettle();

    // All four, not just the two on the clock.
    expect(_colouredDots(tester), 4);
    expect(_moreDots(tester), 0);
  });

  testWidgets('a day with no tasks gets no dots', (tester) async {
    await tester.pumpWidget(_calendar(const []));
    await tester.pumpAndSettle();

    expect(_colouredDots(tester), 0);
  });

  testWidgets('archived tasks are not counted', (tester) async {
    await tester.pumpWidget(
      _calendar([
        _task(id: 1, title: 'Активная'),
        _task(id: 2, title: 'В архиве', status: TaskStatus.archived),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_colouredDots(tester), 1);
  });

  testWidgets('an overflowing day ends with a neutral dot', (tester) async {
    await tester.pumpWidget(
      _calendar([
        for (var i = 1; i <= 7; i++) _task(id: i, title: 'Задача $i'),
      ]),
    );
    await tester.pumpAndSettle();

    // Three of the day's own colours plus one marker standing for the rest, so
    // the cell never claims to hold exactly four.
    expect(_colouredDots(tester), 3);
    expect(_moreDots(tester), 1);
  });

  testWidgets('exactly four tasks fit without a neutral dot', (tester) async {
    await tester.pumpWidget(
      _calendar([
        for (var i = 1; i <= 4; i++) _task(id: i, title: 'Задача $i'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_colouredDots(tester), 4);
    expect(_moreDots(tester), 0);
  });
}
