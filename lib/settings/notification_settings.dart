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

/// How far ahead of a task's own time a reminder may be asked for, in minutes.
///
/// A closed list rather than a free number: it is what the notifications screen
/// offers, and it is also what [reminderLeadLabel] is allowed to be asked
/// about — every entry reads as "минут", so the label needs no plural rules.
const reminderLeadOptions = [0, 5, 10, 15, 30];

/// How long before a task's time its reminder fires, in minutes.
///
/// Zero is "on time" and the default, which is what the app did before this
/// setting existed. Stored like the theme and the diary's view — one int key in
/// the same [sharedPreferencesProvider].
final reminderLeadMinutesProvider =
    NotifierProvider<ReminderLeadMinutesNotifier, int>(
      ReminderLeadMinutesNotifier.new,
    );

class ReminderLeadMinutesNotifier extends Notifier<int> {
  static const _prefsKey = 'reminder_lead_minutes';

  @override
  int build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getInt(_prefsKey);
    // A value that is no longer offered reads as "on time" rather than being
    // kept: the list may shrink, and a lead nothing can select is a lead the
    // user cannot get rid of.
    return reminderLeadOptions.contains(stored) ? stored! : 0;
  }

  Future<void> setMinutes(int minutes) async {
    if (minutes == state) return;
    state = minutes;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(_prefsKey, minutes);
  }
}

/// What a lead time is called on screen.
///
/// Bare interval and no preposition: the row it names is "Напоминать за", and
/// the sheet it fills is a list of intervals — either would read as a stutter
/// with "за" repeated inside every line.
String reminderLeadLabel(int minutes) =>
    minutes <= 0 ? 'Вовремя' : '$minutes минут';
