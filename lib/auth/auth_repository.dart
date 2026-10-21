import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/settings/supabase_config.dart';

/// Everything the app does with accounts, in one place.
///
/// The database has a rule — widgets and providers never touch it directly,
/// always a DAO — and this is its twin: nothing outside `lib/auth/` reaches for
/// a [SupabaseClient]. What the screens see is these six methods.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// The session restored at start-up, before the stream has said anything.
  User? get currentUser => _auth.currentUser;

  /// Who is signed in, as it changes.
  ///
  /// This is also how an OAuth sign-in reports itself: [signInWithGoogle] only
  /// opens a browser, and the session arrives later, through the deep link.
  Stream<User?> userChanges() =>
      _auth.onAuthStateChange.map((state) => state.session?.user);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) => _auth.signUp(email: email, password: password);

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) => _auth.signInWithPassword(email: email, password: password);

  /// Opens the browser for Google, and that is all it does.
  ///
  /// Returns whether the browser could be opened — **not** whether the user
  /// signed in. The session comes back over [authRedirectUrl] and surfaces on
  /// [userChanges], so a caller must listen rather than await an answer here.
  /// A user who backs out of the browser produces no event and no error, which
  /// is right: cancelling is not a failure.
  Future<bool> signInWithGoogle() =>
      _auth.signInWithOAuth(OAuthProvider.google, redirectTo: authRedirectUrl);

  Future<void> signOut() => _auth.signOut();
}

/// The repository, or null when Supabase never came up.
///
/// Null rather than throwing, so a widget test that overrides nothing still
/// renders — see [supabaseReadyProvider].
final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : AuthRepository(client);
});
