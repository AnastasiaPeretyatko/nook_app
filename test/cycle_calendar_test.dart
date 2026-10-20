import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/cycle_calendar_page.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/widgets/app_dialogs.dart' show AppSheet;

/// The calendar behind the Cycle tab's button: months without an end either way,
/// and a tap on a day showing what was marked on it.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  setUp(() async {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    await initializeDateFormatting('ru_RU');
    SharedPreferences.setMockInitialValues({'about_gender': 'female'});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
      ],
    );
    await container
        .read(aboutSettingsProvider.notifier)
        .setLastStart(DateTime(today.year, today.month, today.day - 10));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CycleCalendarPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder month(DateTime first) =>
      find.byKey(ValueKey('month-${first.year}-${first.month}'));

  String title(DateTime first) {
    final name = DateFormat.LLLL('ru_RU').format(first);
    final capital = name[0].toUpperCase() + name.substring(1);
    return first.year == today.year ? capital : '$capital ${first.year}';
  }

  testWidgets('scrolls into the past and the future, far past three months', (
    tester,
  ) async {
    await pump(tester);
    expect(month(DateTime(today.year, today.month)), findsOneWidget);

    // A year back…
    final yearAgo = DateTime(today.year, today.month - 12);
    await tester.dragUntilVisible(
      find.text(title(yearAgo)),
      find.byType(CustomScrollView),
      const Offset(0, 400),
      maxIteration: 200,
    );
    expect(find.text(title(yearAgo)), findsOneWidget);

    // …and back, then a year on.
    await tester.tap(find.byTooltip('Сегодня'));
    await tester.pumpAndSettle();
    expect(month(DateTime(today.year, today.month)), findsOneWidget);

    final yearOn = DateTime(today.year, today.month + 12);
    await tester.dragUntilVisible(
      find.text(title(yearOn)),
      find.byType(CustomScrollView),
      const Offset(0, -400),
      maxIteration: 200,
    );
    expect(find.text(title(yearOn)), findsOneWidget);
  });

  testWidgets('a tap on a day shows what was marked on it', (tester) async {
    await db.cycleDao.saveDay(
      today,
      flow: 2,
      mood: 4,
      symptoms: {0, 5},
      sex: 2,
      note: 'Устала',
    );
    await pump(tester);

    await tester.tap(
      find.descendant(
        of: month(DateTime(today.year, today.month)),
        matching: find.text('${today.day}'),
      ),
    );
    await tester.pumpAndSettle();

    final sheet = find.byType(AppSheet);
    for (final text in [
      DateFormat.MMMMd('ru_RU').format(today),
      'день цикла 11 · фертильный день',
      'Лёгкие',
      'Тревога',
      'Боль внизу живота',
      'Акне',
      'Без защиты',
      'Устала',
      'Изменить',
    ]) {
      expect(
        find.descendant(of: sheet, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
  });

  testWidgets('a day with nothing on it says so, and offers to mark it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(
      find.descendant(
        of: month(DateTime(today.year, today.month)),
        matching: find.text('${today.day}'),
      ),
    );
    await tester.pumpAndSettle();

    final sheet = find.byType(AppSheet);
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('Пока ничего не отмечено'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Отметить')),
      findsOneWidget,
    );
  });
}
