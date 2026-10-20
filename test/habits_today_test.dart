import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/habits/habits_today.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The habits tab in the "Иней" design: one row per habit, today's in one card
/// and the rest under "Не сегодня", and this week's strip on top.
final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);
final _stamp = DateTime(2026, 1, 1);

Task _habit(
  int id,
  String title, {
  RepeatType repeat = RepeatType.daily,
  int? mask,
  int? time,
}) => Task(
  dirty: false,
  id: id,
  title: title,
  status: TaskStatus.active,
  repeatType: repeat,
  repeatDaysMask: mask,
  scheduledTimeMinutes: time,
  trackingMode: TrackingMode.checkbox,
  colorValue: 0xFF9C8DDB,
  startDate: _today.subtract(const Duration(days: 30)),
  createdAt: _today,
  updatedAt: _today,
);

TaskLog _done(int taskId, DateTime day) => TaskLog(
  dirty: false,
  updatedAt: _stamp,
  id: taskId * 1000 + day.day,
  taskId: taskId,
  date: day,
  completed: true,
);

/// The week start, the lateness grace and the "today" switch are read from the
/// store, so anything drawing a habit needs one.
late SharedPreferences _prefs;

Widget _app(Widget body, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_prefs),
        ...overrides,
      ],
      child: MaterialApp(
        theme: buildAppTheme(const Color(0xFF5B6DCB), Brightness.light),
        locale: const Locale('ru', 'RU'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru', 'RU')],
        home: Scaffold(body: body),
      ),
    );

Widget _screen(List<Task> tasks, List<TaskLog> logs) => _app(
  const HabitsToday(),
  overrides: [
    rootTasksProvider.overrideWith((ref) => Stream.value(tasks)),
    logsBetweenProvider.overrideWith((ref, range) => Stream.value(logs)),
    allLogsProvider.overrideWith((ref) => Stream.value(logs)),
    openSessionsProvider.overrideWith((ref) => Stream.value(const [])),
  ],
);

Widget _row(
  Task task, {
  Set<DateTime> completedDays = const {},
  VoidCallback? onMark,
}) => _app(
  HabitRow(
    task: task,
    today: _today,
    completedDays: completedDays,
    todayLog: null,
    timerRunningSince: null,
    onTap: () {},
    onMark: onMark ?? () {},
    onTimerStart: () {},
    onTimerStop: () {},
    onCounterInc: () {},
  ),
);

double contrastRatio(Color a, Color b) {
  final la = Color.alphaBlend(a, b).computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

TextStyle? _titleStyle(WidgetTester tester, String title) =>
    tester.widget<Text>(find.text(title)).style;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  group('a row', () {
    testWidgets('shows the rule and the time under the title', (tester) async {
      await tester.pumpWidget(_row(_habit(1, 'Медитация', time: 22 * 60)));

      expect(find.text('Каждый день · 22:00'), findsOneWidget);
    });

    testWidgets('done today is struck through and offers the untick', (
      tester,
    ) async {
      await tester.pumpWidget(_row(_habit(1, 'Зал'), completedDays: {_today}));

      expect(
        _titleStyle(tester, 'Зал')?.decoration,
        TextDecoration.lineThrough,
      );
      expect(find.byTooltip('Отметить как невыполненное'), findsOneWidget);
    });

    testWidgets('the tick is filled with the task\'s colour, not the accent', (
      tester,
    ) async {
      await tester.pumpWidget(_row(_habit(1, 'Зал'), completedDays: {_today}));

      final circle = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byTooltip('Отметить как невыполненное'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final fill = (circle.decoration! as BoxDecoration).color!;
      // The habit is lavender; its strong tone, on a light screen.
      expect(fill, taskSwatchForKey('violet')!.strong);
      final tick = tester.widget<Icon>(find.byIcon(LucideIcons.check)).color!;
      expect(contrastRatio(tick, fill), greaterThanOrEqualTo(4.5));
    });

    testWidgets('a day done earlier does not tick today', (tester) async {
      var marks = 0;
      await tester.pumpWidget(
        _row(
          _habit(1, 'Зал'),
          completedDays: {_today.subtract(const Duration(days: 1))},
          onMark: () => marks++,
        ),
      );

      expect(_titleStyle(tester, 'Зал')?.decoration, isNull);
      await tester.tap(find.byTooltip('Отметить как выполненное'));
      expect(marks, 1);
    });

    for (final scale in [1.0, 1.6]) {
      testWidgets('a long title stays on one line at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: _row(
              _habit(1, 'Очень длинное название привычки, которое не влезет'),
            ),
          ),
        );

        // A flutter_test overflow is a test failure, so rendering is the
        // assertion.
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the screen', () {
    testWidgets('splits today from the days the rule leaves off', (
      tester,
    ) async {
      // A weekly habit on the weekday after today: never due today.
      final otherDay = _today.weekday % 7 + 1;
      await tester.pumpWidget(
        _screen(
          [
            _habit(1, 'Зарядка'),
            _habit(2, 'Вода'),
            _habit(
              3,
              'Бассейн',
              repeat: RepeatType.weekly,
              mask: 1 << (otherDay - 1),
            ),
          ],
          [_done(1, _today)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('СЕГОДНЯ'), findsOneWidget);
      expect(find.text('1 из 2'), findsOneWidget);
      expect(find.text('НЕ СЕГОДНЯ'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Бассейн')).dy,
        greaterThan(tester.getTopLeft(find.text('НЕ СЕГОДНЯ')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Вода')).dy,
        lessThan(tester.getTopLeft(find.text('НЕ СЕГОДНЯ')).dy),
      );
    });

    testWidgets('the week strip says which days were fully done', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _screen([_habit(1, 'Зарядка')], [_done(1, _today)]),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('${_today.day}, всё выполнено')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the week strip starts on Sunday when the settings say so', (
      tester,
    ) async {
      await _prefs.setInt('week_start_day', DateTime.sunday);
      addTearDown(() => _prefs.remove('week_start_day'));
      await tester.pumpWidget(_screen([_habit(1, 'Зарядка')], const []));
      await tester.pumpAndSettle();

      final names = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
      final xs = [
        for (final n in names) tester.getTopLeft(find.text(n).first).dx,
      ];
      expect(xs, [...xs]..sort(), reason: 'left to right, Sunday first');
    });
  });
}
