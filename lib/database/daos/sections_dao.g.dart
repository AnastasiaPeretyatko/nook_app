// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sections_dao.dart';

// ignore_for_file: type=lint
mixin _$SectionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SectionsTable get sections => attachedDatabase.sections;
  $TasksTable get tasks => attachedDatabase.tasks;
  $LocalProjectsTable get localProjects => attachedDatabase.localProjects;
  $SyncTombstonesTable get syncTombstones => attachedDatabase.syncTombstones;
  SectionsDaoManager get managers => SectionsDaoManager(this);
}

class SectionsDaoManager {
  final _$SectionsDaoMixin _db;
  SectionsDaoManager(this._db);
  $$SectionsTableTableManager get sections =>
      $$SectionsTableTableManager(_db.attachedDatabase, _db.sections);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db.attachedDatabase, _db.tasks);
  $$LocalProjectsTableTableManager get localProjects =>
      $$LocalProjectsTableTableManager(_db.attachedDatabase, _db.localProjects);
  $$SyncTombstonesTableTableManager get syncTombstones =>
      $$SyncTombstonesTableTableManager(
        _db.attachedDatabase,
        _db.syncTombstones,
      );
}
