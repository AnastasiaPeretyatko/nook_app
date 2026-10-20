import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/account_page.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/sync_status.dart';

/// The account screen (`Account.dc.html`) when somebody is signed in: who they
/// are, where syncing stands, the three switches, the way out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final someone = User(
    id: 'a-user-id',
    appMetadata: const {},
    userMetadata: const {'full_name': 'Анастасия'},
    aud: 'authenticated',
    createdAt: DateTime.utc(2026).toIso8601String(),
    email: 'nastya@example.com',
  );

  late AppDatabase db;
  late SharedPreferences prefs;

  Future<void> open(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
    User? user,
  }) async {
    SharedPreferences.setMockInitialValues({
      'sync_enabled': true,
      'sync_claimed_for': 'a-user-id',
      ...stored,
    });
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          supabaseReadyProvider.overrideWithValue(true),
          currentUserProvider.overrideWithValue(user ?? someone),
          databaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(
          locale: Locale('ru', 'RU'),
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('ru', 'RU')],
          home: AccountPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Switch switchIn(WidgetTester tester, String label) {
    final row = find
        .ancestor(of: find.text(label), matching: find.byType(Row))
        .first;
    return tester.widget<Switch>(
      find.descendant(of: row, matching: find.byType(Switch)),
    );
  }

  setUpAll(() => initializeDateFormatting('ru_RU', null));

  cardTests();

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1170, 2600);
    view.devicePixelRatio = 3;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets('names the account', (tester) async {
    await open(tester);

    expect(find.text('Аккаунт'), findsOneWidget);
    expect(find.text('Анастасия'), findsOneWidget);
    expect(find.text('nastya@example.com'), findsOneWidget);
  });

  testWidgets('falls back to the address when there is no name', (
    tester,
  ) async {
    await open(
      tester,
      user: User(
        id: 'a-user-id',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.utc(2026).toIso8601String(),
        email: 'nastya@example.com',
      ),
    );

    // One line, not the same address twice.
    expect(find.text('nastya@example.com'), findsOneWidget);
  });

  group('the status card', () {
    testWidgets('says when syncing last worked', (tester) async {
      final at = DateTime.now().subtract(const Duration(minutes: 5));
      await open(
        tester,
        stored: {'sync_last_success': at.toUtc().toIso8601String()},
      );

      expect(find.text('Всё синхронизировано'), findsOneWidget);
      expect(find.textContaining('Последний раз'), findsOneWidget);
      expect(find.text('Синхронизировать сейчас'), findsOneWidget);
    });

    testWidgets('says "вручную" when automatic syncing is off', (tester) async {
      await open(tester, stored: {'sync_auto': false});

      expect(find.text('Синхронизация вручную'), findsOneWidget);
    });

    testWidgets('asks the question that stands in the way', (tester) async {
      await open(tester, stored: {'sync_claimed_for': 'someone-else'});

      expect(
        find.text('На устройстве данные другого аккаунта'),
        findsOneWidget,
      );
      expect(find.text('Ответить'), findsOneWidget);
      expect(find.text('Синхронизировать сейчас'), findsNothing);
    });
  });

  group('the switches', () {
    testWidgets('are three, and on or off as stored', (tester) async {
      await open(tester);

      expect(switchIn(tester, 'Автоматически').value, isTrue);
      expect(switchIn(tester, 'Только по Wi-Fi').value, isFalse);
      expect(switchIn(tester, 'Синхронизировать Дневник').value, isTrue);
      expect(find.text('Устройства'), findsNothing);
    });

    testWidgets('each writes itself down', (tester) async {
      await open(tester);

      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(prefs.getBool('sync_wifi_only'), isTrue);

      await tester.tap(find.byType(Switch).at(2));
      await tester.pumpAndSettle();
      expect(prefs.getBool('sync_diary'), isFalse);
    });

    testWidgets('"Автоматически" off greys out the Wi-Fi one', (tester) async {
      await open(tester, stored: {'sync_auto': false});

      expect(switchIn(tester, 'Автоматически').value, isFalse);
      expect(switchIn(tester, 'Только по Wi-Fi').onChanged, isNull);
    });

    testWidgets('turning the diary back on reads everything again', (
      tester,
    ) async {
      await open(
        tester,
        stored: {
          'sync_diary': false,
          'sync_pulled_through_v2': '2026-10-01T00:00:00.000Z',
        },
      );

      await tester.tap(find.byType(Switch).at(2));
      await tester.pumpAndSettle();

      expect(prefs.getBool('sync_diary'), isTrue);
      expect(prefs.getString('sync_pulled_through_v2'), isNull);
    });

    testWidgets('are not shown while syncing is off', (tester) async {
      await open(tester, stored: {'sync_enabled': false});

      expect(find.byType(Switch), findsNothing);
    });
  });

  testWidgets('has the way out, and says what it does to the data', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Выйти из аккаунта'), findsOneWidget);
    expect(find.textContaining('Данные на телефоне останутся'), findsOneWidget);
  });
}

