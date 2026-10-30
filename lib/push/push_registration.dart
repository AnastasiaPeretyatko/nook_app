import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/api/sync_api.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/push/push_service.dart';
import 'package:todo_app/push/push_tap.dart';
import 'package:todo_app/sync/providers.dart';

/// Keeps this phone's push token on our server under whoever is signed in.
///
/// Rebuilt when the account changes (keyed on the id, not on the user object,
/// which is a new one whenever the profile is re-read), so a second account
/// signing in on this phone takes the token over: the server gives a token to
/// whoever registered it last. Does nothing without a signed-in user, which is
/// also every widget test.
///
/// Registers after the sign-in, at every launch and at every new token — a
/// repeat changes nothing on the server. Best effort: a failed call is dropped,
/// and a phone that cannot reach the server has no use for a token anyway. The
/// next launch or token registers again.
final pushRegistrationProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUserProvider.select((user) => user?.id));
  if (uid == null) return;
  final api = ref.watch(syncApiProvider);
  final push = ref.watch(pushServiceProvider);

  Future<void> register(String? token) async {
    if (token == null) return;
    try {
      await api.registerDevice(token);
    } on ApiException catch (e) {
      // `bad_token` means this token will never do; asking again is no use.
      debugPrint('Push token not registered: $e');
    } catch (e) {
      debugPrint('Push token not registered: $e');
    }
  }

  // Before the first push can arrive, see ensureGroupChannel.
  unawaited(ref.read(appNotificationsProvider).ensureGroupChannel());

  var disposed = false;
  StreamSubscription<String>? refreshes;
  StreamSubscription<String>? taps;
  unawaited(
    push.init().then((token) {
      if (disposed || token == null) return;
      unawaited(register(token));
      refreshes = push.tokenRefreshes().listen(register);

      // A tap on a push opens its group: from the background by the stream,
      // from a closed app by the launch message.
      void open(String? group) {
        if (!disposed) ref.read(pushTapProvider.notifier).report(group);
      }

      taps = push.openedGroups().listen(open);
      unawaited(push.launchedGroup().then(open));
    }),
  );
  ref.onDispose(() {
    disposed = true;
    refreshes?.cancel();
    taps?.cancel();
  });
});

/// Takes this phone off the signed-in account. Call it **before** signing out:
/// afterwards there is no session left to authorise the call.
///
/// Best effort and quick — leaving must not wait on a bad connection. If the
/// server row stays behind, the token is dead anyway: [PushService.releaseToken]
/// has thrown it away, so a push sent to it goes nowhere.
Future<void> unregisterDevice(
  SyncApi api,
  PushService push, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    await () async {
      final token = await push.releaseToken();
      if (token != null) await api.unregisterDevice(token);
    }().timeout(timeout);
  } catch (e) {
    debugPrint('Push token not unregistered: $e');
  }
}
