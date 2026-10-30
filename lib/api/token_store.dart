import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the session's two tokens live.
///
/// The access token is short-lived and kept in memory only; the refresh token
/// is what lets the app stay signed in across launches, so it is the one that
/// must survive a restart.
abstract class TokenStore {
  String? get accessToken;

  Future<String?> readRefreshToken();

  Future<void> save({required String access, required String refresh});

  Future<void> clear();
}

/// For tests, and the shape every real store follows.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore({this.accessToken, this.refreshToken});

  @override
  String? accessToken;
  String? refreshToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> save({required String access, required String refresh}) async {
    accessToken = access;
    refreshToken = refresh;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }
}

/// The real store: the refresh token goes to the platform's keystore, so the
/// session survives a restart; the access token stays in memory (after a
/// restart [ApiClient] simply refreshes once).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _refreshKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  @override
  String? accessToken;

  @override
  Future<String?> readRefreshToken() async {
    try {
      return await _storage.read(key: _refreshKey);
    } catch (_) {
      // An unreadable keystore (e.g. data restored onto another phone) is the
      // same as no session: the user signs in again.
      return null;
    }
  }

  @override
  Future<void> save({required String access, required String refresh}) async {
    accessToken = access;
    await _storage.write(key: _refreshKey, value: refresh);
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    await _storage.delete(key: _refreshKey);
  }
}
