import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/sync/realtime_listener.dart';

/// The doorbell: a burst of server events becomes one sync. The connection
/// itself needs a live server and is checked by hand, not here.
void main() {
  // Builds a client without touching the network: nothing connects until a
  // channel is subscribed, and these tests never subscribe.
  final client = SupabaseClient('https://example.supabase.co', 'test-key');

  testWidgets('five events in a row make one signal, after the quiet', (
    tester,
  ) async {
    var signals = 0;
    final listener = RealtimeListener(client, onSignal: () => signals++);

    for (var i = 0; i < 5; i++) {
      listener.ring();
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(signals, 0, reason: 'still within a second of the last event');

    await tester.pump(const Duration(seconds: 1));
    expect(signals, 1);
  });

  testWidgets('two separate events make two signals', (tester) async {
    var signals = 0;
    final listener = RealtimeListener(client, onSignal: () => signals++);

    listener.ring();
    await tester.pump(const Duration(seconds: 2));
    listener.ring();
    await tester.pump(const Duration(seconds: 2));

    expect(signals, 2);
  });

  testWidgets('stopping drops an event that has not rung yet', (tester) async {
    var signals = 0;
    final listener = RealtimeListener(client, onSignal: () => signals++);

    listener.ring();
    listener.stop();
    await tester.pump(const Duration(seconds: 2));

    expect(signals, 0);
  });

  test('it watches exactly the tables the realtime migrations switch on', () {
    expect(RealtimeListener.tables, [
      'tasks',
      'task_logs',
      'group_members',
      'profiles',
    ]);
  });
}
