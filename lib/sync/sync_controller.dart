import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/api_config.dart';
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
/// * The connection to the server's doorbell opens — when the app starts or
///   comes back to the front. A new connection hears nothing, so it is followed
///   by one sync: that is how a phone that has been in a pocket all morning
///   catches up.
/// * The doorbell rings: another device changed something.
/// * Something changed here — debounced, so a note saved keystroke by keystroke
///   is one send rather than forty.
/// * The app goes to the background: whatever is unsent goes now, without the
///   debounce, and the connection is closed. Android may freeze the process
///   straight after, so this is best effort; what does not make it stays marked
///   and goes at the next start.
///
/// There is no timer. It used to ask every fifteen minutes and wake the
/// database for nothing; the doorbell and the reconnection sync replace it.
///
/// Over-calling is cheap by design — `SyncService.sync` returns immediately
/// when there is nothing marked, when a run is already going, or when the last
/// one failed recently. That is the same bargain `AppNotifications.sync`
/// strikes: rather than prevent redundant calls, make them free.
class SyncController {
  SyncController(this._ref);

  final Ref _ref;

  Timer? _debounce;
  RealtimeListener? _realtime;

  /// Set by a failed run: no automatic run until the app is opened again, or the
  /// user asks ("Повторить", "Синхронизировать сейчас") and it works. Held in
  /// memory on purpose — a restart is the "next opening" — so a phone that is
  /// offline is told once, not at every timer tick.
  bool _pausedAfterError = false;

  /// Set while the last run found no network: the first sign of a connection
  /// lifts the pause and runs. Only listening in that state, so a phone that
  /// syncs fine keeps no subscription open.
  StreamSubscription<bool>? _waitingForNetwork;

  /// Long enough that a note being written is not sent on every letter, short
  /// enough that closing the app straight after a save still catches it.
  static const _debounceDelay = Duration(seconds: 3);

  RealtimeListener _doorbell() => _realtime ??= RealtimeListener(
    baseUrl: apiBaseUrl,
    token: ({bool force = false}) =>
        _ref.read(apiClientProvider).freshAccessToken(force: force),
    deviceId: () => _ref.read(deviceIdProvider),
    // A connection and a ring ask the same thing: what is new on the server?
    onSignal: () => unawaited(_run(automatic: true)),
    connector: _ref.read(realtimeConnectorProvider),
  );

  /// Brings the connection in line with the settings: open while syncing is on
  /// and automatic, closed otherwise. Safe to call as often as like — an open
  /// connection is left alone, so coming back from a notification shade costs
  /// nothing.
  void start() {
    if (!_ref.read(syncActiveProvider) || !_ref.read(syncAutoProvider)) {
      stop();
      return;
    }
    final doorbell = _doorbell();
    if (!doorbell.isRunning) doorbell.start();
  }

  void stop() {
    _stopWaitingForNetwork();
    _debounce?.cancel();
    _debounce = null;
    _realtime?.stop();
  }

  /// The app is leaving the front: sends what is waiting at once and hangs up.
  Future<void> sendAndDisconnect() async {
    _realtime?.stop();
    _debounce?.cancel();
    _debounce = null;
    await _run(automatic: true, onlyIfPending: true);
  }

  /// Something changed locally. Sends it, once the changes stop coming.
  void nudge() {
    _debounce?.cancel();
    _debounce = Timer(
      _debounceDelay,
      () => _run(automatic: true, onlyIfPending: true),
    );
  }

  /// Sends now, waiting for the result — what the account screen's button
  /// uses, and what a test drives directly with no clock involved. Asked for by
  /// the user, so it ignores "Автоматически" and "Только по Wi-Fi".
  Future<SyncOutcome> syncNow() => _run(automatic: false);

  /// The same, for the moments the app picks itself — coming back to the front.
  /// Does nothing when syncing is manual, or when it waits for Wi-Fi and there
  /// is none.
  Future<SyncOutcome> syncIfAuto() => _run(automatic: true);

  /// Called after a run that found no network. The first "a connection
  /// appeared" lifts the pause and tries at once, still as an automatic run, so
  /// "Только по Wi-Fi" and "Автоматически" keep their say.
  void _waitForNetwork() {
    _waitingForNetwork?.cancel();
    _waitingForNetwork = _ref.read(networkAvailableChangesProvider).listen((
      available,
    ) {
      if (!available) return;
      _stopWaitingForNetwork();
      _pausedAfterError = false;
      unawaited(_run(automatic: true, force: true));
    });
  }

  void _stopWaitingForNetwork() {
    _waitingForNetwork?.cancel();
    _waitingForNetwork = null;
  }

  Future<SyncOutcome> _run({
    required bool automatic,
    bool force = false,
    bool onlyIfPending = false,
  }) async {
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
    // A local write sets this off, and so does the pull's own writing to the
    // database. Nothing marked as unsent means the write was not the user's, and
    // running again would only bring the same rows back — for ever.
    if (onlyIfPending && !await service.hasPending()) {
      return SyncOutcome.skipped;
    }
    // Another run is on its way. Turned away *before* touching the status: a
    // skipped run reports idle, which used to replace the first run's
    // "Синхронизация…" with "Ещё не синхронизировалось" while it was still going.
    if (service.isRunning) return SyncOutcome.skipped;
    // The engine holds no storage of its own, so its place in the server's
    // clock is handed to it and taken back.
    service.watermark = _ref.read(syncWatermarkProvider);

    status.reportRunning();
    // A run the user asked for, or one the returning network triggered, does
    // not wait out the engine's backoff.
    final outcome = await service.sync(force: !automatic || force);

    switch (outcome) {
      case SyncOutcome.done:
        if (service.watermark != _ref.read(syncWatermarkProvider)) {
          await _ref
              .read(syncWatermarkProvider.notifier)
              .set(service.watermark);
        }
        _pausedAfterError = false;
        _stopWaitingForNetwork();
        await status.reportSuccess(DateTime.now());
      case SyncOutcome.offline:
        _pausedAfterError = true;
        _waitForNetwork();
        status.reportFailure(offline: true, detail: service.lastError);
      case SyncOutcome.failed:
        _pausedAfterError = true;
        _stopWaitingForNetwork();
        status.reportFailure(offline: false, detail: service.lastError);
      case SyncOutcome.skipped:
        // Never attempted — a run already going, or a recent failure still
        // being waited out. Saying "failed" would be a lie, and saying
        // "synced" a worse one.
        if (automatic) {
          status.reportIdle();
        } else {
          // The user pressed the button and nothing could start: say why.
          status.reportFailure(offline: false, detail: service.lastError);
        }
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
    void connect(Object? _, Object? _) =>
        ref.read(syncControllerProvider).start();
    ref.listenManual<bool>(syncActiveProvider, connect, fireImmediately: true);
    ref.listenManual<bool>(syncAutoProvider, connect);

    // Any write to the diary or to the tasks — by the user or by a pull —
    // retriggers this. A pull's own writes come back as a nudge too, which is
    // cheaper than teaching the stream who wrote: the run it asks for returns
    // at once when nothing is marked unsent, and sends no request.
    //
    // Three streams and not one, because they are three tables and a write to
    // any of them is something to send. The day marks need their own: ticking a
    // habit changes no task row, so without this a mark would wait for the
    // next connection while the note the user wrote a second later went
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
    final controller = ref.read(syncControllerProvider);
    switch (state) {
      case AppLifecycleState.paused:
        unawaited(controller.sendAndDisconnect());
      case AppLifecycleState.resumed:
        // Connecting is also the sync: the phone may have been away for hours,
        // and nothing on the other device could have told it so.
        controller.start();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
