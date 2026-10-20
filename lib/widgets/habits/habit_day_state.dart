import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';

/// How a single day reads inside a habit's two-week strip. Both the small habit
/// card and the actions sheet derive their squares from this, so the two views
/// can never disagree about what a day means.
enum HabitDayState {
  /// The rule covers this day, but the habit had not started yet. Drawn exactly
  /// like [missed] so history can be filled in, yet kept as its own case: it is
  /// not a failure, so streaks and statistics must not count it as one.
  beforeStart,

  /// The habit does not repeat on this day — there is nothing to mark, and
  /// leaving it unmarked is not a miss.
  off,

  /// Marked as done.
  done,

  /// Marked as done, but later than the habit's time plus the grace set in the
  /// settings. Still a done day: it counts everywhere [done] does.
  late,

  /// Scheduled, already in the past, never marked — a genuine miss.
  missed,

  /// Scheduled for today and still open.
  today,

  /// Scheduled further ahead in the window.
  upcoming,
}

/// Classifies [day] for [task]. [completedDays] holds the dates this habit was
/// marked done on, [lateDays] the subset of them marked late, and [today] is the
/// current date with its time stripped. With [todayStaysOpen] false an unmarked
/// habit due today is [HabitDayState.missed] at once instead of [today].
HabitDayState habitDayState(
  Task task,
  DateTime day, {
  required DateTime today,
  required Set<DateTime> completedDays,
  Set<DateTime> lateDays = const {},
  bool todayStaysOpen = true,
}) {
  // A marked day always reads as done, even if the schedule changed afterwards
  // and no longer covers it — the history actually happened.
  if (completedDays.contains(day)) {
    return lateDays.contains(day) ? HabitDayState.late : HabitDayState.done;
  }

  // The rule is checked before the start date, so a day that the rule would not
  // cover anyway stays "off" rather than being lumped in with pre-history.
  if (!matchesRepeatRule(task, day)) return HabitDayState.off;
  if (day.isAfter(today)) return HabitDayState.upcoming;
  if (day.isBefore(taskAnchorDate(task))) return HabitDayState.beforeStart;
  if (day == today && todayStaysOpen) return HabitDayState.today;
  return HabitDayState.missed;
}

/// Whether tapping [day] may toggle completion. Every day that has already
/// arrived can be toggled, including days outside the schedule: the habit may
/// have been done anyway, and — more importantly — a mark has to be removable
/// and re-addable symmetrically. Days still ahead are inert.
///
/// The schedule shows through the *look* of a day ([habitDayState]), not by
/// making it untouchable.
bool isHabitDayMarkable(DateTime day, {required DateTime today}) =>
    !day.isAfter(today);
