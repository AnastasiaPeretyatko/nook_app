import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/notifications/app_notifications.dart';
import 'package:todo_app/notifications/task_reminder.dart';

final _day = DateTime(2026, 5, 20); // a Wednesday
DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 5, 20, hour, minute);

/// Mid-morning, so both earlier and later occurrences of the same day exist.
final _now = _at(9, 0);

Task _task({
  int id = 1,
  String title = 'Read book',
  int? scheduledTimeMinutes = 10 * 60,
  int? endTimeMinutes,
  RepeatType? repeatType,
  int? repeatDaysMask,
  TaskStatus status = TaskStatus.active,
  int? parentId,
  DateTime? startDate,
}) => Task(
  id: id,
  title: title,
  parentId: parentId,
  status: status,
  repeatType: repeatType,
  repeatDaysMask: repeatDaysMask,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: scheduledTimeMinutes,
  endTimeMinutes: endTimeMinutes,
  startDate: startDate ?? _day,
  createdAt: _day,
  updatedAt: _day,
);

TaskLog _log({
  int id = 1,
  int taskId = 1,
  DateTime? date,
  bool completed = true,
}) => TaskLog(id: id, taskId: taskId, date: date ?? _day, completed: completed);

List<TaskReminder> _reminders({
  List<Task>? tasks,
  List<TaskLog> logs = const [],
  DateTime? now,
  int horizonDays = defaultReminderHorizonDays,
  int limit = maxScheduledReminders,
}) => taskRemindersFor(
  tasks: tasks ?? [_task()],
  logs: logs,
  now: now ?? _now,
  horizonDays: horizonDays,
  limit: limit,
);

