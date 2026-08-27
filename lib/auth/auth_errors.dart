import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// What to show the user when signing in or up did not work.
///
/// Supabase answers in English and the app speaks Russian, so nothing raw ever
/// reaches the screen. The match is on [AuthException.code] — the string the
/// server sent, not the `ErrorCode` enum, which is missing entries the API does
/// return (`invalid_credentials` among them).
///
/// The network case is the one that must not be skipped: without a connection
/// signing in is impossible, and the honest answer is a sentence, not a spinner
/// that never stops.
String authErrorMessage(Object error) {
  if (error is SocketException ||
      error is TimeoutException ||
      error is AuthRetryableFetchException) {
    return 'Нет связи с сервером. Проверьте интернет';
  }

  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'Неверная почта или пароль';
      case 'user_already_exists':
      case 'email_exists':
        return 'Такая почта уже зарегистрирована';
      case 'weak_password':
        return 'Слишком простой пароль';
      case 'email_not_confirmed':
        return 'Подтвердите почту — мы отправили письмо';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return 'Слишком много попыток. Попробуйте позже';
      case 'signup_disabled':
        return 'Регистрация сейчас закрыта';
      case 'user_banned':
        return 'Этот аккаунт заблокирован';
    }
    // A code we have no wording for. The English message is worse than nothing:
    // it names internals the user cannot act on.
    return 'Не удалось войти. Попробуйте ещё раз';
  }

  return 'Не удалось войти. Попробуйте ещё раз';
}
