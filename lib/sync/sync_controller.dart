import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/realtime_listener.dart';
import 'package:todo_app/sync/sync_service.dart';

/// Decides *when* the diary is synced. [SyncService] decides how.
///
/// Split that way because the two fail differently: the engine's job is a
/// network call that may be refused, and this one's is a clock that must not
/// be left running. Keeping the timer out of the engine also means the engine
/// can be driven straight from a test with no waiting at all.
///
/// ## What sets it off
///
/// * The diary changed here — debounced, so a note saved keystroke by
///   keystroke is one send rather than forty.
/// * The app came back to the foreground, which is the moment a phone that has
///   been in a pocket all morning is most likely to have missed something.
/// * The server saying a watched row changed ([RealtimeListener]) — how a tick
///   by another member of a group reaches this phone within a second or two.
///   Only while the app is in front: Android drops the connection in the
///   background, and coming back syncs anyway.
/// * A quiet timer, because not every change announces itself (no connection,
///   or the app was in the background). Deliberately slow: this is a diary, not
///   a chat.
/// * Sync being switched on, or an account appearing.
///
/// Over-calling is cheap by design — `SyncService.sync` returns immediately
/// when there is nothing marked, when a run is already going, or when the last
/// one failed recently. That is the same bargain `AppNotifications.sync`
/// strikes: rather than prevent redundant calls, make them free.
class SyncController {
  SyncController(this._ref);

  final Ref _ref;

  Timer? _debounce;
  Timer? _heartbeat;
  RealtimeListener? _realtime;

  /// Set by a failed run: no automatic run until the app is opened again, or the
  /// user asks ("Повторить", "Синхронизировать сейчас") and it works. Held in
  /// memory on purpose — a restart is the "next opening" — so a phone that is
  /// offline is told once, not at every timer tick.
  bool _pausedAfterError = false;

  /// Long enough that a note being written is not sent on every letter, short
  /// enough that closing the app straight after a save still catches it.
  static const _debounceDelay = Duration(seconds: 3);

  /// The other devices cannot tell this one they changed something, so it has
  /// to ask. Rarely: a diary is not read by the minute.
  static const _heartbeatPeriod = Duration(minutes: 15);

  void start() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatPeriod, (_) => _run(automatic: true));
    // Once immediately: the app has just been opened, or sync has just been
    // switched on, and both are moments where something is probably waiting.
    unawaited(_run(automatic: true));
    startRealtime();
  }

  void stop() {
    stopRealtime();
    _debounce?.cancel();
    _debounce = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// Opens the server's channel of changes. Does nothing when there is no
  /// Supabase client (offline start, tests) or syncing is not active.
  void startRealtime() {
    stopRealtime();
    final client = _ref.read(supabaseClientProvider);
    if (client == null || !_ref.read(syncActiveProvider)) return;
    _realtime = RealtimeListener(
      client,
      onSignal: () => unawaited(_run(automatic: true)),
    )..start();
  }

  void stopRealtime() {
    _realtime?.stop();
    _realtime = null;
  }

  /// Something changed locally. Sends it, once the changes stop coming.
  void nudge() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => _run(automatic: true));
  }

  /// Sends now, waiting for the result — what the account screen's button
  /// uses, and what a test drives directly with no clock involved. Asked for by
  /// the user, so it ignores "Автоматически" and "Только по Wi-Fi".
  Future<SyncOutcome> syncNow() => _run(automatic: false);

  /// The same, for the moments the app picks itself — coming back to the front.
  /// Does nothing when syncing is manual, or when it waits for Wi-Fi and there
  /// is none.
  Future<SyncOutcome> syncIfAuto() => _run(automatic: true);

  Future<SyncOutcome> _run({required bool automatic}) async {
    if (!_ref.read(syncActiveProvider)) return SyncOutcome.skipped;
    if (automatic) {
      // Before anything touches the status: a skipped run reports idle, which
      // would wipe the error the screens are showing.
      if (_pausedAfterError) return SyncOutcome.skipped;
      if (!_ref.read(syncAutoProvider)) return SyncOutcome.skipped;
      if (_ref.read(syncWifiOnlyProvider) &&
          !await _ref.read(onWifiProvider)()) {
        return SyncOutcome.skipped;
      }
    }

    final status = _ref.read(syncStatusProvider.notifier);
    final service = _ref.read(syncServiceProvider);
    // The engine holds no storage of its own, so its place in the server's
    // clock is handed to it and taken back.
    service.watermark = _ref.read(syncWatermarkProvider);

    status.reportRunning();
    final outcome = await service.sync();

    switch (outcome) {
      case SyncOutcome.done:
        if (service.watermark != _ref.read(syncWatermarkProvider)) {
          await _ref
              .read(syncWatermarkProvider.notifier)
              .set(service.watermark);
        }
        _pausedAfterError = false;
        await status.reportSuccess(DateTime.now());
      case SyncOutcome.offline:
        _pausedAfterError = true;
        status.reportFailure(offline: true, detail: service.lastError);
      case SyncOutcome.failed:
        _pausedAfterError = true;
        status.reportFailure(offline: false, detail: service.lastError);
      case SyncOutcome.skipped:
        // Never attempted — a run already going, or a recent failure still
        // being waited out. Saying "failed" would be a lie, and saying
        // "synced" a worse one.
        status.reportIdle();
    }
    return outcome;
  }
}

