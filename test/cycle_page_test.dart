import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/cycle_page.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/widgets/app_bottom_nav_bar.dart';
import 'package:todo_app/widgets/app_dialogs.dart' show AppSheet;
import 'package:todo_app/widgets/cycle/cycle_heart.dart';

/// The Cycle tab: the day picked in the week, the button and the quick marks
/// that follow it, the hearts, and the figures worked out from the marks.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  /// A day of the current week that is not today and has already come — the
  /// strip shows it whichever weekday the test runs on, because the week starts
  /// on Sunday when today is a Monday.
  final yesterday = DateTime(today.year, today.month, today.day - 1);

  setUp(() async {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    await initializeDateFormatting('ru_RU');
    SharedPreferences.setMockInitialValues({
      'about_gender': 'female',
      if (today.weekday == DateTime.monday) 'week_start_day': DateTime.sunday,
    });
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
      ],
    );
    // Cycle day 11 today.
    await container
        .read(aboutSettingsProvider.notifier)
        .setLastStart(DateTime(today.year, today.month, today.day - 10));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    // A tall screen: the list builds only what is on it.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CyclePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The strip comes first in the tree, so its number is the first match.
  Finder stripDay(DateTime day) => find.text('${day.day}').first;

  testWidgets('a picked day is what the button opens', (tester) async {
    await pump(tester);
    await tester.tap(stripDay(yesterday));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Отметить'));
    await tester.pumpAndSettle();

    // The card under the ring says the date too, so look in the sheet.
    expect(
      find.descendant(
        of: find.byType(AppSheet),
        matching: find.text(DateFormat.MMMMd('ru_RU').format(yesterday)),
      ),
      findsOneWidget,
    );
    expect(find.text('День цикла 10'), findsOneWidget);
  });

  testWidgets('and with nothing picked it is today', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Отметить'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppSheet),
        matching: find.text(DateFormat.MMMMd('ru_RU').format(today)),
      ),
      findsOneWidget,
    );
    expect(find.text('День цикла 11'), findsOneWidget);
  });

  testWidgets('the ring follows the picked day', (tester) async {
    await pump(tester);
    // Today: day 11 of the cycle in the centre.
    expect(find.text('11'), findsWidgets);

    await tester.tap(stripDay(yesterday));
    await tester.pumpAndSettle();
    // Day 10 is the big number now, and the badge says 10 as well.
    expect(find.text('10'), findsWidgets);
    expect(find.text('/ 27'), findsOneWidget);
  });

  testWidgets('a day that has not come can be looked at, not marked', (
    tester,
  ) async {
    await pump(tester);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    // Only reachable while tomorrow is in the shown week.
    final shown = find.text('${tomorrow.day}');
    if (shown.evaluate().isEmpty) return;
    await tester.tap(shown.first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Отметить'));
    await tester.pumpAndSettle();
    expect(find.text('Сохранить'), findsNothing);
    expect(find.byTooltip('Сохранить'), findsNothing);
  });

  testWidgets('a quick mark opens only its own choices, and keeps the rest', (
    tester,
  ) async {
    await db.cycleDao.saveDay(today, flow: 3, symptoms: {3});
    await pump(tester);

    await tester.tap(find.text('Настроение'));
    await tester.pumpAndSettle();
    // The moods are there; the symptoms and the flow are not.
    final sheet = find.byType(AppSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('Спокойное')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Вздутие')),
      findsNothing,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Обильные')),
      findsNothing,
    );

    await tester.tap(find.text('Тревога'));
    await tester.pump();
    await tester.tap(find.byTooltip('Сохранить'));
    await tester.pumpAndSettle();

    final saved = (await db.cycleDao.getDay(today))!;
    expect(saved.mood, 4);
    expect(saved.flow, 3);
    expect(saved.symptoms, '3');
  });

  testWidgets('hearts: solid with protection, an outline without', (
    tester,
  ) async {
    await db.cycleDao.saveDay(today, sex: 2);
    await db.cycleDao.saveDay(yesterday, sex: 1);
    await pump(tester);

    // In the strip only — the block of the picked day draws one as well.
    Finder heart(int sex) => find.descendant(
      of: find.byType(PageView),
      matching: find.byWidgetPredicate((w) => w is CycleHeart && w.sex == sex),
    );
    expect(heart(1), findsOneWidget);
    expect(heart(2), findsOneWidget);
    // And no dots: the week no longer paints the phase under each number.
    expect(heart(0), findsNothing);
  });

  testWidgets('the figures are worked out from the marks', (tester) async {
    // Periods starting 84, 57 and 29 days ago: cycles of 27 and 28.
    for (final ago in [84, 57, 29]) {
      for (var i = 0; i < 3; i++) {
        await db.cycleDao.saveDay(
          DateTime(today.year, today.month, today.day - ago + i),
          flow: 2,
        );
      }
    }
    await container
        .read(aboutSettingsProvider.notifier)
        .setLastStart(DateTime(today.year, today.month, today.day - 29));
    await pump(tester);

    expect(find.text('Разброс циклов'), findsOneWidget);
    expect(find.text('±1 д.'), findsOneWidget);
  });

  testWidgets('with no history the spread is a dash', (tester) async {
    await pump(tester);
    expect(find.text('Разброс циклов'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('the week strip swipes to the next and the previous week', (
    tester,
  ) async {
    await pump(tester);
    final nextWeek = DateTime(today.year, today.month, today.day + 7);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    // The pick moved to the same weekday a week on, and the block says so.
    expect(
      find.text(DateFormat.MMMMd('ru_RU').format(nextWeek)),
      findsOneWidget,
    );
    expect(find.text('Сегодня'), findsOneWidget);

    await tester.tap(find.text('Сегодня'));
    await tester.pumpAndSettle();
    expect(find.text(DateFormat.MMMMd('ru_RU').format(today)), findsOneWidget);
    expect(find.text('Сегодня'), findsNothing);

    final lastWeek = DateTime(today.year, today.month, today.day - 7);
    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(
      find.text(DateFormat.MMMMd('ru_RU').format(lastWeek)),
      findsOneWidget,
    );
  });

  testWidgets('the picked day shows what was marked on it', (tester) async {
    await db.cycleDao.saveDay(
      today,
      flow: 4,
      mood: 1,
      symptoms: {3},
      discharge: 4,
      sex: 1,
      note: 'Устала',
    );
    await pump(tester);

    // Today is picked: all of it is there.
    for (final text in [
      'Обильные',
      'Радостное',
      'Вздутие',
      'Тягучие',
      'С защитой',
      'Устала',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }

    // Another day, with nothing on it.
    await tester.tap(stripDay(yesterday));
    await tester.pumpAndSettle();
    expect(find.text('Пока ничего не отмечено'), findsOneWidget);
    expect(find.text('Обильные'), findsNothing);
  });

  testWidgets('the tags on the ring and in the cards fit their text', (
    tester,
  ) async {
    await pump(tester);

    // The test font is wide, so "narrow" is measured against the words: the
    // pill is its text and its padding, not the ring's or the card's width.
    void fits(Finder text) {
      final pill = find
          .ancestor(of: text, matching: find.byType(Container))
          .first;
      expect(
        tester.getSize(pill).width,
        lessThanOrEqualTo(tester.getSize(text).width + 26),
      );
    }

    // Day 11 of the cycle is a fertile one.
    fits(find.text('Фертильные дни'));
    fits(find.textContaining('через').first);
  });

  testWidgets('the list ends clear of the bar', (tester) async {
    // A short screen, so the page has to scroll to reach its last note.
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    // A phone with a gesture bar: the system inset sits under the nav bar.
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CyclePage()),
      ),
    );
    await tester.pumpAndSettle();

    final note = find.textContaining('Прогнозы — это примерная оценка');
    // The page's own scrollable — the week strip has one of its own.
    final list = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(note, 300, scrollable: list);
    await tester.drag(list, const Offset(0, -2000));
    await tester.pumpAndSettle();

    // The bar of the real app is `barHeight` tall plus the inset under it, and
    // the note must end above that with some air to spare.
    expect(
      tester.getBottomLeft(note).dy,
      lessThanOrEqualTo(900 - 34 - AppBottomNavBar.barHeight - 16),
    );
  });
}
