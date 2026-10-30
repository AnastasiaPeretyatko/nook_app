import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/auth/auth_repository.dart';
import 'package:todo_app/auth/auth_user.dart';
import 'package:todo_app/auth/google_id_token.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/pages/account_page.dart';
import 'package:todo_app/settings/theme_provider.dart';

class _FakeAuth implements AuthRepository {
  final tokens = <String>[];

  /// While set, the "server" has not answered yet.
  Completer<void>? answer;

  /// Whether the "server" accepts the sign-in.
  bool accept = false;

  @override
  Future<AuthUser> signInWithGoogle(String idToken) async {
    tokens.add(idToken);
    await answer?.future;
    if (!accept) {
      throw StateError('stop here: the screen only needs to have asked');
    }
    return const AuthUser(id: 'u', email: 'a@b.c');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU', null));

  Future<_FakeAuth> open(
    WidgetTester tester,
    Future<String?> Function() google, {
    _FakeAuth? with_,
    bool pushed = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = with_ ?? _FakeAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWithValue(null),
          authRepositoryProvider.overrideWithValue(auth),
          googleIdTokenProvider.overrideWithValue(google),
        ],
        child: MaterialApp(
          locale: const Locale('ru', 'RU'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru', 'RU')],
          home: pushed
              ? Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AccountPage(),
                          ),
                        ),
                        child: const Text('к привычкам'),
                      ),
                    ),
                  ),
                )
              : const AccountPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (pushed) {
      await tester.tap(find.text('к привычкам'));
      await tester.pumpAndSettle();
    }
    return auth;
  }

  testWidgets('the Google token goes to the server, with no browser', (
    tester,
  ) async {
    final auth = await open(tester, () async => 'id-token');
    await tester.ensureVisible(find.text('Войти через Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти через Google'));
    await tester.pumpAndSettle();

    expect(auth.tokens, ['id-token']);
  });

  testWidgets('closing the Google sheet is not an error', (tester) async {
    final auth = await open(tester, () async => null);
    await tester.ensureVisible(find.text('Войти через Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти через Google'));
    await tester.pumpAndSettle();

    expect(auth.tokens, isEmpty);
    expect(find.textContaining('Не удалось'), findsNothing);
  });

  testWidgets(
    'while the server thinks, the screen says so; once in, it leaves',
    (tester) async {
      final auth = _FakeAuth()
        ..accept = true
        ..answer = Completer<void>();
      await open(tester, () async => 'id-token', with_: auth, pushed: true);
      await tester.ensureVisible(find.text('Войти через Google'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Войти через Google'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Входим через Google…'), findsOneWidget);
      expect(
        find.text('Вход'),
        findsOneWidget,
        reason: 'still on the account screen',
      );

      auth.answer!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Вход'), findsNothing);
      expect(
        find.text('к привычкам'),
        findsOneWidget,
        reason: 'back on the screen below',
      );
    },
  );
}
