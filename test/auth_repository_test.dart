import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/api/api_client.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/api/token_store.dart';
import 'package:todo_app/auth/auth_errors.dart';
import 'package:todo_app/auth/auth_repository.dart';
import 'package:todo_app/auth/auth_user.dart';

http.Response json(int status, Object? body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const user = {
  'id': 'u1',
  'email': 'a@b.c',
  'displayName': null,
  'avatarUrl': null,
};
const session = {'accessToken': 'acc', 'refreshToken': 'ref', 'user': user};

void main() {
  late MemoryTokenStore tokens;
  late SharedPreferences prefs;
  late List<String> seen;
  late Future<http.Response> Function(http.Request) handler;

  AuthRepository repo() => AuthRepository(
    ApiClient(
      baseUrl: 'https://x.test',
      tokens: tokens,
      client: MockClient((req) {
        seen.add('${req.method} ${req.url.path} ${req.body}');
        return handler(req);
      }),
    ),
    tokens,
    prefs,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tokens = MemoryTokenStore();
    seen = [];
    handler = (_) async => json(200, session);
  });

  test(
    'signing in keeps the tokens, caches the user and announces it',
    () async {
      final r = repo();
      final changes = <AuthUser?>[];
      r.userChanges().listen(changes.add);

      final signedIn = await r.signInWithPassword(
        email: 'a@b.c',
        password: 'password1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(signedIn.id, 'u1');
      expect(seen.single, startsWith('POST /auth/login'));
      expect(tokens.accessToken, 'acc');
      expect(await tokens.readRefreshToken(), 'ref');
      expect(r.currentUser, signedIn);
      expect(changes, [signedIn]);
    },
  );

  test('Google sign-in posts the ID token to /auth/google', () async {
    final r = repo();
    final signedIn = await r.signInWithGoogle('google-id-token');
    expect(seen.single, 'POST /auth/google {"idToken":"google-id-token"}');
    expect(signedIn.id, 'u1');
  });

  test('a new instance (a restart) starts signed in from the cache', () async {
    await repo().signUp(email: 'a@b.c', password: 'password1');
    expect(repo().currentUser?.email, 'a@b.c');
  });

  test('the server saying no leaves nobody signed in', () async {
    handler = (_) async =>
        json(401, {'code': 'invalid_credentials', 'message': 'x'});
    final r = repo();
    await expectLater(
      r.signInWithPassword(email: 'a@b.c', password: 'nope'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'invalid_credentials',
        ),
      ),
    );
    expect(r.currentUser, isNull);
    expect(tokens.accessToken, isNull);
  });

  test('signing out works with no connection', () async {
    final r = repo();
    await r.signInWithPassword(email: 'a@b.c', password: 'password1');
    handler = (_) async => throw const SocketException('down');

    await r.signOut();

    expect(r.currentUser, isNull);
    expect(tokens.accessToken, isNull);
    expect(await tokens.readRefreshToken(), isNull);
    expect(repo().currentUser, isNull, reason: 'the cache is gone too');
  });

  test('signing out tells the server which refresh token to retire', () async {
    final r = repo();
    await r.signInWithPassword(email: 'a@b.c', password: 'password1');
    handler = (_) async => http.Response('', 204);
    await r.signOut();
    expect(seen.last, 'POST /auth/logout {"refreshToken":"ref"}');
  });

  test('refreshUser picks up a new name, and stays quiet offline', () async {
    final r = repo();
    await r.signInWithPassword(email: 'a@b.c', password: 'password1');

    handler = (_) async => json(200, {...user, 'displayName': 'Настя'});
    await r.refreshUser();
    expect(r.currentUser?.displayName, 'Настя');

    handler = (_) async => throw const SocketException('down');
    await r.refreshUser();
    expect(r.currentUser?.displayName, 'Настя');
  });

  test('a dead refresh token ends the session', () async {
    final r = repo();
    await r.signInWithPassword(email: 'a@b.c', password: 'password1');
    tokens.accessToken = null; // as after a restart
    handler = (_) async =>
        json(401, {'code': 'invalid_refresh_token', 'message': 'x'});

    await r.refreshUser(); // throws nothing: it is just the end of the session

    expect(r.currentUser, isNull);
    expect(await tokens.readRefreshToken(), isNull);
  });

  group('deleting the account', () {
    test('sends the password and signs out on 204', () async {
      final r = repo();
      await r.signInWithPassword(email: 'a@b.c', password: 'password1');
      handler = (_) async => http.Response('', 204);

      await r.deleteAccount(password: 'password1');

      expect(seen.last, 'DELETE /me {"password":"password1"}');
      expect(r.currentUser, isNull);
      expect(tokens.accessToken, isNull);
    });

    test(
      'a wrong password keeps the session and never refreshes the token',
      () async {
        final r = repo();
        await r.signInWithPassword(email: 'a@b.c', password: 'password1');
        seen.clear();
        handler = (_) async =>
            json(401, {'code': 'invalid_credentials', 'message': 'x'});

        await expectLater(
          r.deleteAccount(password: 'wrong'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'invalid_credentials',
            ),
          ),
        );

        expect(seen, hasLength(1));
        expect(r.currentUser, isNotNull);
      },
    );

    test('a Google account sends a fresh ID token instead', () async {
      final r = repo();
      await r.signInWithPassword(email: 'a@b.c', password: 'password1');
      handler = (_) async => http.Response('', 204);
      await r.deleteAccount(idToken: 'tok');
      expect(seen.last, 'DELETE /me {"idToken":"tok"}');
    });
  });

  group('what the screen says', () {
    String say(ApiException e) => authErrorMessage(e);
    ApiException refused(String code) =>
        ApiException(ApiFailure.server, status: 400, code: code);

    test('known codes are in Russian', () {
      expect(say(refused('invalid_credentials')), 'Неверная почта или пароль');
      expect(say(refused('email_taken')), contains('уже зарегистрирована'));
      expect(say(refused('weak_password')), contains('8'));
      expect(say(refused('google_email_conflict')), contains('по паролю'));
    });

    test('no connection has its own sentence', () {
      expect(say(const ApiException.offline()), contains('Нет связи'));
    });

    test('an unknown code never leaks through', () {
      expect(
        say(refused('something_new')),
        'Не удалось войти. Попробуйте ещё раз',
      );
      expect(authErrorMessage(StateError('boom')), isNot(contains('boom')));
    });
  });

  test(
    'AuthUser: initial from the name, else the address; a blank name is none',
    () {
      expect(const AuthUser(id: '1', email: 'zed@x.y').avatarInitial, 'Z');
      expect(
        const AuthUser(
          id: '1',
          email: 'zed@x.y',
          displayName: 'анна',
        ).avatarInitial,
        'А',
      );
      expect(
        AuthUser.fromJson({...user, 'displayName': '  '}).displayName,
        isNull,
      );
    },
  );
}
