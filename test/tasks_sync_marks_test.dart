import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';

/// The marks tasks and their day marks leave so that a sync can tell what
/// changed: a `uid` to be known by, a `dirty` flag for "changed here", and a
/// tombstone for the one edit that otherwise leaves nothing behind.
///
/// Nothing here touches a network — that is the whole point of putting the marks
/// in the DAO. What is being pinned is the asymmetry: a write the *user* made is
/// dirty, a write the *server* sent is not.
///
/// The twin of `diary_sync_marks_test.dart`, and the interesting differences are
/// all about the logs: they carry no `uid`, they leave no tombstone, and their
/// day is folded to midnight on the way in.
void main() {
  late AppDatabase db;
  late TasksDao dao;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    dao = db.tasksDao;
  });

  tearDown(() => db.close());

  final day = DateTime(2026, 8, 26);

  Future<int> addTask(String title, {int? parentId}) => dao.insertTask(
    TasksCompanion.insert(title: title, parentId: Value(parentId)),
  );

  Future<Task> task(int id) async => (await dao.getTaskById(id))!;
  Future<TaskLog> log(int taskId, DateTime on) async =>
      (await dao.getLogForDate(taskId, on))!;

  group('what the user writes', () {
    test('a new task is given a uid and starts out unsent', () async {
      final saved = await task(await addTask('Зарядка'));

      expect(saved.uid, isNotNull);
      expect(saved.uid, isNotEmpty);
      expect(saved.dirty, isTrue);
    });

    test('two tasks do not share a uid', () async {
      final first = await task(await addTask('Одна'));
      final second = await task(await addTask('Другая'));

      expect(first.uid, isNot(second.uid));
    });

    test('a subtask gets its own uid, not its parent’s', () async {
      // It is a row of its own on the server, and the server would never learn
      // about it from anything said about the parent.
      final parentId = await addTask('Уборка');
      final childId = await addTask('Пыль', parentId: parentId);

      expect((await task(childId)).uid, isNot((await task(parentId)).uid));
    });

    test('an edit marks the task unsent again and moves its stamp', () async {
      final id = await addTask('Зарядка');
      final before = await task(id);
      await dao.clearTaskDirty({before.uid!: DateTime.now()});
      expect((await task(id)).dirty, isFalse);

      await dao.updateTaskById(id, const TasksCompanion(title: Value('Бег')));
      final after = await task(id);

      expect(after.dirty, isTrue);
      expect(after.updatedAt.isBefore(before.updatedAt), isFalse);
    });

    test('archiving a habit is an edit like any other', () async {
      // `setTaskStatus` funnels through `updateTaskById`, which is the single
      // place the mark is stamped — so shelving a habit is not a way past it.
      final id = await addTask('Зарядка');
      await dao.clearTaskDirty({(await task(id)).uid!: DateTime.now()});

      await dao.setTaskStatus(id, TaskStatus.archived);

      expect((await task(id)).dirty, isTrue);
    });
  });

  group('the day marks', () {
    test('ticking a day marks it unsent and stamps it', () async {
      final id = await addTask('Зарядка');
      await dao.toggleCompletion(id, day);
      final marked = await log(id, day);

      expect(marked.completed, isTrue);
      expect(marked.dirty, isTrue);
      // Not the column's epoch default: the row has been written by hand.
      expect(marked.updatedAt.year, greaterThan(2000));
    });

    test('a second tick moves the stamp forward', () async {
      final id = await addTask('Зарядка');
      await dao.toggleCompletion(id, day);
      final first = await log(id, day);
      await dao.clearLogDirty([first]);
      expect((await log(id, day)).dirty, isFalse);

      await dao.toggleCompletion(id, day);
      final second = await log(id, day);

      expect(second.completed, isFalse);
      expect(second.dirty, isTrue);
      // Strictly greater, even inside one second: `clearLogDirty` decides
      // whether an edit happened during a send by comparing exactly this, and
      // equal stamps would clear a mark covering an edit nobody has sent.
      expect(second.updatedAt.isAfter(first.updatedAt), isTrue);
    });

    test('a counter step marks the day too', () async {
      final id = await addTask('Вода');
      await dao.incrementCounter(id, day, 8);
      final marked = await log(id, day);

      expect(marked.value, 1);
      expect(marked.dirty, isTrue);
    });

    test('an instant is folded onto its day', () async {
      // `HomePage` opens on `DateTime.now()`, so the timeline can hand over a
      // moment rather than a day. Before v14 that moment went into the column as
      // it was, and the unique index over `(taskId, date)` would then have been
      // describing something it does not.
      final id = await addTask('Зарядка');
      await dao.toggleCompletion(
        id,
        day.add(const Duration(hours: 14, minutes: 32)),
      );

      final rows = await db.select(db.taskLogs).get();
      expect(rows, hasLength(1));
      expect(rows.single.date, day);
    });

    test('two ticks of the same day are one row, whatever the time', () async {
      final id = await addTask('Зарядка');
      await dao.toggleCompletion(id, day.add(const Duration(hours: 9)));
      await dao.setLog(id, day.add(const Duration(hours: 21)), value: 3);

      final rows = await db.select(db.taskLogs).get();
      expect(rows, hasLength(1));
      expect(rows.single.completed, isTrue);
      expect(rows.single.value, 3);
    });

    test('clearing a mark ignores a row edited since it was read', () async {
      final id = await addTask('Зарядка');
      await dao.toggleCompletion(id, day);
      final sent = await log(id, day);

      // The send is in flight and the user ticks again.
      await dao.toggleCompletion(id, day);
      await dao.clearLogDirty([sent]);

      // Still unsent: what went up is not what is here any more.
      expect((await log(id, day)).dirty, isTrue);
    });
  });

  group('deleting', () {
    test('leaves a tombstone for the task and for every subtask', () async {
      final parentId = await addTask('Уборка');
      final firstChild = await addTask('Пыль', parentId: parentId);
      final secondChild = await addTask('Пол', parentId: parentId);
      final uids = {
        (await task(parentId)).uid,
        (await task(firstChild)).uid,
        (await task(secondChild)).uid,
      };

      await dao.deleteTaskCascade(parentId);

      final graves = await db.select(db.syncTombstones).get();
      expect(graves.map((g) => g.uid).toSet(), uids);
      expect(graves.map((g) => g.sourceTable).toSet(), {'tasks'});
    });

    test('leaves none for the logs', () async {
      // A log's disappearance is always already told by its task's: the one
      // statement in the app that deletes any deletes every log of one task, and
      // on the server the same fact is a foreign key.
      final id = await addTask('Зарядка');
      await dao.toggleCompletion(id, day);

      await dao.deleteTaskCascade(id);

      final graves = await db.select(db.syncTombstones).get();
      expect(graves, hasLength(1));
      expect(await db.select(db.taskLogs).get(), isEmpty);
    });

    test('a deletion the server sent takes a running timer with it', () async {
      // The reachable version of this: a timer going on this phone while the
      // task is deleted on another. `task_sessions` does not sync — an open
      // session *is* one device's live state — so the row can only go when the
      // deletion arrives, and both delete paths share `_deleteCascade`.
      final id = await addTask('Медитация');
      final uid = (await task(id)).uid!;
      await dao.startTimer(id, DateTime(2026, 8, 26, 9), targetSeconds: 600);
      expect(await dao.getOpenSession(id), isNotNull);

      await dao.deleteTaskByUid(uid);

      expect(await db.select(db.taskSessions).get(), isEmpty);
    });

    test('a deletion the server sent leaves no tombstone', () async {
      // The whole difference between the two paths. A tombstone for a deletion
      // this device is merely *learning about* would be sent back as news.
      final parentId = await addTask('Уборка');
      await addTask('Пыль', parentId: parentId);
      final uid = (await task(parentId)).uid!;

      final removed = await dao.deleteTaskByUid(uid);

      expect(removed, isTrue);
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(await db.select(db.syncTombstones).get(), isEmpty);
    });

    test('forgetting a deletion the server was told about', () async {
      final id = await addTask('Зарядка');
      final uid = (await task(id)).uid!;
      await dao.deleteTaskCascade(id);

      await db.diaryDao.clearTombstones([uid]);

      expect(await db.select(db.syncTombstones).get(), isEmpty);
    });
  });

  group('what the server sends', () {
    test('a task that arrives is not marked unsent', () async {
      await dao.insertRemoteTask(
        'remote-uid',
        TasksCompanion.insert(title: 'С сервера'),
      );

      final saved = await dao.taskByUid('remote-uid');
      expect(saved, isNotNull);
      expect(saved!.dirty, isFalse);
      expect(saved.uid, 'remote-uid');
    });

    test('an overwrite from the server does not mark the task', () async {
      final id = await addTask('Своё');
      final uid = (await task(id)).uid!;

      final applied = await dao.applyRemoteTask(
        uid,
        TasksCompanion(title: const Value('С сервера')),
      );

      expect(applied, isTrue);
      final saved = await task(id);
      expect(saved.title, 'С сервера');
      expect(saved.dirty, isFalse);
    });

    test('applyRemoteTask reports a task this device has never seen', () async {
      // False is how the engine knows to insert instead — only it can turn a
      // parent's uid into a local id.
      expect(
        await dao.applyRemoteTask('nobody', const TasksCompanion()),
        isFalse,
      );
    });

    test('a day mark that arrives is not marked unsent', () async {
      final id = await addTask('Зарядка');

      await dao.applyRemoteLog(
        id,
        TaskLogsCompanion(
          date: Value(day),
          completed: const Value(true),
          updatedAt: Value(DateTime(2026, 8, 26, 12)),
        ),
      );

      final marked = await log(id, day);
      expect(marked.completed, isTrue);
      expect(marked.dirty, isFalse);
    });

    test('a day mark from the server updates rather than duplicates', () async {
      // The point of the unique index and of resolving on the pair: without them
      // the same day would arrive as a second row and `getLogForDate` would
      // start throwing.
      final id = await addTask('Зарядка');
      await dao.toggleCompletion(id, day);

      await dao.applyRemoteLog(
        id,
        TaskLogsCompanion(
          date: Value(day),
          completed: const Value(false),
          value: const Value(5),
          updatedAt: Value(DateTime(2026, 8, 26, 12)),
        ),
      );

      final rows = await db.select(db.taskLogs).get();
      expect(rows, hasLength(1));
      expect(rows.single.completed, isFalse);
      expect(rows.single.value, 5);
      expect(rows.single.dirty, isFalse);
    });
  });

  group('the first-sync answer', () {
    test('"do not upload" clears every mark and every tombstone', () async {
      final keptId = await addTask('Останется');
      await dao.toggleCompletion(keptId, day);
      final goneId = await addTask('Удалённая');
      await dao.deleteTaskCascade(goneId);

      await dao.keepExistingTasksLocal();

      expect((await task(keptId)).dirty, isFalse);
      expect((await log(keptId, day)).dirty, isFalse);
      expect(await db.select(db.syncTombstones).get(), isEmpty);
      expect(await dao.pendingTasks(), isEmpty);
      expect(await dao.pendingLogs(), isEmpty);
    });

    test('the count is of root tasks, which is what the user can see', () async {
      final parentId = await addTask('Уборка');
      await addTask('Пыль', parentId: parentId);
      await addTask('Зарядка');

      // Three rows are unsent and all three go up; two are things on a screen.
      expect(await dao.pendingTasks(), hasLength(3));
      expect(await dao.unsentTaskCount(), 2);
    });
  });

  group('the uid map a push works through', () {
    test('answers for every task that has one', () async {
      final parentId = await addTask('Уборка');
      final childId = await addTask('Пыль', parentId: parentId);

      final uids = await dao.taskUidsById();

      expect(uids[parentId], (await task(parentId)).uid);
      expect(uids[childId], (await task(childId)).uid);
    });
  });
}
