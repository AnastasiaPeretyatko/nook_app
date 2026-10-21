import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/task_audience.dart';

/// A group task "for everyone" is one shared task: the first member to tick it
/// closes it for all.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const me = 'aaaaaaaa-0000-0000-0000-000000000000';
  const other = 'bbbbbbbb-0000-0000-0000-000000000000';
  final day = DateTime(2026, 10, 16);

  late AppDatabase db;
  late TasksDao dao;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    dao = db.tasksDao;
  });
  tearDown(() => db.close());

  Future<int> groupTask({String? assignee}) => dao.insertTask(
    TasksCompanion.insert(
      title: 'общая',
      groupUid: const Value('g1'),
      authorUid: const Value(me),
      assigneeUid: Value(assignee),
      startDate: Value(day),
    ),
  );

  Future<void> otherTicks(int taskId, {bool completed = true}) =>
      dao.applyGroupMark(
        taskId: taskId,
        userUid: other,
        date: day,
        completed: completed,
      );

  group('the ticks of the others count as done', () {
    test(
      'a stand-in log appears, and goes when they take the tick back',
      () async {
        final id = await groupTask();
        await otherTicks(id);
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        addTearDown(container.dispose);
        container.listen(allLogsProvider, (_, _) {});
        container.listen(allTasksProvider, (_, _) {});
        container.listen(groupMarksProvider, (_, _) {});

        Future<List<TaskLog>> logs() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return container.read(allLogsProvider).requireValue;
        }

        final done = await logs();
        expect(done.single.taskId, id);
        expect(done.single.completed, isTrue);

        await otherTicks(id, completed: false);
        expect(await logs(), isEmpty);
      },
    );

    test('not for a task handed to one member, nor on another day', () async {
      final assigned = await groupTask(assignee: me);
      final shared = await groupTask();
      await otherTicks(assigned);
      await dao.applyGroupMark(
        taskId: shared,
        userUid: other,
        date: day.add(const Duration(days: 1)),
        completed: true,
      );
      final tasks = await dao.watchAllTasks().first;
      final marks = await dao.watchGroupMarks().first;
      expect(withSharedTicks(const [], tasks, marks), isEmpty);
    });
  });

  group('ticking', () {
    test('is refused once another member has ticked it', () async {
      final id = await groupTask();
      await otherTicks(id);
      await dao.toggleCompletion(id, day);
      expect(await dao.getLogForDate(id, day), isNull);
    });

    test('works while nobody has, and again if they take it back', () async {
      final id = await groupTask();
      await otherTicks(id);
      await otherTicks(id, completed: false);
      await dao.toggleCompletion(id, day);
      expect((await dao.getLogForDate(id, day))!.completed, isTrue);
    });

    test('my own tick can still be taken back', () async {
      final id = await groupTask();
      await dao.toggleCompletion(id, day);
      await otherTicks(id);
      await dao.toggleCompletion(id, day);
      expect((await dao.getLogForDate(id, day))!.completed, isFalse);
    });

    test(
      'a task handed to me is mine to tick whatever the others did',
      () async {
        final id = await groupTask(assignee: me);
        await otherTicks(id);
        await dao.toggleCompletion(id, day);
        expect((await dao.getLogForDate(id, day))!.completed, isTrue);
      },
    );
  });
}
