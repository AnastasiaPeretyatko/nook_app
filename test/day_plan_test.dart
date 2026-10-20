import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/day_plan.dart';

/// Overlaps on the timeline: which tasks are drawn as one block, what each one
/// says it collides with, and how much of the day is taken.
void main() {
  final day = DateTime(2026, 10, 16);
  var nextId = 1;

  Task t(String title, String from, [String? to]) {
    int m(String hm) {
      final [h, mm] = hm.split(':').map(int.parse).toList();
      return h * 60 + mm;
    }

    return Task(
      dirty: false,
      id: nextId++,
      title: title,
      status: TaskStatus.active,
      trackingMode: TrackingMode.checkbox,
      scheduledTimeMinutes: m(from),
      endTimeMinutes: to == null ? null : m(to),
      startDate: day,
      createdAt: day,
      updatedAt: day,
    );
  }

  List<List<String>> titles(List<TimedCluster> clusters) => [
    for (final c in clusters) [for (final e in c.entries) e.span.task.title],
  ];

  group('clusters', () {
    test('tasks that do not touch stay apart', () {
      final clusters = clusterByOverlap([
        t('a', '09:00', '10:00'),
        t('b', '10:00', '11:00'), // starts as a ends: not an overlap
      ]);
      expect(titles(clusters), [
        ['a'],
        ['b'],
      ]);
      expect(clusters.any((c) => c.overlaps), isFalse);
    });

    test(
      'two overlapping tasks are one block, the later naming the earlier',
      () {
        final call = t('Созвон', '15:00', '15:30');
        final mail = t('Письма', '15:15', '15:45');
        final [cluster] = clusterByOverlap([mail, call]);

        expect(titles([cluster]), [
          ['Созвон', 'Письма'],
        ]);
        expect(cluster.start, 15 * 60);
        expect(cluster.end, 15 * 60 + 45);
        expect(cluster.entries.first.conflicts, isEmpty);
        final [conflict] = cluster.entries.last.conflicts;
        expect(conflict.other, call);
        expect(conflict.minutes, 15);
      },
    );

    test('a chain is one block even where its ends never meet', () {
      final clusters = clusterByOverlap([
        t('a', '09:00', '10:00'),
        t('b', '09:30', '11:00'),
        t('c', '10:30', '12:00'),
      ]);
      expect(titles(clusters), [
        ['a', 'b', 'c'],
      ]);
      // c touches b, not a.
      expect(clusters.single.entries.last.conflicts.map((c) => c.other.title), [
        'b',
      ]);
    });

    test('three at once: each names every earlier one it hits', () {
      final [cluster] = clusterByOverlap([
        t('a', '15:00', '15:30'),
        t('b', '15:15', '15:45'),
        t('c', '15:20', '15:50'),
      ]);
      final last = cluster.entries.last.conflicts;
      expect(last.map((c) => c.other.title), ['a', 'b']);
      expect(last.map((c) => c.minutes), [10, 25]);
    });

    test('a point inside a range overlaps it, with no minutes to report', () {
      final [cluster] = clusterByOverlap([
        t('Созвон', '15:00', '15:30'),
        t('Таблетки', '15:10'),
      ]);
      final [conflict] = cluster.entries.last.conflicts;
      expect(conflict.other.title, 'Созвон');
      expect(conflict.minutes, isNull);
    });

    test('a point at the very start counts, at the very end does not', () {
      expect(
        clusterByOverlap([t('r', '15:00', '15:30'), t('p', '15:00')]),
        hasLength(1),
      );
      expect(
        clusterByOverlap([t('r', '15:00', '15:30'), t('p', '15:30')]),
        hasLength(2),
      );
    });

    test('two points overlap only at the same minute', () {
      expect(
        clusterByOverlap([t('a', '09:00'), t('b', '09:00')]),
        hasLength(1),
      );
      expect(
        clusterByOverlap([t('a', '09:00'), t('b', '09:01')]),
        hasLength(2),
      );
    });

    test('an end not after the start is a point', () {
      final span = TimedSpan(t('x', '10:00', '09:00'));
      expect(span.isPoint, isTrue);
      expect(span.end, span.start);
    });
  });

  group('lanes', () {
    List<int> lanes(List<Task> tasks) => [
      for (final e in clusterByOverlap(tasks).single.entries) e.lane,
    ];

    test('two at once take two lanes', () {
      expect(lanes([t('a', '15:00', '15:30'), t('b', '15:15', '15:45')]), [
        0,
        1,
      ]);
    });

    test('tasks of a block that never meet share a lane', () {
      // a ends at 10:00, c starts at 10:30: c goes back into a's lane.
      final tasks = [
        t('a', '09:00', '10:00'),
        t('b', '09:30', '11:00'),
        t('c', '10:30', '12:00'),
      ];
      expect(lanes(tasks), [0, 1, 0]);
      expect(clusterByOverlap(tasks).single.laneCount, 2);
    });

    test('four at once take four lanes', () {
      final tasks = [
        t('a', '15:00', '15:30'),
        t('b', '15:10', '15:45'),
        t('c', '15:20', '15:50'),
        t('d', '15:25', '15:40'),
      ];
      expect(lanes(tasks), [0, 1, 2, 3]);
      expect(clusterByOverlap(tasks).single.laneCount, 4);
    });

    test('a task alone is in lane 0', () {
      expect(clusterByOverlap([t('a', '09:00')]).single.entries.single.lane, 0);
    });
  });

  test('busy time counts an overlap once and a point not at all', () {
    expect(
      busyMinutes([
        t('a', '15:00', '15:30'),
        t('b', '15:15', '15:45'),
        t('c', '17:00', '18:00'),
        t('p', '19:00'),
      ]),
      45 + 60,
    );
    expect(busyMinutes(const []), 0);
  });

  test('durations read the way the rows print them', () {
    expect(durationLabel(30), '30 мин');
    expect(durationLabel(60), '1 ч');
    expect(durationLabel(90), '1 ч 30 мин');
  });
}
