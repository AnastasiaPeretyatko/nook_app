import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../sync/merge.dart' show storedSeconds;
import '../app_database.dart';

part 'sections_dao.g.dart';

/// Local sections, scoped to one account and either regular tasks or a project.
@DriftAccessor(tables: [Sections, Tasks, LocalProjects, SyncTombstones])
class SectionsDao extends DatabaseAccessor<AppDatabase>
    with _$SectionsDaoMixin {
  SectionsDao(super.db);

  static const _uuid = Uuid();

  Stream<List<Section>> watchSections({
    required String userId,
    String? projectId,
  }) => (_scoped(
    userId: userId,
    projectId: projectId,
  )..orderBy([(section) => OrderingTerm.asc(section.position)])).watch();

  /// Every project-scoped section, ordered inside each project.
  ///
  /// The home-screen project widget needs one reactive source for all of its
  /// independently configured projects. Regular (non-project) sections stay
  /// out of this stream.
  Stream<List<Section>> watchProjectSections() =>
      (select(sections)
            ..where((section) => section.projectId.isNotNull())
            ..orderBy([
              (section) => OrderingTerm.asc(section.projectId),
              (section) => OrderingTerm.asc(section.position),
            ]))
          .watch();

  Future<List<Section>> getProjectSections() =>
      (select(sections)
            ..where((section) => section.projectId.isNotNull())
            ..orderBy([
              (section) => OrderingTerm.asc(section.projectId),
              (section) => OrderingTerm.asc(section.position),
            ]))
          .get();

  Future<List<Section>> getSections({
    required String userId,
    String? projectId,
  }) => (_scoped(
    userId: userId,
    projectId: projectId,
  )..orderBy([(section) => OrderingTerm.asc(section.position)])).get();

  Future<Section?> getSection(
    String id, {
    required String userId,
    String? projectId,
  }) => (_scoped(
    userId: userId,
    projectId: projectId,
  )..where((section) => section.id.equals(id))).getSingleOrNull();

  Future<Section> createSection({
    required String userId,
    String? projectId,
    required String name,
    required int position,
  }) async {
    _validateUserId(userId);
    await _validateProject(projectId);
    final now = DateTime.now();
    final id = _uuid.v4();
    await into(sections).insert(
      SectionsCompanion.insert(
        id: id,
        userId: userId,
        projectId: Value(projectId),
        name: name,
        position: position,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return (await getSection(id, userId: userId, projectId: projectId))!;
  }

  Future<Section> updateSection({
    required String id,
    required String userId,
    String? projectId,
    String? name,
    int? position,
  }) => transaction(() async {
    final existing = await _requireSection(
      id: id,
      userId: userId,
      projectId: projectId,
    );
    await (update(sections)..where((section) => section.id.equals(id))).write(
      SectionsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        position: position == null ? const Value.absent() : Value(position),
        updatedAt: Value(_updatedAtAfter(existing.updatedAt)),
        dirty: const Value(true),
      ),
    );
    return (await getSection(id, userId: userId, projectId: projectId))!;
  });

  Future<void> deleteSection({
    required String id,
    required String userId,
    String? projectId,
  }) => transaction(() async {
    await _requireSection(id: id, userId: userId, projectId: projectId);
    final assignedTasks = await (select(
      tasks,
    )..where((task) => task.sectionId.equals(id))).get();
    for (final task in assignedTasks) {
      await (update(tasks)..where((row) => row.id.equals(task.id))).write(
        TasksCompanion(
          sectionId: const Value(null),
          updatedAt: Value(_updatedAtAfter(task.updatedAt)),
          dirty: const Value(true),
          sectionDirty: const Value(true),
        ),
      );
    }
    await (delete(sections)..where((section) => section.id.equals(id))).go();
    await _writeTombstone(id);
  });

  /// Saves the complete visual order of sections in one scope.
  ///
  /// Requiring every id makes a stale drag result fail safely instead of
  /// accidentally assigning positions across projects or accounts.
  Future<void> reorderSections({
    required String userId,
    String? projectId,
    required List<String> orderedIds,
  }) => transaction(() async {
    final current = await getSections(userId: userId, projectId: projectId);
    if (current.length != orderedIds.length ||
        current.map((section) => section.id).toSet().length !=
            orderedIds.toSet().length ||
        !current.map((section) => section.id).toSet().containsAll(orderedIds)) {
      throw StateError('Section order does not match this scope.');
    }

    final byId = {for (final section in current) section.id: section};
    for (var position = 0; position < orderedIds.length; position++) {
      final section = byId[orderedIds[position]]!;
      if (section.position == position) continue;
      await (update(sections)..where((row) => row.id.equals(section.id))).write(
        SectionsCompanion(
          position: Value(position),
          updatedAt: Value(_updatedAtAfter(section.updatedAt)),
          dirty: const Value(true),
        ),
      );
    }
  });

  Future<List<Section>> pendingSections() =>
      (select(sections)..where((section) => section.dirty.equals(true))).get();

  Future<void> wipeAll() => transaction(() async {
    await delete(sections).go();
    await (delete(
      syncTombstones,
    )..where((row) => row.sourceTable.equals(sections.actualTableName))).go();
  });

  Future<Section?> sectionById(String id) => (select(
    sections,
  )..where((section) => section.id.equals(id))).getSingleOrNull();

  Future<void> insertRemoteSection(SectionsCompanion section) =>
      into(sections).insert(section.copyWith(dirty: const Value(false)));

  Future<void> applyRemoteSection(String id, SectionsCompanion section) =>
      (update(sections)..where((row) => row.id.equals(id))).write(
        section.copyWith(dirty: const Value(false)),
      );

  Future<void> deleteRemoteSection(String id) => transaction(() async {
    await (update(tasks)..where((task) => task.sectionId.equals(id))).write(
      const TasksCompanion(sectionId: Value(null)),
    );
    await (delete(sections)..where((section) => section.id.equals(id))).go();
  });

  Future<void> clearSectionDirty(Map<String, DateTime> sentAt) async {
    for (final entry in sentAt.entries) {
      await (update(sections)..where(
            (section) =>
                section.id.equals(entry.key) &
                section.updatedAt.isSmallerOrEqualValue(entry.value),
          ))
          .write(const SectionsCompanion(dirty: Value(false)));
    }
  }

  Future<void> _writeTombstone(String id) => into(syncTombstones).insert(
    SyncTombstonesCompanion.insert(
      sourceTable: sections.actualTableName,
      uid: id,
    ),
    mode: InsertMode.insertOrReplace,
  );

  SimpleSelectStatement<$SectionsTable, Section> _scoped({
    required String userId,
    required String? projectId,
  }) {
    _validateUserId(userId);
    return select(sections)..where(
      (section) =>
          section.userId.equals(userId) &
          (projectId == null
              ? section.projectId.isNull()
              : section.projectId.equals(projectId)),
    );
  }

  Future<void> _validateProject(String? projectId) async {
    if (projectId == null) return;
    final exists = await (select(
      localProjects,
    )..where((project) => project.id.equals(projectId))).getSingleOrNull();
    if (exists == null) {
      throw StateError('Project $projectId is not available locally.');
    }
  }

  Future<Section> _requireSection({
    required String id,
    required String userId,
    required String? projectId,
  }) async {
    final section = await getSection(id, userId: userId, projectId: projectId);
    if (section == null) {
      throw StateError('Section $id is not available in this scope.');
    }
    return section;
  }

  void _validateUserId(String userId) {
    if (userId.isEmpty) throw ArgumentError.value(userId, 'userId');
  }

  DateTime _updatedAtAfter(DateTime previous) {
    final now = DateTime.now();
    return storedSeconds(now) > storedSeconds(previous)
        ? now
        : previous.add(const Duration(milliseconds: 1));
  }
}
