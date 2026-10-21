import 'package:todo_app/database/app_database.dart';

/// A timed task's place on the day: [start] and [end] in minutes from midnight.
/// A task with no end, or an end not after its start, is a point: [end] equals
/// [start].
class TimedSpan {
  TimedSpan(this.task)
    : start = task.scheduledTimeMinutes!,
      end =
          (task.endTimeMinutes != null &&
              task.endTimeMinutes! > task.scheduledTimeMinutes!)
          ? task.endTimeMinutes!
          : task.scheduledTimeMinutes!;

  final Task task;
  final int start;
  final int end;

  bool get isPoint => end == start;
  int get minutes => end - start;
}

/// One task of a [TimedCluster], with what it collides with.
class ClusterEntry {
  ClusterEntry(this.span, this.conflicts, this.lane);

  final TimedSpan span;

  /// The lane of the block's axis this task's capsule runs in, from 0. See
  /// [clusterByOverlap].
  final int lane;

  /// The earlier tasks of the cluster this one overlaps, in order.
  final List<Conflict> conflicts;
}

/// An overlap with an earlier task: [minutes] of it, or null when one of the two
/// is a point — a moment inside the other, with no length to report.
class Conflict {
  const Conflict(this.other, this.minutes);

  final Task other;
  final int? minutes;
}

/// Tasks whose times run into each other, drawn as one block of side-by-side
/// pills. A task that overlaps nothing is a cluster of one.
class TimedCluster {
  TimedCluster(this.entries);

  final List<ClusterEntry> entries;

  int get start => entries.first.span.start;
  int get end => entries.map((e) => e.span.end).reduce((a, b) => a > b ? a : b);
  bool get overlaps => entries.length > 1;

  /// How many lanes the block needs: the most tasks on the clock at once.
  int get laneCount =>
      entries.map((e) => e.lane).reduce((a, b) => a > b ? a : b) + 1;
}

/// Whether [a] and [b] are on the clock at once.
///
/// Two ranges overlap when they share a minute of length. A point counts as
/// overlapping a range it falls inside, start included and end excluded —
/// 15:30 is free after a 15:00–15:30 call — and two points overlap only when
/// they are at the same minute.
bool spansOverlap(TimedSpan a, TimedSpan b) {
  if (!a.isPoint && !b.isPoint) return a.start < b.end && b.start < a.end;
  if (a.isPoint && b.isPoint) return a.start == b.start;
  final (point, range) = a.isPoint ? (a, b) : (b, a);
  return point.start >= range.start && point.start < range.end;
}

/// The minutes [a] and [b] share; null when either is a point.
int? overlapMinutes(TimedSpan a, TimedSpan b) {
  if (a.isPoint || b.isPoint) return null;
  final from = a.start > b.start ? a.start : b.start;
  final to = a.end < b.end ? a.end : b.end;
  return to - from;
}

/// [tasks] — each with a `scheduledTimeMinutes` — in time order, grouped into
/// the runs that overlap. A task joins the cluster when it overlaps any task
/// already in it, so a chain A–B, B–C is one cluster even if A and C never
/// touch. Within a cluster each task names the earlier ones it overlaps.
///
/// Each task also gets a lane: the first one whose tasks it does not overlap.
/// Two tasks of a block that never meet — one ends, the other starts — share a
/// lane, so a block is only as wide as the most tasks running at once.
List<TimedCluster> clusterByOverlap(Iterable<Task> tasks) {
  final spans = [for (final t in tasks) TimedSpan(t)]
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.end.compareTo(b.end);
    });

  final clusters = <List<TimedSpan>>[];
  for (final span in spans) {
    final current = clusters.isEmpty ? null : clusters.last;
    if (current != null && current.any((s) => spansOverlap(s, span))) {
      current.add(span);
    } else {
      clusters.add([span]);
    }
  }

  return [for (final members in clusters) _cluster(members)];
}

TimedCluster _cluster(List<TimedSpan> members) {
  final lanes = _lanesOf(members);
  return TimedCluster([
    for (final (i, span) in members.indexed)
      ClusterEntry(span, [
        for (final earlier in members.take(i))
          if (spansOverlap(earlier, span))
            Conflict(earlier.task, overlapMinutes(earlier, span)),
      ], lanes[i]),
  ]);
}

/// The lane of each of [spans] — in start order — by first fit.
List<int> _lanesOf(List<TimedSpan> spans) {
  final lanes = <List<TimedSpan>>[];
  return [
    for (final span in spans)
      () {
        var lane = lanes.indexWhere(
          (taken) => !taken.any((s) => spansOverlap(s, span)),
        );
        if (lane < 0) {
          lanes.add([]);
          lane = lanes.length - 1;
        }
        lanes[lane].add(span);
        return lane;
      }(),
  ];
}

/// Minutes of the day taken by [tasks], overlaps counted once. Points take none.
int busyMinutes(Iterable<Task> tasks) {
  final ranges = [
    for (final t in tasks)
      if (!TimedSpan(t).isPoint) TimedSpan(t),
  ]..sort((a, b) => a.start.compareTo(b.start));
  var total = 0;
  int? from, to;
  for (final r in ranges) {
    if (to == null || r.start > to) {
      if (to != null) total += to - from!;
      from = r.start;
      to = r.end;
    } else if (r.end > to) {
      to = r.end;
    }
  }
  if (to != null) total += to - from!;
  return total;
}

/// "30 мин", "2 ч", "1 ч 30 мин".
String durationLabel(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m мин';
  return m == 0 ? '$h ч' : '$h ч $m мин';
}
