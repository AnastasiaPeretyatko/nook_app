import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'token_store.dart';

typedef Sleep = Future<void> Function(Duration);

/// A thin JSON client for the app's own server (contract: BACKEND_PLAN.md §4).
///
/// It owns the token dance so the callers never see it: a Bearer header on
/// every request, **one** refresh when the server answers `401 unauthorized`
/// and a retry of the same request, and the failures flattened into
/// [ApiException].
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokens,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.sleep = _realSleep,
    this.deviceId,
    this.clock = DateTime.now,
  }) : _http = client ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final http.Client _http;

  /// One request. Long on purpose: Neon needs seconds to wake up.
  final Duration timeout;

  /// Injected so a test does not really wait out a `Retry-After`.
  final Sleep sleep;

  /// This phone's name, sent as `X-Device-Id` with every request that changes
  /// something, so the server does not ring the phone that made the change.
  /// A function because the id lives in prefs, which may not be ready yet.
  final String? Function()? deviceId;

  /// Injected so a test can say what time it is when a token is read.
  final DateTime Function() clock;

  /// Called once the session is gone for good (the refresh token is dead or
  /// missing and the tokens were wiped): whoever shows "signed in" lets go.
  void Function()? onSignedOut;

  /// The refresh in flight, if any. A refresh token is single-use, so a second
  /// parallel refresh would get `401`: everyone waits for this one instead.
  Future<void>? _refreshing;

  static const _dbAttempts = 3;
  static const _dbDefaultWait = Duration(seconds: 5);

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  /// Returns the decoded JSON body (`null` for an empty one, e.g. a `204`).
  ///
  /// `auth: false` is for `/auth/*` and `/health`, which take no token.
  Future<Object?> request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool auth = true,
  }) async {
    var refreshed = false;
    var dbFailures = 0;
    while (true) {
      final token = auth ? await _accessToken() : null;
      final res = await _send(method, path, query, body, token);
      if (res.statusCode < 300) return _decode(res);

      final error = _serverError(res);
      // Only `unauthorized` means "the access token is stale". A `401` with
      // another code (a wrong password on DELETE /me) must not trigger a refresh.
      if (auth &&
          !refreshed &&
          res.statusCode == 401 &&
          error.code == 'unauthorized') {
        refreshed = true;
        await _refresh(token);
        continue;
      }
      // The database is asleep or restarting: wait and ask again, then give up
      // as "no connection". Safe to repeat — pushes are written by id.
      if (error.code == 'db_unavailable') {
        if (++dbFailures >= _dbAttempts) throw ApiException.offline(error);
        await sleep(error.retryAfter ?? _dbDefaultWait);
        continue;
      }
      throw _failureFor(res, error);
    }
  }

  void close() => _http.close();

  /// An access token good for at least [margin] more — for a connection that
  /// outlives one request (the socket takes the token once, at the handshake,
  /// and cannot retry on `401` the way a request does). Refreshes through the
  /// same single-flight path when the token is gone, past its `exp`, or about
  /// to be. A token whose `exp` cannot be read is passed on as it is: the
  /// server is the judge of it.
  ///
  /// [force] is for when the server has just called the token bad though its
  /// `exp` looks fine (the clock on the phone is off, or the session moved).
  Future<String> freshAccessToken({
    Duration margin = const Duration(minutes: 1),
    bool force = false,
  }) async {
    final token = tokens.accessToken;
    if (!force && token != null && !_expiresWithin(token, margin)) return token;
    await _refresh(token);
    return tokens.accessToken ?? (throw const ApiException.signInRequired());
  }

  bool _expiresWithin(String jwt, Duration margin) {
    try {
      final payload = jwt.split('.')[1];
      final json =
          jsonDecode(utf8.decode(base64Url.decode(base64.normalize(payload))))
              as Map;
      final exp = json['exp'];
      if (exp is! num) return false;
      final expires = DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
      return !expires.isAfter(clock().toUtc().add(margin));
    } catch (_) {
      return false;
    }
  }

  Future<String> _accessToken() async {
    final token = tokens.accessToken;
    if (token != null) return token;
    // A cold start: only the refresh token survived the restart.
    await _refresh(null);
    return tokens.accessToken ?? (throw const ApiException.signInRequired());
  }

  Future<void> _refresh(String? failedToken) {
    final current = tokens.accessToken;
    // Another request already got a fresh token while this one was in flight.
    if (failedToken != null && current != null && current != failedToken) {
      return Future.value();
    }
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    final refresh = await tokens.readRefreshToken();
    if (refresh == null) return _endSession();

    final res = await _send('POST', '/auth/refresh', null, {
      'refreshToken': refresh,
    }, null);
    if (res.statusCode == 200) {
      final json = _decode(res) as Map<String, dynamic>;
      await tokens.save(
        access: json['accessToken'] as String,
        refresh: json['refreshToken'] as String,
      );
      return;
    }
    final error = _serverError(res);
    if (error.code == 'invalid_refresh_token') return _endSession();
    // Anything else (no network, a sleeping server) leaves the tokens alone.
    throw _failureFor(res, error);
  }

  Future<void> _endSession() async {
    await tokens.clear();
    onSignedOut?.call();
    throw const ApiException.signInRequired();
  }

  Future<http.Response> _send(
    String method,
    String path,
    Map<String, String>? query,
    Object? body,
    String? token,
  ) async {
    final uri = Uri.parse(baseUrl).replace(path: path, queryParameters: query);
    try {
      return await Future(() async {
        final req = http.Request(method, uri)
          ..headers['accept'] = 'application/json';
        if (token != null) req.headers['authorization'] = 'Bearer $token';
        final device = deviceId?.call();
        if (token != null && method != 'GET' && device != null) {
          req.headers['x-device-id'] = device;
        }
        if (body != null) {
          req.headers['content-type'] = 'application/json';
          req.body = jsonEncode(body);
        }
        return http.Response.fromStream(await _http.send(req));
      }).timeout(timeout);
    } catch (e) {
      if (ApiException.isNetworkError(e)) throw ApiException.offline(e);
      rethrow;
    }
  }

  static Object? _decode(http.Response res) =>
      res.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));

  static ApiException _serverError(http.Response res) {
    String? code, message;
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is Map) {
        code = json['code'] as String?;
        message = json['message'] as String?;
      }
    } catch (_) {
      // Not JSON (a proxy's HTML page): the status alone tells the story.
    }
    final wait = int.tryParse(
      res.headers['retry-after-burst'] ?? res.headers['retry-after'] ?? '',
    );
    return ApiException(
      ApiFailure.server,
      status: res.statusCode,
      code: code,
      message: message,
      retryAfter: wait == null ? null : Duration(seconds: wait),
    );
  }

  /// 502/503/504 come from Render's proxy while the service wakes up or
  /// restarts — the same "no connection" as a dead socket.
  static ApiException _failureFor(http.Response res, ApiException error) =>
      const {502, 503, 504}.contains(res.statusCode)
      ? ApiException.offline(error)
      : error;
}
