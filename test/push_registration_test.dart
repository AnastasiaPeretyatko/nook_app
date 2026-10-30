import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/auth/auth_user.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/push/push_registration.dart';
import 'package:todo_app/push/push_service.dart';
import 'package:todo_app/push/push_tap.dart';
import 'package:todo_app/sync/providers.dart';

import 'support/fake_app_notifications.dart';
import 'support/fake_sync_api.dart';

class _FakePush implements PushService {
  String? token = 'token-of-this-phone-0000';
  int inits = 0;
  final refreshes = StreamController<String>.broadcast();
  final opened = StreamController<String>.broadcast();
  String? launched;

  /// What `releaseToken` hands back, and whether it ever answers.
  String? released = 'token-of-this-phone-0000';
  bool releaseHangs = false;

  @override
  Future<String?> init() async {
    inits++;
    return token;
  }

  @override
  Stream<String> tokenRefreshes() => refreshes.stream;

  @override
  Stream<String> openedGroups() => opened.stream;

  @override
  Future<String?> launchedGroup() async => launched;

  @override
  Future<String?> releaseToken() {
    if (releaseHangs) return Completer<String?>().future;
    return Future.value(released);
  }
}

/// This phone's push token on our server: when it is registered, moved to the
/// next account, taken off, and what a tap on a push does.
void main() {
  late FakeSyncApi api;
  late _FakePush push;
  final account = StateProvider<AuthUser?>((ref) => null);

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        syncApiProvider.overrideWithValue(api),
        pushServiceProvider.overrideWithValue(push),
        appNotificationsProvider.overrideWithValue(FakeAppNotifications()),
        currentUserProvider.overrideWith((ref) => ref.watch(account)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  const ann = AuthUser(id: 'ann', email: 'a@x.test');
  const bob = AuthUser(id: 'bob', email: 'b@x.test');

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    api = FakeSyncApi();
    push = _FakePush();
  });

  group('registering', () {
    test('nobody signed in: push is not even started', () async {
      final c = container();
      c.read(pushRegistrationProvider);
      await settle();

      expect(push.inits, 0);
      expect(api.calls, isEmpty);
    });

    test('signed in: the token goes to our server', () async {
      final c = container();
      c.read(account.notifier).state = ann;
      c.listen(pushRegistrationProvider, (_, _) {});
      await settle();

      expect(api.calls, ['registerDevice(token-of-this-phone-0000)']);
    });

    test('a new token is registered too', () async {
      final c = container();
      c.read(account.notifier).state = ann;
      c.listen(pushRegistrationProvider, (_, _) {});
      await settle();

      push.refreshes.add('another-token-for-the-phone-1');
      await settle();

      expect(api.calls, [
        'registerDevice(token-of-this-phone-0000)',
        'registerDevice(another-token-for-the-phone-1)',
      ]);
    });

    test('signing in as someone else registers the phone again', () async {
      final c = container();
      c.read(account.notifier).state = ann;
      c.listen(pushRegistrationProvider, (_, _) {});
      await settle();

      c.read(account.notifier).state = bob;
      await settle();

      expect(push.inits, 2);
      expect(
        api.calls.where((call) => call.startsWith('registerDevice')),
        hasLength(2),
      );
    });

    test(
      'the same account again (a re-read profile) does nothing new',
      () async {
        final c = container();
        c.read(account.notifier).state = ann;
        c.listen(pushRegistrationProvider, (_, _) {});
        await settle();

        c.read(account.notifier).state = const AuthUser(
          id: 'ann',
          email: 'a@x.test',
          displayName: 'Аня',
        );
        await settle();

        expect(push.inits, 1);
      },
    );

    test(
      'a refused token is dropped without a fuss, and not retried',
      () async {
        api.error = const ApiException(
          ApiFailure.server,
          status: 400,
          code: 'bad_token',
        );
        final c = container();
        c.read(account.notifier).state = ann;
        c.listen(pushRegistrationProvider, (_, _) {});
        await settle();
        await settle();

        expect(api.calls, hasLength(1));
      },
    );

    test('no network: nothing thrown, the next launch tries again', () async {
      api.error = const ApiException.offline();
      final c = container();
      c.read(account.notifier).state = ann;
      c.listen(pushRegistrationProvider, (_, _) {});
      await settle();

      expect(api.calls, hasLength(1));
    });

    test('where push did not come up, nothing is registered', () async {
      push.token = null;
      final c = container();
      c.read(account.notifier).state = ann;
      c.listen(pushRegistrationProvider, (_, _) {});
      await settle();

      expect(api.calls, isEmpty);
    });
  });

  group('a tap on a push', () {
    test('from the background opens its group', () async {
      final c = container();
      c.read(account.notifier).state = ann;
      c.listen(pushRegistrationProvider, (_, _) {});
      await settle();

      push.opened.add('group-1');
      await settle();

      expect(c.read(pushTapProvider)?.groupUid, 'group-1');
    });

    test('the one that started the app opens its group', () async {
      push.launched = 'group-2';
      final c = container();
      c.read(account.notifier).state = ann;
      c.listen(pushRegistrationProvider, (_, _) {});
      await settle();

      expect(c.read(pushTapProvider)?.groupUid, 'group-2');
    });
  });

  group('taking the phone off the account', () {
    test('the token is released and removed from the server', () async {
      await unregisterDevice(api, push);

      expect(api.calls, ['unregisterDevice(token-of-this-phone-0000)']);
    });

    test('a phone with no token has nothing to remove', () async {
      push.released = null;
      await unregisterDevice(api, push);

      expect(api.calls, isEmpty);
    });

    test('a failure does not stop signing out', () async {
      api.error = const ApiException.offline();
      await unregisterDevice(api, push);

      expect(api.calls, hasLength(1));
    });

    test('a hanging call is given up on', () async {
      push.releaseHangs = true;
      await unregisterDevice(
        api,
        push,
        timeout: const Duration(milliseconds: 50),
      );
      // Reaching here is the test: leaving did not wait for ever.
    });
  });
}
