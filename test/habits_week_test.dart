import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/pages/habits_page.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// The habits screen's two views: today, and how the week went.
final _stamp = DateTime(2026, 1, 1);

Task _habit(int id, String title) => Task(
  dirty: false,
  id: id,
  title: title,
  status: TaskStatus.active,
  repeatType: RepeatType.daily,
  trackingMode: TrackingMode.checkbox,
  startDate: DateTime(2026, 1, 1),
  createdAt: _stamp,
  updatedAt: _stamp,
);

Future<void> _pump(WidgetTester tester, List<Task> tasks) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        rootTasksProvider.overrideWith((ref) => Stream.value(tasks)),
        logsBetweenProvider.overrideWith(
          (ref, range) => Stream.value(const <TaskLog>[]),
        ),
        allLogsProvider.overrideWith((ref) => Stream.value(const <TaskLog>[])),
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
        home: const HabitsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU', null));

  testWidgets('opens on today', (tester) async {
    await _pump(tester, [_habit(1, 'Зарядка')]);
    expect(find.text('Сегодня'), findsWidgets);
    expect(find.text('Зарядка'), findsOneWidget);
    expect(find.text('ПО ПРИВЫЧКАМ'), findsNothing);
  });

  testWidgets('a sideways swipe moves between "Сегодня" and "Неделя"', (
    tester,
  ) async {
    await _pump(tester, [_habit(1, 'Зарядка')]);

    await tester.fling(find.text('Зарядка'), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('ПО ПРИВЫЧКАМ'), findsOneWidget);

    // Nowhere further left; and right goes back.
    await tester.fling(find.text('Зарядка'), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('ПО ПРИВЫЧКАМ'), findsOneWidget);
    await tester.fling(find.text('Зарядка'), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('ПО ПРИВЫЧКАМ'), findsNothing);
  });

  testWidgets('"Неделя" shows the summary and every habit', (tester) async {
    await _pump(tester, [_habit(1, 'Зарядка'), _habit(2, 'Чтение')]);
    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();

    expect(find.text('выполнено'), findsOneWidget);
    expect(find.text('вовремя'), findsOneWidget);
    expect(find.text('среднее опоздание'), findsOneWidget);
    expect(find.text('ПО ПРИВЫЧКАМ'), findsOneWidget);
    expect(find.text('Зарядка'), findsOneWidget);
    expect(find.text('Чтение'), findsOneWidget);

    // And back.
    await tester.tap(find.text('Сегодня').first);
    await tester.pumpAndSettle();
    expect(find.text('ПО ПРИВЫЧКАМ'), findsNothing);
  });

  testWidgets('the arrows page back, and the week ahead is not offered', (
    tester,
  ) async {
    await _pump(tester, [_habit(1, 'Зарядка')]);
    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();

    final label = find.textContaining(' — ');
    final now = tester.widget<Text>(label).data;

    // Forward does nothing on the current week.
    await tester.tap(find.byTooltip('Следующая неделя'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(label).data, now);

    await tester.tap(find.byTooltip('Прошлая неделя'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(label).data, isNot(now));

    await tester.tap(find.byTooltip('Следующая неделя'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(label).data, now);
  });

  testWidgets('with no habits it says so', (tester) async {
    await _pump(tester, const []);
    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(find.text('На этой неделе привычек нет'), findsOneWidget);
  });
}
