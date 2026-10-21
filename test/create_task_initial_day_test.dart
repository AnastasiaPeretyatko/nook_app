import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/widgets/app_bottom_nav_bar.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/pages/home_page.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/widgets/home/day_schedule_section.dart';

/// A new task belongs to the day you are looking at, not to the day it is.
///
/// The schedule can be swiped anywhere, and the form used to seed its date from
/// `DateTime.now()` regardless — so a task added while the 1st of September was
/// on screen was saved for whatever today happened to be, and only showed up on
/// the right day after a trip through the date picker.
///
/// Both halves are pinned here: `MainScreen` handing the day over, and the form
/// putting it on screen when it is given one.
void main() {
  late SharedPreferences prefs;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget wrap(Widget home) => ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      rootTasksProvider.overrideWith((ref) => Stream.value(const <Task>[])),
      allTasksProvider.overrideWith((ref) => Stream.value(const <Task>[])),
      allLogsProvider.overrideWith((ref) => Stream.value(const <TaskLog>[])),
      logsForDateProvider.overrideWith(
        (ref, date) => Stream.value(const <TaskLog>[]),
      ),
      logsBetweenProvider.overrideWith(
        (ref, range) => Stream.value(const <TaskLog>[]),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('ru', 'RU'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU')],
      home: home,
    ),
  );

  /// The day the schedule is drawing, read off the widget that draws it rather
  /// than off the provider — the point is what is on screen.
  DateTime shownDay(WidgetTester tester) => tester
      .widget<DayScheduleSection>(find.byType(DayScheduleSection))
      .selectedDay;

  /// A handful of frames. Not `pumpAndSettle`: the schedule runs a ticker for
  /// its "now" marker and never settles. A single `pump` is not enough either —
  /// a route pushed on this frame has not built its page yet.
  Future<void> settleish(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Swipes the schedule one day forward. Not a tap on a calendar cell: the cell
  /// for tomorrow is in the next week's row for one day in seven, and this test
  /// runs on all of them.
  Future<void> swipeToNextDay(WidgetTester tester) async {
    await tester.fling(
      find.byType(DayScheduleSection),
      const Offset(-200, 0),
      600,
    );
    await settleish(tester);
  }

  testWidgets('the "+" button opens the form on the day being looked at', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const MainScreen()));
    await settleish(tester);

    expect(shownDay(tester), today, reason: 'the app did not open on today');

    await swipeToNextDay(tester);
    final tomorrow = today.add(const Duration(days: 1));
    expect(shownDay(tester), tomorrow, reason: 'the swipe changed no day');

    await tester.tap(find.byTooltip('Новая задача'));
    await settleish(tester);

    expect(
      tester.widget<CreateTaskPage>(find.byType(CreateTaskPage)).initialDate,
      tomorrow,
    );
    expect(
      find.textContaining(DateFormat('d MMM', 'ru_RU').format(tomorrow)),
      findsOneWidget,
      reason: 'the form does not show the day it was opened on',
    );
  });

  testWidgets('a tab with no day on it still opens the form on today', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const MainScreen()));
    await settleish(tester);

    await swipeToNextDay(tester);
    // The habits screen is about today whatever the schedule was left showing,
    // so there is no day to inherit here.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNavBar),
        matching: find.text('Привычки'),
      ),
    );
    await settleish(tester);

    await tester.tap(find.byTooltip('Новая задача'));
    await settleish(tester);

    final form = tester.widget<CreateTaskPage>(find.byType(CreateTaskPage));
    expect(form.initialDate, isNull);
    expect(
      find.textContaining(DateFormat('d MMM', 'ru_RU').format(today)),
      findsOneWidget,
    );
  });

  testWidgets('with no day given the form falls back to today', (tester) async {
    await tester.pumpWidget(wrap(const CreateTaskPage()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(DateFormat('d MMM', 'ru_RU').format(today)),
      findsOneWidget,
    );
  });

  testWidgets('the day is a day, whatever the calendar hands over', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const HomePage()));
    await tester.pump();

    // `table_calendar` reports a UTC midnight, so a tap used to put a value in
    // state that carried a time. What a task is created on has to be a plain
    // local day — it becomes `startDate`, which every screen compares date-only.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container
        .read(selectedDayProvider.notifier)
        .select(
          DateTime.utc(
            today.year,
            today.month,
            today.day,
          ).add(const Duration(days: 2)),
        );
    await tester.pump();

    final day = container.read(selectedDayProvider);
    expect(day, DateTime(day.year, day.month, day.day));
    expect(day, today.add(const Duration(days: 2)));
  });
}
