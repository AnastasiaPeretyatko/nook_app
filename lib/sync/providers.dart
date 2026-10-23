import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/sync_service.dart';
import 'package:todo_app/sync/sync_status.dart';

/// The engine itself.
///
/// Rebuilt when the client appears or goes away, which is also what resets the
/// watermark's owner — see [syncControllerProvider], which puts the stored one
/// back on it.
final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    dao: ref.watch(diaryDaoProvider),
    tasksDao: ref.watch(tasksDaoProvider),
    cycleDao: ref.watch(cycleDaoProvider),
    client: ref.watch(supabaseClientProvider),
    // Read when a run starts, not here: the switch can move without the engine
    // being rebuilt.
    syncDiary: () => ref.read(syncDiaryProvider),
    syncCycle: () => ref.read(syncCycleProvider),
  );
});

/// Whether the phone is on Wi-Fi (or a cable) right now.
///
/// A function in a provider so a test can say what the network is. When the
/// platform cannot answer — no plugin, which is every widget test — it says yes:
/// a setting about saving mobile data must never be the reason nothing syncs on
/// a phone it cannot see.
final onWifiProvider = Provider<Future<bool> Function()>((ref) {
  return () async {
    try {
      final kinds = await Connectivity().checkConnectivity();
      return kinds.contains(ConnectivityResult.wifi) ||
          kinds.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return true;
    }
  };
});

/// Fires when the phone's connection changes; true = some network is there.
///
/// A provider so a test can swap it: listening to the real stream without the
/// platform plugin reports an error and fails the test.
final networkAvailableChangesProvider = Provider<Stream<bool>>((ref) {
  return Connectivity().onConnectivityChanged.map(
    (kinds) => kinds.any((k) => k != ConnectivityResult.none),
  );
});

/// Switches the diary's part of syncing, and makes sure nothing is lost on the
/// way back on.
///
/// The server clock's watermark is one position for every table. While the
/// diary is off, tasks keep moving it forward, so notes changed on another
/// device in the meantime would sit behind it and never be asked for. Putting it
/// back to the start costs one full re-read once, and every row that comes back
/// is merged by its own timestamp, so nothing already here is overwritten.
final syncDiarySetterProvider = Provider<Future<void> Function(bool)>((ref) {
  return (enabled) async {
    await ref.read(syncDiaryProvider.notifier).setValue(enabled);
    if (enabled) await ref.read(syncWatermarkProvider.notifier).set(null);
  };
});

/// Switches the cycle's part of syncing — the twin of [syncDiarySetterProvider],
/// and for the same reason: the watermark is one position for every table, so
/// days changed on another device while this was off sit behind it. Switched
/// on, it goes back to the start once.
final syncCycleSetterProvider = Provider<Future<void> Function(bool)>((ref) {
  return (enabled) async {
    await ref.read(syncCycleProvider.notifier).setValue(enabled);
    if (enabled) await ref.read(syncWatermarkProvider.notifier).set(null);
  };
});

/// Whether syncing should actually be happening right now.
///
/// Four things have to be true at once, and they are kept apart on purpose:
/// the user asked for it, an account exists, Supabase came up, and the notes
/// already on this device have been settled with **this** account. Only the
/// first is a setting — the rest are facts about the world, and folding them
/// into the stored value would rewrite the user's choice behind their back
/// every time they signed out.
final syncActiveProvider = Provider<bool>((ref) {
  return ref.watch(syncEnabledProvider) &&
      ref.watch(supabaseReadyProvider) &&
      ref.watch(currentUserProvider) != null &&
      !ref.watch(syncNeedsDecisionProvider);
});

/// Whether the user still has to say what happens to the notes already here.
///
/// True when sync is wanted, somebody is signed in, and the stored answer was
/// given for a **different** account — or for none at all. Until it is false
/// nothing is sent and nothing is fetched, which is the point: the dangerous
/// moment is not the first sign-in but the second, when a phone that already
/// holds one person's diary is handed to another account.
final syncNeedsDecisionProvider = Provider<bool>((ref) {
  if (!ref.watch(syncEnabledProvider)) return false;
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  return ref.watch(syncClaimProvider) != user.id;
});

