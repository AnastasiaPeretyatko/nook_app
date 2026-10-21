import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// The day a week starts on, as [DateTime.weekday]: Monday or Sunday. It shapes
/// what is *drawn* — the habits strip, the calendars — and nothing about when a
/// task lands: `recurrence.dart` keeps counting weeks between Mondays, or a
/// "every 2 weeks" habit would change its days with a display setting.
final weekStartProvider = NotifierProvider<WeekStartNotifier, int>(
  WeekStartNotifier.new,
);

class WeekStartNotifier extends Notifier<int> {
  static const _prefsKey = 'week_start_day';

  @override
  int build() =>
      analyticsFromPrefs(ref.watch(sharedPreferencesProvider)).weekStart;

  Future<void> setDay(int weekday) async {
    if (weekday == state) return;
    state = weekday;
    await ref.read(sharedPreferencesProvider).setInt(_prefsKey, weekday);
  }
}

/// The three settings above, read straight from the store — for the widget's
/// background isolate, which has no providers. The notifiers decode through this
/// too, so the two cannot disagree about a stored value.
({int weekStart, int graceMinutes, bool todayStaysOpen}) analyticsFromPrefs(
  SharedPreferences prefs,
) {
  final grace = prefs.getInt(LateGraceMinutesNotifier._prefsKey);
  return (
    weekStart: prefs.getInt(WeekStartNotifier._prefsKey) == DateTime.sunday
        ? DateTime.sunday
        : DateTime.monday,
    graceMinutes: lateGraceOptions.contains(grace) ? grace! : 15,
    todayStaysOpen: prefs.getBool(TodayStaysOpenNotifier._prefsKey) ?? true,
  );
}

String weekStartLabel(int weekday) =>
    weekday == DateTime.sunday ? 'Воскресенье' : 'Понедельник';

/// How many minutes after a task's own time a tick still counts as on time.
/// A closed list, like [reminderLeadOptions]: it is what the settings offer.
const lateGraceOptions = [0, 15, 30, 60];

String lateGraceLabel(int minutes) => switch (minutes) {
  0 => 'Сразу',
  60 => '1 ч',
  _ => '$minutes мин',
};

/// The grace before a tick counts as late. 15 minutes until the user says
/// otherwise (`Settings.dc.html`). A stored value no longer offered reads as the
/// default, so there is never a setting the user cannot see.
final lateGraceMinutesProvider =
    NotifierProvider<LateGraceMinutesNotifier, int>(
      LateGraceMinutesNotifier.new,
    );

class LateGraceMinutesNotifier extends Notifier<int> {
  static const _prefsKey = 'late_grace_minutes';

  @override
  int build() =>
      analyticsFromPrefs(ref.watch(sharedPreferencesProvider)).graceMinutes;

  Future<void> setMinutes(int minutes) async {
    if (minutes == state) return;
    state = minutes;
    await ref.read(sharedPreferencesProvider).setInt(_prefsKey, minutes);
  }
}

/// Whether a habit still open today is spared the word "missed" until the day
/// is over. On by default — that is how the app has always drawn today. Off,
/// an unmarked habit due today reads as missed at once.
final todayStaysOpenProvider = NotifierProvider<TodayStaysOpenNotifier, bool>(
  TodayStaysOpenNotifier.new,
);

class TodayStaysOpenNotifier extends Notifier<bool> {
  static const _prefsKey = 'today_stays_open';

  @override
  bool build() =>
      analyticsFromPrefs(ref.watch(sharedPreferencesProvider)).todayStaysOpen;

  Future<void> setEnabled(bool enabled) async {
    if (enabled == state) return;
    state = enabled;
    await ref.read(sharedPreferencesProvider).setBool(_prefsKey, enabled);
  }
}

/// What the switch does, for the line under it.
String todayStaysOpenLabel(bool on) => on
    ? 'До конца дня невыполненное не считается пропуском'
    : 'Невыполненное сегодня сразу считается пропуском';
