import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/auth/auth_user.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/account_page.dart';
import 'package:todo_app/pages/cycle_calendar_page.dart';
import 'package:todo_app/pages/cycle_page.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/widgets/cycle/cycle_heart.dart';
import 'package:todo_app/widgets/list_card.dart';

/// "Синхронизировать цикл" on the account screen, and the sheet that makes the
/// days there are to sync.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  final someone = AuthUser(id: 'a-user-id', email: 'me@example.com');

  Future<ProviderContainer> container(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    await initializeDateFormatting('ru_RU');
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserProvider.overrideWithValue(someone),
        databaseProvider.overrideWithValue(db),
      ],
    );
  }

  Future<void> pump(
    WidgetTester tester,
    ProviderContainer c,
    Widget home,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
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

  // Sync on, claimed for this account — the toggles only show then.
  const syncOn = {'sync_enabled': true, 'sync_claimed_for': 'a-user-id'};

  testWidgets(
    'the cycle toggle is there for a woman who tracks, off by default',
    (tester) async {
      final c = await container({...syncOn, 'about_gender': 'female'});
      addTearDown(c.dispose);
      await pump(tester, c, const AccountPage());

      expect(find.text('Синхронизировать цикл'), findsOneWidget);
      expect(c.read(syncCycleProvider), isFalse);
    },
  );

  testWidgets('and is absent for anybody else', (tester) async {
    final c = await container({...syncOn, 'about_gender': 'male'});
    addTearDown(c.dispose);
    await pump(tester, c, const AccountPage());

    expect(find.text('Синхронизировать Дневник'), findsOneWidget);
    expect(find.text('Синхронизировать цикл'), findsNothing);
  });

  testWidgets(
    'switching it on is kept, and re-reads the server from the start',
    (tester) async {
      final c = await container({...syncOn, 'about_gender': 'female'});
      addTearDown(c.dispose);
      await c
          .read(syncWatermarkProvider.notifier)
          .set(DateTime.utc(2026, 10, 1));
      await pump(tester, c, const AccountPage());

      await tester.ensureVisible(find.text('Синхронизировать цикл'));
      await tester.pumpAndSettle();
      // The row's text is not the control — its switch is.
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Синхронизировать цикл'),
            matching: find.byType(ToggleRow),
          ),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      expect(c.read(syncCycleProvider), isTrue);
      expect(c.read(sharedPreferencesProvider).getBool('sync_cycle'), isTrue);
      // Days marked elsewhere while it was off sit behind the old watermark.
      expect(c.read(syncWatermarkProvider), isNull);
    },
  );

  testWidgets(
    'a day marked in the sheet is saved, unsent, with everything chosen',
    (tester) async {
      final c = await container({'about_gender': 'female'});
      addTearDown(c.dispose);
      await c.read(aboutSettingsProvider.notifier).setLastStart(DateTime.now());
      // The full sheet lives in the calendar now: "Отметить день".
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, c, const CycleCalendarPage());

      await tester.tap(find.text('Отметить день'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Обильные'));
      await tester.tap(find.text('Тревога'));
      await tester.tap(find.text('Вздутие'));
      await tester.tap(find.text('С защитой'));
      await tester.pump();
      await tester.tap(find.byTooltip('Сохранить'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final saved = (await db.cycleDao.getDay(now))!;
      expect(saved.flow, 4);
      expect(saved.mood, 4);
      expect(saved.symptoms, '3');
      expect(saved.sex, 1);
      expect(saved.dirty, isTrue);
      // Medicines are gone from the sheet; sex comes right after the flow.
      expect(find.text('Лекарства'), findsNothing);
      // The heart of a marked day shows in the month, not only in the legend.
      expect(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byWidgetPredicate(
            (w) => w is CycleHeart && w.sex == 1,
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('the header has the calendar and the way to settings', (
    tester,
  ) async {
    final c = await container({'about_gender': 'female'});
    addTearDown(c.dispose);
    await c.read(aboutSettingsProvider.notifier).setLastStart(DateTime.now());
    await pump(tester, c, const CyclePage());

    await tester.tap(find.byTooltip('Календарь цикла'));
    await tester.pumpAndSettle();
    // Three months, and today's number is among them.
    expect(find.text('Календарь'), findsOneWidget);
    expect(find.text('Месячные'), findsOneWidget);
    expect(find.text('${DateTime.now().day}'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Профиль и настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Настройки'), findsOneWidget);
  });
}
