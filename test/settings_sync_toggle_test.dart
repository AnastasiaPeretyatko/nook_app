import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/auth/auth_user.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/groups/groups_repository.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/pages/settings_page.dart';
import 'package:todo_app/pages/account_page.dart';
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
  final someone = AuthUser(id: 'a-user-id', email: 'me@example.com');

  Future<ProviderContainer> container({
    Map<String, Object> stored = const {},
    AuthUser? user,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // The settings screen's groups block would otherwise build a real one.
        groupsRepositoryProvider.overrideWithValue(null),
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

  /// Syncing lives on the account screen, so that is what these pump —
  /// [SettingsPage] only carries the row that leads to it.
  Future<void> pump(
    WidgetTester tester,
    ProviderContainer c, {
    Widget home = const AccountPage(),
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

  Finder enableButton() => find.text('Включить синхронизацию');

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

  group('turning it on, on the account screen', () {
    testWidgets('is out of reach until there is an account', (tester) async {
      final c = await container(user: null);
      addTearDown(c.dispose);
      await pump(tester, c);

      // The sign-in form, not a sync card.
      expect(find.text('Вход'), findsOneWidget);
      expect(enableButton(), findsNothing);
    });

    testWidgets('is off, and says so, until asked for', (tester) async {
      final c = await container(user: someone);
      addTearDown(c.dispose);
      await pump(tester, c);

      expect(find.text('Синхронизация выключена'), findsOneWidget);
      expect(enableButton(), findsOneWidget);
      // Nothing to configure while it is off.
      expect(find.text('Автоматически'), findsNothing);
    });

    testWidgets('can be turned on once signed in', (tester) async {
      final c = await container(user: someone);
      addTearDown(c.dispose);
      await pump(tester, c);

      await tester.tap(enableButton());
      await tester.pumpAndSettle();

      expect(prefs.getBool('sync_enabled'), isTrue);
      expect(enableButton(), findsNothing);
      expect(find.text('Синхронизировать сейчас'), findsOneWidget);
      expect(find.text('Автоматически'), findsOneWidget);
    });

    testWidgets('reads as off while signed out, even when stored on', (
      tester,
    ) async {
      // The wish is kept, but the screen must not claim the diary is being
      // synced when there is no account to sync it to.
      final c = await container(stored: {'sync_enabled': true}, user: null);
      addTearDown(c.dispose);
      await pump(tester, c);

      expect(find.text('Синхронизировать сейчас'), findsNothing);
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

      await tester.tap(enableButton());
      await tester.pumpAndSettle();

      expect(find.text('На устройстве 1 заметка'), findsOneWidget);
      await tester.tap(find.text('Не загружать'));
      await tester.pumpAndSettle();

      expect(c.read(syncEnabledProvider), isTrue);
      expect(await db.diaryDao.unsentEntryCount(), 0);
      expect(prefs.getString('sync_claimed_for'), 'a-user-id');
    });

    testWidgets('backing out of the question leaves it off', (tester) async {
      // Dismissing is not an answer, and a sync left on would start a run the
      // user never agreed to.
      await db.diaryDao.insertEntry(
        DiaryEntriesCompanion.insert(title: const Value('Личное')),
      );
      final c = await container(user: someone);
      addTearDown(c.dispose);
      await pump(tester, c);

      await tester.tap(enableButton());
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Не загружать'))).pop();
      await tester.pumpAndSettle();

      expect(enableButton(), findsOneWidget);
      expect(c.read(syncEnabledProvider), isFalse);
      expect(await db.diaryDao.unsentEntryCount(), 1);
    });

    testWidgets('an empty diary is not asked about', (tester) async {
      final c = await container(user: someone);
      addTearDown(c.dispose);
      await pump(tester, c);

      await tester.tap(enableButton());
      await tester.pumpAndSettle();

      // Nothing to weigh: sending an empty diary is the same as not sending
      // one, so the question would be noise.
      expect(find.text('Не загружать'), findsNothing);
      expect(c.read(syncEnabledProvider), isTrue);
    });

    testWidgets('the settings screen leads here rather than deciding', (
      tester,
    ) async {
      // The profile card is a way in, not a control: the switch itself lives
      // on the account screen.
      final c = await container(user: someone);
      addTearDown(c.dispose);
      await pump(tester, c, home: const SettingsPage());

      expect(enableButton(), findsNothing);

      await tester.tap(find.text('Вы вошли'));
      await tester.pumpAndSettle();
      expect(find.text('Аккаунт'), findsOneWidget);
      expect(enableButton(), findsOneWidget);
    });
  });
}

class _FakePermission extends NotificationPermissionNotifier {
  @override
  Future<bool?> build() async => null;

  @override
  Future<void> refresh() async {}
}
