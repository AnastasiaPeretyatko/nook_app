import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo_app/api/api_client.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/api/token_store.dart';

http.Response json(int status, Object? body, {Map<String, String>? headers}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
    );

const unauthorized = {'code': 'unauthorized', 'message': 'x'};
const refreshed = {'accessToken': 'new', 'refreshToken': 'r2'};

void main() {
  late MemoryTokenStore tokens;
  late List<Duration> slept;

  ApiClient clientFor(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 5),
    String? device,
    DateTime Function()? now,
  }) => ApiClient(
    deviceId: device == null ? null : () => device,
    clock: now ?? DateTime.now,
    baseUrl: 'https://x.test',
    tokens: tokens,
    client: MockClient(handler),
    timeout: timeout,
    sleep: (d) async => slept.add(d),
  );

  setUp(() {
    tokens = MemoryTokenStore(accessToken: 'old', refreshToken: 'r1');
    slept = [];
  });

  test('sends the Bearer token and decodes the answer', () async {
    final api = clientFor((req) async {
      expect(req.headers['authorization'], 'Bearer old');
      expect(req.url.toString(), 'https://x.test/me?a=1');
      return json(200, {'id': 'u'});
    });
    expect(await api.request('GET', '/me', query: {'a': '1'}), {'id': 'u'});
  });

  group('freshAccessToken', () {
    final now = DateTime.utc(2026, 10, 30, 12);

    /// A token that expires [after] from [now] (the signature is not read).
    String jwt(Duration after) {
      String part(Object o) =>
          base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      final exp = now.add(after).millisecondsSinceEpoch ~/ 1000;
      return '${part({'alg': 'HS256'})}.${part({'exp': exp})}.sig';
    }

    test('a token with time left is used as it is, with no request', () async {
      final good = jwt(const Duration(minutes: 30));
      tokens.accessToken = good;
      final api = clientFor(
        (_) async => fail('no request expected'),
        now: () => now,
      );

      expect(await api.freshAccessToken(), good);
    });

    for (final (name, left) in [
      ('one that has expired', const Duration(minutes: -5)),
      ('one that expires within the minute', const Duration(seconds: 40)),
    ]) {
      test('$name is refreshed first', () async {
        tokens.accessToken = jwt(left);
        final api = clientFor((req) async {
          expect(req.url.path, '/auth/refresh');
          return json(200, refreshed);
        }, now: () => now);

        expect(await api.freshAccessToken(), 'new');
        expect(tokens.accessToken, 'new');
      });
    }

    test('no token in memory (a cold start) refreshes', () async {
      tokens.accessToken = null;
      final api = clientFor((_) async => json(200, refreshed), now: () => now);
      expect(await api.freshAccessToken(), 'new');
    });

    test('a token it cannot read is left to the server', () async {
      tokens.accessToken = 'not-a-jwt';
      final api = clientFor((_) async => fail('no request expected'));
      expect(await api.freshAccessToken(), 'not-a-jwt');
    });

    test('no network: offline, and the tokens stay', () async {
      tokens.accessToken = jwt(const Duration(minutes: -1));
      final api = clientFor(
        (_) async => throw const SocketException('down'),
        now: () => now,
      );

      await expectLater(
        api.freshAccessToken(),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'offline', true),
        ),
      );
      expect(await tokens.readRefreshToken(), 'r1');
    });

    test('a dead refresh token signs the user out', () async {
      tokens.accessToken = jwt(const Duration(minutes: -1));
      var signedOut = false;
      final api = clientFor(
        (_) async => json(401, {'code': 'invalid_refresh_token'}),
        now: () => now,
      )..onSignedOut = () => signedOut = true;

      await expectLater(
        api.freshAccessToken(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.failure,
            'failure',
            ApiFailure.signInRequired,
          ),
        ),
      );
      expect(signedOut, isTrue);
    });
  });

  group('X-Device-Id', () {
    test('goes with every request that changes something', () async {
      final seen = <String, String?>{};
      final api = clientFor((req) async {
        seen[req.method] = req.headers['x-device-id'];
        return http.Response('', 204);
      }, device: 'phone-1');
      for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
        await api.request(method, '/x');
      }
      expect(seen, {
        'POST': 'phone-1',
        'PUT': 'phone-1',
        'PATCH': 'phone-1',
        'DELETE': 'phone-1',
      });
    });

    test('not with a read, nor to /auth, nor when there is no id', () async {
      final seen = <String?>[];
      final api = clientFor((req) async {
        seen.add(req.headers['x-device-id']);
        return json(200, {'accessToken': 'a', 'refreshToken': 'b'});
      }, device: 'phone-1');
      await api.request('GET', '/me');
      await api.request('POST', '/auth/login', auth: false);
      expect(seen, [null, null]);

      final plain = clientFor((req) async {
        seen.add(req.headers['x-device-id']);
        return http.Response('', 204);
      });
      await plain.request('POST', '/sync/push');
      expect(seen.last, isNull);
    });

    test('the refresh a request triggers does not carry it', () async {
      final seen = <String, String?>{};
      final api = clientFor((req) async {
        seen[req.url.path] = req.headers['x-device-id'];
        if (req.url.path == '/auth/refresh') return json(200, refreshed);
        return req.headers['authorization'] == 'Bearer old'
            ? json(401, unauthorized)
            : http.Response('', 204);
      }, device: 'phone-1');
      await api.request('POST', '/sync/push');
      expect(seen['/auth/refresh'], isNull);
      expect(seen['/sync/push'], 'phone-1');
    });
  });

  test('an empty 204 answer is null', () async {
    final api = clientFor((_) async => http.Response('', 204));
    expect(
      await api.request('DELETE', '/devices', body: {'token': 't'}),
      isNull,
    );
  });

  test('401 unauthorized: one refresh, then the same request again', () async {
    final seen = <String>[];
    final api = clientFor((req) async {
      seen.add('${req.url.path} ${req.headers['authorization']}');
      if (req.url.path == '/auth/refresh') {
        expect(jsonDecode(req.body), {'refreshToken': 'r1'});
        return json(200, refreshed);
      }
      return req.headers['authorization'] == 'Bearer old'
          ? json(401, unauthorized)
          : json(200, {'ok': true});
    });
    expect(await api.request('GET', '/me'), {'ok': true});
    expect(seen, ['/me Bearer old', '/auth/refresh null', '/me Bearer new']);
    expect(tokens.accessToken, 'new');
    expect(await tokens.readRefreshToken(), 'r2');
  });

  test('parallel requests share one refresh', () async {
    var refreshCalls = 0;
    final api = clientFor((req) async {
      if (req.url.path == '/auth/refresh') {
        refreshCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return json(200, refreshed);
      }
      return req.headers['authorization'] == 'Bearer old'
          ? json(401, unauthorized)
          : json(200, {});
    });
    await Future.wait([api.request('GET', '/a'), api.request('GET', '/b')]);
    expect(refreshCalls, 1);
  });

  test('a second 401 after the refresh is an error, not a loop', () async {
    var calls = 0;
    final api = clientFor((req) async {
      calls++;
      return req.url.path == '/auth/refresh'
          ? json(200, refreshed)
          : json(401, unauthorized);
    });
    await expectLater(
      api.request('GET', '/me'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.server)
            .having((e) => e.status, 'status', 401),
      ),
    );
    expect(calls, 3); // request, refresh, request
  });

  test('a 401 with another code never refreshes (wrong password)', () async {
    var calls = 0;
    final api = clientFor((_) async {
      calls++;
      return json(401, {'code': 'invalid_credentials', 'message': 'x'});
    });
    await expectLater(
      api.request('DELETE', '/me', body: {'password': 'p'}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'invalid_credentials',
        ),
      ),
    );
    expect(calls, 1);
  });

  test('invalid_refresh_token wipes the tokens and asks to sign in', () async {
    final api = clientFor(
      (req) async => req.url.path == '/auth/refresh'
          ? json(401, {'code': 'invalid_refresh_token', 'message': 'x'})
          : json(401, unauthorized),
    );
    await expectLater(
      api.request('GET', '/me'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.failure,
          'failure',
          ApiFailure.signInRequired,
        ),
      ),
    );
    expect(tokens.accessToken, isNull);
    expect(await tokens.readRefreshToken(), isNull);
  });

  test('no network during refresh keeps the tokens', () async {
    final api = clientFor(
      (req) async => req.url.path == '/auth/refresh'
          ? throw const SocketException('down')
          : json(401, unauthorized),
    );
    await expectLater(
      api.request('GET', '/me'),
      throwsA(isA<ApiException>().having((e) => e.isOffline, 'offline', true)),
    );
    expect(tokens.accessToken, 'old');
    expect(await tokens.readRefreshToken(), 'r1');
  });

  test('a cold start (only the refresh token) refreshes first', () async {
    tokens = MemoryTokenStore(refreshToken: 'r1');
    final api = clientFor(
      (req) async => req.url.path == '/auth/refresh'
          ? json(200, refreshed)
          : json(200, {'auth': req.headers['authorization']}),
    );
    expect(await api.request('GET', '/me'), {'auth': 'Bearer new'});
  });

  test('no tokens at all asks to sign in without calling the server', () async {
    tokens = MemoryTokenStore();
    final api = clientFor((_) async => fail('must not be called'));
    await expectLater(
      api.request('GET', '/me'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.failure,
          'failure',
          ApiFailure.signInRequired,
        ),
      ),
    );
  });

  test('auth: false sends no token and does not refresh', () async {
    final api = clientFor((req) async {
      expect(req.headers.containsKey('authorization'), isFalse);
      return json(401, {'code': 'invalid_credentials', 'message': 'x'});
    });
    await expectLater(
      api.request('POST', '/auth/login', body: {}, auth: false),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
  });

  group('no connection', () {
    for (final error in <Object>[
      const SocketException('down'),
      const HandshakeException('tls'),
      http.ClientException('reset'),
    ]) {
      test('${error.runtimeType} is offline', () async {
        final api = clientFor((_) async => throw error);
        await expectLater(
          api.request('GET', '/me'),
          throwsA(
            isA<ApiException>().having((e) => e.isOffline, 'offline', true),
          ),
        );
      });
    }

    test('a slow server times out as offline', () async {
      final api = clientFor(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        api.request('GET', '/me'),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'offline', true),
        ),
      );
    });

    test('a 502 from the proxy is offline', () async {
      final api = clientFor((_) async => http.Response('<html>', 502));
      await expectLater(
        api.request('GET', '/me'),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'offline', true),
        ),
      );
    });
  });

  test('429 is not retried and carries the wait', () async {
    var calls = 0;
    final api = clientFor((_) async {
      calls++;
      return json(
        429,
        {'code': 'too_many_requests', 'message': 'x'},
        headers: {'retry-after-burst': '17'},
      );
    });
    await expectLater(
      api.request('GET', '/me'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'too_many_requests')
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 17),
            ),
      ),
    );
    expect(calls, 1);
    expect(slept, isEmpty);
  });

  group('503 db_unavailable', () {
    final down = {'code': 'db_unavailable', 'message': 'x'};

    test('waits Retry-After and repeats the same request', () async {
      var calls = 0;
      final api = clientFor(
        (_) async => ++calls < 3
            ? json(503, down, headers: {'retry-after': '5'})
            : json(200, {'ok': 1}),
      );
      expect(await api.request('POST', '/sync/push', body: {}), {'ok': 1});
      expect(slept, [const Duration(seconds: 5), const Duration(seconds: 5)]);
    });

    test('three failures in a row become "no connection"', () async {
      var calls = 0;
      final api = clientFor((_) async {
        calls++;
        return json(503, down, headers: {'retry-after': '5'});
      });
      await expectLater(
        api.request('GET', '/me'),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'offline', true),
        ),
      );
      expect(calls, 3);
    });
  });

  test('400 and 413 are not retried', () async {
    for (final status in [400, 413]) {
      var calls = 0;
      final api = clientFor((_) async {
        calls++;
        return json(status, {'code': 'bad_request', 'message': 'x'});
      });
      await expectLater(
        api.request('POST', '/sync/push', body: {}),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', status)),
      );
      expect(calls, 1);
    }
  });
}
