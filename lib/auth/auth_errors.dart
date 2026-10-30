import 'package:google_sign_in/google_sign_in.dart';
import 'package:todo_app/api/api_exception.dart';

/// What to show the user when signing in or up did not work.
///
/// The server answers with a snake_case `code` (BACKEND_PLAN.md §4.1) and the
/// app speaks Russian, so nothing raw ever reaches the screen.
///
/// The network case is the one that must not be skipped: without a connection
/// signing in is impossible, and the honest answer is a sentence, not a spinner
/// that never stops.
String authErrorMessage(Object error) {
  if (error is ApiException) {
    if (error.isOffline) return 'Нет связи с сервером. Проверьте интернет';
    if (error.failure == ApiFailure.signInRequired) {
      return 'Сессия закончилась. Войдите снова';
    }
    switch (error.code) {
      case 'invalid_credentials':
        return 'Неверная почта или пароль';
      case 'email_taken':
        return 'Такая почта уже зарегистрирована';
      case 'invalid_email':
        return 'Проверьте адрес почты';
      case 'weak_password':
        return 'Пароль должен быть от 8 до 128 символов';
      case 'google_token_invalid':
        return 'Не удалось войти через Google. Попробуйте ещё раз';
      case 'google_email_conflict':
        return 'На эту почту уже есть аккаунт с паролем — войдите по паролю';
      case 'too_many_requests':
        return 'Слишком много попыток. Попробуйте позже';
      case 'db_unavailable':
        return 'Сервер сейчас недоступен. Попробуйте позже';
      case 'confirmation_required':
      case 'validation_failed':
        return 'Проверьте введённые данные';
    }
  }
  // Google itself refused or is not set up on this phone (no Play services, no
  // account, a signing key the console does not know).
  if (error is GoogleSignInException) {
    return 'Не удалось войти через Google. Проверьте, что на телефоне есть '
        'аккаунт Google';
  }
  // A code we have no wording for. The raw message is worse than nothing: it
  // names internals the user cannot act on.
  return 'Не удалось войти. Попробуйте ещё раз';
}

/// The same for `DELETE /me`. A `401 invalid_credentials` here is a wrong
/// password, not "the session ended" — see [AuthRepository.deleteAccount].
String deleteAccountErrorMessage(Object error) {
  if (error is GoogleSignInException) {
    return 'Не удалось подтвердить вход через Google. Попробуйте ещё раз';
  }
  if (error is ApiException && !error.isOffline) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'Неверный пароль';
      case 'google_token_invalid':
        return 'Не удалось подтвердить вход через Google. Попробуйте ещё раз';
      case 'too_many_requests':
        return 'Слишком много попыток. Попробуйте позже';
      case 'db_unavailable':
        return 'Сервер сейчас недоступен. Попробуйте позже';
    }
    return 'Не удалось удалить аккаунт. Попробуйте ещё раз';
  }
  if (error is ApiException) return 'Нет связи с сервером. Проверьте интернет';
  return 'Не удалось удалить аккаунт. Попробуйте ещё раз';
}
