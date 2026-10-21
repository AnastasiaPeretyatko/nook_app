import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// Whether the diary should be kept on the server as well as on this device.
///
/// **Off until asked for.** Every other setting in this app opts the user *in*
/// to a convenience; this one sends what they have written to a machine
/// somewhere else, and that is not a decision to make on their behalf.
///
/// This is the user's *wish*, and only that — the same split as
/// `taskRemindersEnabledProvider` (what the user wants) against
/// `notificationPermissionProvider` (what the system allows). Syncing also
/// needs an account and a working connection, and neither of those belongs
/// here: signing out must not silently rewrite the switch, so that the setting
/// is still on when they sign back in.
final syncEnabledProvider = NotifierProvider<SyncEnabledNotifier, bool>(
  SyncEnabledNotifier.new,
);

class SyncEnabledNotifier extends Notifier<bool> {
  static const _prefsKey = 'sync_enabled';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled == state) return;
    state = enabled;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_prefsKey, enabled);
  }
}

/// Whose account the notes already on this device were settled with.
///
/// A user id, or null when nobody has been asked yet. It exists because
/// "should what is already here go up?" is a question about **an account**, not
/// about the phone: answering it once and never again would mean that signing
/// into a second account on the same device silently hands it the first
/// account's diary.
///
/// So the value is compared against whoever is signed in now, and a mismatch
/// puts the question back — see `syncNeedsDecisionProvider`.
final syncClaimProvider = NotifierProvider<SyncClaimNotifier, String?>(
  SyncClaimNotifier.new,
);

class SyncClaimNotifier extends Notifier<String?> {
  static const prefsKey = 'sync_claimed_for';

  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(prefsKey);

  Future<void> claimFor(String userId) async {
    state = userId;
    await ref.read(sharedPreferencesProvider).setString(prefsKey, userId);
  }

  /// Nobody has answered for this device.
  ///
  /// What signing out and clearing the device leaves behind. Not the same as
  /// leaving the old claim in place: the next account to sign in has to be
  /// asked, and a stale claim naming somebody who is no longer here would
  /// either match nobody — harmless but a lie — or, worse, match that same
  /// person signing back in to a device whose data has been deleted, and let
  /// the sync start from a watermark that no longer describes anything.
  Future<void> clear() async {
    state = null;
    await ref.read(sharedPreferencesProvider).remove(prefsKey);
  }
}

/// One yes/no setting of how syncing behaves, kept in the same prefs as the rest.
///
/// The three on the account screen are all this shape, and all of them are the
/// user's wish about *when* and *what* — whether syncing is on at all is
/// [syncEnabledProvider], which also carries the question about the data
/// already on the phone.
class SyncFlagNotifier extends Notifier<bool> {
  SyncFlagNotifier(this._prefsKey, this._fallback);

  final String _prefsKey;
  final bool _fallback;

  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsKey) ?? _fallback;

  Future<void> setValue(bool value) async {
    if (value == state) return;
    state = value;
    await ref.read(sharedPreferencesProvider).setBool(_prefsKey, value);
  }
}

/// "Автоматически": whether changes go up by themselves — after an edit, when
/// the app comes back, on the quiet timer. Off is manual syncing: nothing
/// leaves the phone until the button is pressed. On by default, because once
/// syncing is on at all, that is what people expect of it.
final syncAutoProvider = NotifierProvider<SyncFlagNotifier, bool>(
  () => SyncFlagNotifier('sync_auto', true),
);

/// "Только по Wi-Fi": automatic runs wait for Wi-Fi instead of using mobile
/// data. A run the user asks for with the button is not held back — pressing it
/// is the answer to the question this setting asks.
final syncWifiOnlyProvider = NotifierProvider<SyncFlagNotifier, bool>(
  () => SyncFlagNotifier('sync_wifi_only', false),
);

/// "Синхронизировать Дневник": whether notes travel with the tasks. Off keeps
/// them on this phone only; they are left marked as unsent and go up if it is
/// switched back on. See `setSyncDiary` for the part that is not just a flag.
final syncDiaryProvider = NotifierProvider<SyncFlagNotifier, bool>(
  () => SyncFlagNotifier('sync_diary', true),
);

/// "Синхронизировать цикл": whether the days marked in the Cycle tab go up with
/// the rest.
///
/// **Off until asked for**, unlike the diary's switch: this is health data, and
/// the user decides when it leaves the phone. While it is off nothing is sent or
/// read, and what is marked meanwhile stays marked as unsent. The cycle's
/// *settings* (gender, the dates and lengths) are not part of it — they live on
/// the phone only.
final syncCycleProvider = NotifierProvider<SyncFlagNotifier, bool>(
  () => SyncFlagNotifier('sync_cycle', false),
);
