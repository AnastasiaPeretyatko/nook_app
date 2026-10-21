import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/push/push_init.dart';

/// Keeps this phone's push token on the server under whoever is signed in.
///
/// Rebuilt when the account changes (keyed on the id, not on the `User`, which
/// is a new object at every hourly session refresh), so a second account
/// signing in on this phone takes the token over — `register_device` in
/// `supabase/011_device_tokens.sql` moves the row. Does nothing without a
/// client or a signed-in user, which is also every widget test.
///
/// Best effort: a failed call is dropped. The next launch, or a new token,
/// registers again, and a phone that cannot reach the server has no use for one.
final pushRegistrationProvider = Provider<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final uid = ref.watch(currentUserProvider.select((user) => user?.id));
  if (client == null || uid == null) return;

  Future<void> register(String? token) async {
    if (token == null) return;
    try {
      await client.rpc('register_device', params: {'p_token': token});
    } catch (e) {
      debugPrint('Push token not registered: $e');
    }
  }

  var disposed = false;
  StreamSubscription<String>? refreshes;
  unawaited(
    initPush().then((token) {
      if (disposed || token == null) return;
      unawaited(register(token));
      refreshes = pushTokenRefreshes().listen(register);
    }),
  );
  ref.onDispose(() {
    disposed = true;
    refreshes?.cancel();
  });
});

/// Takes this phone off the signed-in account. Call it **before** signing out:
/// afterwards there is no session left to authorise the call.
///
/// Best effort and quick — leaving must not wait on a bad connection. If the
/// server row stays behind, the token is dead anyway ([releasePushToken]).
Future<void> unregisterDevice(SupabaseClient? client) async {
  if (client == null) return;
  try {
    await () async {
      final token = await releasePushToken();
      if (token != null) {
        await client.rpc('unregister_device', params: {'p_token': token});
      }
    }().timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('Push token not unregistered: $e');
  }
}
