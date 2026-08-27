import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/notifications/timer_notification.dart';
import 'package:todo_app/notifications/app_notifications.dart';

/// Any moment at all: these tests never read a log's edit time. It exists
/// because the sync needs one and the column is therefore not nullable.
final _fixtureStamp = DateTime(2026, 1, 1);

final _day = DateTime(2026, 5, 20);
DateTime _at(int hour, int minute) => DateTime(2026, 5, 20, hour, minute);

Task _task({
  int id = 1,
  String title = 'Медитация',
  int? targetDurationMinutes = 10,
  TrackingMode trackingMode = TrackingMode.timer,
  TaskStatus status = TaskStatus.active,
}) => Task(dirty: false, 
  id: id,
  title: title,
  status: status,
  repeatType: RepeatType.daily,
  trackingMode: trackingMode,
  targetDurationMinutes: targetDurationMinutes,
  startDate: _day,
  createdAt: _day,
  updatedAt: _day,
);

TaskSession _session({
  int id = 1,
  int taskId = 1,
  required DateTime startedAt,
}) => TaskSession(id: id, taskId: taskId, startedAt: startedAt);

TaskLog _log({
  int id = 1,
  int taskId = 1,
  DateTime? date,
  double? value,
  bool completed = false,
}) => TaskLog(dirty: false, updatedAt: _fixtureStamp, 
  id: id,
  taskId: taskId,
  date: date ?? _day,
  completed: completed,
  value: value,
);

List<TimerNotification> _entries({
  List<Task>? tasks,
  List<TaskSession> sessions = const [],
  List<TaskLog> logs = const [],
}) => timerNotificationsFor(
  tasks: tasks ?? [_task()],
  openSessions: sessions,
  logs: logs,
);

