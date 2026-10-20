import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/pages/habit_detail_page.dart';
import 'package:todo_app/pages/habits_page.dart';
import 'package:todo_app/settings/theme_provider.dart';

final _stamp = DateTime(2026, 1, 1);
final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);
DateTime _ago(int n) => DateTime(_today.year, _today.month, _today.day - n);

/// [age]: how many days ago it began — under 28 is "young", up to 92 is
/// weeks, beyond that months.
Task _habit({int? time = 22 * 60, int age = 40}) => Task(
  dirty: false,
  id: 1,
  title: 'Медитация',
  status: TaskStatus.active,
  repeatType: RepeatType.daily,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: time,
  startDate: _ago(age),
  createdAt: _stamp,
  updatedAt: _stamp,
);

/// How many minutes after its time each mark of [_logs] was made.
int _offset = 0;

/// Ticked on the 9th to the 4th day back and the last two; the 3rd back is
/// missed. Each at its time on the dot.
List<TaskLog> _logs() => [
  for (final n in [9, 8, 7, 6, 5, 4, 2, 1])
    TaskLog(
      dirty: false,
      updatedAt: _stamp,
      id: n,
      taskId: 1,
      date: _ago(n),
      completed: true,
      completedAt: DateTime(
        _ago(n).year,
        _ago(n).month,
        _ago(n).day,
        22,
        _offset,
      ),
    ),
];

