import 'package:drift/drift.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:uuid/uuid.dart';

import 'project.dart';

/// Local working copy of projects and their pending sync markers.
class LocalProjectsStore {
  LocalProjectsStore(this.db);

  final AppDatabase db;

  Future<bool> hasPendingTasks(String projectId) async =>
      (await (db.select(db.tasks)..where(
                (task) =>
                    task.projectUid.equals(projectId) & task.dirty.equals(true),
              ))
              .get())
          .isNotEmpty;

  Future<void> wipeAll() => db.delete(db.localProjects).go().then((_) {});

  Future<void> keepLocal() async {
    await db
        .update(db.localProjects)
        .write(const LocalProjectsCompanion(dirty: Value(false)));
  }

  Future<void> adopt() => db.transaction(() async {
    for (final row in await db.select(db.localProjects).get()) {
      final id = const Uuid().v4();
      await (db.update(
        db.localProjects,
      )..where((p) => p.id.equals(row.id))).write(
        LocalProjectsCompanion(
          id: Value(id),
          dirty: const Value(true),
          updatedAt: Value(TasksDao.stampAfter(row.updatedAt)),
        ),
      );
      await (db.update(
        db.tasks,
      )..where((t) => t.projectUid.equals(row.id))).write(
        TasksCompanion(
          projectUid: Value(id),
          projectDirty: const Value(true),
          dirty: const Value(true),
        ),
      );
    }
  });

  Stream<List<LocalProject>> watchAll() => db.select(db.localProjects).watch();

  Future<void> mergeRemote(Project project) async {
    await db.transaction(() async {
      final current = await (db.select(
        db.localProjects,
      )..where((row) => row.id.equals(project.id))).getSingleOrNull();
      if (current?.dirty == true) return;
      await db
          .into(db.localProjects)
          .insertOnConflictUpdate(
            LocalProjectsCompanion.insert(
              id: project.id,
              name: project.name,
              description: Value(project.description),
              color: Value(project.color),
              createdAt: project.createdAt,
              updatedAt: project.updatedAt,
              archivedAt: Value(project.archivedAt),
              dirty: const Value(false),
            ),
          );
    });
  }

  Future<Project> _project(LocalProject row) async {
    final counts = await db
        .customSelect(
          'SELECT COUNT(*) AS total, SUM(CASE WHEN EXISTS '
          '(SELECT 1 FROM task_logs l WHERE l.task_id = t.id AND l.completed = 1) '
          'THEN 1 ELSE 0 END) AS completed FROM tasks t '
          'WHERE t.project_uid = ? AND t.parent_id IS NULL AND t.group_uid IS NULL',
          variables: [Variable<String>(row.id)],
          readsFrom: {db.tasks, db.taskLogs},
        )
        .getSingle();
    final total = counts.read<int>('total');
    final completed = counts.readNullable<int>('completed') ?? 0;
    return Project(
      id: row.id,
      name: row.name,
      description: row.description,
      color: row.color,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      archivedAt: row.archivedAt,
      statistics: ProjectStatistics(
        total: total,
        completed: completed,
        progress: total == 0 ? 0 : (completed * 100 / total).round(),
      ),
    );
  }

  Future<List<Project>> list({bool archived = false}) async {
    final rows =
        await (db.select(db.localProjects)..where(
              (row) => archived
                  ? row.archivedAt.isNotNull()
                  : row.archivedAt.isNull(),
            ))
            .get();
    return Future.wait(rows.map(_project));
  }

  Future<List<Project>> pending() async {
    final rows = await (db.select(
      db.localProjects,
    )..where((row) => row.dirty.equals(true))).get();
    return Future.wait(rows.map(_project));
  }

  Future<Project> create(CreateProjectRequest request) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    await db
        .into(db.localProjects)
        .insert(
          LocalProjectsCompanion.insert(
            id: id,
            name: request.name,
            description: Value(request.description),
            color: Value(request.color),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return get(id);
  }

  Future<Project> get(String id) async => _project(
    await (db.select(
      db.localProjects,
    )..where((row) => row.id.equals(id))).getSingle(),
  );

  Future<Project> update(String id, UpdateProjectRequest request) => _edit(
    id,
    (old) => LocalProjectsCompanion(
      name: request.name == null ? const Value.absent() : Value(request.name!),
      description: request.description.present
          ? Value(request.description.value)
          : const Value.absent(),
      color: request.color.present
          ? Value(request.color.value)
          : const Value.absent(),
    ),
  );

  Future<Project> archive(String id) => _edit(
    id,
    (old) => LocalProjectsCompanion(
      archivedAt: Value(old.archivedAt ?? DateTime.now()),
    ),
  );

  Future<Project> restore(String id) =>
      _edit(id, (_) => const LocalProjectsCompanion(archivedAt: Value(null)));

  Future<Project> _edit(
    String id,
    LocalProjectsCompanion Function(Project) change,
  ) => db.transaction(() async {
    final old = await get(id);
    await (db.update(
      db.localProjects,
    )..where((row) => row.id.equals(id))).write(
      change(old).copyWith(
        updatedAt: Value(TasksDao.stampAfter(old.updatedAt)),
        dirty: const Value(true),
      ),
    );
    return get(id);
  });

  Future<void> markSynced(String id, DateTime sentAt) async {
    await (db.update(db.localProjects)..where(
          (row) =>
              row.id.equals(id) & row.updatedAt.isSmallerOrEqualValue(sentAt),
        ))
        .write(const LocalProjectsCompanion(dirty: Value(false)));
  }
}
