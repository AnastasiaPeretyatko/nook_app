import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/sync/payload.dart';

/// `task_logs.completedAt`: when a day was ticked. Stamped on the tick, cleared
/// on the untick, kept while the day stays ticked, and carried by the sync.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final day = DateTime(2026, 10, 16);

  late AppDatabase db;
  late TasksDao dao;
  late int taskId;

  setUp(() async {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    dao = db.tasksDao;
    taskId = await dao.insertTask(TasksCompanion.insert(title: 'зарядка'));
  });
  tearDown(() => db.close());

  Future<TaskLog> log() async => (await dao.getLogForDate(taskId, day))!;

  test('a tick stamps the moment and an untick clears it', () async {
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    await dao.toggleCompletion(taskId, day);
    final ticked = await log();
    expect(ticked.completedAt, isNotNull);
    expect(ticked.completedAt!.isAfter(before), isTrue);
    expect(ticked.date, day, reason: 'the day stays a day');

    await dao.toggleCompletion(taskId, day);
    expect((await log()).completedAt, isNull);

    await dao.toggleCompletion(taskId, day);
    expect((await log()).completedAt, isNotNull);
  });

  test('a counter keeps the moment it reached its target', () async {
    await dao.incrementCounter(taskId, day, 2);
    expect((await log()).completedAt, isNull);

    await dao.incrementCounter(taskId, day, 2);
    final reached = (await log()).completedAt;
    expect(reached, isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await dao.incrementCounter(taskId, day, 2);
    expect((await log()).completedAt, reached);
  });

  test(
    'a write that does not touch the tick leaves the moment alone',
    () async {
      await dao.setLog(taskId, day, completed: true);
      final stamped = (await log()).completedAt;
      await dao.setLog(taskId, day, value: 5);
      expect((await log()).completedAt, stamped);
    },
  );

  test('the sync carries the moment both ways', () async {
    await dao.toggleCompletion(taskId, day);
    final local = await log();

    final row = logToRow(local, taskUid: 'u');
    expect(row['completed_at'], isA<String>());
    final back = logFromRow(row);
    expect(back.completedAt.value, local.completedAt);

    // A row from a server without the column, or an unticked one.
    expect(logFromRow({'date': '2026-10-16'}).completedAt.value, isNull);
  });

  test('a v16 device with ticks upgrades to v17 and keeps them', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('nook_v17').path}/db.sqlite',
    );
    final current = AppDatabase.forExecutor(NativeDatabase(file));
    final id = await current.tasksDao.insertTask(
      TasksCompanion.insert(title: 'старая'),
    );
    await current.tasksDao.toggleCompletion(id, day);
    for (final statement in [
      'ALTER TABLE task_logs DROP COLUMN completed_at',
      'PRAGMA user_version = 16',
    ]) {
      await current.customStatement(statement);
    }
    await current.close();

    final upgraded = AppDatabase.forExecutor(NativeDatabase(file));
    addTearDown(upgraded.close);
    final old = (await upgraded.tasksDao.getLogForDate(id, day))!;
    expect(old.completed, isTrue);
    expect(old.completedAt, isNull, reason: 'that time was never recorded');

    // Unticking and ticking again stamps it from now on.
    await upgraded.tasksDao.toggleCompletion(id, day);
    await upgraded.tasksDao.toggleCompletion(id, day);
    expect(
      (await upgraded.tasksDao.getLogForDate(id, day))!.completedAt,
      isNotNull,
    );
  });
}