/// The card's words, state by state — pure, so no screen is needed.
void cardTests() {
  group('syncCardInfo', () {
    final now = DateTime(2026, 10, 19, 15, 0);

    ({String title, String subtitle, SyncCardTone tone}) info({
      bool enabled = true,
      bool needsDecision = false,
      bool changingHands = false,
      bool auto = true,
      SyncStatus status = const SyncStatus(),
    }) => syncCardInfo(
      enabled: enabled,
      needsDecision: needsDecision,
      changingHands: changingHands,
      auto: auto,
      status: status,
      now: now,
    );

    test('off comes first, whatever else is true', () {
      final card = info(enabled: false, needsDecision: true);
      expect(card.title, 'Синхронизация выключена');
      expect(card.tone, SyncCardTone.neutral);
    });

    test('a pending question comes before the last run', () {
      final card = info(
        needsDecision: true,
        status: const SyncStatus(phase: SyncPhase.failed),
      );
      expect(card.tone, SyncCardTone.attention);
    });

    test('another account\'s data is named as such', () {
      expect(
        info(needsDecision: true, changingHands: true).title,
        'На устройстве данные другого аккаунта',
      );
    });

    test('a refusal carries the server\'s words', () {
      final card = info(
        status: const SyncStatus(
          phase: SyncPhase.failed,
          lastError: 'duplicate key value',
        ),
      );
      expect(card.title, 'Не удалось синхронизировать');
      expect(card.subtitle, 'duplicate key value');
      expect(card.tone, SyncCardTone.error);
    });

    test('offline is not a fault', () {
      final card = info(status: const SyncStatus(phase: SyncPhase.offline));
      expect(card.tone, SyncCardTone.neutral);
    });

    test('a run that worked today', () {
      final card = info(
        status: SyncStatus(lastSuccessAt: DateTime(2026, 10, 19, 9, 12)),
      );
      expect(card.title, 'Всё синхронизировано');
      expect(card.subtitle, 'Последний раз сегодня в 09:12');
      expect(card.tone, SyncCardTone.ok);
    });

    test('…yesterday, and on an older day', () {
      expect(
        info(
          status: SyncStatus(lastSuccessAt: DateTime(2026, 10, 18, 21, 40)),
        ).subtitle,
        'Последний раз вчера в 21:40',
      );
      expect(
        info(
          status: SyncStatus(lastSuccessAt: DateTime(2026, 10, 12, 9, 5)),
        ).subtitle,
        'Последний раз 12 октября в 09:05',
      );
    });

    test('manual mode is not "all synced"', () {
      final card = info(
        auto: false,
        status: SyncStatus(lastSuccessAt: DateTime(2026, 10, 19, 9, 12)),
      );
      expect(card.title, 'Синхронизация вручную');
      expect(card.tone, SyncCardTone.neutral);
    });

    test('never synced yet', () {
      expect(info().title, 'Ещё не синхронизировалось');
    });
  });
}
