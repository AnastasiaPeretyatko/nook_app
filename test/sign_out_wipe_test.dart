import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/auth/auth_user.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/auth/auth_repository.dart';
import 'package:todo_app/auth/google_id_token.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/account_page.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/sync_service.dart';
import 'support/fake_sync_api.dart';

/// A server that accepts everything.
class _OkService extends SyncService {
  _OkService(AppDatabase db)
    : super(
        dao: db.diaryDao,
        tasksDao: db.tasksDao,
        cycleDao: db.cycleDao,
        api: FakeSyncApi(),
        userId: () => null,
      );

  @override
  Future<SyncOutcome> sync({bool force = false}) async => SyncOutcome.done;
}

class _FakeAuth implements AuthRepository {
  bool signedOut = false;
  String? deletedWith;
  String? deletedWithGoogle;

  /// Set to make `deleteAccount` refuse the way the server does for a wrong
  /// password.
  Object? deleteError;

  @override
  Future<void> deleteAccount({String? password, String? idToken}) async {
    if (deleteError != null) throw deleteError!;
    deletedWith = password;
    deletedWithGoogle = idToken;
  }

  @override
  Future<void> signOut() async => signedOut = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// "Выйти и стереть" on the account screen, end to end: the rows must be gone
/// from the database afterwards, and the account forgotten.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final someone = AuthUser(id: 'a-user-id', email: 'a@example.com');

  late AppDatabase db;
  late SharedPreferences prefs;
  late _FakeAuth auth;

  setUpAll(() => initializeDateFormatting('ru_RU', null));

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    auth = _FakeAuth();
    final dir = Directory.systemTemp.createTempSync('nook_docs');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1170, 2600);
    view.devicePixelRatio = 3;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  /// File and database work runs on the real clock, which `pumpAndSettle`
  /// does not wait for. Plain `pump` in the loop: while the work runs the busy
  /// overlay's spinner animates for ever, and `pumpAndSettle` would never see a
  /// still screen.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> signOutAndWipe(
    WidgetTester tester, {
    required bool syncOn,
    bool serverOk = false,
    bool deleteAccount = false,
    bool viaGoogle = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'sync_enabled': syncOn,
      'sync_claimed_for': 'a-user-id',
      'sync_pulled_through_v2': '2026-10-01T00:00:00.000Z',
      'cycle_last_start': '2026-10-01',
      'about_gender': 'male',
    });
    prefs = await SharedPreferences.getInstance();
    await db.tasksDao.insertTask(TasksCompanion.insert(title: 'Зарядка'));
    await db.diaryDao.insertEntry(
      DiaryEntriesCompanion.insert(title: const Value('Заметка')),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWithValue(someone),
          databaseProvider.overrideWithValue(db),
          authRepositoryProvider.overrideWithValue(auth),
          googleIdTokenProvider.overrideWithValue(() async => 'google-tok'),
          if (serverOk) syncServiceProvider.overrideWithValue(_OkService(db)),
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

    if (deleteAccount) {
      await tester.ensureVisible(find.text('Удалить аккаунт'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить аккаунт'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      if (viaGoogle) {
        await tester.tap(find.text('Войти через Google'));
        await settle(tester);
        return;
      }
      await tester.tap(find.text('Ввести пароль'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret pass');
      await tester.tap(find.text('Удалить аккаунт').last);
      await settle(tester);
      return;
    }

    await tester.ensureVisible(find.text('Выйти из аккаунта'));
    await tester.tap(find.text('Выйти из аккаунта'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти и стереть'));
    await settle(tester);
    // Whichever confirmation the path asks for.
    for (final label in ['Стереть', 'Всё равно стереть']) {
      if (find.text(label).evaluate().isNotEmpty) {
        await tester.tap(find.text(label));
        await settle(tester);
      }
    }
  }

  testWidgets('with syncing off the rows are removed', (tester) async {
    await signOutAndWipe(tester, syncOn: false);

    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await db.select(db.diaryEntries).get(), isEmpty);
    expect(prefs.getString('sync_claimed_for'), isNull);
    expect(auth.signedOut, isTrue);
  });

  testWidgets('with syncing on the rows are removed', (tester) async {
    await signOutAndWipe(tester, syncOn: true);

    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await db.select(db.diaryEntries).get(), isEmpty);
    expect(prefs.getString('sync_claimed_for'), isNull);
    expect(auth.signedOut, isTrue);
  });

  testWidgets(
    'with syncing on and the server answering, no question is asked',
    (tester) async {
      await signOutAndWipe(tester, syncOn: true, serverOk: true);

      expect(await db.select(db.tasks).get(), isEmpty);
      expect(await db.select(db.diaryEntries).get(), isEmpty);
      expect(prefs.getString('sync_claimed_for'), isNull);
      expect(prefs.getString('sync_pulled_through_v2'), isNull);
      // Health data kept in prefs goes with the rows.
      expect(prefs.getString('cycle_last_start'), isNull);
      expect(prefs.getString('about_gender'), isNull);
      expect(auth.signedOut, isTrue);
    },
  );

  testWidgets(
    'deleting the account sends the password as typed and wipes the phone',
    (tester) async {
      await signOutAndWipe(tester, syncOn: true, deleteAccount: true);

      expect(auth.deletedWith, 'secret pass');
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(await db.select(db.diaryEntries).get(), isEmpty);
      expect(prefs.getString('sync_claimed_for'), isNull);
    },
  );

  testWidgets('a wrong password leaves the phone alone and says so', (
    tester,
  ) async {
    auth.deleteError = const ApiException(
      ApiFailure.server,
      status: 401,
      code: 'invalid_credentials',
    );

    await signOutAndWipe(tester, syncOn: true, deleteAccount: true);

    expect(find.text('Неверный пароль'), findsOneWidget);
    expect(await db.select(db.tasks).get(), isNotEmpty);
    expect(prefs.getString('sync_claimed_for'), 'a-user-id');
  });

  testWidgets('a Google account confirms with a fresh Google token', (
    tester,
  ) async {
    await signOutAndWipe(
      tester,
      syncOn: true,
      deleteAccount: true,
      viaGoogle: true,
    );

    expect(auth.deletedWithGoogle, 'google-tok');
    expect(auth.deletedWith, isNull);
    expect(await db.select(db.tasks).get(), isEmpty);
  });
}
