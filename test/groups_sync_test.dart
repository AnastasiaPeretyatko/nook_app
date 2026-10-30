import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/sync/payload.dart';

/// Groups on the device: the v16 migration, the mirror the sync writes, and
/// what group tasks change about uploading, adopting and wiping.
///
/// The server half — who may see and write what — is the server's (BACKEND_PLAN.md §4.3, its own tests);
/// nothing here can stand in for it.
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

  TaskGroupsCompanion aGroup(String uid, {String owner = me}) =>
      TaskGroupsCompanion.insert(uid: uid, name: 'Семья', ownerUid: owner);

  Future<int> groupTask(String groupUid, {String author = me}) =>
      dao.insertTask(
        TasksCompanion.insert(
          title: 'общая',
          groupUid: Value(groupUid),
          authorUid: Value(author),
        ),
      );

  group('the mirror of groups', () {
    test('a group no longer listed takes its tasks and marks along', () async {
      await dao.replaceGroups([aGroup('g1'), aGroup('g2')], []);
      final personal = await dao.insertTask(
        TasksCompanion.insert(title: 'моя'),
      );
      final kept = await groupTask('g1');
      final dropped = await groupTask('g2');
      await dao.toggleCompletion(dropped, day);
      await dao.applyGroupMark(
        taskId: dropped,
        userUid: other,
        date: day,
        completed: true,
      );

      await dao.replaceGroups([aGroup('g1')], []);

      final ids = [for (final t in await dao.select(db.tasks).get()) t.id];
      expect(ids, unorderedEquals([personal, kept]));
      expect(await dao.select(db.taskLogs).get(), isEmpty);
      expect(await dao.select(db.groupMarks).get(), isEmpty);
      // Learning of a departure is not news to tell anyone.
      expect(await dao.select(db.syncTombstones).get(), isEmpty);
    });

    test('members are replaced, not accumulated', () async {
      await dao.replaceGroups(
        [aGroup('g1')],
        [
          GroupMembersCompanion.insert(groupUid: 'g1', userUid: me),
          GroupMembersCompanion.insert(groupUid: 'g1', userUid: other),
        ],
      );
      await dao.replaceGroups(
        [aGroup('g1')],
        [GroupMembersCompanion.insert(groupUid: 'g1', userUid: me)],
      );
      final members = await dao.select(db.groupMembers).get();
      expect([for (final m in members) m.userUid], [me]);
    });
  });

  group('who may edit', () {
    test('a personal task, the author and the owner — nobody else', () async {
      await dao.replaceGroups([aGroup('g1', owner: other)], []);
      final personal = await dao.getTaskById(
        await dao.insertTask(TasksCompanion.insert(title: 'моя')),
      );
      final mine = await dao.getTaskById(await groupTask('g1'));
      final theirs = await dao.getTaskById(
        await groupTask('g1', author: other),
      );

      expect(await dao.canEditTask(personal!, me), isTrue);
      expect(await dao.canEditTask(mine!, me), isTrue);
      expect(await dao.canEditTask(theirs!, me), isFalse);
      // `other` owns the group, so may edit what `me` wrote.
      expect(await dao.canEditTask(mine, other), isTrue);
    });
  });

  group("other members' marks", () {
    test('one row per member and day, never in task_logs', () async {
      await dao.replaceGroups([aGroup('g1')], []);
      final task = await groupTask('g1');
      for (final completed in [true, false]) {
        await dao.applyGroupMark(
          taskId: task,
          userUid: other,
          date: day.add(const Duration(hours: 14)),
          completed: completed,
        );
      }
      final marks = await dao.select(db.groupMarks).get();
      expect(marks, hasLength(1));
      expect(marks.single.completed, isFalse);
      expect(marks.single.date, day);
      expect(await dao.getLogForDate(task, day), isNull);
    });

    test('a task deleted from the server takes them along', () async {
      await dao.replaceGroups([aGroup('g1')], []);
      final task = await groupTask('g1');
      await dao.applyGroupMark(
        taskId: task,
        userUid: other,
        date: day,
        completed: true,
      );
      final uid = (await dao.getTaskById(task))!.uid!;
      await dao.deleteTaskByUid(uid);
      expect(await dao.select(db.groupMarks).get(), isEmpty);
    });
  });

  group('changing accounts', () {
    test('the first-sync counts leave group tasks out', () async {
      await dao.replaceGroups([aGroup('g1')], []);
      await dao.insertTask(TasksCompanion.insert(title: 'моя'));
      await groupTask('g1');
      expect(await dao.taskCount(), 1);
      expect(await dao.unsentTaskCount(), 1);
    });

    test('adopting keeps personal tasks and drops the groups', () async {
      await dao.replaceGroups(
        [aGroup('g1')],
        [GroupMembersCompanion.insert(groupUid: 'g1', userUid: me)],
      );
      await dao.insertTask(TasksCompanion.insert(title: 'моя'));
      await groupTask('g1');

      await dao.remintTaskUids();

      final left = await dao.select(db.tasks).get();
      expect([for (final t in left) t.title], ['моя']);
      expect(await dao.select(db.taskGroups).get(), isEmpty);
      expect(await dao.select(db.groupMembers).get(), isEmpty);
    });

    test('wiping removes the groups too', () async {
      await dao.replaceGroups([aGroup('g1')], []);
      final task = await groupTask('g1');
      await dao.applyGroupMark(
        taskId: task,
        userUid: other,
        date: day,
        completed: true,
      );
      await dao.wipeAllTasks();
      expect(await dao.select(db.taskGroups).get(), isEmpty);
      expect(await dao.select(db.groupMarks).get(), isEmpty);
      expect(await dao.select(db.tasks).get(), isEmpty);
    });
  });

  group('payload', () {
    test('a group task goes up with its group and assignee', () async {
      await dao.replaceGroups([aGroup('g1')], []);
      final id = await dao.insertTask(
        TasksCompanion.insert(
          title: 'общая',
          groupUid: const Value('g1'),
          assigneeUid: const Value(other),
          authorUid: const Value(me),
        ),
      );
      final row = taskToRow((await dao.getTaskById(id))!);
      expect(row['group_id'], 'g1');
      expect(row['assignee_id'], other);
      expect(row.containsKey('user_id'), isFalse);
    });

    test('the author is kept for a group task only', () {
      final base = {'id': 't', 'title': 'x', 'user_id': other};
      expect(taskFromRow(base).authorUid.value, isNull);
      final shared = taskFromRow({...base, 'group_id': 'g1'});
      expect(shared.authorUid.value, other);
      expect(shared.groupUid.value, 'g1');
    });
  });

  test('a v15 device with tasks upgrades to v16', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('nook_v16').path}/db.sqlite',
    );
    final current = AppDatabase.forExecutor(NativeDatabase(file));
    await current.tasksDao.insertTask(TasksCompanion.insert(title: 'старая'));
    // Back to what v15 left: no group columns, no group tables.
    for (final statement in [
      'DROP TABLE task_groups',
      'DROP TABLE group_members',
      'DROP TABLE group_marks',
      for (final column in ['group_uid', 'assignee_uid', 'author_uid'])
        'ALTER TABLE tasks DROP COLUMN $column',
      'PRAGMA user_version = 15',
    ]) {
      await current.customStatement(statement);
    }
    await current.close();

    final upgraded = AppDatabase.forExecutor(NativeDatabase(file));
    addTearDown(upgraded.close);
    final tasks = await upgraded.select(upgraded.tasks).get();
    expect(tasks.single.title, 'старая');
    expect(tasks.single.groupUid, isNull);
    await upgraded.tasksDao.replaceGroups([aGroup('g1')], []);
    expect(await upgraded.select(upgraded.taskGroups).get(), hasLength(1));
  });
}
