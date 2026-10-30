import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/api/api_client.dart';
import 'package:todo_app/api/device_id.dart';
import 'package:todo_app/api/token_store.dart';
import 'package:todo_app/auth/auth_repository.dart';
import 'package:todo_app/auth/auth_user.dart';
import 'package:todo_app/settings/api_config.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// Where the session's tokens live. A provider so a test can swap in
/// `MemoryTokenStore` — the real one asks the platform's keystore.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// This phone's name for the server, or null where there are no prefs to keep
/// it in (a widget test that overrides nothing).
final deviceIdProvider = Provider<String?>((ref) {
  try {
    return deviceIdIn(ref.watch(sharedPreferencesProvider));
  } on UnimplementedError {
    return null;
  }
});

/// The one client every request to our server goes through.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: apiBaseUrl,
    tokens: ref.watch(tokenStoreProvider),
    deviceId: () => ref.read(deviceIdProvider),
  );
  ref.onDispose(client.close);
  return client;
});

/// The repository, or null when there are no prefs to cache the account in.
///
/// The app always provides them; the null is for a widget test that overrides
/// nothing and still has to render — as before, such a test simply sees nobody
/// signed in. (`sharedPreferencesProvider` throws when it is not overridden,
/// so that is the one error caught here.)
final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final SharedPreferences prefs;
  try {
    prefs = ref.watch(sharedPreferencesProvider);
  } on UnimplementedError {
    return null;
  }
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
    prefs,
  );
});

/// Who is signed in, live.
///
/// Plain `StreamProvider`, the same shape the database providers use; a
/// `Notifier` would imply the screens own the session, and the repository does.
final authUserProvider = StreamProvider<AuthUser?>(
  (ref) =>
      ref.watch(authRepositoryProvider)?.userChanges() ?? Stream.value(null),
);

/// The signed-in user, or null. What the screens read.
///
/// Falls back to the account cached at start-up while the stream has yet to
/// emit, so the settings row does not flash "не вошли" on every launch.
final currentUserProvider = Provider<AuthUser?>(
  (ref) =>
      ref.watch(authUserProvider).valueOrNull ??
      ref.watch(authRepositoryProvider)?.currentUser,
);
