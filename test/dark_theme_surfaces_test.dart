import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/pages/habits_page.dart';
import 'package:todo_app/pages/home_page.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/habits/task_actions_sheet.dart';

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

final _dark = buildAppTheme(const Color(0xFFD33243), Brightness.dark);

final _task = Task(
  dirty: false,
  id: 1,
  title: 'Read book',
  status: TaskStatus.active,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: 10 * 60 + 15,
  endTimeMinutes: 11 * 60 + 15,
  colorValue: 0xFFE998A1,
  startDate: _today,
  createdAt: _today,
  updatedAt: _today,
);

Widget _app(Widget home) => ProviderScope(
  overrides: [
    rootTasksProvider.overrideWith((ref) => Stream.value([_task])),
    allTasksProvider.overrideWith((ref) => Stream.value([_task])),
    subtasksProvider.overrideWith((ref, parentId) => Stream.value(const [])),
    logsForDateProvider.overrideWith(
      (ref, date) => Stream.value(const <TaskLog>[]),
    ),
    allLogsProvider.overrideWith((ref) => Stream.value(const <TaskLog>[])),
    logsBetweenProvider.overrideWith(
      (ref, range) => Stream.value(const <TaskLog>[]),
    ),
    openSessionsProvider.overrideWith(
      (ref) => Stream.value(const <TaskSession>[]),
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
    theme: _dark,
    home: home,
  ),
);

/// "Август" — the calendar's own header, capitalised the same way.
String _monthLabel() {
  final month = DateFormat.MMMM('ru_RU').format(_today);
  return '${month[0].toUpperCase()}${month.substring(1)}';
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// Every box painted in a flat colour, so a stray white slab cannot hide.
Iterable<Color> _paintedSurfaces(WidgetTester tester) => [
  for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)))
    if (box.decoration case BoxDecoration(:final color?)) color,
  for (final box in tester.widgetList<Container>(find.byType(Container)))
    if (box.decoration case BoxDecoration(:final color?)) color,
];

/// Guards the two checks above from passing on an empty tree.
void _expectSomethingWasPainted(WidgetTester tester) {
  expect(_paintedSurfaces(tester), isNotEmpty);
  expect(tester.widgetList<Text>(find.byType(Text)), isNotEmpty);
}

/// Contrast of every explicitly coloured label against the surface it is on.
void _expectLabelsRead(WidgetTester tester, Color surface) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final color = text.style?.color;
    // A null colour inherits the theme's, which is dark-theme correct.
    if (color == null) continue;
    expect(
      _contrast(Color.alphaBlend(color, surface), surface),
      greaterThanOrEqualTo(3.0),
      reason: '"${text.data}" is drawn in $color',
    );
  }
}

/// Fill colour of the tab bar's selected thumb, whatever tone it is.
Color _tabThumbColour(WidgetTester tester) {
  final container = tester
      .widgetList<Container>(find.byType(Container))
      .firstWhere(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).borderRadius ==
                BorderRadius.circular(999),
      );
  return ((container.decoration! as BoxDecoration).color)!;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1000, 2600);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  group('the task form in the dark theme', () {
    testWidgets('paints no white cards', (tester) async {
      await tester.pumpWidget(_app(const CreateTaskPage()));
      await tester.pumpAndSettle();

      _expectSomethingWasPainted(tester);
      expect(_paintedSurfaces(tester), isNot(contains(Colors.white)));
    });

    testWidgets('every label reads on its card', (tester) async {
      await tester.pumpWidget(_app(const CreateTaskPage()));
      await tester.pumpAndSettle();

      _expectSomethingWasPainted(tester);
      _expectLabelsRead(tester, raisedSurface(_dark));
    });
  });

  group('the actions sheet in the dark theme', () {
    Widget sheet() => Scaffold(
      body: Builder(
        builder: (context) => TaskActionsSheet(task: _task, completed: false),
      ),
    );

    testWidgets('is not a white card', (tester) async {
      await tester.pumpWidget(_app(sheet()));
      await tester.pumpAndSettle();

      _expectSomethingWasPainted(tester);
      expect(_paintedSurfaces(tester), isNot(contains(Colors.white)));
    });

    testWidgets('every label reads on the sheet', (tester) async {
      await tester.pumpWidget(_app(sheet()));
      await tester.pumpAndSettle();

      _expectSomethingWasPainted(tester);
      _expectLabelsRead(tester, raisedSurface(_dark));
    });

    testWidgets('the action colours are lifted to read on it', (tester) async {
      final sheetColor = raisedSurface(_dark);
      // Indigo "изменить" is the one that vanishes on near-black untouched.
      const indigo = Color(0xFF4C5CE0);
      expect(_contrast(indigo, sheetColor), lessThan(4.5));
      expect(
        _contrast(inkOn(sheetColor, indigo), sheetColor),
        greaterThanOrEqualTo(4.5),
      );
      // On a white sheet it already reads, so it is left exactly as it is.
      expect(inkOn(Colors.white, indigo), indigo);
    });
  });

  group('the habits screen in the dark theme', () {
    testWidgets('paints no white slabs', (tester) async {
      await tester.pumpWidget(_app(const HabitsPage()));
      await tester.pumpAndSettle();
      // The rows live on the "Задачи" tab, which is not the one that opens.
      await tester.tap(find.text('Задачи'));
      await tester.pumpAndSettle();

      _expectSomethingWasPainted(tester);
      expect(_paintedSurfaces(tester), isNot(contains(Colors.white)));
      expect(
        _paintedSurfaces(tester),
        isNot(contains(const Color(0xFFF7F7F8))),
        reason: 'the light-theme task row',
      );
      expect(
        _paintedSurfaces(tester),
        isNot(contains(const Color(0xFFEFEFF0))),
        reason: 'the light-theme tab track',
      );
    });

    testWidgets('the date, the tabs and the task rows all read', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const HabitsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Задачи'));
      await tester.pumpAndSettle();

      // Task rows are the lightest surface on the screen, so checking against
      // them is the strict end of the range.
      _expectLabelsRead(tester, rowSurface(_dark));
    });

    testWidgets('the selected tab label reads on its thumb', (tester) async {
      await tester.pumpWidget(_app(const HabitsPage()));
      await tester.pumpAndSettle();

      final thumb = _tabThumbColour(tester);
      expect(thumb, isNot(const Color(0xFFD1D1D6)));
      expect(
        _contrast(Color.alphaBlend(onTaskColor(thumb), thumb), thumb),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('the home screen in the dark theme', () {
    testWidgets('the month and the year read on the page', (tester) async {
      await tester.pumpWidget(_app(const HomePage()));
      await tester.pumpAndSettle();

      _expectSomethingWasPainted(tester);
      expect(find.text(_monthLabel()), findsOneWidget);
      expect(find.text('${_today.year}'), findsOneWidget);
      // The calendar sits on the page, the timeline on its sheet; the sheet is
      // the lighter of the two, so it is the stricter background to check.
      _expectLabelsRead(tester, raisedSurface(_dark));
    });
  });
}