Future<void> _pump(WidgetTester tester, Widget home, List<Task> tasks) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        rootTasksProvider.overrideWith((ref) => Stream.value(tasks)),
        logsForTaskProvider.overrideWith((ref, id) => Stream.value(_logs())),
        logsBetweenProvider.overrideWith((ref, r) => Stream.value(_logs())),
        allLogsProvider.overrideWith((ref) => Stream.value(_logs())),
        openSessionsProvider.overrideWith((ref) => Stream.value(const [])),
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
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU', null));
  setUp(() => _offset = 0);

  testWidgets('shows who the habit is, its streaks and how often it is done', (
    tester,
  ) async {
    await _pump(tester, const HabitDetailPage(taskId: 1), [_habit()]);

    expect(find.text('Привычка'), findsOneWidget);
    expect(find.text('Медитация'), findsOneWidget);
    expect(find.textContaining('Каждый день · 22:00'), findsOneWidget);
    // Two in a row since the miss; the best run was six.
    expect(find.text('2 дня', findRichText: true), findsOneWidget);
    expect(find.text('Лучшая — 6 дней'), findsOneWidget);
    expect(find.text('8 из 40', findRichText: true), findsOneWidget);
    expect(find.text('20% за всё время'), findsOneWidget);
  });

  group('"Всё время" by how old the habit is', () {
    testWidgets('under four weeks there is no such tab, only the month', (
      tester,
    ) async {
      await _pump(tester, const HabitDetailPage(taskId: 1), [_habit(age: 9)]);

      expect(find.text('Всё время'), findsNothing);
      expect(find.text('Месяц'), findsOneWidget);
      expect(find.text('Год'), findsOneWidget);
      // It opens on the month, with the day it began under the calendar.
      expect(find.text('Каждый месяц'), findsNothing);
      expect(find.text('Каждая неделя'), findsNothing);
      expect(find.textContaining('Создана '), findsOneWidget);
      expect(find.textContaining('· 10 дней'), findsOneWidget);
    });

    testWidgets('the month calendar draws every day, also before the habit', (
      tester,
    ) async {
      await _pump(tester, const HabitDetailPage(taskId: 1), [_habit(age: 1)]);

      final days = DateTime(_today.year, _today.month + 1, 0).day;
      final numbers = find.descendant(
        of: find.byType(GridView).first,
        matching: find.byType(Text),
      );
      expect(numbers, findsNWidgets(days));
    });

    testWidgets('a habit of one to three months gets a bar per week', (
      tester,
    ) async {
      await _pump(tester, const HabitDetailPage(taskId: 1), [_habit(age: 40)]);

      expect(find.text('Всё время'), findsOneWidget);
      expect(find.text('Каждая неделя'), findsOneWidget);
      expect(find.text('Каждый месяц'), findsNothing);
      expect(find.text('По дням недели'), findsOneWidget);
      expect(find.textContaining('Среднее по неделям'), findsOneWidget);
      expect(find.textContaining('С '), findsWidgets);
    });

    testWidgets('beyond three months it is a bar per month', (tester) async {
      await _pump(tester, const HabitDetailPage(taskId: 1), [_habit(age: 200)]);

      expect(find.text('Каждый месяц'), findsOneWidget);
      expect(find.text('Каждая неделя'), findsNothing);
      expect(find.textContaining('Среднее по месяцам'), findsOneWidget);
    });

    testWidgets('the edges: 27 days is young, 28 is weeks, 93 is months', (
      tester,
    ) async {
      // `age` is days ago, so the history is age + 1 days long.
      for (final (age, young, weeks) in [
        (26, true, false),
        (27, false, true),
        (91, false, true),
        (92, false, false),
      ]) {
        await _pump(tester, const HabitDetailPage(taskId: 1), [
          _habit(age: age),
        ]);
        expect(find.text('Всё время'), young ? findsNothing : findsOneWidget);
        if (!young) {
          expect(
            find.text('Каждая неделя'),
            weeks ? findsOneWidget : findsNothing,
            reason: '$age',
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  testWidgets('the tabs swap the middle of the page', (tester) async {
    await _pump(tester, const HabitDetailPage(taskId: 1), [_habit()]);

    await tester.tap(find.text('Год'));
    await tester.pumpAndSettle();
    expect(find.text('Последние 12 месяцев'), findsOneWidget);
    expect(find.text('Каждый месяц'), findsNothing);

    await tester.tap(find.text('Месяц'));
    await tester.pumpAndSettle();
    expect(find.text('Последние 12 месяцев'), findsNothing);
    expect(find.text('Каждый месяц'), findsNothing);
    expect(find.text('Во сколько выполняешь'), findsOneWidget);
  });

  testWidgets('the time chart needs a time, and says when it runs', (
    tester,
  ) async {
    await _pump(tester, const HabitDetailPage(taskId: 1), [_habit()]);
    expect(find.text('Во сколько выполняешь'), findsOneWidget);
    expect(find.textContaining('вовремя'), findsWidgets);
  });

  testWidgets('a habit with no time has no time chart', (tester) async {
    await _pump(tester, const HabitDetailPage(taskId: 1), [_habit(time: null)]);
    expect(find.text('Во сколько выполняешь'), findsNothing);
  });

  testWidgets('a tap on a habit opens its page, holding it opens the sheet', (
    tester,
  ) async {
    await _pump(tester, const HabitsPage(), [_habit()]);

    await tester.longPress(find.text('Медитация'));
    await tester.pumpAndSettle();
    expect(find.text('Изменить'), findsOneWidget);
    Navigator.of(tester.element(find.text('Изменить'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Медитация'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitDetailPage), findsOneWidget);
    expect(find.text('Другие действия'), findsOneWidget);
  });

  testWidgets('the tally under the title stays on one line, on every tab', (
    tester,
  ) async {
    // Narrow, so that a long title and a long tally would both want the row.
    tester.view.physicalSize = const Size(320, 3000);
    await _pump(tester, const HabitDetailPage(taskId: 1), [_habit()]);
    tester.view.physicalSize = const Size(320, 3000);
    tester.view.devicePixelRatio = 1;

    for (final tab in ['Год', 'Месяц']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      final tally = find.textContaining(' поздно · ');
      expect(tally, findsOneWidget);
      expect(tester.getSize(tally).height, lessThan(20), reason: tab);
    }
  });

  group('the line under the time chart', () {
    Future<void> insight(WidgetTester tester, int offset, String says) async {
      _offset = offset;
      await _pump(tester, const HabitDetailPage(taskId: 1), [_habit()]);
      expect(find.textContaining(says), findsOneWidget);
    }

    testWidgets('on the dot is "вовремя"', (tester) async {
      await insight(tester, 0, 'отмечается около 22:00, вовремя.');
    });

    testWidgets('under an hour it counts minutes', (tester) async {
      await insight(tester, 25, 'на 25 минут позже плана');
    });

    testWidgets('from an hour up it rounds to whole hours', (tester) async {
      await insight(tester, 60, 'на 1 час позже плана');
    });

    testWidgets('an hour and a half is two, a hundred minutes too', (
      tester,
    ) async {
      await insight(tester, 100, 'на 2 часа позже плана');
    });

    testWidgets('a long delay is "часов"', (tester) async {
      await insight(tester, 300, 'на 5 часов позже плана');
    });
  });
}
