import 'package:todo_app/database/app_database.dart';

/// What the notification shade should be showing for one running habit timer.
///
/// Deliberately free of any plugin type: deciding *what* to show is ordinary
/// logic that can be tested, while actually posting it is a thin platform call.
class TimerNotification {
  const TimerNotification({
    required this.taskId,
    required this.title,
    required this.startedAt,
    required this.finishesAt,
  });

  final int taskId;
  final String title;

  /// When the run this entry belongs to began.
  final DateTime startedAt;

  /// The instant the target is reached. Android counts the shade entry down to
  /// it on its own, and the "time is up" alert is scheduled for it — which is
  /// why the whole entry is expressed as an instant rather than as a remaining
  /// duration that would need updating every second.
  final DateTime finishesAt;

  @override
  bool operator ==(Object other) =>
      other is TimerNotification &&
      other.taskId == taskId &&
      other.title == title &&
      other.startedAt == startedAt &&
      other.finishesAt == finishesAt;

  @override
  int get hashCode => Object.hash(taskId, title, startedAt, finishesAt);

  @override
  String toString() =>
      'TimerNotification(task: $taskId, "$title", finishes: $finishesAt)';
}

/// The shade entries the currently running timers call for, ordered by task so
/// the result is stable to compare against what is already on screen.
///
/// A run earns an entry only when it can still finish: the habit is active, is
/// tracked by a timer with a target, and the day it is running for has not been
/// marked done already. [logs] must cover the days the sessions started on —
/// what is already banked there is what shortens the countdown.
List<TimerNotification> timerNotificationsFor({
  required List<Task> tasks,
  required List<TaskSession> openSessions,
  required List<TaskLog> logs,
}) {
  final byId = {for (final task in tasks) task.id: task};

  // A crash can leave more than one run open for a task; the latest is the one
  // the app is actually showing, so it is the one the shade follows.
  final latestByTask = <int, TaskSession>{};
  for (final session in openSessions) {
    final current = latestByTask[session.taskId];
    if (current == null || session.startedAt.isAfter(current.startedAt)) {
      latestByTask[session.taskId] = session;
    }
  }

  final logByKey = {
    for (final log in logs) (log.taskId, _dateOnly(log.date)): log,
  };

  final entries = <TimerNotification>[];
  for (final session in latestByTask.values) {
    final task = byId[session.taskId];
    if (task == null) continue;
    if (task.status != TaskStatus.active) continue;
    if (task.trackingMode != TrackingMode.timer) continue;

    final targetMinutes = task.targetDurationMinutes ?? 0;
    if (targetMinutes <= 0) continue;

    // A run belongs to the day it began on, so that is the day whose progress
    // and completion count — not whatever day it happens to be now.
    final log = logByKey[(task.id, _dateOnly(session.startedAt))];
    if (log?.completed ?? false) continue;

    final banked = (log?.value ?? 0).round();
    final remaining = targetMinutes * 60 - banked;

    entries.add(
      TimerNotification(
        taskId: task.id,
        title: task.title,
        startedAt: session.startedAt,
        // A run already past its target keeps an entry with a finish in the
        // past: the app closes it the moment it is on screen again, and until
        // then the shade truthfully reads as finished rather than vanishing.
        finishesAt: session.startedAt.add(Duration(seconds: remaining)),
      ),
    );
  }

  entries.sort((a, b) => a.taskId.compareTo(b.taskId));
  return entries;
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
