import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/habits_page.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/widgets/home/task_calendar.dart';

/// The two screens' top headings — "27 августа ЧТ" over the habits and
/// "Август 2026" over the day screen — are written in the same style and have
/// to come out the same size, at every system font size and not only at 1.0.
///
/// They did not: the habits one was a bare `RichText`, which defaults to
/// `TextScaler.noScaling`, while the calendar's month is a `Text` and reads
/// `MediaQuery.textScalerOf`. Nothing in either style said so, which is why
/// this is pinned rather than left to a reading of the two files.
void main() {
  const scale = 1.5;
  late SharedPreferences prefs;

  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget wrap(Widget child) => ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      rootTasksProvider.overrideWith((ref) => Stream.value([])),
      allTasksProvider.overrideWith((ref) => Stream.value([])),
      allLogsProvider.overrideWith((ref) => Stream.value([])),
      logsForDateProvider.overrideWith((ref, date) => Stream.value([])),
      logsBetweenProvider.overrideWith((ref, range) => Stream.value([])),
    ],
    child: MaterialApp(
      locale: const Locale('ru', 'RU'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU')],
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: scale,
        maxScaleFactor: scale,
        child: child!,
      ),
      home: child,
    ),
  );

  /// The paragraph carrying [needle], found by its text rather than by widget
  /// type — a `Text` builds a `RichText` of its own, so both spellings answer
  /// the same lookup and the test cannot pass by matching the wrong one.
  RenderParagraph paragraph(WidgetTester tester, String needle) => tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .firstWhere((p) => p.text.toPlainText().contains(needle));

  testWidgets('both top date headings follow the system font size', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const HabitsPage()));
    await tester.pump(const Duration(milliseconds: 400));
    // Read out now: the second tree replaces this one, and a paragraph held
    // across the swap is a render object that has been taken down.
    final habits = paragraph(tester, 'августа');
    final habitsSize = habits.text.style?.fontSize;
    final habitsScaler = habits.textScaler;

    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: TaskCalendar(
            focusedDay: DateTime.now(),
            selectedDay: DateTime.now(),
            calendarFormat: CalendarFormat.week,
            onDaySelected: (_, _) {},
            onPageChanged: (_) {},
            onTodayPressed: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final month = paragraph(tester, 'вгуст');

    expect(habitsSize, isNotNull);
    expect(habitsSize, month.text.style?.fontSize);
    expect(habitsScaler, const TextScaler.linear(scale));
    expect(habitsScaler, month.textScaler);
  });
}
