import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// Whether habits get a marker dot in the month calendar.
///
/// On by default: the dots have always counted everything the day screen shows,
/// and that is still the honest default. Turning it off is for the calendar
/// where habits drown the rest — a daily one puts a dot on every single cell,
/// after which no day looks any busier than another and the one-off task with a
/// real date does not stand out any more.
///
/// It changes **only the dots**. The day screen underneath still shows habits:
/// the setting is about what the month view can be read for, not about hiding a
/// habit from the day it is due on.
///
/// Stored like the theme and the reminder switch — one bool key in the same
/// [sharedPreferencesProvider].
final showHabitsInCalendarProvider =
    NotifierProvider<ShowHabitsInCalendarNotifier, bool>(
      ShowHabitsInCalendarNotifier.new,
    );

class ShowHabitsInCalendarNotifier extends Notifier<bool> {
  static const _prefsKey = 'calendar_show_habits';

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

/// What the calendar's dots cover, for the row that holds the switch.
String calendarMarkersLabel({required bool showHabits}) => showHabits
    ? 'Точками отмечены задачи и привычки'
    : 'Точками отмечены только задачи';
