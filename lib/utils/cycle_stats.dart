import 'package:todo_app/database/app_database.dart' show CycleDay;

/// What the user's own marks say about her cycle — the three figures of the
/// "Цикл" tab. Pure, so the rules are testable and live in one place.
///
/// A figure is null while there is not enough to compute it; the screen then
/// shows the value from the settings, or a dash for the spread.
class CycleStats {
  const CycleStats({this.cycleLength, this.periodLength, this.spread});

  /// Average days from the first day of one period to the first of the next.
  final int? cycleLength;

  /// Average days a period lasts.
  final int? periodLength;

  /// "±N": half of the gap between the shortest and the longest cycle, rounded
  /// up. Needs two cycles, which is three period starts.
  final int? spread;
}

/// The last [keep] cycles are what is averaged — recent ones say more about the
/// body now than ones from a year ago.
///
/// Every day with a flow (`flow > 0`) is a day of a period. Days at most one day
/// apart are one period (bleeding that skips a day is still one), so a period
/// runs from its first marked day to its last. [lastStart] — the start entered
/// in the settings — counts as a start too, unless a marked period begins within
/// ten days of it (then that one is the same period, and the marks win).
///
/// A gap shorter than 15 or longer than 60 days between two starts is not a
/// cycle — a mistaken tap, or months of nothing marked — and is left out of the
/// average rather than spoiling it.
CycleStats cycleStats(
  Iterable<CycleDay> days, {
  DateTime? lastStart,
  int keep = 6,
}) {
  final marked = [
    for (final d in days)
      if (d.flow > 0) DateTime(d.date.year, d.date.month, d.date.day),
  ]..sort();

  // Periods as (first day, last day).
  final periods = <(DateTime, DateTime)>[];
  for (final day in marked) {
    if (periods.isNotEmpty && _gap(periods.last.$2, day) <= 2) {
      periods[periods.length - 1] = (periods.last.$1, day);
    } else {
      periods.add((day, day));
    }
  }

  final starts = [for (final p in periods) p.$1];
  if (lastStart != null && !starts.any((s) => _gap(s, lastStart).abs() <= 10)) {
    starts
      ..add(DateTime(lastStart.year, lastStart.month, lastStart.day))
      ..sort();
  }

  final cycles = <int>[
    for (var i = 1; i < starts.length; i++)
      if (_gap(starts[i - 1], starts[i]) case final n when n >= 15 && n <= 60)
        n,
  ];
  final recent = cycles.length > keep
      ? cycles.sublist(cycles.length - keep)
      : cycles;

  final lasts = [for (final p in periods) _gap(p.$1, p.$2) + 1];
  final recentLasts = lasts.length > keep
      ? lasts.sublist(lasts.length - keep)
      : lasts;

  int? average(List<int> xs) =>
      xs.isEmpty ? null : (xs.reduce((a, b) => a + b) / xs.length).round();

  int? spread;
  if (recent.length >= 2) {
    final lo = recent.reduce((a, b) => a < b ? a : b);
    final hi = recent.reduce((a, b) => a > b ? a : b);
    spread = ((hi - lo) / 2).ceil();
  }

  return CycleStats(
    cycleLength: average(recent),
    periodLength: average(recentLasts),
    spread: spread,
  );
}

/// Whole calendar days from [a] to [b] — through UTC, so a clock change between
/// them cannot make a day 23 or 25 hours.
int _gap(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
