import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// Whether tasks and habits that carry a time should remind the user.
///
/// On by default: a task given a time is asking to be reminded of, and the
/// permission is still only requested when the first reminder is actually
/// scheduled. Turning it off takes down everything already scheduled.
final taskRemindersEnabledProvider =
    NotifierProvider<TaskRemindersEnabledNotifier, bool>(
      TaskRemindersEnabledNotifier.new,
    );

class TaskRemindersEnabledNotifier extends Notifier<bool> {
  static const _prefsKey = 'task_reminders_enabled';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(_prefsKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled == state) return;
    state = enabled;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_prefsKey, enabled);
  }
}
