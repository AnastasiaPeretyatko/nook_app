import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/widgets/home/day_schedule_section.dart';
import 'package:todo_app/widgets/home/task_timeline.dart';

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

/// The accent the palette opens on; the timeline's own colours must not depend
/// on it either way.
const _accent = Color(0xFFD33243);

Task _task({
  required int id,
  required String title,
  required int start,
  int? end,
  int? colorValue,
}) => Task(
  id: id,
  title: title,
  status: TaskStatus.active,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: start,
  endTimeMinutes: end,
  colorValue: colorValue ?? 0xFFE998A1,
  startDate: _today,
  createdAt: _today,
  updatedAt: _today,
);

final _tasks = [
  _task(id: 1, title: 'Утро', start: 8 * 60, end: 9 * 60),
  // Far enough after the first to leave a gap row between them.
  _task(id: 2, title: 'Вечер', start: 20 * 60),
  _task(id: 3, title: 'Полночь', start: 0),
];

Widget _darkTimeline({Widget? child}) => ProviderScope(
  overrides: [
    rootTasksProvider.overrideWith((ref) => Stream.value(_tasks)),
    allTasksProvider.overrideWith((ref) => Stream.value(_tasks)),
    logsForDateProvider.overrideWith(
      (ref, date) => Stream.value(const <TaskLog>[]),
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
    theme: buildAppTheme(_accent, Brightness.dark),
    home: Scaffold(
      body: child ?? TaskTimeline(selectedDay: _today),
    ),
  ),
);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// The sheet the timeline is drawn on, in the dark theme.
Color _sheetColor(WidgetTester tester) {
  // The sheet is the outermost decorated box of the section.
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(DayScheduleSection),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return ((box.decoration as BoxDecoration).color)!;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
  });

  testWidgets('the sheet is not a white slab in the dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      _darkTimeline(
        child: DayScheduleSection(
          selectedDay: _today,
          onHandleDragUpdate: (_) {},
          onHandleDragEnd: (_) {},
          onDayChange: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sheet = _sheetColor(tester);
    expect(sheet, isNot(Colors.white));
    // Lifted above the page behind it, which is the darkest surface.
    expect(
      sheet.computeLuminance(),
      greaterThan(buildAppTheme(
        _accent,
        Brightness.dark,
      ).colorScheme.surface.computeLuminance()),
    );
  });

  testWidgets('every label on the timeline reads on the dark sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_darkTimeline());
    await tester.pumpAndSettle();

    final sheet = buildAppTheme(
      _accent,
      Brightness.dark,
    ).colorScheme.surfaceContainerLow;

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final color = text.style?.color;
      // A null colour inherits from the theme, which is dark-theme correct.
      if (color == null) continue;
      expect(
        _contrast(Color.alphaBlend(color, sheet), sheet),
        greaterThanOrEqualTo(3.0),
        reason: '"${text.data}" is drawn in $color',
      );
    }
  });

  testWidgets('the hanging line follows the theme', (tester) async {
    await tester.pumpWidget(_darkTimeline());
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(TaskTimeline));
    expect(
      TaskTimeline.lineColorOf(context),
      Theme.of(context).colorScheme.outlineVariant,
    );
    expect(TaskTimeline.lineColorOf(context), isNot(const Color(0xFFD9D9D9)));
  });
}
