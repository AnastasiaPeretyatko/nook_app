import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/main.dart';
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
  dirty: false,
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
    home: Scaffold(body: child ?? TaskTimeline(selectedDay: _today)),
  ),
);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// Every flat colour the timeline paints a box with.
Iterable<Color> _painted(WidgetTester tester) => [
  for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)))
    if (box.decoration case BoxDecoration(:final color?)) color,
  for (final m in tester.widgetList<Material>(find.byType(Material))) ?m.color,
];

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
  });

  testWidgets('the cards are not white slabs in the dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(_darkTimeline());
    await tester.pumpAndSettle();

    final theme = buildAppTheme(_accent, Brightness.dark);
    expect(_painted(tester), isNot(contains(Colors.white)));
    // The cards are the dark card tone, lifted above the page behind them.
    expect(_painted(tester), contains(theme.colorScheme.surface));
    expect(
      theme.colorScheme.surface.computeLuminance(),
      greaterThan(theme.scaffoldBackgroundColor.computeLuminance()),
    );
  });

  testWidgets('every label on the timeline reads on the dark card', (
    tester,
  ) async {
    await tester.pumpWidget(_darkTimeline());
    await tester.pumpAndSettle();

    final sheet = buildAppTheme(_accent, Brightness.dark).colorScheme.surface;

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
}