void main() {
  group('what earns a shade entry', () {
    test('nothing running, nothing to show', () {
      expect(_entries(), isEmpty);
    });

    test('a running timer finishes a full target after it started', () {
      final entries = _entries(sessions: [_session(startedAt: _at(9, 0))]);

      expect(entries, hasLength(1));
      expect(entries.single.taskId, 1);
      expect(entries.single.title, 'Медитация');
      expect(entries.single.startedAt, _at(9, 0));
      expect(entries.single.finishesAt, _at(9, 10));
    });

    test('time already banked today shortens the countdown', () {
      final entries = _entries(
        sessions: [_session(startedAt: _at(9, 0))],
        logs: [_log(value: 240)],
      );

      // Four of the ten minutes were already done, so six are left.
      expect(entries.single.finishesAt, _at(9, 6));
    });

    test('a day already marked done gets no entry', () {
      final entries = _entries(
        sessions: [_session(startedAt: _at(9, 0))],
        logs: [_log(value: 600, completed: true)],
      );

      expect(entries, isEmpty);
    });

    test(
      'a run past its target keeps an entry that already reads finished',
      () {
        final entries = _entries(
          sessions: [_session(startedAt: _at(9, 0))],
          logs: [_log(value: 900)],
        );

        expect(entries.single.finishesAt, _at(8, 55));
      },
    );

    test('an archived habit gets no entry', () {
      final entries = _entries(
        tasks: [_task(status: TaskStatus.archived)],
        sessions: [_session(startedAt: _at(9, 0))],
      );

      expect(entries, isEmpty);
    });

    test('a habit that is no longer tracked by a timer gets no entry', () {
      final entries = _entries(
        tasks: [_task(trackingMode: TrackingMode.checkbox)],
        sessions: [_session(startedAt: _at(9, 0))],
      );

      expect(entries, isEmpty);
    });

    test('a timer without a target gets no entry', () {
      final entries = _entries(
        tasks: [_task(targetDurationMinutes: null)],
        sessions: [_session(startedAt: _at(9, 0))],
      );

      expect(entries, isEmpty);
    });

    test('a session whose task is gone is skipped, not crashed on', () {
      final entries = _entries(
        tasks: const [],
        sessions: [_session(startedAt: _at(9, 0))],
      );

      expect(entries, isEmpty);
    });
  });

  group('several habits at once', () {
    test('each running timer gets its own entry, ordered by task', () {
      final entries = _entries(
        tasks: [
          _task(id: 2, title: 'Чтение'),
          _task(id: 1),
        ],
        sessions: [
          _session(id: 1, taskId: 2, startedAt: _at(9, 0)),
          _session(id: 2, taskId: 1, startedAt: _at(9, 5)),
        ],
      );

      expect(entries.map((e) => e.taskId), [1, 2]);
      expect(entries.map((e) => e.title), ['Медитация', 'Чтение']);
    });

    test('one habit\'s banked time does not shorten another\'s', () {
      final entries = _entries(
        tasks: [
          _task(id: 1),
          _task(id: 2, title: 'Чтение'),
        ],
        sessions: [
          _session(id: 1, taskId: 1, startedAt: _at(9, 0)),
          _session(id: 2, taskId: 2, startedAt: _at(9, 0)),
        ],
        logs: [_log(taskId: 1, value: 300)],
      );

      expect(entries[0].finishesAt, _at(9, 5));
      expect(entries[1].finishesAt, _at(9, 10));
    });

    test('two runs left open for one habit collapse to the latest', () {
      final entries = _entries(
        sessions: [
          _session(id: 1, startedAt: _at(9, 0)),
          _session(id: 2, startedAt: _at(9, 30)),
        ],
      );

      expect(entries, hasLength(1));
      expect(entries.single.startedAt, _at(9, 30));
    });
  });

  group('a run that began yesterday', () {
    test('is measured against the day it started on', () {
      final lateNight = DateTime(2026, 5, 19, 23, 55);
      final entries = _entries(
        sessions: [_session(startedAt: lateNight)],
        logs: [
          _log(id: 1, date: DateTime(2026, 5, 19), value: 300),
          // Today's log belongs to a different run and must not be read here.
          _log(id: 2, date: _day, value: 540),
        ],
      );

      expect(entries.single.finishesAt, DateTime(2026, 5, 20, 0, 0));
    });

    test('is dropped when that day was already finished', () {
      final lateNight = DateTime(2026, 5, 19, 23, 55);
      final entries = _entries(
        sessions: [_session(startedAt: lateNight)],
        logs: [_log(date: DateTime(2026, 5, 19), value: 600, completed: true)],
      );

      expect(entries, isEmpty);
    });
  });

  group('entry identity', () {
    test('two entries for the same run are equal', () {
      final a = TimerNotification(
        taskId: 1,
        title: 'Медитация',
        startedAt: _at(9, 0),
        finishesAt: _at(9, 10),
      );
      final b = TimerNotification(
        taskId: 1,
        title: 'Медитация',
        startedAt: _at(9, 0),
        finishesAt: _at(9, 10),
      );

      // The service reposts only what changed, so this is what keeps an
      // untouched run from being rewritten on every rebuild.
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a renamed habit is a different entry', () {
      final a = TimerNotification(
        taskId: 1,
        title: 'Медитация',
        startedAt: _at(9, 0),
        finishesAt: _at(9, 10),
      );
      final b = TimerNotification(
        taskId: 1,
        title: 'Дыхание',
        startedAt: _at(9, 0),
        finishesAt: _at(9, 10),
      );

      expect(a, isNot(b));
    });
  });

  group('notification ids', () {
    test('a habit\'s two entries never collide', () {
      expect(
        AppNotifications.runningIdFor(7),
        isNot(AppNotifications.doneIdFor(7)),
      );
    });

    test('no two habits share an id', () {
      final ids = <int>{};
      for (var taskId = 1; taskId <= 50; taskId++) {
        ids.add(AppNotifications.runningIdFor(taskId));
        ids.add(AppNotifications.doneIdFor(taskId));
      }

      expect(ids, hasLength(100));
    });
  });
}
