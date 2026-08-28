import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/pages/settings_page.dart';
import 'package:todo_app/pages/sync_page.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// The switch that decides whether the diary leaves the device.
///
/// Two things are being pinned. That it is **off** until asked for — sending
/// what somebody wrote to a machine elsewhere is not a default. And that it is
/// out of reach, with a reason given, when there is nowhere to sync to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late AppDatabase db;

  setUp(() => db = AppDatabase.forExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Stands in for a signed-in account. Only `id` is read by anything here;
  /// the rest is what `User` insists on having.
  final someone = User(
    id: 'a-user-id',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: DateTime.utc(2026).toIso8601String(),
    email: 'me@example.com',
  );

  Future<ProviderContainer> container({
    Map<String, Object> stored = const {},
    bool ready = true,
    User? user,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseReadyProvider.overrideWithValue(ready),
        currentUserProvider.overrideWithValue(user),
        // The real one reaches for a plugin that a widget test does not have.
        notificationPermissionProvider.overrideWith(_FakePermission.new),
        // Turning the switch on now asks about the notes already here, so
        // the handler reads the diary. Without this it reaches for a real
        // on-disk database, which a widget test has no path provider for.
        databaseProvider.overrideWithValue(db),
      ],
    );
  }

  /// The switch lives on its own screen now, so that is what these pump —
  /// [SettingsPage] only carries the row that leads to it.
  Future<void> pump(
    WidgetTester tester,
    ProviderContainer c, {
    Widget home = const SyncPage(),
  }) async {
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

  Finder syncSwitch() =>
      find.widgetWithText(SwitchListTile, 'Включить синхронизацию');

  group('the stored setting', () {
    test('is off until the user asks for it', () async {
      final c = await container();
      addTearDown(c.dispose);

      expect(c.read(syncEnabledProvider), isFalse);
    });

    test('a stored "on" survives a restart', () async {
      final c = await container(stored: {'sync_enabled': true});
      addTearDown(c.dispose);

      expect(c.read(syncEnabledProvider), isTrue);
    });

    test('turning it on writes it down', () async {
      final c = await container();
      addTearDown(c.dispose);

      await c.read(syncEnabledProvider.notifier).setEnabled(true);

      expect(prefs.getBool('sync_enabled'), isTrue);
    });

    test('signing out does not rewrite it', () async {
      // The setting is the user's wish; having an account is a separate fact.
      // Conflating them would silently turn sync off on a sign-out and leave it
      // off after signing back in.
      final c = await container(stored: {'sync_enabled': true}, user: null);
      addTearDown(c.dispose);

      expect(c.read(syncEnabledProvider), isTrue);
    });
  });

  group('the switch on screen', () {
    testWidgets('is out of reach until there is an account', (tester) async {
      final c = await container(user: null);
      addTearDown(c.dispose);
      await pump(tester, c);

      final tile = tester.widget<SwitchListTile>(syncSwitch());
      expect(tile.onChanged, isNull);
      expect(tile.value, isFalse);
      expect(find.text('Войдите в аккаунт, чтобы включить'), findsOneWidget);
    });

    testWidgets('says so when the server never came up', (tester) async {
      final c = await container(ready: false, user: someone);
      addTearDown(c.dispose);
      await pump(tester, c);

      expect(tester.widget<SwitchListTile>(syncSwitch()).onChanged, isNull);
      expect(find.text('Сервер недоступен'), findsOneWidget);
    });

    testWidgets('can be turned on once signed in', (tester) async {
      final c = await container(user: someone);
      addTearDown(c.dispose);
      await pump(tester, c);

      expect(tester.widget<SwitchListTile>(syncSwitch()).value, isFalse);

      await tester.tap(syncSwitch());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(syncSwitch()).value, isTrue);
      expect(prefs.getBool('sync_enabled'), isTrue);
    });

    testWidgets('reads as off while signed out, even when stored on', (
      tester,
    ) async {
      // The wish is kept, but the screen must not claim the diary is being
      // synced when there is no account to sync it to.
      final c = await container(stored: {'sync_enabled': true}, user: null);
      addTearDown(c.dispose);
      await pump(tester, c);

      expect(tester.widget<SwitchListTile>(syncSwitch()).value, isFalse);
      expect(c.read(syncEnabledProvider), isTrue);
    });

    testWidgets('asks about the notes already here, and "не загружать" '
        'leaves them unsent', (tester) async {
      await db.diaryDao.insertEntry(
        DiaryEntriesCompanion.insert(title: const Value('Личное')),
      );
      final c = await container(user: someone);
      addTearDown(c.dispose);
      await pump(tester, c);

      await tester.tap(syncSwitch());
      await tester.pumpAndSettle();

      expect(find.text('На устройстве 1 заметка'), findsOneWidget);
      await tester.tap(find.text('Не загружать'));
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(syncSwitch()).value, isTrue);
      expect(await db.diaryDao.unsentEntryCount(), 0);
      expect(prefs.getString('sync_claimed_for'), 'a-user-id');
    });

    testWidgets('backing out of the question leaves the switch off', (
      tester,
    ) async {
      // Dismissing is not an answer, and a switch left on would start a sync
      // the user never agreed to.
      await db.diaryDao.insertEntry(
        DiaryEntriesCompanion.insert(title: const Value('Личное')),
      );
      final c = await container(user: someone);
      addTearDown(c.dispose);
      await pump(tester, c);

      await tester.tap(syncSwitch());
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Не загружать'))).pop();
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(syncSwitch()).value, isFalse);
      expect(c.read(syncEnabledProvider), isFalse);
      expect(await db.diaryDao.unsentEntryCount(), 1);
    });

    testWidgets('an empty diary is not asked about', (tester) async {
      final c = await container(user: someone);
      addTearDown(c.dispose);
      await pump(tester, c);

      await tester.tap(syncSwitch());
      await tester.pumpAndSettle();

      // Nothing to weigh: sending an empty diary is the same as not sending
      // one, so the question would be noise.
      expect(find.text('Не загружать'), findsNothing);
      expect(tester.widget<SwitchListTile>(syncSwitch()).value, isTrue);
    });

    testWidgets('the settings screen leads here rather than deciding', (
      tester,
    ) async {
      // The row is a way in, not a control — and so is every other row there
      // now that reminders have a screen of their own: the settings list holds
      // no switch at all and only reports what each screen is doing.
      final c = await container(user: someone);
      addTearDown(c.dispose);
      await pump(tester, c, home: const SettingsPage());

      expect(find.text('Синхронизация'), findsOneWidget);
      expect(syncSwitch(), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Уведомления'), findsOneWidget);
    });
  });
}

class _FakePermission extends NotificationPermissionNotifier {
  @override
  Future<bool?> build() async => null;

  @override
  Future<void> refresh() async {}
}
