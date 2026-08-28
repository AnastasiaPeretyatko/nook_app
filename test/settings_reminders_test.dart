import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/pages/notifications_page.dart';
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

/// The same stand-in for the exact-alarm answer, which is a second permission
/// with a second system screen behind it.
class _FakeExactAlarms extends ExactAlarmPermissionNotifier {
  _FakeExactAlarms(this.allowed);

  final bool? allowed;
  int requests = 0;

  @override
  Future<bool?> build() async => allowed;

  @override
  Future<void> request() async {
    requests++;
    state = AsyncData(allowed);
  }

  @override
  Future<void> refresh() async {}
}

Future<ProviderContainer> _container({
  Map<String, Object>? prefs,
  _FakePermission? permission,
  _FakeExactAlarms? exactAlarms,
}) async {
  SharedPreferences.setMockInitialValues(prefs ?? {});
  final instance = await SharedPreferences.getInstance();
  // Always faked, even when a test does not care: the real notifier reaches for
  // the plugin, which a widget test does not have.
  final platform = permission ?? _FakePermission(null);
  final alarms = exactAlarms ?? _FakeExactAlarms(null);
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(instance),
      notificationPermissionProvider.overrideWith(() => platform),
      exactAlarmPermissionProvider.overrideWith(() => alarms),
    ],
  );
}