/// What to tell the user about syncing.
///
/// The phase is in memory — it describes right now — but `lastSuccessAt` is
/// stored, because "when did you last manage" is the question people actually
/// ask of a sync, and an app that forgets the answer every launch cannot be
/// trusted to be doing anything at all.
final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);

class SyncStatusNotifier extends Notifier<SyncStatus> {
  static const _prefsKey = 'sync_last_success';

  @override
  SyncStatus build() {
    final stored = ref.watch(sharedPreferencesProvider).getString(_prefsKey);
    return SyncStatus(
      lastSuccessAt: stored == null ? null : DateTime.tryParse(stored),
    );
  }

  void reportRunning() => state = state.copyWith(phase: SyncPhase.running);

  Future<void> reportSuccess(DateTime at) async {
    state = SyncStatus(phase: SyncPhase.idle, lastSuccessAt: at);
    await ref
        .read(sharedPreferencesProvider)
        .setString(_prefsKey, at.toUtc().toIso8601String());
  }

  /// A failed run leaves `lastSuccessAt` alone: it is still true, and replacing
  /// it with nothing would say the sync has never worked.
  void reportFailure({required bool offline, String? detail}) =>
      state = SyncStatus(
        phase: offline ? SyncPhase.offline : SyncPhase.failed,
        lastSuccessAt: state.lastSuccessAt,
        // Rebuilt rather than `copyWith`, which cannot put a null back: a run
        // that failed without a message must not inherit the last one's.
        lastError: detail,
      );

  /// Back to resting without claiming anything happened — what a run that was
  /// never attempted leaves behind.
  void reportIdle() => state = state.copyWith(phase: SyncPhase.idle);

  /// Forgets that a sync ever worked here.
  ///
  /// For the device being cleared of an account. "Синхронизировано 5 минут
  /// назад" is true of data that is no longer on the phone, which makes it a
  /// sentence about nothing — and the next person to sign in would read it as
  /// being about theirs.
  Future<void> forget() async {
    state = const SyncStatus();
    await ref.read(sharedPreferencesProvider).remove(_prefsKey);
  }
}

/// How far through the server's clock this device has read.
///
/// Kept in `SharedPreferences` beside the other settings rather than in the
/// database: it describes this installation's progress, not the diary, and a
/// user who clears the app's data should start a fresh sync rather than
/// silently skip everything written before.
///
/// Stored as an ISO-8601 string — a `DateTime` in prefs would have to be an
/// int, and an int of unknown scale is exactly the kind of thing that reads
/// back as 1970 after a refactor.
final syncWatermarkProvider =
    NotifierProvider<SyncWatermarkNotifier, DateTime?>(
      SyncWatermarkNotifier.new,
    );

class SyncWatermarkNotifier extends Notifier<DateTime?> {
  /// Retired once, at v14, and the rename **is** the reset.
  ///
  /// The watermark is one position for every table, so a device carrying one
  /// from before tasks were synced would ask for "tasks changed since X" and be
  /// told about none of the ones written before X. Today that is harmless —
  /// there are no tasks on the server yet — but it is the class of bug where
  /// something is silently skipped and nothing ever goes back for it.
  ///
  /// A rename rather than a migration because the value lives in
  /// `SharedPreferences`, which a drift migration has no business reaching, and
  /// rather than a one-shot flag because a flag is a second thing to keep right.
  /// Every device that opens this version starts its pull from the beginning
  /// once. The cost is one full re-read of the diary, which changes nothing on
  /// screen: every row that comes back is a row already here.
  static const _prefsKey = 'sync_pulled_through_v2';

  @override
  DateTime? build() {
    final stored = ref.watch(sharedPreferencesProvider).getString(_prefsKey);
    return stored == null ? null : DateTime.tryParse(stored);
  }

  Future<void> set(DateTime? moment) async {
    state = moment;
    final prefs = ref.read(sharedPreferencesProvider);
    if (moment == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, moment.toUtc().toIso8601String());
    }
  }
}
