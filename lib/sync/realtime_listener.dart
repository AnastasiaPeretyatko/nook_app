import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One open WebSocket, as little of it as the listener needs — so that a test
/// can put a fake in its place.
abstract class WsConnection {
  /// Text frames from the server. Done when the connection is gone, for any
  /// reason.
  Stream<String> get messages;

  void send(String text);

  Future<void> close();
}

typedef WsConnector = Future<WsConnection> Function(Uri url);

class _IoConnection implements WsConnection {
  _IoConnection(this._socket);

  final WebSocket _socket;

  @override
  Stream<String> get messages =>
      _socket.where((m) => m is String).cast<String>();

  @override
  void send(String text) => _socket.add(text);

  @override
  Future<void> close() => _socket.close();
}

/// The real connector. A server waking up can take half a minute, so the wait
/// is long; a socket that opens after we gave up is closed, not leaked.
Future<WsConnection> connectWebSocket(Uri url) async {
  final opening = WebSocket.connect(url.toString());
  try {
    return _IoConnection(await opening.timeout(const Duration(seconds: 30)));
  } on TimeoutException {
    unawaited(opening.then((socket) => socket.close(), onError: (_) {}));
    rethrow;
  }
}

/// Hears from the server that something changed, and says so — nothing more.
///
/// The server's `{"t":"changed"}` is a **doorbell, not data**: [onSignal] runs
/// the ordinary sync, so the merge rules live in one place and a missed or
/// duplicated ring can do no harm.
///
/// Two things make this more than "open a socket":
///
/// * The server tells a new connection nothing, so whatever happened while the
///   phone was not connected is found out by one sync **after every
///   connection**. That is also why there is no timer any more: a ring that
///   never arrived is caught at the next (re)connection.
/// * Every drop is a reason to reconnect, whatever the close code: the proxy in
///   front of the server does not pass the server's codes on, so a dead
///   connection is only ever seen as a silence. Pauses grow 1, 2, 4 … 60 s.
class RealtimeListener {
  RealtimeListener({
    required this.baseUrl,
    required this.token,
    required this.deviceId,
    required this.onSignal,
    this.connector = connectWebSocket,
    this.quietFor = const Duration(seconds: 1),
    this.pingEvery = const Duration(minutes: 4),
    this.stableAfter = const Duration(seconds: 30),
  });

  /// The server's `https://…` address.
  final String baseUrl;

  /// A token good for the handshake; `force` asks for a new one regardless of
  /// its expiry (the server just called the old one bad).
  final Future<String> Function({bool force}) token;

  /// This phone's name, so the server does not ring the phone that wrote.
  final String? Function() deviceId;

  /// Called once per burst of rings, and after every connection.
  final VoidCallback onSignal;
  final WsConnector connector;

  /// A tick fires several rings at once (a task and its logs); waiting for
  /// quiet turns a burst into one sync.
  final Duration quietFor;

  /// The server closes a connection silent for ten minutes.
  final Duration pingEvery;

  /// A connection that lived this long counts as a good one and resets the
  /// pause — otherwise one that opens and drops at once would be retried every
  /// second for ever.
  final Duration stableAfter;

  static const _maxPause = 60;

  /// Bumped by every start and stop; whatever an older round was waiting for
  /// finds it changed and lets go.
  int _round = 0;
  int _failures = 0;
  bool _forceToken = false;
  WsConnection? _connection;
  StreamSubscription<String>? _listening;
  Timer? _quiet;
  Timer? _ping;
  Timer? _stable;
  Timer? _retry;

  bool _running = false;

  bool get isConnected => _connection != null;

  /// Started and not stopped since — whether or not a connection is up right
  /// now (it may be between two tries).
  bool get isRunning => _running;

  void start() {
    stop();
    _running = true;
    unawaited(_open(_round));
  }

  void stop() {
    if (_connection != null) debugPrint('Realtime: closed by the app');
    _running = false;
    _round++;
    _failures = 0;
    _forceToken = false;
    _retry?.cancel();
    _quiet?.cancel();
    _retry = _quiet = null;
    _drop();
  }

  Future<void> _open(int round) async {
    try {
      final access = await token(force: _forceToken);
      _forceToken = false;
      if (round != _round) return;
      final connection = await connector(_address(access));
      if (round != _round) {
        unawaited(connection.close());
        return;
      }
      _connection = connection;
      _listening = connection.messages.listen(
        (text) => _heard(round, text),
        onDone: () => _lost(round, 'closed'),
        onError: (Object e) => _lost(round, '$e'),
      );
      _ping = Timer.periodic(pingEvery, (_) => connection.send('{"t":"ping"}'));
      _stable = Timer(stableAfter, () => _failures = 0);
      debugPrint('Realtime: connected');
      // Nothing is said on connecting; this is what finds out what was missed.
      onSignal();
    } catch (e) {
      if (round != _round) return;
      debugPrint('Realtime: could not connect: $e');
      _scheduleRetry(round);
    }
  }

  Uri _address(String access) {
    final base = Uri.parse(baseUrl);
    final device = deviceId();
    return base.replace(
      scheme: base.scheme == 'http' ? 'ws' : 'wss',
      path: '/ws',
      queryParameters: {'token': access, 'device': ?device},
    );
  }

  void _heard(int round, String text) {
    if (round != _round) return;
    final Object? message;
    try {
      message = jsonDecode(text);
    } catch (_) {
      return;
    }
    switch (message is Map ? message['t'] : null) {
      case 'changed':
        debugPrint('Realtime: changed');
        ring();
      case 'unauthorized':
        // The token was refused while the connection lived. Hang up, get a new
        // one, come back.
        debugPrint('Realtime: token refused');
        _forceToken = true;
        _lost(round, 'unauthorized');
    }
  }

  void _lost(int round, String why) {
    if (round != _round) return;
    debugPrint('Realtime: connection lost ($why)');
    _drop();
    _scheduleRetry(round);
  }

  void _scheduleRetry(int round) {
    final pause = Duration(
      seconds: _failures >= 6 ? _maxPause : 1 << _failures,
    );
    _failures++;
    _retry?.cancel();
    _retry = Timer(pause, () => unawaited(_open(round)));
  }

  /// Lets go of the connection, if there is one.
  void _drop() {
    _ping?.cancel();
    _stable?.cancel();
    _ping = _stable = null;
    unawaited(_listening?.cancel());
    _listening = null;
    final connection = _connection;
    _connection = null;
    if (connection != null) unawaited(connection.close().catchError((_) {}));
  }

  /// One ring arrived. Public so a test can ring it without a server.
  @visibleForTesting
  void ring() {
    _quiet?.cancel();
    _quiet = Timer(quietFor, onSignal);
  }
}
