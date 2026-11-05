import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/widgets/date_range_calendar.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU'));

  Finder date(String value) => find.byKey(ValueKey('date-$value'));

  testWidgets('selects a range and toggles individual days inside it', (
    tester,
  ) async {
    var selected = <DateTime>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DateRangeCalendar(
              firstDate: DateTime(2026, 11, 1),
              lastDate: DateTime(2026, 11, 30),
              initialMonth: DateTime(2026, 11),
              selectedDates: selected,
              onSelectionChanged: (days) => setState(() => selected = days),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(date('2026-11-05'));
    await tester.pump();
    await tester.tap(date('2026-11-08'));
    await tester.pump();
    expect(selected, {
      DateTime(2026, 11, 5),
      DateTime(2026, 11, 6),
      DateTime(2026, 11, 7),
      DateTime(2026, 11, 8),
    });

    await tester.tap(date('2026-11-06'));
    await tester.pump();
    expect(selected.contains(DateTime(2026, 11, 6)), isFalse);
    expect(selected, hasLength(3));

    await tester.tap(date('2026-11-06'));
    await tester.pump();
    expect(selected.contains(DateTime(2026, 11, 6)), isTrue);
    expect(selected, hasLength(4));
  });

  testWidgets('keeps a range while navigating across months', (tester) async {
    var selected = <DateTime>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DateRangeCalendar(
              firstDate: DateTime(2026, 11, 1),
              lastDate: DateTime(2026, 12, 31),
              initialMonth: DateTime(2026, 11),
              selectedDates: selected,
              onSelectionChanged: (days) => setState(() => selected = days),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(date('2026-11-29'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('calendar-next-month')));
    await tester.pumpAndSettle();
    expect(find.text('Декабрь 2026'), findsOneWidget);
    await tester.tap(date('2026-12-02'));
    await tester.pump();

    expect(selected, {
      DateTime(2026, 11, 29),
      DateTime(2026, 11, 30),
      DateTime(2026, 12, 1),
      DateTime(2026, 12, 2),
    });

    await tester.tap(find.byKey(const ValueKey('calendar-previous-month')));
    await tester.pumpAndSettle();
    expect(find.text('Ноябрь 2026'), findsOneWidget);
    expect(
      (tester.widget<Container>(date('2026-11-29')).decoration
              as BoxDecoration?)
          ?.color,
      isNotNull,
    );
  });

  testWidgets('single mode replaces the selected date without a range', (
    tester,
  ) async {
    const accent = Color(0xFF2A7190);
    var selected = <DateTime>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light(primary: accent)),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DateRangeCalendar(
              firstDate: DateTime(2026, 11, 1),
              lastDate: DateTime(2026, 11, 30),
              initialMonth: DateTime(2026, 11),
              selectedDates: selected,
              selectionMode: DateSelectionMode.single,
              onSelectionChanged: (days) => setState(() => selected = days),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(date('2026-11-05'));
    await tester.pump();
    expect(selected, {DateTime(2026, 11, 5)});

    await tester.tap(date('2026-11-08'));
    await tester.pump();
    expect(selected, {DateTime(2026, 11, 8)});
    expect(
      (tester.widget<Container>(date('2026-11-05')).decoration
              as BoxDecoration?)
          ?.color,
      isNull,
    );
    expect(
      (tester.widget<Container>(date('2026-11-08')).decoration
              as BoxDecoration?)
          ?.color,
      accent,
    );
  });
}
