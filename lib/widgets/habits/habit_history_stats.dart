import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/week.dart';
import 'package:todo_app/widgets/habits/habit_week_stats.dart';

/// How the days of a stretch were spent, over the days the rule planned that are
/// already settled — an open today and the days ahead are nobody's failure yet.
class DayCounts {
  const DayCounts({
    this.onTime = 0,
    this.late = 0,
    this.partial = 0,
    this.missed = 0,
  });

  final int onTime;
  final int late;

  /// A counter or timer with progress short of its target.
  final int partial;
  final int missed;

  int get done => onTime + late;
  int get planned => onTime + late + partial + missed;

  /// Whole percent, or null with nothing planned.
  int? get donePercent => planned == 0 ? null : (done * 100 / planned).round();

  DayCounts operator +(DayCounts o) => DayCounts(
    onTime: onTime + o.onTime,
    late: late + o.late,
    partial: partial + o.partial,
    missed: missed + o.missed,
  );
}

/// One calendar month of a habit's history.
class MonthStat {
  const MonthStat({
    required this.year,
    required this.month,
    required this.counts,
    required this.averageOffset,
  });

  final int year;
  final int month;
  final DayCounts counts;

  /// Mean minutes from the habit's time to the tick, over the month's ticks that
  /// carry a moment. Null when there are none.
  final double? averageOffset;
}

/// One week of a habit's history, from [start] (the first day of the week).
class WeekStat {
  const WeekStat({
    required this.start,
    required this.counts,
    required this.averageOffset,
  });

  final DateTime start;
  final DayCounts counts;
  final double? averageOffset;
}

/// A settled day of the last stretch the time chart plots.
class TimePoint {
  const TimePoint({
    required this.day,
    required this.cell,
    required this.offset,
  });

  final DateTime day;
  final WeekCell cell;

  /// Minutes from the habit's time; null for a miss or a mark with no moment.
  final int? offset;
}

/// A habit's whole history, from its first day to today, read through the same
/// day rules as the week view ([habitWeek]).
class HabitHistory {
  const HabitHistory._(this.task, this.days, this.week);

  final Task task;

  /// Every day from the first one that matters to today, in order.
  final List<DateTime> days;
  final HabitWeek week;

  /// [logs] are this task's logs, all of them.
  factory HabitHistory.of({
    required Task task,
    required Iterable<TaskLog> logs,
    required DateTime today,
    required int graceMinutes,
    required bool todayStaysOpen,
  }) {
    var first = taskAnchorDate(task);
    for (final l in logs) {
      final d = DateTime(l.date.year, l.date.month, l.date.day);
      if (l.taskId == task.id && d.isBefore(first)) first = d;
    }
    if (first.isAfter(today)) first = today;
    final days = [
      for (
        var d = first;
        !d.isAfter(today);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        d,
    ];
    return HabitHistory._(
      task,
      days,
      habitWeek(
        task: task,
        days: days,
        logs: logs,
        today: today,
        graceMinutes: graceMinutes,
        todayStaysOpen: todayStaysOpen,
      ),
    );
  }

  WeekCell cellOf(int i) => week.cells[i];

  bool _settled(int i) =>
      week.scheduled[i] &&
      switch (week.cells[i]) {
        WeekCell.onTime ||
        WeekCell.late ||
        WeekCell.partial ||
        WeekCell.missed => true,
        _ => false,
      };

  /// Counts over the days [include] accepts (all of them by default).
  DayCounts counts([bool Function(DateTime day)? include]) {
    var c = const DayCounts();
    for (var i = 0; i < days.length; i++) {
      if (!_settled(i) || (include != null && !include(days[i]))) continue;
      c =
          c +
          switch (week.cells[i]) {
            WeekCell.onTime => const DayCounts(onTime: 1),
            WeekCell.late => const DayCounts(late: 1),
            WeekCell.partial => const DayCounts(partial: 1),
            _ => const DayCounts(missed: 1),
          };
    }
    return c;
  }

  /// The run of planned days done in a row, ending now, and the longest there
  /// was. A day off the rule neither adds nor breaks one; a miss, or a counter
  /// that fell short, ends it.
  ({int current, int best}) get streaks {
    var run = 0, best = 0;
    for (var i = 0; i < days.length; i++) {
      if (!week.scheduled[i]) continue;
      switch (week.cells[i]) {
        case WeekCell.onTime || WeekCell.late:
          run++;
          if (run > best) best = run;
        case WeekCell.missed || WeekCell.partial:
          run = 0;
        case _:
          break;
      }
    }
    return (current: run, best: best);
  }

  /// Per weekday (`DateTime.weekday - 1`): the share of planned days done, null
  /// for a weekday the rule never lands on.
  List<double?> get weekdayRates => [
    for (var w = DateTime.monday; w <= DateTime.sunday; w++)
      () {
        final c = counts((d) => d.weekday == w);
        return c.planned == 0 ? null : c.done / c.planned;
      }(),
  ];

  /// Every calendar month from the first day to today.
  List<MonthStat> get months {
    final out = <MonthStat>[];
    var y = days.first.year, m = days.first.month;
    final last = days.last;
    while (y < last.year || (y == last.year && m <= last.month)) {
      final offsets = [
        for (var i = 0; i < days.length; i++)
          if (days[i].year == y &&
              days[i].month == m &&
              week.offsets[i] != null)
            week.offsets[i]!,
      ];
      out.add(
        MonthStat(
          year: y,
          month: m,
          counts: counts((d) => d.year == y && d.month == m),
          averageOffset: offsets.isEmpty
              ? null
              : offsets.reduce((a, b) => a + b) / offsets.length,
        ),
      );
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
    }
    return out;
  }

  /// Every week from the one the first day falls in to the current one, each
  /// starting on [firstWeekday] ([DateTime.monday] or [DateTime.sunday]). The
  /// first is cut short by the habit's start: days before it are not planned,
  /// so they count for nothing.
  List<WeekStat> weeks(int firstWeekday) {
    final out = <WeekStat>[];
    var start = startOfWeek(days.first, firstWeekday);
    while (!start.isAfter(days.last)) {
      final end = DateTime(start.year, start.month, start.day + 7);
      bool inWeek(DateTime d) => !d.isBefore(start) && d.isBefore(end);
      out.add(
        WeekStat(
          start: start,
          counts: counts(inWeek),
          averageOffset: averageOffset(inWeek),
        ),
      );
      start = end;
    }
    return out;
  }

  /// The last [n] settled days before today — what the "Месяц" time chart plots.
  List<TimePoint> recentPoints(DateTime today, {int n = 14}) {
    final all = [
      for (var i = 0; i < days.length; i++)
        if (_settled(i) && days[i] != today)
          TimePoint(day: days[i], cell: week.cells[i], offset: week.offsets[i]),
    ];
    return all.length <= n ? all : all.sublist(all.length - n);
  }

  /// Mean minutes from the habit's time to the tick over the ticks that carry a
  /// moment, within [include]. Null when there are none.
  double? averageOffset([bool Function(DateTime day)? include]) {
    final v = [
      for (var i = 0; i < days.length; i++)
        if (week.offsets[i] != null && (include == null || include(days[i])))
          week.offsets[i]!,
    ];
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }
}
