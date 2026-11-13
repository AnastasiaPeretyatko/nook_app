import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/projects/local_projects_store.dart';
import 'package:todo_app/projects/project.dart';
import 'package:todo_app/projects/projects_sync.dart';
import 'package:todo_app/sync/sync_service.dart';

import '../support/fake_projects_api.dart';
import '../support/fake_sync_api.dart';

class ProjectsFirstSyncApi extends FakeSyncApi {
  ProjectsFirstSyncApi(this.projects);
  final IdempotentProjectsApi projects;

  @override
  Future<Map<String, dynamic>> push(Map<String, dynamic> body) async {
    for (final task in (body['tasks'] as List? ?? [])) {
      final projectId = task['project_id'];
      if (projectId != null && !projects.projects.containsKey(projectId)) {
        throw StateError('task reached server before its project');
      }
    }
    return super.push(body);
  }
}

class IdempotentProjectsApi extends FakeProjectsApi {
  @override
  Future<Project> createProject(CreateProjectRequest request) async {
    calls.add('create(${request.id})');
    if (error != null) throw error!;
    return projects.putIfAbsent(
      request.id!,
      () => Project(
        id: request.id!,
        name: request.name,
        description: request.description,
        color: request.color,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
  }
}

void main() {
  test(
    'sync preserves local identity and clears pending only after success',
    () async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalProjectsStore(db);
      final api = IdempotentProjectsApi();
      final sync = ProjectsSync(store, api);
      final project = await store.create(
        const CreateProjectRequest(name: 'Дом'),
      );
      await sync.pull();
      await sync.beforeTasks();
      await sync.afterTasks();
      expect(api.projects[project.id]?.name, 'Дом');
      expect(await store.pending(), isEmpty);
      expect(api.calls.first, 'list(archived: false)');
    },
  );

  test('failed upload keeps a project pending', () async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalProjectsStore(db);
    final api = IdempotentProjectsApi()..error = const ApiException.offline();
    final project = await store.create(const CreateProjectRequest(name: 'Дом'));
    await expectLater(
      ProjectsSync(store, api).beforeTasks(),
      throwsA(isA<ApiException>()),
    );
    expect((await store.pending()).single.id, project.id);
  });

  test('a local project reaches the server before its task', () async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalProjectsStore(db);
    final remoteProjects = IdempotentProjectsApi();
    final api = ProjectsFirstSyncApi(remoteProjects);
    final project = await store.create(const CreateProjectRequest(name: 'Дом'));
    await db.tasksDao.insertTask(
      TasksCompanion.insert(title: 'Задача', projectUid: Value(project.id)),
    );
    final sync = SyncService(
      dao: db.diaryDao,
      tasksDao: db.tasksDao,
      cycleDao: db.cycleDao,
      api: api,
      userId: () => 'user',
      projectsSync: ProjectsSync(store, remoteProjects),
    );
    expect(await sync.sync(), SyncOutcome.done);
    expect(remoteProjects.projects, contains(project.id));
    expect(
      (api.pushed.single['tasks'] as List).single['project_id'],
      project.id,
    );
    expect(await store.pending(), isEmpty);
  });
}
