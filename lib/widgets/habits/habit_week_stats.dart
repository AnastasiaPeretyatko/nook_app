import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/week.dart';
import 'package:todo_app/widgets/habits/habit_day_state.dart';

/// What one square of the week view says about a habit's day (`Week.dc.html`).
enum WeekCell {
  /// Marked at or before its time plus the grace.
  onTime,

  /// Marked, but later.
  late,

  /// A counter or timer with progress that did not reach its target.
  partial,

  /// Scheduled, over, and not marked.
  missed,

  /// Nothing planned: off the rule, or before the habit began.
  off,

  /// A day still ahead.
  future,

  /// Today, still open.
  pending,
}

/// One habit across one week: a square per day plus the figures behind its
/// "4/5".
class HabitWeek {
  const HabitWeek({
    required this.task,
    required this.cells,
    required this.scheduled,
    required this.lateMinutes,
    required this.offsets,
  });

  final Task task;
  final List<WeekCell> cells;

  /// Whether the rule lands on each day. A mark made on a day the rule skips
  /// still draws as done, but is nobody's plan, so it counts for nothing below.
  final List<bool> scheduled;

  /// How far past its time each late mark ran, in minutes.
  final List<int> lateMinutes;

  /// Per day: minutes from the habit's time to the tick, negative when early.
  /// Null for a day with no tick, a habit with no time, or a mark from before
  /// the moment was recorded.
  final List<int?> offsets;

  bool _counted(int i) =>
      scheduled[i] &&
      switch (cells[i]) {
        WeekCell.onTime ||
        WeekCell.late ||
        WeekCell.partial ||
        WeekCell.missed => true,
        _ => false,
      };

  /// Days planned and already settled: an open today and the days ahead are
  /// not counted — they have not failed yet.
  int get planned => [
    for (var i = 0; i < cells.length; i++) _counted(i),
  ].where((c) => c).length;

  int get onTime => _count(WeekCell.onTime);
  int get late => _count(WeekCell.late);
  int get done => onTime + late;

  int _count(WeekCell cell) => [
    for (var i = 0; i < cells.length; i++)
      if (scheduled[i] && cells[i] == cell) i,
  ].length;
}

/// [days] is the week, [logs] every log of [task] in it.
///
/// A habit of the same day state as the rest of the app — it goes through
/// [habitDayState] — with the one case that has no place there: partial
/// progress.
HabitWeek habitWeek({
  required Task task,
  required List<DateTime> days,
  required Iterable<TaskLog> logs,
  required DateTime today,
  required int graceMinutes,
  required bool todayStaysOpen,
}) {
  final mine = [
    for (final l in logs)
      if (l.taskId == task.id) l,
  ];
  DateTime dayOf(TaskLog l) => DateTime(l.date.year, l.date.month, l.date.day);
  final completed = {
    for (final l in mine)
      if (l.completed) dayOf(l),
  };
  final late = lateDays(task, mine, graceMinutes);
  final progress = {
    for (final l in mine)
      if (!l.completed &&
          task.trackingMode != TrackingMode.checkbox &&
          (l.value ?? 0) > 0)
        dayOf(l),
  };

  final planned = task.scheduledTimeMinutes;
  final atByDay = {
    for (final l in mine)
      if (l.completed && l.completedAt != null) dayOf(l): l.completedAt!,
  };
  final lateMinutes = <int>[];
  final offsets = <int?>[];
  final cells = <WeekCell>[];
  final scheduled = <bool>[];
  for (final day in days) {
    final state = habitDayState(
      task,
      day,
      today: today,
      completedDays: completed,
      lateDays: late,
      todayStaysOpen: todayStaysOpen,
    );
    var cell = switch (state) {
      HabitDayState.done => WeekCell.onTime,
      HabitDayState.late => WeekCell.late,
      HabitDayState.off || HabitDayState.beforeStart => WeekCell.off,
      HabitDayState.upcoming => WeekCell.future,
      HabitDayState.today => WeekCell.pending,
      HabitDayState.missed => WeekCell.missed,
    };
    if ((cell == WeekCell.missed || cell == WeekCell.pending) &&
        progress.contains(day)) {
      cell = WeekCell.partial;
    }
    cells.add(cell);
    scheduled.add(isTaskScheduledOn(task, day));
    final at = atByDay[day];
    final offset = planned == null || at == null
        ? null
        : at
              .difference(DateTime(day.year, day.month, day.day, 0, planned))
              .inMinutes;
    offsets.add(offset);
    if (cell == WeekCell.late && offset != null) lateMinutes.add(offset);
  }
  return HabitWeek(
    task: task,
    cells: cells,
    scheduled: scheduled,
    lateMinutes: lateMinutes,
    offsets: offsets,
  );
}

/// One day's bar: the share of the habits scheduled that day that were done on
/// time, and the share done late. Both 0 for a day with nothing scheduled or
/// not yet begun. Unlike the week's figures an open today counts in the
/// denominator — the bar says how far the day has come.
class DayBar {
  const DayBar({required this.onTime, required this.late, required this.open});

  final double onTime;
  final double late;

  /// Today, not over.
  final bool open;
}

/// The figures of the summary card.
class WeekSummary {
  const WeekSummary({
    required this.planned,
    required this.done,
    required this.onTime,
    required this.averageLateMinutes,
    required this.bars,
  });

  final int planned;
  final int done;
  final int onTime;

  /// Null when nothing was late.
  final int? averageLateMinutes;
  final List<DayBar> bars;

  /// Whole percent, or null with nothing planned.
  int? get donePercent => planned == 0 ? null : (done * 100 / planned).round();
  int? get onTimePercent =>
      planned == 0 ? null : (onTime * 100 / planned).round();
}

WeekSummary weekSummary(
  List<HabitWeek> habits,
  List<DateTime> days, {
  required DateTime today,
}) {
  var planned = 0, done = 0, onTime = 0;
  final lateMinutes = <int>[];
  for (final h in habits) {
    planned += h.planned;
    done += h.done;
    onTime += h.onTime;
    lateMinutes.addAll(h.lateMinutes);
  }
  final bars = <DayBar>[
    for (final (d, day) in days.indexed)
      () {
        if (day.isAfter(today)) {
          return const DayBar(onTime: 0, late: 0, open: false);
        }
        final due = habits.where((h) => h.scheduled[d]).toList();
        if (due.isEmpty) return const DayBar(onTime: 0, late: 0, open: false);
        double share(WeekCell c) =>
            due.where((h) => h.cells[d] == c).length / due.length;
        return DayBar(
          onTime: share(WeekCell.onTime),
          late: share(WeekCell.late),
          open: day == today,
        );
      }(),
  ];
  return WeekSummary(
    planned: planned,
    done: done,
    onTime: onTime,
    averageLateMinutes: lateMinutes.isEmpty
        ? null
        : (lateMinutes.reduce((a, b) => a + b) / lateMinutes.length).round(),
    bars: bars,
  );
}

/// "+40 мин", "+1 ч 10 мин", or "—" when nothing was late.
String lateAverageLabel(int? minutes) {
  if (minutes == null) return '—';
  if (minutes < 60) return '+$minutes мин';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '+$h ч' : '+$h ч $m мин';
}
