/// What a day of the cycle is. Order matters: a day that is both a period day
/// and inside the fertile window (a very short cycle) reads as the period.
enum CyclePhase { period, fertile, ovulation, other }

/// The cycle rules of `DESIGN.md` §6.3, pure — the only place that decides what
/// phase a day is in.
///
/// The model: [lastStart] is the first day of the last period, a cycle is
/// [length] days, a period [periodLength]. Ovulation falls 14 days before the
/// next period (day `length - 13`), and the fertile window is the five days
/// before it plus the day after. Every cycle is assumed to run like the last
/// one, so a day is placed by counting from [lastStart] and wrapping every
/// [length] days — the forecast, not a record of what happened.
///
/// An estimate, not contraception: the screen says so too.
class CycleModel {
  const CycleModel({
    required this.lastStart,
    this.length = 27,
    this.periodLength = 5,
  });

  final DateTime lastStart;
  final int length;
  final int periodLength;

  /// The day of the cycle (1-based) that [day] falls on, or null before
  /// [lastStart] — nothing is known about those days.
  int? cycleDay(DateTime day) {
    final passed = _days(lastStart, day);
    return passed < 0 ? null : passed % length + 1;
  }

  /// The ovulation day of a cycle, counted from its first day.
  int get ovulationDay => length - 13;

  CyclePhase phaseOfCycleDay(int cycleDay) {
    if (cycleDay <= periodLength) return CyclePhase.period;
    if (cycleDay == ovulationDay) return CyclePhase.ovulation;
    if (cycleDay >= ovulationDay - 5 && cycleDay <= ovulationDay + 1) {
      return CyclePhase.fertile;
    }
    return CyclePhase.other;
  }

  CyclePhase phaseOn(DateTime day) {
    final d = cycleDay(day);
    return d == null ? CyclePhase.other : phaseOfCycleDay(d);
  }

  /// Whether [day] lies beyond the cycle the user entered — a forecast of the
  /// cycles to come, drawn dashed on the calendar. The entered one is as far as
  /// [length] days from [lastStart].
  bool isForecast(DateTime day) => _days(lastStart, day) >= length;

  /// The first day of the next period, strictly after [today].
  DateTime nextPeriodStart(DateTime today) {
    final passed = _days(lastStart, today);
    final cycles = passed < 0 ? 0 : passed ~/ length + 1;
    return _plus(lastStart, cycles * length);
  }

  /// The next ovulation day, today included.
  DateTime nextOvulation(DateTime today) {
    final passed = _days(lastStart, today);
    final cycle = passed < 0 ? 0 : passed ~/ length;
    var day = _plus(lastStart, cycle * length + ovulationDay - 1);
    if (_days(today, day) < 0) day = _plus(day, length);
    return day;
  }

  /// The fertile window that is on today or the next one to come: the five days
  /// before ovulation and the day after it. It stays "current" through its last
  /// day, so on that day it is still the one being lived, not the next cycle's.
  ({DateTime start, DateTime end}) fertileWindow(DateTime today) {
    final passed = _days(lastStart, today);
    var cycle = passed < 0 ? 0 : passed ~/ length;
    DateTime ovulation() => _plus(lastStart, cycle * length + ovulationDay - 1);
    if (_days(today, _plus(ovulation(), 1)) < 0) cycle++;
    return (start: _plus(ovulation(), -5), end: _plus(ovulation(), 1));
  }

  /// Whole days from [a] to [b], both taken as calendar days — through UTC so a
  /// clock change in between cannot make a day 23 or 25 hours.
  static int daysBetween(DateTime a, DateTime b) => _days(a, b);

  static int _days(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static DateTime _plus(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);
}
