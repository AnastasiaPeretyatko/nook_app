import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/api/api_client.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/api/token_store.dart';
import 'package:todo_app/auth/auth_user.dart';

/// Everything the app does with accounts, in one place.
///
/// The database has a rule — widgets and providers never touch it directly,
/// always a DAO — and this is its twin: nothing outside `lib/auth/` talks to
/// `/auth/*`. What the screens see is these few methods.
///
/// "Signed in" means a [AuthUser] is cached in prefs. It is written when the
/// server accepts a sign-in and removed when the session ends, so the settings
/// row answers at once and offline; the tokens behind it live in [TokenStore].
class AuthRepository {
  AuthRepository(this._api, this._tokens, this._prefs) {
    _user = _readCache();
    // The refresh token died somewhere inside a request: let go of the account.
    _api.onSignedOut = _forget;
  }

  static const _prefsKey = 'auth_user';

  final ApiClient _api;
  final TokenStore _tokens;
  final SharedPreferences _prefs;
  final _changes = StreamController<AuthUser?>.broadcast();

  AuthUser? _user;

  /// The account restored at start-up, before the stream has said anything.
  AuthUser? get currentUser => _user;

  /// Who is signed in, as it changes.
  Stream<AuthUser?> userChanges() => _changes.stream;

  Future<AuthUser> signUp({required String email, required String password}) =>
      _enter('/auth/register', {'email': email, 'password': password});

  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  }) => _enter('/auth/login', {'email': email, 'password': password});

  /// [idToken] is the ID token Google handed the app; the server checks it.
  Future<AuthUser> signInWithGoogle(String idToken) =>
      _enter('/auth/google', {'idToken': idToken});

  /// Ends the session here, and on the server when it can be reached quickly.
  ///
  /// Leaving must be quick and must work with no connection, so the server is
  /// given three seconds: a failed or slow `logout` is dropped (the request, if
  /// it was sent, still finishes by itself). The refresh token is wiped from the
  /// phone either way and is of no use to anyone who did not already have it.
  Future<void> signOut() async {
    final refresh = await _tokens.readRefreshToken();
    if (refresh != null) {
      try {
        await _api
            .request(
              'POST',
              '/auth/logout',
              body: {'refreshToken': refresh},
              auth: false,
            )
            .timeout(const Duration(seconds: 3));
      } on ApiException {
        // See above.
      } on TimeoutException {
        // See above.
      }
    }
    await _tokens.clear();
    _forget();
  }

  /// Asks the server who this is, to pick up a changed name or picture. Quiet
  /// when there is no connection; a dead session ends through [ApiClient].
  Future<void> refreshUser() async {
    if (_user == null) return;
    try {
      final json = await _api.request('GET', '/me') as Map<String, dynamic>;
      _set(AuthUser.fromJson(json));
    } on ApiException {
      // Offline: the cached copy stays.
    }
  }

  /// `DELETE /me`: exactly one of [password] (an account with a password) or
  /// [idToken] (a Google account, a **fresh** token). Irreversible. A refusal
  /// comes back as an [ApiException] (`invalid_credentials` = wrong password);
  /// on success the session is gone here too. The local data is the caller's.
  Future<void> deleteAccount({String? password, String? idToken}) async {
    await _api.request(
      'DELETE',
      '/me',
      body: {'password': ?password, 'idToken': ?idToken},
    );
    await _tokens.clear();
    _forget();
  }

  Future<AuthUser> _enter(String path, Map<String, String> body) async {
    final json =
        await _api.request('POST', path, body: body, auth: false)
            as Map<String, dynamic>;
    await _tokens.save(
      access: json['accessToken'] as String,
      refresh: json['refreshToken'] as String,
    );
    return _set(AuthUser.fromJson(json['user'] as Map<String, dynamic>));
  }

  AuthUser _set(AuthUser user) {
    if (user == _user) return user;
    _user = user;
    _prefs.setString(_prefsKey, jsonEncode(user.toJson()));
    _changes.add(user);
    return user;
  }

  void _forget() {
    if (_user == null) return;
    _user = null;
    _prefs.remove(_prefsKey);
    _changes.add(null);
  }

  AuthUser? _readCache() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null) return null;
    try {
      return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A cache we cannot read is no cache: the next sign-in writes a new one.
      return null;
    }
  }
}
