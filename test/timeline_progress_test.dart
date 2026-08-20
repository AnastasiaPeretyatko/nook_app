import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/home/task_timeline.dart';

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);
final _yesterday = _today.subtract(const Duration(days: 1));

/// Minutes since midnight, right now.
int get _nowMinutes => _now.hour * 60 + _now.minute;

/// A one-off ranged task. [on] must be the day being rendered: without a repeat
/// rule the task falls on its start date only.
/// The pink family of the palette, so its light tone is an exact lookup.
const _accent = Color(0xFFD98BA8);

Task _ranged({
  required int id,
  required String title,
  required int start,
  required int end,
  DateTime? on,
}) => Task(
  id: id,
  title: title,
  status: TaskStatus.active,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: start,
  endTimeMinutes: end,
  colorValue: 0xFFD98BA8, // == _accent
  startDate: on ?? _today,
  createdAt: on ?? _today,
  updatedAt: on ?? _today,
);

Widget _timeline(List<Task> tasks, {DateTime? day}) => ProviderScope(
  overrides: [
    rootTasksProvider.overrideWith((ref) => Stream.value(tasks)),
    allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
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
    home: Scaffold(body: TaskTimeline(selectedDay: day ?? _today)),
  ),
);

/// The "now" label, found by its weight rather than by its text: comparing
/// against a captured timestamp goes flaky the moment the clock ticks mid-test.
/// Nothing else on the timeline is set in w800 — titles are w700, the gap label
/// w600, the time column normal.
Finder _nowMarker() => find.byWidgetPredicate(
  (w) => w is Text && w.style?.fontWeight == FontWeight.w800,
);

