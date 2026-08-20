import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/pages/settings_page.dart';
import 'package:todo_app/settings/notification_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// Stands in for the platform: the real notifier talks to the plugin, which is
/// not there in a test, and what matters here is only *when* the screen asks.
class _FakePermission extends NotificationPermissionNotifier {
  _FakePermission(this.granted);

  final bool? granted;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<bool?> build() async => granted;

  @override
  Future<void> request() async {
    requests++;
    state = AsyncData(granted);
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> openSystemSettings() async => settingsOpened++;
}

Future<ProviderContainer> _container({
  Map<String, Object>? prefs,
  _FakePermission? permission,
}) async {
  SharedPreferences.setMockInitialValues(prefs ?? {});
  final instance = await SharedPreferences.getInstance();
  // Always faked, even when a test does not care: the real notifier reaches for
  // the plugin, which a widget test does not have.
  final platform = permission ?? _FakePermission(null);
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(instance),
      notificationPermissionProvider.overrideWith(() => platform),
    ],
  );
}

Future<void> _pumpSettings(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _switch() => find.byType(SwitchListTile);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the stored setting', () {
    test('is on until the user says otherwise', () async {
      final container = await _container();
      addTearDown(container.dispose);

      expect(container.read(taskRemindersEnabledProvider), isTrue);
    });

    test('a stored "off" survives a restart', () async {
      final container = await _container(
        prefs: {'task_reminders_enabled': false},
      );
      addTearDown(container.dispose);

      expect(container.read(taskRemindersEnabledProvider), isFalse);
    });

    test('turning it off writes it down', () async {
      final container = await _container();
      addTearDown(container.dispose);

      await container
          .read(taskRemindersEnabledProvider.notifier)
          .setEnabled(false);

      expect(container.read(taskRemindersEnabledProvider), isFalse);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getBool('task_reminders_enabled'), isFalse);
    });

    test('setting it to what it already is changes nothing', () async {
      final container = await _container();
      addTearDown(container.dispose);

      await container
          .read(taskRemindersEnabledProvider.notifier)
          .setEnabled(true);

      // Left unwritten, so a later default change would still reach the user.
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getBool('task_reminders_enabled'), isNull);
    });
  });

  group('the settings screen', () {
    testWidgets('offers the switch, on by default', (tester) async {
      final container = await _container();
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      expect(find.text('Уведомления задач'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(_switch()).value, isTrue);
    });

    testWidgets('tapping it turns reminders off', (tester) async {
      final container = await _container();
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      await tester.tap(_switch());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(_switch()).value, isFalse);
      expect(container.read(taskRemindersEnabledProvider), isFalse);
    });

    testWidgets('it shows what is already stored', (tester) async {
      final container = await _container(
        prefs: {'task_reminders_enabled': false},
      );
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      expect(tester.widget<SwitchListTile>(_switch()).value, isFalse);
    });

    testWidgets('turning the switch on asks for the permission', (
      tester,
    ) async {
      // The only in-context moment there is: the lazy ask inside the reminder
      // sync waits for a task that carries a time, so without this a fresh
      // install is never prompted at all.
      final permission = _FakePermission(true);
      final container = await _container(
        prefs: {'task_reminders_enabled': false},
        permission: permission,
      );
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      await tester.tap(_switch());
      await tester.pumpAndSettle();

      expect(permission.requests, 1);
    });

    testWidgets('turning it off asks for nothing', (tester) async {
      final permission = _FakePermission(true);
      final container = await _container(permission: permission);
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      await tester.tap(_switch());
      await tester.pumpAndSettle();

      expect(permission.requests, 0);
    });

    testWidgets('a refused permission is shown, with a way out', (
      tester,
    ) async {
      final permission = _FakePermission(false);
      final container = await _container(permission: permission);
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      expect(
        find.text('Уведомления запрещены в настройках системы'),
        findsOneWidget,
      );

      await tester.tap(find.text('Открыть настройки системы'));
      await tester.pumpAndSettle();

      expect(permission.settingsOpened, 1);
    });

    testWidgets('a granted permission is not commented on', (tester) async {
      final container = await _container(permission: _FakePermission(true));
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      expect(
        find.text('Уведомления запрещены в настройках системы'),
        findsNothing,
      );
    });

    testWidgets('a platform with nothing to ask is not warned about', (
      tester,
    ) async {
      // null, not false: desktop and the tests themselves have no permission to
      // report, and that is not a refusal.
      final container = await _container(permission: _FakePermission(null));
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      expect(
        find.text('Уведомления запрещены в настройках системы'),
        findsNothing,
      );
    });

    testWidgets('a refusal is silent while reminders are off', (tester) async {
      final container = await _container(
        prefs: {'task_reminders_enabled': false},
        permission: _FakePermission(false),
      );
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      expect(
        find.text('Уведомления запрещены в настройках системы'),
        findsNothing,
      );
    });

    testWidgets('the appearance row is still there', (tester) async {
      final container = await _container();
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      expect(find.text('Внешний вид'), findsOneWidget);
    });
  });
}
