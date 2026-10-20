import 'package:todo_app/database/app_database.dart';

/// First day [task] can occur on: its start date, or its creation date when no
/// start date was given. Returned as a local date with the time stripped.
DateTime taskAnchorDate(Task task) {
  final anchor = task.startDate ?? task.createdAt;
  return DateTime(anchor.year, anchor.month, anchor.day);
}

/// Determines whether [task] is scheduled to appear on the given calendar [day].
///
/// [taskAnchorDate] is the first occurrence; a task never appears before it. When
/// [Task.repeatType] is null the task is a one-off and only shows on that day.
///
/// A [TrackingMode.value] task is on no day at all: its start date says when the
/// watching began, not when something is due, and it has no time to remind of.
/// Answering here keeps it off the timeline, the calendar dots, the reminders and
/// the home-screen widget in one stroke — they all ask this function.
bool isTaskScheduledOn(Task task, DateTime day) {
  if (task.trackingMode == TrackingMode.value) return false;
  // A task cannot occur before its start date.
  if (_dateOnly(day).isBefore(_dateOnly(taskAnchorDate(task)))) return false;
  return matchesRepeatRule(task, day);
}

/// Whether [task]'s repeat rule alone covers [day], ignoring the start date.
///
/// Useful for days before the habit began: the rule still tells us whether such a
/// day *would* have been one of its days, which is what distinguishes "the habit
/// did not exist yet" from "this weekday is not part of the rule". The anchor is
/// still the phase reference for intervals, so the pattern extends backwards
/// consistently.
bool matchesRepeatRule(Task task, DateTime day) {
  final created = _dateOnly(taskAnchorDate(task));
  final target = _dateOnly(day);

  final repeatType = task.repeatType;
  if (repeatType == null) {
    return target == created;
  }

  final interval = (task.repeatInterval == null || task.repeatInterval! < 1)
      ? 1
      : task.repeatInterval!;

  switch (repeatType) {
    case RepeatType.daily:
      // Daily means every single day. It carries no interval — an "every N days"
      // rule is [RepeatType.custom]. Rows saved before the two were split may
      // still hold a stale interval, which is deliberately ignored here so the
      // schedule matches what the form promises.
      return true;

    case RepeatType.custom:
      final diff = _daysBetween(created, target);
      return diff % interval == 0;

    case RepeatType.weekly:
      // Compare whole weeks between the Mondays of both weeks, so the interval
      // still works when the selected weekdays differ from the anchor's.
      final weeks = _daysBetween(_weekStart(created), _weekStart(target)) ~/ 7;
      if (weeks % interval != 0) return false;

      final selected = daysFromMask(task.repeatDaysMask, maxDay: 7);
      // No explicit selection: keep the original behaviour of repeating on the
      // same weekday as the anchor.
      if (selected.isEmpty) return created.weekday == target.weekday;
      return selected.contains(target.weekday);

    case RepeatType.monthly:
      final months =
          (target.year - created.year) * 12 + (target.month - created.month);
      if (months % interval != 0) return false;

      final selected = daysFromMask(task.repeatDaysMask, maxDay: 31);
      final length = _daysInMonth(target.year, target.month);
      if (selected.isEmpty) {
        return _clampToMonth(created.day, length) == target.day;
      }
      return selected.any((day) => _clampToMonth(day, length) == target.day);
  }
}

/// Largest day number a [Tasks.repeatDaysMask] can hold. Day 31 occupies bit 30,
/// so a full mask stays inside 32 bits and survives the JavaScript number
/// semantics of a web build.
const _maxMaskDay = 31;

/// Unpacks a [Tasks.repeatDaysMask] value into day numbers, ignoring anything
/// above [maxDay] — pass 7 for weekdays ([DateTime.weekday], Monday = 1) and 31
/// for days of the month. Returns an empty set for null or 0.
Set<int> daysFromMask(int? mask, {required int maxDay}) {
  if (mask == null || mask == 0) return const {};
  return {
    for (var day = 1; day <= maxDay; day++)
      if (mask & (1 << (day - 1)) != 0) day,
  };
}

/// Packs day numbers into a [Tasks.repeatDaysMask] value, where day `d` sets bit
/// `d - 1`. Returns null for an empty selection, so "nothing picked" stays null
/// in the database rather than becoming a 0 that means the same thing.
int? daysToMask(Set<int> days) {
  var mask = 0;
  for (final day in days) {
    if (day < 1 || day > _maxMaskDay) continue;
    mask |= 1 << (day - 1);
  }
  return mask == 0 ? null : mask;
}

/// Number of days in the given month. `day: 0` of the next month is the last day
/// of this one, and it wraps correctly from December into January.
int _daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

/// Pulls a day number back to the end of a short month, so that a task set to
/// the 31st lands on 28 February instead of vanishing from that month. As a
/// consequence "the 31st" reads as "the last day of the month" everywhere.
int _clampToMonth(int day, int monthLength) =>
    day > monthLength ? monthLength : day;

DateTime _dateOnly(DateTime dt) => DateTime.utc(dt.year, dt.month, dt.day);

DateTime _weekStart(DateTime date) =>
    date.subtract(Duration(days: date.weekday - 1));

int _daysBetween(DateTime from, DateTime to) => to.difference(from).inDays;
