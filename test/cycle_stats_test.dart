import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/cycle_stats.dart';

CycleDay _day(DateTime date, {int flow = 2}) => CycleDay(
  id: 0,
  date: date,
  flow: flow,
  symptoms: '',
  pill: false,
  dirty: false,
  updatedAt: DateTime(2026),
);

/// [length] days of flow from [start].
List<CycleDay> _period(DateTime start, int length, {int flow = 2}) => [
  for (var i = 0; i < length; i++)
    _day(DateTime(start.year, start.month, start.day + i), flow: flow),
];

void main() {
  group('cycleStats', () {
    test('nothing marked says nothing', () {
      final s = cycleStats(const []);
      expect([s.cycleLength, s.periodLength, s.spread], [null, null, null]);
    });

    test('averages the cycles and the periods', () {
      // Starts: 1 Aug, 28 Aug (27), 25 Sep (28), 23 Oct (28).
      final s = cycleStats([
        ..._period(DateTime(2026, 8, 1), 5),
        ..._period(DateTime(2026, 8, 28), 4),
        ..._period(DateTime(2026, 9, 25), 5),
        ..._period(DateTime(2026, 10, 23), 6),
      ]);

      expect(s.cycleLength, 28); // (27 + 28 + 28) / 3 = 27.67
      expect(s.periodLength, 5); // (5 + 4 + 5 + 6) / 4
      expect(s.spread, 1); // 28 - 27 = 1 → half, rounded up
    });

    test('the spread needs two cycles', () {
      final s = cycleStats([
        ..._period(DateTime(2026, 9, 1), 5),
        ..._period(DateTime(2026, 9, 28), 5),
      ]);
      expect(s.cycleLength, 27);
      expect(s.spread, isNull);
    });

    test(
      'a day without flow and spotting-free gaps: one skipped day is one period',
      () {
        final s = cycleStats([
          _day(DateTime(2026, 9, 1)),
          _day(DateTime(2026, 9, 2)),
          // 3 September skipped
          _day(DateTime(2026, 9, 4)),
        ]);
        expect(s.periodLength, 4);
      },
    );

    test('flow 0 is not a day of a period', () {
      final s = cycleStats([
        _day(DateTime(2026, 9, 1)),
        _day(DateTime(2026, 9, 2), flow: 0),
      ]);
      expect(s.periodLength, 1);
    });

    test(
      'the start from the settings counts, unless a marked period is the same one',
      () {
        final marked = _period(DateTime(2026, 10, 5), 5);
        // Entered 27 days earlier: a cycle of 27.
        expect(
          cycleStats(marked, lastStart: DateTime(2026, 9, 8)).cycleLength,
          27,
        );
        // Entered two days off the marked start: the same period, no cycle.
        expect(
          cycleStats(marked, lastStart: DateTime(2026, 10, 3)).cycleLength,
          isNull,
        );
      },
    );

    test('a gap that is not a cycle is left out', () {
      final s = cycleStats([
        ..._period(DateTime(2026, 1, 1), 5),
        ..._period(DateTime(2026, 1, 8), 5), // 7 days: a mistaken tap
        ..._period(DateTime(2026, 4, 20), 5), // 102 days: months unmarked
        ..._period(DateTime(2026, 5, 18), 5), // 28
      ]);
      expect(s.cycleLength, 28);
    });

    test('only the last six cycles are averaged', () {
      // Seven cycles: one of 40 days first, then six of 28.
      var start = DateTime(2026, 1, 1);
      final days = [..._period(start, 3)];
      for (final length in [40, 28, 28, 28, 28, 28, 28]) {
        start = DateTime(start.year, start.month, start.day + length);
        days.addAll(_period(start, 3));
      }
      final s = cycleStats(days);
      expect(s.cycleLength, 28);
      expect(s.spread, 0);
    });
  });
}
