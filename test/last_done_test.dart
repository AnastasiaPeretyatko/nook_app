import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/overdue.dart';
import 'package:todo_app/utils/recurrence.dart';

/// Any moment at all: these tests never read a log's edit time.
final _stamp = DateTime(2026, 1, 1);

final _today = DateTime(2026, 10, 8);

TaskLog _log(int taskId, DateTime date, {bool completed = true}) => TaskLog(
  dirty: false,
  updatedAt: _stamp,
  id: 0,
  taskId: taskId,
  date: date,
  completed: completed,
);

Task _task({
  TrackingMode mode = TrackingMode.value,
  DateTime? startDate,
  RepeatType? repeatType,
}) => Task(
  dirty: false,
  id: 1,
  title: 'Смена белья',
  status: TaskStatus.active,
  repeatType: repeatType,
  trackingMode: mode,
  startDate: startDate ?? DateTime(2026, 9, 1),
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
);

void main() {
  group('lastDoneByTask', () {
    test('keeps the latest marked day of each task', () {
      final latest = lastDoneByTask([
        _log(1, DateTime(2026, 9, 20)),
        _log(1, DateTime(2026, 10, 3)),
        _log(1, DateTime(2026, 9, 28)),
        _log(2, DateTime(2026, 8, 1)),
      ]);

      expect(latest, {1: DateTime(2026, 10, 3), 2: DateTime(2026, 8, 1)});
    });

    test('a mark taken back is not a day it was done', () {
      final latest = lastDoneByTask([
        _log(1, DateTime(2026, 9, 20)),
        // Undone: the row stays (a log is never deleted on its own) but says no.
        _log(1, DateTime(2026, 10, 3), completed: false),
      ]);

      expect(latest, {1: DateTime(2026, 9, 20)});
    });

    test('a task never marked is simply absent', () {
      expect(
        lastDoneByTask([_log(1, DateTime(2026, 10, 3), completed: false)]),
        isEmpty,
      );
      expect(lastDoneByTask(const []), isEmpty);
    });

    test('reads the day and not the moment', () {
      final latest = lastDoneByTask([_log(1, DateTime(2026, 10, 3, 17, 45))]);
      expect(latest[1], DateTime(2026, 10, 3));
    });
  });

  group('daysSince', () {
    test('counts whole days', () {
      expect(daysSince(DateTime(2026, 10, 8), _today), 0);
      expect(daysSince(DateTime(2026, 10, 7), _today), 1);
      expect(daysSince(DateTime(2026, 9, 8), _today), 30);
    });

    test('is not thrown by a day that is 23 or 25 hours long', () {
      // Clocks change on these nights in the zones that observe it; the count
      // is taken between calendar dates, so the length of the night is moot.
      expect(daysSince(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(daysSince(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
      expect(daysSince(DateTime(2026, 10, 31), DateTime(2026, 11, 2)), 2);
    });

    test('never goes negative', () {
      expect(daysSince(DateTime(2026, 10, 20), _today), 0);
    });
  });

  group('lastDoneLabel', () {
    String label(DateTime? lastDone) => lastDoneLabel(lastDone, today: _today);

    test('names the near days', () {
      expect(label(DateTime(2026, 10, 8)), 'Сегодня');
      expect(label(DateTime(2026, 10, 7)), 'Вчера');
    });

    test('declines the day count', () {
      expect(label(DateTime(2026, 10, 6)), '2 дня назад');
      expect(label(DateTime(2026, 10, 3)), '5 дней назад');
      expect(label(DateTime(2026, 9, 27)), '11 дней назад');
      expect(label(DateTime(2026, 9, 17)), '21 день назад');
      expect(label(DateTime(2026, 9, 16)), '22 дня назад');
    });

    test('a task never marked has no count to give', () {
      expect(label(null), 'Нет отметок');
    });
  });

  group('markedDaysNewestFirst', () {
    test('lists one task, once per day, newest first', () {
      final days = markedDaysNewestFirst([
        _log(1, DateTime(2026, 9, 20)),
        _log(2, DateTime(2026, 10, 1)),
        _log(1, DateTime(2026, 10, 3)),
        _log(1, DateTime(2026, 10, 1), completed: false),
      ], 1);

      expect(days, [DateTime(2026, 10, 3), DateTime(2026, 9, 20)]);
    });
  });

  group('a "Значение" task is on no day', () {
    test('it is recognised by its mode alone', () {
      expect(isValueTask(_task()), isTrue);
      expect(isValueTask(_task(mode: TrackingMode.checkbox)), isFalse);
      expect(isValueTask(_task(mode: TrackingMode.counter)), isFalse);
    });

    test('so it is scheduled nowhere, neither on its start date nor after', () {
      final value = _task();
      expect(isTaskScheduledOn(value, DateTime(2026, 9, 1)), isFalse);
      expect(isTaskScheduledOn(value, DateTime(2026, 9, 2)), isFalse);
      expect(isTaskScheduledOn(value, _today), isFalse);

      // The same row as a plain one-off task is on its start date: the mode is
      // the whole difference.
      expect(
        isTaskScheduledOn(
          _task(mode: TrackingMode.checkbox),
          DateTime(2026, 9, 1),
        ),
        isTrue,
      );
    });

    test('it is never overdue, however long ago it started', () {
      expect(isTaskOverdue(_task(), completed: false, today: _today), isFalse);
      expect(
        isTaskOverdue(
          _task(mode: TrackingMode.checkbox),
          completed: false,
          today: _today,
        ),
        isTrue,
      );
    });
  });

  group('how little it writes', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forExecutor(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('a row appears when a day is marked, and not before', () async {
      final id = await db.tasksDao.insertTask(
        TasksCompanion.insert(
          title: 'Смена белья',
          trackingMode: const Value(TrackingMode.value),
          startDate: Value(DateTime(2026, 9, 1)),
        ),
      );

      // Created, and then weeks go by: nothing is written for any of them.
      expect(await db.select(db.taskLogs).get(), isEmpty);

      await db.tasksDao.setLog(id, DateTime(2026, 9, 20), completed: true);
      final logs = await db.select(db.taskLogs).get();
      expect(logs, hasLength(1));
      expect(lastDoneByTask(logs), {id: DateTime(2026, 9, 20)});
    });

    test('marking the same day twice is still one row', () async {
      final id = await db.tasksDao.insertTask(
        TasksCompanion.insert(
          title: 'Смена белья',
          trackingMode: const Value(TrackingMode.value),
        ),
      );

      await db.tasksDao.setLog(id, DateTime(2026, 9, 20), completed: true);
      await db.tasksDao.setLog(
        id,
        DateTime(2026, 9, 20, 18, 30),
        completed: true,
      );

      expect(await db.select(db.taskLogs).get(), hasLength(1));
    });

    test('taking a mark back moves "last done" to the one before', () async {
      final id = await db.tasksDao.insertTask(
        TasksCompanion.insert(
          title: 'Смена белья',
          trackingMode: const Value(TrackingMode.value),
        ),
      );
      await db.tasksDao.setLog(id, DateTime(2026, 9, 12), completed: true);
      await db.tasksDao.setLog(id, DateTime(2026, 9, 20), completed: true);
      await db.tasksDao.setLog(id, DateTime(2026, 9, 20), completed: false);

      final logs = await db.select(db.taskLogs).get();
      expect(lastDoneByTask(logs), {id: DateTime(2026, 9, 12)});
    });
  });
}