void main() {
  group('what earns a reminder', () {
    test('a one-off task later today', () {
      final reminders = _reminders();

      expect(reminders, hasLength(1));
      expect(reminders.single.taskId, 1);
      expect(reminders.single.title, 'Read book');
      expect(reminders.single.at, _at(10, 0));
      expect(reminders.single.day, _day);
    });

    test('a task without a time is never reminded of', () {
      expect(_reminders(tasks: [_task(scheduledTimeMinutes: null)]), isEmpty);
    });

    test('an occurrence that has already passed is skipped', () {
      final reminders = _reminders(
        tasks: [_task(scheduledTimeMinutes: 8 * 60)],
      );

      expect(reminders, isEmpty);
    });

    test('the exact current minute counts as passed', () {
      final reminders = _reminders(
        tasks: [_task(scheduledTimeMinutes: 9 * 60)],
      );

      expect(reminders, isEmpty);
    });

    test('a day already ticked off gets no reminder', () {
      expect(_reminders(logs: [_log()]), isEmpty);
    });

    test('an unfinished log is not a tick', () {
      expect(_reminders(logs: [_log(completed: false)]), hasLength(1));
    });

    test('an archived task gets no reminder', () {
      expect(_reminders(tasks: [_task(status: TaskStatus.archived)]), isEmpty);
    });

    test('a subtask is reported through its parent, never on its own', () {
      final reminders = _reminders(
        tasks: [
          _task(),
          _task(id: 2, title: 'Глава 1', parentId: 1),
        ],
      );

      expect(reminders.map((r) => r.taskId), [1]);
    });
  });

  group('the body carries the time', () {
    test('a point in time is just that time', () {
      expect(_reminders().single.body, '10:00');
    });

    test('a task with a duration reads as a range', () {
      final reminders = _reminders(
        tasks: [_task(endTimeMinutes: 11 * 60 + 30)],
      );

      expect(reminders.single.body, '10:00 – 11:30');
    });

    test('an end that is not after the start is left out', () {
      final reminders = _reminders(tasks: [_task(endTimeMinutes: 10 * 60)]);

      expect(reminders.single.body, '10:00');
    });
  });

  group('repeating habits', () {
    test('a daily habit is reminded of every day in the window', () {
      final reminders = _reminders(
        tasks: [_task(repeatType: RepeatType.daily)],
      );

      expect(reminders, hasLength(defaultReminderHorizonDays));
      expect(reminders.first.at, _at(10, 0));
      expect(reminders.last.day, DateTime(2026, 5, 26));
    });

    test('a weekly habit only lands on its own weekdays', () {
      // Monday and Wednesday; the window starts on a Wednesday.
      final reminders = _reminders(
        tasks: [
          _task(repeatType: RepeatType.weekly, repeatDaysMask: 1 | (1 << 2)),
        ],
      );

      expect(reminders.map((r) => r.day), [
        DateTime(2026, 5, 20), // Wed
        DateTime(2026, 5, 25), // Mon
      ]);
    });

    test('only the days already ticked are dropped', () {
      final reminders = _reminders(
        tasks: [_task(repeatType: RepeatType.daily)],
        logs: [_log(date: DateTime(2026, 5, 22))],
      );

      expect(
        reminders.map((r) => r.day),
        isNot(contains(DateTime(2026, 5, 22))),
      );
      expect(reminders, hasLength(defaultReminderHorizonDays - 1));
    });

    test('a habit that has not started yet waits for its start date', () {
      final reminders = _reminders(
        tasks: [
          _task(repeatType: RepeatType.daily, startDate: DateTime(2026, 5, 24)),
        ],
      );

      expect(reminders.first.day, DateTime(2026, 5, 24));
    });
  });

  group('ordering and volume', () {
    test('reminders come out in the order they fire', () {
      final reminders = _reminders(
        tasks: [
          _task(id: 1, title: 'Позже', scheduledTimeMinutes: 18 * 60),
          _task(id: 2, title: 'Раньше', scheduledTimeMinutes: 11 * 60),
        ],
      );

      expect(reminders.map((r) => r.title), ['Раньше', 'Позже']);
    });

    test('the nearest ones win when there are too many', () {
      final reminders = _reminders(
        tasks: [
          for (var id = 1; id <= 10; id++)
            _task(id: id, repeatType: RepeatType.daily),
        ],
        limit: 12,
      );

      expect(reminders, hasLength(12));
      // All twelve are the soonest two days, not a slice of one habit's week.
      expect(reminders.map((r) => r.day).toSet(), {
        _day,
        DateTime(2026, 5, 21),
      });
    });

    test('a shorter horizon schedules less', () {
      final reminders = _reminders(
        tasks: [_task(repeatType: RepeatType.daily)],
        horizonDays: 2,
      );

      expect(reminders, hasLength(2));
    });
  });

  group('identity', () {
    test('the fingerprint changes when the task is renamed', () {
      final before = _reminders().single;
      final after = _reminders(tasks: [_task(title: 'Читать книгу')]).single;

      // What tells an already scheduled reminder from one that has to be
      // replaced, since only the payload comes back from the platform.
      expect(before.fingerprint, isNot(after.fingerprint));
    });

    test('the fingerprint changes when the time moves', () {
      final before = _reminders().single;
      final after = _reminders(
        tasks: [_task(scheduledTimeMinutes: 11 * 60)],
      ).single;

      expect(before.fingerprint, isNot(after.fingerprint));
    });

    test('an untouched task keeps its fingerprint', () {
      expect(_reminders().single.fingerprint, _reminders().single.fingerprint);
    });
  });

  group('notification ids', () {
    test('a reminder never collides with a timer entry', () {
      // Timer ids are two per task from zero up; reminders start above them.
      for (var taskId = 1; taskId <= 1000; taskId++) {
        expect(
          AppNotifications.runningIdFor(taskId),
          lessThan(AppNotifications.reminderIdBase),
        );
        expect(
          AppNotifications.doneIdFor(taskId),
          lessThan(AppNotifications.reminderIdBase),
        );
      }
    });

    test('every day of the window gets its own id', () {
      final ids = {
        for (var offset = 0; offset < defaultReminderHorizonDays; offset++)
          AppNotifications.reminderIdFor(7, DateTime(2026, 5, 20 + offset)),
      };

      expect(ids, hasLength(defaultReminderHorizonDays));
    });

    test('no two tasks share a reminder id inside the window', () {
      final ids = <int>{};
      for (var taskId = 1; taskId <= 100; taskId++) {
        for (var offset = 0; offset < defaultReminderHorizonDays; offset++) {
          ids.add(
            AppNotifications.reminderIdFor(
              taskId,
              DateTime(2026, 5, 20 + offset),
            ),
          );
        }
      }

      expect(ids, hasLength(100 * defaultReminderHorizonDays));
    });

    test('the same task and day always map to the same id', () {
      expect(
        AppNotifications.reminderIdFor(7, _day),
        AppNotifications.reminderIdFor(7, _day),
      );
    });
  });
}