Future<void> _pumpNotifications(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NotificationsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The settings list, which now only reports on reminders and leads to them.
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

/// The reminders switch specifically.
///
/// Named rather than "the only `SwitchListTile` on the screen": it is that
/// again now that exact alarms have no row, but it has already stopped being it
/// twice, and `tester.widget<SwitchListTile>` throws on two matches rather than
/// picking one.
Finder _switch() => find.widgetWithText(SwitchListTile, 'Включить уведомления');

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

  group('the stored lead time', () {
    test('is "on time" until the user picks otherwise', () async {
      final container = await _container();
      addTearDown(container.dispose);

      expect(container.read(reminderLeadMinutesProvider), 0);
    });

    test('a stored lead survives a restart', () async {
      final container = await _container(prefs: {'reminder_lead_minutes': 15});
      addTearDown(container.dispose);

      expect(container.read(reminderLeadMinutesProvider), 15);
    });

    test('picking one writes it down', () async {
      final container = await _container();
      addTearDown(container.dispose);

      await container.read(reminderLeadMinutesProvider.notifier).setMinutes(5);

      expect(container.read(reminderLeadMinutesProvider), 5);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getInt('reminder_lead_minutes'), 5);
    });

    test('a lead nothing offers any more reads as "on time"', () async {
      // Otherwise a value dropped from the list would be a setting the user
      // cannot see and cannot get rid of.
      final container = await _container(prefs: {'reminder_lead_minutes': 7});
      addTearDown(container.dispose);

      expect(container.read(reminderLeadMinutesProvider), 0);
    });

    test('what each lead is called', () {
      // A bare interval: the row above it says "Напоминать за", so a label
      // carrying the preposition too would read as a stutter.
      expect(reminderLeadLabel(0), 'Вовремя');
      expect(reminderLeadLabel(5), '5 минут');
      expect(reminderLeadLabel(30), '30 минут');
    });
  });

  group('the notifications screen', () {
    testWidgets('offers the switch, on by default', (tester) async {
      final container = await _container();
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(find.text('Включить уведомления'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(_switch()).value, isTrue);
    });

    testWidgets('tapping it turns reminders off', (tester) async {
      final container = await _container();
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

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
      await _pumpNotifications(tester, container);

      expect(tester.widget<SwitchListTile>(_switch()).value, isFalse);
    });

    testWidgets('it cannot read "on" while the system says no', (tester) async {
      // The wish is on — it is on by default — and a fresh install has no
      // permission yet. A switch showing that as "on" is a switch saying
      // notifications work when nothing will arrive.
      final container = await _container(permission: _FakePermission(false));
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(tester.widget<SwitchListTile>(_switch()).value, isFalse);
      // Underneath, the wish is untouched: it is what the permission being
      // granted later has to restore.
      expect(container.read(taskRemindersEnabledProvider), isTrue);
    });

    testWidgets('the wish alone is enough where there is nothing to ask', (
      tester,
    ) async {
      final container = await _container(permission: _FakePermission(null));
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(tester.widget<SwitchListTile>(_switch()).value, isTrue);
    });

    testWidgets('a blocked switch sends the user to the system screen', (
      tester,
    ) async {
      final permission = _FakePermission(false);
      final container = await _container(permission: permission);
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      await tester.tap(_switch());
      await tester.pumpAndSettle();

      // Asked first, and only then handed over: the request is what shows the
      // system dialog while there is still one to show.
      expect(permission.requests, 1);
      expect(permission.settingsOpened, 1);
    });

    testWidgets('a granted request does not open anything', (tester) async {
      final permission = _FakePermission(true);
      final container = await _container(
        prefs: {'task_reminders_enabled': false},
        permission: permission,
      );
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      await tester.tap(_switch());
      await tester.pumpAndSettle();

      expect(permission.settingsOpened, 0);
    });

    testWidgets('nothing to set while the system blocks it', (tester) async {
      final container = await _container(
        permission: _FakePermission(false),
        exactAlarms: _FakeExactAlarms(false),
      );
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(find.text('Напоминать за'), findsNothing);
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
      await _pumpNotifications(tester, container);

      await tester.tap(_switch());
      await tester.pumpAndSettle();

      expect(permission.requests, 1);
    });

    testWidgets('turning it off asks for nothing', (tester) async {
      final permission = _FakePermission(true);
      final container = await _container(permission: permission);
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

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
      await _pumpNotifications(tester, container);

      expect(
        find.text('Уведомления выключены в настройках телефона'),
        findsOneWidget,
      );

      await tester.tap(find.text('Открыть настройки системы'));
      await tester.pumpAndSettle();

      expect(permission.settingsOpened, 1);
    });

    testWidgets('a granted permission is not commented on', (tester) async {
      final container = await _container(permission: _FakePermission(true));
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(
        find.text('Уведомления выключены в настройках телефона'),
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
      await _pumpNotifications(tester, container);

      expect(
        find.text('Уведомления выключены в настройках телефона'),
        findsNothing,
      );
    });

    testWidgets('a refusal is silent while reminders are off', (tester) async {
      final container = await _container(
        prefs: {'task_reminders_enabled': false},
        permission: _FakePermission(false),
      );
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(
        find.text('Уведомления выключены в настройках телефона'),
        findsNothing,
      );
    });

    testWidgets('the lead row opens on "on time"', (tester) async {
      final container = await _container();
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(find.widgetWithText(ListTile, 'Напоминать за'), findsOneWidget);
      expect(find.text('Вовремя'), findsOneWidget);
    });

    testWidgets('the lead row shows what is already stored', (tester) async {
      final container = await _container(prefs: {'reminder_lead_minutes': 5});
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(find.text('5 минут'), findsOneWidget);
    });

    testWidgets('picking a lead in the sheet stores it', (tester) async {
      final container = await _container();
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      await tester.tap(find.text('Напоминать за'));
      await tester.pumpAndSettle();
      // Only in the sheet: the row shows the lead in force, which is not this
      // one, so there is no second widget with the same words.
      await tester.tap(find.text('10 минут'));
      await tester.pumpAndSettle();

      expect(container.read(reminderLeadMinutesProvider), 10);
      expect(find.text('10 минут'), findsOneWidget);
    });

    testWidgets('nothing to set while reminders are off', (tester) async {
      final container = await _container(
        prefs: {'task_reminders_enabled': false},
        exactAlarms: _FakeExactAlarms(false),
      );
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(find.text('Напоминать за'), findsNothing);
    });

    testWidgets('exact alarms get no row of their own', (tester) async {
      // A permission of the phone's, which an app can neither grant nor revoke:
      // drawn as a switch it would look like the setting above it and mean
      // something else. The callout is the whole of its presence here.
      final container = await _container(exactAlarms: _FakeExactAlarms(false));
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('Напоминания приходят с опозданием'), findsOneWidget);
    });

    testWidgets('a platform with no alarms to ask about says nothing', (
      tester,
    ) async {
      // null, not false: iOS schedules exactly as it is and the tests have no
      // alarms at all, so there is nothing to report.
      final container = await _container(exactAlarms: _FakeExactAlarms(null));
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(find.text('Напоминания приходят с опозданием'), findsNothing);
    });

    testWidgets('late reminders are explained, with a way out', (tester) async {
      final alarms = _FakeExactAlarms(false);
      final container = await _container(exactAlarms: alarms);
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(find.text('Напоминания приходят с опозданием'), findsOneWidget);

      await tester.tap(find.text('Разрешить точное время'));
      await tester.pumpAndSettle();

      expect(alarms.requests, 1);
    });

    testWidgets('exact alarms granted are not commented on', (tester) async {
      final container = await _container(exactAlarms: _FakeExactAlarms(true));
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(find.text('Напоминания приходят с опозданием'), findsNothing);
    });

    testWidgets('a device that posts nothing is not told about lateness too', (
      tester,
    ) async {
      // Two warnings stacked say less than one, and "nothing gets through" is
      // the louder problem.
      final container = await _container(
        permission: _FakePermission(false),
        exactAlarms: _FakeExactAlarms(false),
      );
      addTearDown(container.dispose);
      await _pumpNotifications(tester, container);

      expect(
        find.text('Уведомления выключены в настройках телефона'),
        findsOneWidget,
      );
      expect(find.text('Напоминания приходят с опозданием'), findsNothing);
    });
  });

  group('the summary line', () {
    test('names the lead while everything is in order', () {
      expect(
        reminderSummaryLabel(
          enabled: true,
          notificationsAllowed: true,
          leadMinutes: 5,
        ),
        'Напоминают за 5 минут',
      );
      expect(
        reminderSummaryLabel(
          enabled: true,
          notificationsAllowed: null,
          leadMinutes: 0,
        ),
        'Напоминают вовремя',
      );
    });

    test('the phone refusing is what the line reports', () {
      expect(
        reminderSummaryLabel(
          enabled: true,
          notificationsAllowed: false,
          leadMinutes: 5,
        ),
        'Выключены в настройках телефона',
      );
    });

    test('switched off is switched off, whatever the phone says', () {
      // The user's own "no" is not a problem to be reported, so it wins over
      // the permission — there is nothing left to fix.
      expect(
        reminderSummaryLabel(
          enabled: false,
          notificationsAllowed: false,
          leadMinutes: 5,
        ),
        'Выключены',
      );
    });
  });

  group('the settings row', () {
    testWidgets('reports the state and leads to the screen', (tester) async {
      final container = await _container(prefs: {'reminder_lead_minutes': 10});
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      expect(find.text('Уведомления'), findsOneWidget);
      expect(find.text('Напоминают за 10 минут'), findsOneWidget);
      // No switch of its own: the row cannot say what the screen says, so it
      // does not try.
      expect(_switch(), findsNothing);

      await tester.tap(find.text('Уведомления'));
      await tester.pumpAndSettle();

      expect(_switch(), findsOneWidget);
    });

    testWidgets('a phone that refuses is visible from the list', (
      tester,
    ) async {
      final container = await _container(permission: _FakePermission(false));
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      expect(find.text('Выключены в настройках телефона'), findsOneWidget);
    });

    testWidgets('the other rows are still there', (tester) async {
      final container = await _container();
      addTearDown(container.dispose);
      await _pumpSettings(tester, container);

      expect(find.text('Внешний вид'), findsOneWidget);
      expect(find.text('Синхронизация'), findsOneWidget);
    });
  });
}
