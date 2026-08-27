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
  static const _prefsKey = 'sync_claimed_for';

  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(_prefsKey);

  Future<void> claimFor(String userId) async {
    state = userId;
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, userId);
  }
}