/// How much of the pill is painted in the task colour, 0…1.
double _fillFraction(WidgetTester tester) {
  final box = tester.widget<FractionallySizedBox>(
    find.byType(FractionallySizedBox),
  );
  return box.heightFactor ?? 0;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
  });

  group('pill fill', () {
    testWidgets('a task still ahead reads as empty', (tester) async {
      // Two hours from now, clamped so it stays inside the day.
      final start = (_nowMinutes + 120).clamp(0, 22 * 60);
      await tester.pumpWidget(
        _timeline([
          _ranged(id: 1, title: 'Позже', start: start, end: start + 60),
        ]),
      );
      await tester.pumpAndSettle();

      expect(_fillFraction(tester), 0);
    });

    testWidgets('a finished task is filled to the top', (tester) async {
      await tester.pumpWidget(
        _timeline([_ranged(id: 1, title: 'Утро', start: 8 * 60, end: 9 * 60)]),
      );
      await tester.pumpAndSettle();

      expect(_fillFraction(tester), 1);
    });

    testWidgets(
      'a running task is filled part way',
      (tester) async {
        // A four-hour window with now sitting one hour in — a quarter elapsed.
        final start = _nowMinutes - 60;
        final task = _ranged(
          id: 1,
          title: 'Идёт',
          start: start,
          end: start + 240,
        );
        await tester.pumpWidget(_timeline([task]));
        await tester.pumpAndSettle();

        expect(_fillFraction(tester), closeTo(0.25, 0.01));
      },
      skip: _nowMinutes < 60 || _nowMinutes + 180 > 24 * 60,
    );

    testWidgets('another day is drawn as fully elapsed', (tester) async {
      await tester.pumpWidget(
        _timeline([
          _ranged(
            id: 1,
            title: 'Вчера',
            start: 10 * 60,
            end: 11 * 60,
            on: _yesterday,
          ),
        ], day: _yesterday),
      );
      await tester.pumpAndSettle();

      expect(_fillFraction(tester), 1);
    });
  });

  group('now marker', () {
    testWidgets(
      'shows the current time inside a running task',
      (tester) async {
        final start = _nowMinutes - 30;
        await tester.pumpWidget(
          _timeline([
            _ranged(id: 1, title: 'Идёт', start: start, end: start + 120),
          ]),
        );
        await tester.pumpAndSettle();

        expect(_nowMarker(), findsOneWidget);
      },
      skip: _nowMinutes < 30 || _nowMinutes + 90 > 24 * 60,
    );

    testWidgets(
      'is centred on the moment, level with the fill boundary',
      (tester) async {
        // Two hours long with 30 minutes gone: the fill ends a quarter down, and
        // the bold time must sit level with that edge, not hang below it.
        final start = _nowMinutes - 30;
        await tester.pumpWidget(
          _timeline([
            _ranged(id: 1, title: 'Идёт', start: start, end: start + 120),
          ]),
        );
        await tester.pumpAndSettle();

        final marker = tester.getRect(_nowMarker());
        // The filled part of the pill starts at its top, so its bottom edge is
        // the current moment.
        final fill = tester.getRect(find.byType(FractionallySizedBox));

        expect(marker.center.dy, closeTo(fill.bottom, 2));
      },
      skip: _nowMinutes < 30 || _nowMinutes + 90 > 24 * 60,
    );

    testWidgets('stays away from another day', (tester) async {
      await tester.pumpWidget(
        _timeline([
          _ranged(
            id: 1,
            title: 'Вчера',
            start: 10 * 60,
            end: 11 * 60,
            on: _yesterday,
          ),
        ], day: _yesterday),
      );
      await tester.pumpAndSettle();

      expect(_nowMarker(), findsNothing);
    });
  });

  group('marker styling', () {
    testWidgets(
      'nothing on the timeline casts a shadow',
      (tester) async {
        final start = _nowMinutes - 30;
        await tester.pumpWidget(
          _timeline([
            _ranged(id: 1, title: 'Идёт', start: start, end: start + 120),
          ]),
        );
        await tester.pumpAndSettle();

        final shadows = tester
            .widgetList<Widget>(find.byType(Container))
            .whereType<Container>()
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .where((d) => d.boxShadow?.isNotEmpty ?? false);
        expect(shadows, isEmpty);
      },
      skip: _nowMinutes < 30 || _nowMinutes + 90 > 24 * 60,
    );

    testWidgets(
      'the now marker is just the time, with no line across the row',
      (tester) async {
        final start = _nowMinutes - 30;
        await tester.pumpWidget(
          _timeline([
            _ranged(id: 1, title: 'Идёт', start: start, end: start + 120),
          ]),
        );
        await tester.pumpAndSettle();

        final marker = tester.getRect(_nowMarker());

        // It lives in the 56dp time column. The exact width depends on the font
        // — what matters is that nothing runs off to the right, as the old line
        // did all the way to the 800dp screen edge.
        expect(marker.right, lessThan(120));
      },
      skip: _nowMinutes < 30 || _nowMinutes + 90 > 24 * 60,
    );
  });

  testWidgets('the timeline keeps ticking without leaking its timer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _timeline([_ranged(id: 1, title: 'Утро', start: 8 * 60, end: 9 * 60)]),
    );
    await tester.pumpAndSettle();

    // Replacing the tree disposes the timeline; a surviving timer would make the
    // test fail with a pending-timer error.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
  });

  group('the two tones of a family', () {
    testWidgets('a pill is the light tone, filled with the accent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _timeline([_ranged(id: 1, title: 'Утро', start: 8 * 60, end: 9 * 60)]),
      );
      await tester.pumpAndSettle();

      // The body of the pill: a light-tone base with the accent filled over it.
      final base = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .map((b) => b.color)
          .toList();
      expect(base, contains(taskLightTone(_accent)));

      final fill = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(FractionallySizedBox),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((fill.decoration as BoxDecoration?)?.color, _accent);
    });

    testWidgets('the glyph on a filled marker is white', (tester) async {
      await tester.pumpWidget(
        _timeline([_ranged(id: 1, title: 'Утро', start: 8 * 60, end: 9 * 60)]),
      );
      await tester.pumpAndSettle();

      // The morning task is over, so the pill is solid accent underneath it.
      final icons = tester
          .widgetList<Icon>(find.byType(Icon))
          .map((i) => i.color)
          .toList();
      expect(icons, contains(Colors.white));
    });
  });
}