/// Owns the controller for the life of the app, and takes its timers down with
/// it — a `Timer` left running is what makes `testWidgets` report a pending
/// timer and fail, and there are already two cancel-on-dispose tickers in this
/// codebase for the same reason.
final syncControllerProvider = Provider<SyncController>((ref) {
  final controller = SyncController(ref);
  ref.onDispose(controller.stop);
  return controller;
});

/// Wires the controller to the app: watches whether syncing should be happening
/// at all, notices local writes, and catches the app coming back to the front.
///
/// A widget rather than a provider because two of those three are things only
/// the widget tree knows about — the lifecycle and the disposal. It draws
/// nothing.
class SyncScope extends ConsumerStatefulWidget {
  const SyncScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends ConsumerState<SyncScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // `listenManual`, not `ref.listen`: the latter cannot fire for the state
    // that is already there, and an app opening with sync already on has to
    // start it rather than wait for the setting to change. The same reasoning
    // the notification subscriptions in `main.dart` are built on.
    ref.listenManual<bool>(syncActiveProvider, (_, active) {
      final controller = ref.read(syncControllerProvider);
      active ? controller.start() : controller.stop();
    }, fireImmediately: true);

    // Any write to the diary or to the tasks — by the user or by a pull —
    // retriggers this. A pull's own writes cost one extra no-op run, which is
    // cheaper than teaching the stream who wrote.
    //
    // Three streams and not one, because they are three tables and a write to
    // any of them is something to send. The day marks need their own: ticking a
    // habit changes no task row, so without this a mark would wait for the
    // fifteen-minute heartbeat while the note the user wrote a second later went
    // straight up. All three are already watched by live screens, so none of
    // these opens a query that was not open anyway.
    void nudge(Object? _, Object? _) =>
        ref.read(syncControllerProvider).nudge();

    ref.listenManual<AsyncValue<List<DiaryEntry>>>(diaryEntriesProvider, nudge);
    ref.listenManual<AsyncValue<List<Task>>>(allTasksProvider, nudge);
    ref.listenManual<AsyncValue<List<TaskLog>>>(allLogsProvider, nudge);
    ref.listenManual<AsyncValue<List<CycleDay>>>(cycleDaysProvider, nudge);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back is the one moment worth asking unprompted: the phone may
    // have been away for hours, and nothing on the other device could have
    // told it so.
    final controller = ref.read(syncControllerProvider);
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.syncIfAuto());
      controller.startRealtime();
    } else if (state == AppLifecycleState.paused) {
      controller.stopRealtime();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
