import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/projects/local_projects_store.dart';
import 'package:todo_app/projects/project.dart';

void main() {
  test('upgrading v22 creates project storage and preserves tasks', () async {
    final db = AppDatabase.forExecutor(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL)',
          );
          raw.execute(
            "INSERT INTO tasks (id, title) VALUES (1, 'Existing task')",
          );
          raw.execute('PRAGMA user_version = 22');
        },
      ),
    );
    addTearDown(db.close);
    final existing = await db
        .customSelect('SELECT title FROM tasks')
        .getSingle();
    expect(existing.read<String>('title'), 'Existing task');
    final store = LocalProjectsStore(db);
    expect(await store.list(), isEmpty);
  });

  test('local create, edit, archive and restore remain pending', () async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalProjectsStore(db);
    final created = await store.create(const CreateProjectRequest(name: 'Дом'));
    expect(created.id, isNotEmpty);
    expect((await store.pending()).single.id, created.id);
    await store.update(
      created.id,
      const UpdateProjectRequest(
        name: 'Работа',
        description: PatchValue('Описание'),
      ),
    );
    expect((await store.list()).single.name, 'Работа');
    await store.archive(created.id);
    expect(await store.list(), isEmpty);
    expect((await store.list(archived: true)).single.description, 'Описание');
    await store.restore(created.id);
    expect((await store.list()).single.id, created.id);
    expect((await store.pending()).single.id, created.id);
  });

  test('acknowledging an old version does not clear a newer edit', () async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalProjectsStore(db);
    final created = await store.create(const CreateProjectRequest(name: 'Дом'));
    await store.update(created.id, const UpdateProjectRequest(name: 'Другое'));
    await store.markSynced(created.id, created.updatedAt);
    expect(await store.pending(), hasLength(1));
  });

  test(
    'adopting an account remints projects and keeps task references',
    () async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalProjectsStore(db);
      final project = await store.create(
        const CreateProjectRequest(name: 'Дом'),
      );
      final taskId = await db.tasksDao.insertTask(
        TasksCompanion.insert(title: 'Задача', projectUid: Value(project.id)),
      );
      await store.adopt();
      final adopted = (await store.list()).single;
      expect(adopted.id, isNot(project.id));
      expect((await db.tasksDao.getTaskById(taskId))!.projectUid, adopted.id);
      expect((await store.pending()).single.id, adopted.id);
      await store.wipeAll();
      expect(await store.list(), isEmpty);
    },
  );
}
