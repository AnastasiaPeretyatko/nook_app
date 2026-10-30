import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/groups/groups_repository.dart';
import 'package:todo_app/notifications/permission_prompt.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/settings/theme_provider.dart';

import 'support/fake_app_notifications.dart';
import 'support/fake_sync_api.dart';

/// Asking for the permission to show notifications: after the first task and
/// after the first group, once each, and only if the system says no.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAppNotifications system;
  late SharedPreferences prefs;

  Future<ProviderContainer> container({
    bool? enabled = false,
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    system = FakeAppNotifications(enabled: enabled);
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appNotificationsProvider.overrideWithValue(system),
        // Granting re-plans the reminders; there are none to read.
        taskRemindersProvider.overrideWithValue(const []),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> offer(ProviderContainer c, NotificationAsk reason) =>
      c.read(offerNotificationPermissionProvider)(reason);

  test(
    'the first task asks when the system does not allow notifications',
    () async {
      final c = await container();

      await offer(c, NotificationAsk.task);

      expect(system.asks, 1);
    },
  );

  test('and only once for that reason', () async {
    final c = await container();
    system.grantWhenAsked = false;

    await offer(c, NotificationAsk.task);
    await offer(c, NotificationAsk.task);

    expect(system.asks, 1);
  });

  test(
    'a group is a reason of its own, so the system gets a second try',
    () async {
      final c = await container();
      system.grantWhenAsked = false;

      await offer(c, NotificationAsk.task);
      await offer(c, NotificationAsk.group);

      expect(system.asks, 2);
    },
  );

  test(
    'already allowed: not asked, and the reason is kept for later',
    () async {
      final c = await container(enabled: true);

      await offer(c, NotificationAsk.task);

      expect(system.asks, 0);
      expect(prefs.getBool(NotificationAsk.task.prefsKey), isNull);
    },
  );

  test('nothing to ask on this platform: silence', () async {
    final c = await container(enabled: null);

    await offer(c, NotificationAsk.group);

    expect(system.asks, 0);
  });

  test('an ask remembered from an earlier launch is not repeated', () async {
    final c = await container(stored: {NotificationAsk.task.prefsKey: true});

    await offer(c, NotificationAsk.task);

    expect(system.asks, 0);
  });

  test('creating or joining a group is the group reason', () async {
    final c = await container();
    final repo = GroupsRepository(
      FakeSyncApi(),
      () async {},
      onFirstGroup: () => offer(c, NotificationAsk.group),
    );

    await repo.createGroup('Семья');
    await Future<void>.delayed(Duration.zero);

    expect(system.asks, 1);
    expect(prefs.getBool(NotificationAsk.group.prefsKey), isTrue);
  });

  test('a refused group does not ask', () async {
    final c = await container();
    final api = FakeSyncApi()
      ..error = const ApiException(
        ApiFailure.server,
        status: 400,
        code: 'bad_code',
      );
    final repo = GroupsRepository(
      api,
      () async {},
      onFirstGroup: () => offer(c, NotificationAsk.group),
    );

    await expectLater(
      repo.joinGroup('1'),
      throwsA(isA<GroupActionException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(system.asks, 0);
  });

  test('without preferences it just does nothing', () async {
    final c = ProviderContainer(
      overrides: [
        appNotificationsProvider.overrideWithValue(
          FakeAppNotifications(enabled: false),
        ),
      ],
    );
    addTearDown(c.dispose);

    await c.read(offerNotificationPermissionProvider)(NotificationAsk.task);
  });
}
