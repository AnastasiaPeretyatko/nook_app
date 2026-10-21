import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/settings/supabase_config.dart';

/// Brings Supabase up, and never throws.
///
/// Returns whether the client is usable. The app is offline-first: a launch
/// without a network, with placeholder keys, or with a typo in the URL has to
/// end in a running app, so the one thing this must not do is take `main()`
/// down with it.
///
/// `Supabase.initialize` itself does not need the network — it builds the
/// client and restores a persisted session from local storage, and an expired
/// access token is refreshed lazily rather than awaited (the launch-blocking
/// behaviour of v1 was fixed in v2, supabase-flutter#630). The guard is here
/// because that is a promise from a package, on the cold-start path, and the
/// offline-first requirement is ours to keep.
Future<bool> initSupabase() async {
  if (!supabaseConfigured) return false;
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    ).timeout(const Duration(seconds: 5));
    return true;
  } catch (_) {
    return false;
  }
}

/// Whether [initSupabase] succeeded this launch.
///
/// Overridden in `main()` with the real answer. The default is `false` rather
/// than a throwing `UnimplementedError` — unlike `sharedPreferencesProvider`,
/// which every screen already provides — because widget tests build a
/// `ProviderContainer` with only the overrides they care about and pump
/// `SettingsPage`, which reads this. Defaulting keeps them green and renders
/// the signed-out row, which is the truth in a test anyway.
final supabaseReadyProvider = Provider<bool>((ref) => false);

/// The Supabase client, or null when it never came up.
///
/// Null rather than an exception for the same reason: `Supabase.instance.client`
/// throws when `initialize` was not called, which is exactly the case in every
/// widget test.
final supabaseClientProvider = Provider<SupabaseClient?>(
  (ref) => ref.watch(supabaseReadyProvider) ? Supabase.instance.client : null,
);
