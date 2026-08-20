import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';

void main() {
  late AppDatabase db;
  late TasksDao dao;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    dao = db.tasksDao;
  });

  tearDown(() => db.close());

  Future<int> addTask(String title, {int? parentId}) {
    return dao.insertTask(
      TasksCompanion.insert(title: title, parentId: Value(parentId)),
    );
  }

  test('deleteTaskCascade removes subtasks, logs and sessions', () async {
    final parentId = await addTask('Parent');
    final subId = await addTask('Sub', parentId: parentId);
    final otherId = await addTask('Unrelated');

    await dao.toggleCompletion(parentId, DateTime(2026, 1, 1));
    await dao.toggleCompletion(subId, DateTime(2026, 1, 1));
    await dao.toggleCompletion(otherId, DateTime(2026, 1, 1));
    await dao.insertSession(
      TaskSessionsCompanion.insert(taskId: parentId, startedAt: DateTime.now()),
    );

    await dao.deleteTaskCascade(parentId);

    expect(await dao.getTaskById(parentId), isNull);
    expect(await dao.getTaskById(subId), isNull);
    expect(await dao.getTaskById(otherId), isNotNull);

    final logs = await dao.watchAllLogs().first;
    expect(logs.map((l) => l.taskId), [otherId]);

    final parentSessions = await dao.watchSessionsForTask(parentId).first;
    expect(parentSessions, isEmpty);
  });

  test('copySubtasks duplicates children without completion history', () async {
    final sourceId = await addTask('Source');
    await addTask('Child A', parentId: sourceId);
    await addTask('Child B', parentId: sourceId);
    await dao.toggleCompletion(sourceId, DateTime(2026, 1, 1));

    final cloneId = await addTask('Source (копия)');
    await dao.copySubtasks(fromTaskId: sourceId, toTaskId: cloneId);

    final clonedChildren = await dao.watchSubtasks(cloneId).first;
    expect(clonedChildren.map((t) => t.title), ['Child A', 'Child B']);

    // Original children are untouched.
    final sourceChildren = await dao.watchSubtasks(sourceId).first;
    expect(sourceChildren.length, 2);

    // Clone has no logs copied.
    final cloneLogs = await dao.getLogForDate(cloneId, DateTime(2026, 1, 1));
    expect(cloneLogs, isNull);
  });

  test('toggleCompletion on adjacent days is independent', () async {
    final id = await addTask('Habit');
    final d1 = DateTime(2026, 1, 1);
    final d2 = DateTime(2026, 1, 2);

    await dao.toggleCompletion(id, d1);
    await dao.toggleCompletion(id, d2);

    // Both days marked, each has exactly one log (no boundary bleed / crash).
    expect((await dao.getLogForDate(id, d1))!.completed, isTrue);
    expect((await dao.getLogForDate(id, d2))!.completed, isTrue);

    // Unmarking one day does not touch the neighbour.
    await dao.toggleCompletion(id, d1);
    expect((await dao.getLogForDate(id, d1))!.completed, isFalse);
    expect((await dao.getLogForDate(id, d2))!.completed, isTrue);
  });

  test('updateTaskById clears optional fields with explicit null', () async {
    final id = await dao.insertTask(
      TasksCompanion.insert(
        title: 'With desc',
        description: const Value('some details'),
        startDate: Value(DateTime(2026, 5, 1)),
      ),
    );

    await dao.updateTaskById(
      id,
      TasksCompanion(
        title: const Value('No desc'),
        description: const Value(null),
        startDate: const Value(null),
      ),
    );

    final updated = await dao.getTaskById(id);
    expect(updated!.title, 'No desc');
    expect(updated.description, isNull);
    expect(updated.startDate, isNull);
  });

  group('timer runs', () {
    // A fixed clock: the DAO never reads the time itself, every call is handed
    // the instant it should treat as "now".
    final day = DateTime(2026, 5, 20);
    DateTime at(int minute, [int second = 0]) =>
        DateTime(2026, 5, 20, 10, minute, second);

    const target = 600; // ten minutes

    Future<int> addTimerTask() => dao.insertTask(
      TasksCompanion.insert(
        title: 'Медитация',
        trackingMode: const Value(TrackingMode.timer),
        targetDurationMinutes: const Value(10),
        startDate: Value(day),
      ),
    );

    test('starting opens a session and banks nothing yet', () async {
      final id = await addTimerTask();
      await dao.startTimer(id, at(0), targetSeconds: target);

      final open = await dao.getOpenSession(id);
      expect(open, isNotNull);
      expect(open!.startedAt, at(0));
      expect(open.endedAt, isNull);
      expect(await dao.getLogForDate(id, day), isNull);
    });

    test('stopping closes the run and banks its seconds', () async {
      final id = await addTimerTask();
      await dao.startTimer(id, at(0), targetSeconds: target);
      await dao.stopTimer(id, at(1, 30), targetSeconds: target);

      expect(await dao.getOpenSession(id), isNull);
      final log = await dao.getLogForDate(id, day);
      expect(log!.value, 90);
      expect(log.completed, isFalse);

      final sessions = await dao.watchSessionsForTask(id).first;
      expect(sessions.single.durationSeconds, 90);
      expect(sessions.single.endedAt, at(1, 30));
    });

    test('a second run adds to the first', () async {
      final id = await addTimerTask();
      await dao.startTimer(id, at(0), targetSeconds: target);
      await dao.stopTimer(id, at(1), targetSeconds: target);
      await dao.startTimer(id, at(5), targetSeconds: target);
      await dao.stopTimer(id, at(7), targetSeconds: target);

      final log = await dao.getLogForDate(id, day);
      expect(log!.value, 180);
      expect(log.completed, isFalse);
    });

    test('reaching the target ticks the day and caps the value', () async {
      final id = await addTimerTask();
      await dao.startTimer(id, at(0), targetSeconds: target);
      // Ran two minutes past the ten it needed.
      await dao.stopTimer(id, at(12), targetSeconds: target);

      final log = await dao.getLogForDate(id, day);
      expect(log!.value, target);
      expect(log.completed, isTrue);
    });

    test('pausing does not clear a day already marked done by hand', () async {
      final id = await addTimerTask();
      await dao.setLog(id, day, completed: true);

      await dao.startTimer(id, at(0), targetSeconds: target);
      await dao.stopTimer(id, at(1), targetSeconds: target);

      final log = await dao.getLogForDate(id, day);
      expect(
        log!.completed,
        isTrue,
        reason: 'a short run must not undo a tick',
      );
      expect(log.value, 60);
    });

    test('a run left open is banked by the next start, not lost', () async {
      final id = await addTimerTask();
      // The app died here without ever closing the run.
      await dao.startTimer(id, at(0), targetSeconds: target);
      await dao.startTimer(id, at(3), targetSeconds: target);

      final log = await dao.getLogForDate(id, day);
      expect(log!.value, 180);

      final open = await dao.getOpenSession(id);
      expect(open!.startedAt, at(3), reason: 'the new run is the open one');

      final closed = (await dao.watchSessionsForTask(id).first).where(
        (s) => s.endedAt != null,
      );
      expect(closed.single.durationSeconds, 180);
    });

    test('a run is banked against the day it began on', () async {
      final id = await addTimerTask();
      final lateNight = DateTime(2026, 5, 20, 23, 55);
      final afterMidnight = DateTime(2026, 5, 21, 0, 2);

      await dao.startTimer(id, lateNight, targetSeconds: target);
      await dao.stopTimer(id, afterMidnight, targetSeconds: target);

      expect((await dao.getLogForDate(id, day))!.value, 420);
      expect(await dao.getLogForDate(id, DateTime(2026, 5, 21)), isNull);
    });

    test('a clock that moved backwards banks zero, not negative', () async {
      final id = await addTimerTask();
      await dao.startTimer(id, at(5), targetSeconds: target);
      await dao.stopTimer(id, at(2), targetSeconds: target);

      final log = await dao.getLogForDate(id, day);
      expect(log!.value, 0);
      expect(log.completed, isFalse);
    });

    test('stopping with nothing running does nothing', () async {
      final id = await addTimerTask();
      await dao.stopTimer(id, at(1), targetSeconds: target);

      expect(await dao.getLogForDate(id, day), isNull);
      expect(await dao.watchSessionsForTask(id).first, isEmpty);
    });

    test('one habit\'s run does not touch another\'s', () async {
      final a = await addTimerTask();
      final b = await addTimerTask();

      await dao.startTimer(a, at(0), targetSeconds: target);
      await dao.stopTimer(a, at(1), targetSeconds: target);

      expect((await dao.getLogForDate(a, day))!.value, 60);
      expect(await dao.getLogForDate(b, day), isNull);
      expect(await dao.getOpenSession(b), isNull);
    });

    test('open sessions stream carries only the running ones', () async {
      final a = await addTimerTask();
      final b = await addTimerTask();

      await dao.startTimer(a, at(0), targetSeconds: target);
      await dao.startTimer(b, at(0), targetSeconds: target);
      await dao.stopTimer(a, at(1), targetSeconds: target);

      final open = await dao.watchOpenSessions().first;
      expect(open.map((s) => s.taskId), [b]);
    });
  });
}
