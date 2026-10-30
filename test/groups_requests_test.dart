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
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/pages/settings_page.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/sync_controller.dart';
import 'package:todo_app/sync/sync_service.dart';

import 'support/fake_sync_api.dart';

class _CountingSync extends SyncController {
  _CountingSync(super.ref);

  /// Reset by each test; the provider is lazy, so a test where nothing asks
  /// for a sync never builds the controller at all.
  static int runs = 0;

  @override
  Future<SyncOutcome> syncNow() async {
    runs++;
    return SyncOutcome.done;
  }
}

class _FakePermission extends NotificationPermissionNotifier {
  @override
  Future<bool?> build() async => null;

  @override
  Future<void> refresh() async {}
}

/// Groups cost the server nothing until the user asks: opening the settings or
/// a group reads the phone's own copy, and pulling down is the one way to
/// refresh it.
void main() {
  const me = 'a';

  late AppDatabase db;
  late FakeSyncApi api;

  setUpAll(() => initializeDateFormatting('ru_RU', null));

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    api = FakeSyncApi();
    _CountingSync.runs = 0;
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1170, 2600);
    view.devicePixelRatio = 3;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'sync_enabled': true,
      'sync_claimed_for': me,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWithValue(
            const AuthUser(id: me, email: 'a@b.c'),
          ),
          syncApiProvider.overrideWithValue(api),
          groupsProvider.overrideWith(
            (ref) => Stream.value(const [
              TaskGroup(uid: 'g1', name: 'Семья', ownerUid: me),
            ]),
          ),
          groupMembersProvider.overrideWith(
            (ref) => Stream.value(const [
              GroupMember(groupUid: 'g1', userUid: me, displayName: 'Аня'),
              GroupMember(groupUid: 'g1', userUid: 'b', displayName: 'Миша'),
            ]),
          ),
          allTasksProvider.overrideWith((ref) => Stream.value(const <Task>[])),
          allLogsProvider.overrideWith(
            (ref) => Stream.value(const <TaskLog>[]),
          ),
          groupMarksProvider.overrideWith(
            (ref) => Stream.value(const <GroupMark>[]),
          ),
          syncControllerProvider.overrideWith(_CountingSync.new),
          notificationPermissionProvider.overrideWith(_FakePermission.new),
        ],
        child: const MaterialApp(
          locale: Locale('ru', 'RU'),
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('ru', 'RU')],
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the groups and their members show with no request', (
    tester,
  ) async {
    await open(tester);
    await tester.scrollUntilVisible(find.text('Семья'), 300);
    await tester.pumpAndSettle();
    expect(find.text('Семья'), findsOneWidget);

    await tester.tap(find.text('Семья'));
    await tester.pumpAndSettle();

    expect(find.text('Группа'), findsOneWidget);
    expect(find.text('Миша'), findsWidgets);
    expect(api.calls, isEmpty);
    expect(_CountingSync.runs, 0);
  });

  testWidgets('pulling the settings down syncs once', (tester) async {
    await open(tester);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(_CountingSync.runs, 1);
    expect(api.calls, isEmpty, reason: 'the controller is the one asked');
  });

  testWidgets('pulling a group down syncs once', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(find.text('Семья'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Семья'));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(_CountingSync.runs, 1);
  });
}
