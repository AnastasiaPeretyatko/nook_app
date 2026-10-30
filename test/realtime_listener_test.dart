import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/sync/realtime_listener.dart';

class _FakeConnection implements WsConnection {
  final _incoming = StreamController<String>();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  /// The server speaks.
  void say(String text) => _incoming.add(text);

  /// The wire breaks (what a proxy's silent drop looks like from here).
  void drop() => _incoming.close();
}

/// The doorbell: what makes the phone ask the server, and when it reconnects.
/// The connection itself is a fake; the real one is checked on a phone.
void main() {
  late List<Uri> attempts;
  late List<_FakeConnection> opened;
  late List<bool> forced;
  late int signals;

  /// Set to make the next connection attempts fail.
  late Object? refuseWith;
  late Object? tokenFails;

  late RealtimeListener listener;

  RealtimeListener make({String baseUrl = 'https://x.test'}) =>
      RealtimeListener(
        baseUrl: baseUrl,
        token: ({bool force = false}) async {
          forced.add(force);
          if (tokenFails != null) throw tokenFails!;
          return force ? 'fresh' : 'tok';
        },
        deviceId: () => 'phone-1',
        onSignal: () => signals++,
        connector: (url) async {
          attempts.add(url);
          if (refuseWith != null) throw refuseWith!;
          final connection = _FakeConnection();
          opened.add(connection);
          return connection;
        },
      );

  setUp(() {
    attempts = [];
    opened = [];
    forced = [];
    signals = 0;
    refuseWith = null;
    tokenFails = null;
    listener = make();
  });

  /// A test that also hangs up when it is done: the binding refuses to end a
  /// test with a timer still pending, and a live listener always has one.
  void listenerTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        await body(tester);
        listener.stop();
        await tester.pump();
      });

  Future<void> after(WidgetTester tester, Duration d) => tester.pump(d);

  listenerTest('connecting asks once, with the token and the phone\'s name', (
    tester,
  ) async {
    listener.start();
    await tester.pump();

    expect(
      attempts.single.toString(),
      'wss://x.test/ws?token=tok&device=phone-1',
    );
    expect(signals, 1);
    expect(listener.isConnected, isTrue);
  });

  listenerTest('a plain http server gets a plain ws address', (tester) async {
    listener = make(baseUrl: 'http://10.0.2.2:3000');
    listener.start();
    await tester.pump();

    expect(attempts.single.scheme, 'ws');
    expect(attempts.single.port, 3000);
  });

  listenerTest('five rings in a row make one signal, after the quiet', (
    tester,
  ) async {
    listener.start();
    await tester.pump();
    signals = 0;

    for (var i = 0; i < 5; i++) {
      opened.single.say('{"t":"changed"}');
      await after(tester, const Duration(milliseconds: 200));
    }
    expect(signals, 0, reason: 'still within a second of the last ring');

    await after(tester, const Duration(seconds: 1));
    expect(signals, 1);
  });

  listenerTest('two separate rings make two signals', (tester) async {
    listener.start();
    await tester.pump();
    signals = 0;

    opened.single.say('{"t":"changed"}');
    await after(tester, const Duration(seconds: 2));
    opened.single.say('{"t":"changed"}');
    await after(tester, const Duration(seconds: 2));

    expect(signals, 2);
  });

  listenerTest('what is not a ring is ignored', (tester) async {
    listener.start();
    await tester.pump();
    signals = 0;

    for (final noise in ['{"t":"pong"}', 'not json', '[1]', '{"x":1}']) {
      opened.single.say(noise);
    }
    await after(tester, const Duration(seconds: 3));

    expect(signals, 0);
    expect(listener.isConnected, isTrue);
  });

  listenerTest('it pings every four minutes, so the server keeps it', (
    tester,
  ) async {
    listener.start();
    await tester.pump();

    await after(tester, const Duration(minutes: 3, seconds: 59));
    expect(opened.single.sent, isEmpty);
    await after(tester, const Duration(seconds: 2));
    expect(opened.single.sent, ['{"t":"ping"}']);
    await after(tester, const Duration(minutes: 4));
    expect(opened.single.sent, hasLength(2));
  });

  group('when the connection drops', () {
    listenerTest('it comes back after 1 s, and asks once more', (tester) async {
      listener.start();
      await tester.pump();
      signals = 0;

      opened.single.drop();
      await after(tester, const Duration(milliseconds: 900));
      expect(opened, hasLength(1));
      await after(tester, const Duration(milliseconds: 200));

      expect(opened, hasLength(2));
      expect(signals, 1);
    });

    listenerTest('the pause doubles up to a minute while it keeps failing', (
      tester,
    ) async {
      listener.start();
      await tester.pump();
      refuseWith = StateError('down');
      opened.single.drop();

      // Waits: 1, 2, 4, 8, 16, 32, then 60 s each.
      var tries = attempts.length;
      for (final wait in [1, 2, 4, 8, 16, 32, 60, 60]) {
        await after(tester, Duration(seconds: wait - 1));
        expect(
          attempts,
          hasLength(tries),
          reason: 'not yet after ${wait - 1} s',
        );
        await after(tester, const Duration(seconds: 1, milliseconds: 100));
        expect(attempts, hasLength(++tries), reason: 'tried after $wait s');
      }
    });

    listenerTest('a connection that held for a while starts the pauses over', (
      tester,
    ) async {
      listener.start();
      await tester.pump();
      refuseWith = StateError('down');
      opened.single.drop();
      await after(tester, const Duration(seconds: 4)); // 1 s, 2 s tried
      refuseWith = null;
      await after(tester, const Duration(seconds: 4)); // 4 s: back
      final live = opened.last;

      await after(tester, const Duration(seconds: 31)); // held past 30 s
      live.drop();
      final before = attempts.length;
      await after(tester, const Duration(milliseconds: 1100));

      expect(attempts, hasLength(before + 1), reason: 'back to a 1 s pause');
    });

    listenerTest(
      'one that opens and drops at once is not retried at a gallop',
      (tester) async {
        listener.start();
        await tester.pump();

        opened.last.drop();
        await after(tester, const Duration(milliseconds: 1100));
        expect(attempts, hasLength(2), reason: 'the first pause is 1 s');

        opened.last.drop();
        await after(tester, const Duration(milliseconds: 1100));
        expect(attempts, hasLength(2), reason: 'the next one is already 2 s');
        await after(tester, const Duration(seconds: 1));
        expect(attempts, hasLength(3));
      },
    );
  });

  group('the token', () {
    listenerTest('"unauthorized" hangs up and comes back with a new one', (
      tester,
    ) async {
      listener.start();
      await tester.pump();
      signals = 0;

      opened.single.say('{"t":"unauthorized"}');
      await after(tester, const Duration(milliseconds: 1100));

      expect(opened.first.closed, isTrue);
      expect(forced, [false, true]);
      expect(attempts.last.queryParameters['token'], 'fresh');
      expect(signals, 1, reason: 'one sync after the new connection');
    });

    listenerTest(
      'a refused handshake (429) waits and does not touch the token',
      (tester) async {
        refuseWith = const ApiException(ApiFailure.server, status: 429);
        listener.start();
        await tester.pump();
        await after(tester, const Duration(seconds: 1, milliseconds: 100));

        expect(attempts, hasLength(2));
        expect(forced, [false, false]);
        expect(signals, 0);
      },
    );

    listenerTest('no network for the token: tried again, later', (
      tester,
    ) async {
      tokenFails = const ApiException.offline();
      listener.start();
      await tester.pump();
      expect(attempts, isEmpty);

      tokenFails = null;
      await after(tester, const Duration(seconds: 1, milliseconds: 100));

      expect(attempts, hasLength(1));
      expect(signals, 1);
    });
  });

  group('stopping', () {
    listenerTest('closes the connection and nothing comes back', (
      tester,
    ) async {
      listener.start();
      await tester.pump();
      signals = 0;

      listener.stop();
      await after(tester, const Duration(minutes: 10));

      expect(opened.single.closed, isTrue);
      expect(listener.isConnected, isFalse);
      expect(opened, hasLength(1));
      expect(signals, 0);
    });

    listenerTest('a ring that was on its way is forgotten', (tester) async {
      listener.start();
      await tester.pump();
      signals = 0;
      opened.single.say('{"t":"changed"}');
      await tester.pump(const Duration(milliseconds: 300));

      listener.stop();
      await after(tester, const Duration(seconds: 2));

      expect(signals, 0);
    });

    listenerTest('stopping while a retry is waiting cancels it', (
      tester,
    ) async {
      listener.start();
      await tester.pump();
      opened.single.drop();
      await tester.pump(const Duration(milliseconds: 100));

      listener.stop();
      await after(tester, const Duration(minutes: 2));

      expect(opened, hasLength(1));
    });

    listenerTest('starting again connects afresh', (tester) async {
      listener.start();
      await tester.pump();
      listener.stop();
      listener.start();
      await tester.pump();

      expect(opened, hasLength(2));
      expect(opened.first.closed, isTrue);
      expect(listener.isConnected, isTrue);
    });

    listenerTest('a connection that opens after stop is closed at once', (
      tester,
    ) async {
      final slow = Completer<WsConnection>();
      listener = RealtimeListener(
        baseUrl: 'https://x.test',
        token: ({bool force = false}) async => 'tok',
        deviceId: () => null,
        onSignal: () => signals++,
        connector: (_) => slow.future,
      );
      listener.start();
      await tester.pump();
      listener.stop();

      final late = _FakeConnection();
      slow.complete(late);
      await tester.pump();

      expect(late.closed, isTrue);
      expect(listener.isConnected, isFalse);
      expect(signals, 0);
    });
  });
}
