import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// What went wrong with a request, in the three ways the app reacts to.
enum ApiFailure {
  /// No connection, a timeout, or a server that is waking up. Not an error of
  /// the app: work goes on from the local data and the next sync tries again.
  offline,

  /// The server answered and said no; [ApiException.code] says why.
  server,

  /// The session is gone (the refresh token is dead): show the sign-in screen.
  signInRequired,
}

class ApiException implements Exception {
  const ApiException(
    this.failure, {
    this.status,
    this.code,
    this.message,
    this.retryAfter,
    this.cause,
  });

  const ApiException.offline([Object? cause])
    : this(ApiFailure.offline, code: 'offline', cause: cause);

  const ApiException.signInRequired()
    : this(ApiFailure.signInRequired, code: 'sign_in_required');

  final ApiFailure failure;

  /// HTTP status, only for [ApiFailure.server].
  final int? status;

  /// The server's snake_case `code` (`bad_code`, `email_taken`, …).
  final String? code;
  final String? message;

  /// How long the server asked us to wait (`Retry-After-burst` on a 429).
  final Duration? retryAfter;

  final Object? cause;

  bool get isOffline => failure == ApiFailure.offline;

  /// A failure of the wire itself: nothing reached the server, or the TLS
  /// handshake broke (what a network that blocks the server looks like).
  /// `http`'s own `ClientException` is what `IOClient` wraps a socket error in.
  static bool isNetworkError(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException ||
      error is http.ClientException;

  @override
  String toString() =>
      'ApiException($failure${status == null ? '' : ' $status'}'
      '${code == null ? '' : ' $code'})';
}
