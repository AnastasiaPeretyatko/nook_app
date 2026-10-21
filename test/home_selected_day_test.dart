import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/home_page.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/widgets/home/day_schedule_section.dart';

/// The day the home screen opens on is a **day**, not the moment the app
/// happened to launch.
///
/// It used to be `DateTime.now()`, and the consequences were spread thin enough
/// to be easy to miss. `recurrence.dart` strips the time on every comparison, so
/// the schedule itself was never wrong, and `TasksDao` now folds a log onto its
/// day on the way in, so nothing lands in the database with a time on it either.
///
/// What is left is the one place the value is used **as a value** rather than as
/// a date: `DayScheduleSection` keys its `AnimatedSwitcher` on it and works out
/// which way to slide by comparing it with the previous one. An instant there
/// means the first tap on today's own date in the calendar — which hands back
/// midnight — reads as a change, and the schedule plays a full backwards
/// day-change animation for a day that did not change.
///
/// `logsForDateProvider` is a `family` keyed by the same value, so an instant
/// also opens a stream nothing else on the screen shares.
void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget app() => ProviderScope(
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
    child: const MaterialApp(
      locale: Locale('ru', 'RU'),
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [Locale('ru', 'RU')],
      home: HomePage(),
    ),
  );

  testWidgets('the day it opens on carries no time', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    final schedule = tester.widget<DayScheduleSection>(
      find.byType(DayScheduleSection),
    );
    final day = schedule.selectedDay;

    expect(
      day,
      DateTime(day.year, day.month, day.day),
      reason: 'the home screen opened on an instant, not on a day',
    );
  });

  testWidgets('tapping today does not animate a day change', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    final before = tester
        .widget<DayScheduleSection>(find.byType(DayScheduleSection))
        .selectedDay;

    // The calendar's own cell for today, scoped to the grid — the header's
    // "today" button carries the same number and sits above it in the tree.
    // `table_calendar` hands `onDaySelected` a day at midnight, so with an
    // instant in state this is a different value for the same date — a key
    // change, and a 260ms slide.
    await tester.tap(
      find
          .descendant(
            of: find.byType(Table),
            matching: find.text('${before.day}'),
          )
          .first,
    );
    await tester.pump();

    final after = tester
        .widget<DayScheduleSection>(find.byType(DayScheduleSection))
        .selectedDay;

    expect(after, before, reason: 'the same day arrived as a different value');
  });
}
