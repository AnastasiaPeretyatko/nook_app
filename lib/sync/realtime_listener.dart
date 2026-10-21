import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hears from the server that something changed, and says so — nothing more.
///
/// Supabase Realtime sends an event whenever a row of a watched table changes.
/// The event is deliberately treated as a **doorbell, not data**: its row is
/// ignored and [onSignal] runs the ordinary sync, so the merge rules live in one
/// place and a missed or duplicated event can do no harm.
///
/// The server side is `supabase/009_realtime.sql`; without it the channel opens
/// and stays silent. Events arrive only for rows this account may read.
///
/// The package reconnects by itself after a dropped connection and joins the
/// channel again, which reports `subscribed` once more — that is what makes the
/// catch-up below run for anything missed meanwhile.
class RealtimeListener {
  RealtimeListener(
    this._client, {
    required this.onSignal,
    this.quietFor = const Duration(seconds: 1),
  });

  final SupabaseClient _client;

  /// Called once per burst of events, and on every (re)subscription.
  final VoidCallback onSignal;

  /// A tick fires several events at once (a task and its logs) and our own
  /// pushes echo back; waiting for quiet turns a burst into one sync.
  final Duration quietFor;

  /// The tables whose changes matter — the ones `009_realtime.sql` and
  /// `010_realtime_profiles.sql` switch on.
  static const tables = ['tasks', 'task_logs', 'group_members', 'profiles'];

  RealtimeChannel? _channel;
  Timer? _quiet;

  void start() {
    stop();
    var channel = _client.channel('nook-sync');
    for (final table in tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => ring(),
      );
    }
    _channel = channel.subscribe((status, _) {
      // Events missed while the connection was down are not replayed, so every
      // (re)join asks once.
      if (status == RealtimeSubscribeStatus.subscribed) onSignal();
    });
  }

  void stop() {
    _quiet?.cancel();
    _quiet = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_client.removeChannel(channel));
  }

  /// One event arrived. Public so a test can ring it without a server.
  @visibleForTesting
  void ring() {
    _quiet?.cancel();
    _quiet = Timer(quietFor, onSignal);
  }
}
