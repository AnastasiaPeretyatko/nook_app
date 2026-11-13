import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/sync/payload.dart';

void main() {
  late AppDatabase db;
  late TasksDao dao;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    dao = db.tasksDao;
  });

  tearDown(() => db.close());

  test(
    'offline edits preserve omission and explicit project removal',
    () async {
      final id = await dao.insertTask(
        TasksCompanion.insert(
          title: 'Original',
          projectUid: const Value('home'),
        ),
      );
      final original = (await dao.getTaskById(id))!;
      await dao.clearTaskDirty({original.uid!: original.updatedAt});
      await dao.updateTaskById(
        id,
        const TasksCompanion(title: Value('Renamed')),
      );
      var task = (await dao.getTaskById(id))!;
      expect(taskToRow(task).containsKey('project_id'), isFalse);
      await dao.updateTaskById(
        id,
        const TasksCompanion(projectUid: Value(null)),
      );
      await dao.updateTaskById(
        id,
        const TasksCompanion(description: Value('Offline')),
      );
      task = (await dao.getTaskById(id))!;
      expect(taskToRow(task).containsKey('project_id'), isTrue);
      expect(taskToRow(task)['project_id'], isNull);
      expect(task.title, 'Renamed');
      expect(task.description, 'Offline');
    },
  );

  test(
    'undoing a deleted project task sends its project with the new identity',
    () async {
      final id = await dao.insertTask(
        TasksCompanion.insert(title: 'Task', projectUid: const Value('home')),
      );
      final task = (await dao.getTaskById(id))!;
      await dao.clearTaskDirty({task.uid!: task.updatedAt});
      final deleted = (await dao.deleteTaskCascade(id))!;
      await dao.restoreDeleted(deleted);
      final restored = (await dao.getTaskById(id))!;
      expect(restored.uid, isNot(task.uid));
      expect(taskToRow(restored)['project_id'], 'home');
    },
  );

  test(
    'creates tasks with or without a project and serializes project_id',
    () async {
      final assigned = await dao.insertTask(
        TasksCompanion.insert(
          title: 'Kitchen',
          projectUid: const Value('home'),
        ),
      );
      final unassigned = await dao.insertTask(
        TasksCompanion.insert(title: 'Inbox'),
      );

      final assignedTask = (await dao.getTaskById(assigned))!;
      expect(assignedTask.projectUid, 'home');
      expect((await dao.getTaskById(unassigned))!.projectUid, isNull);
      expect(taskToRow(assignedTask)['project_id'], 'home');
      final unassignedTask = (await dao.getTaskById(unassigned))!;
      expect(taskToRow(unassignedTask)['project_id'], isNull);
    },
  );

  test(
    'an explicit null removes a project while an omitted field preserves it',
    () async {
      final id = await dao.insertTask(
        TasksCompanion.insert(
          title: 'Kitchen',
          projectUid: const Value('home'),
        ),
      );
      final task = (await dao.getTaskById(id))!;

      await dao.applyRemoteTask(
        task.uid!,
        taskFromRow({
          ...taskToRow(task, includeProjectId: false),
          'updated_at': '2026-11-10T10:00:00.000Z',
        }),
      );
      expect((await dao.getTaskById(id))!.projectUid, 'home');

      await dao.applyRemoteTask(
        task.uid!,
        taskFromRow({
          ...taskToRow(task),
          'project_id': null,
          'updated_at': '2026-11-10T11:00:00.000Z',
        }),
      );
      expect((await dao.getTaskById(id))!.projectUid, isNull);
    },
  );

  test(
    'does not hide a personal-project validation error behind client validation',
    () async {
      final id = await dao.insertTask(
        TasksCompanion.insert(
          title: 'Shared task',
          groupUid: const Value('group-1'),
          projectUid: const Value('personal-project'),
        ),
      );

      final row = taskToRow((await dao.getTaskById(id))!);
      // The backend owns ownership and group/project validation. The data layer
      // keeps the attempted association intact so its structured rejection can
      // reach sync unchanged.
      expect(row['group_id'], 'group-1');
      expect(row['project_id'], 'personal-project');
    },
  );
}
