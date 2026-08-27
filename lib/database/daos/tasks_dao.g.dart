// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tasks_dao.dart';

// ignore_for_file: type=lint
mixin _$TasksDaoMixin on DatabaseAccessor<AppDatabase> {
  $TasksTable get tasks => attachedDatabase.tasks;
  $TaskLogsTable get taskLogs => attachedDatabase.taskLogs;
  $TaskSessionsTable get taskSessions => attachedDatabase.taskSessions;
  $SyncTombstonesTable get syncTombstones => attachedDatabase.syncTombstones;
  TasksDaoManager get managers => TasksDaoManager(this);
}

class TasksDaoManager {
  final _$TasksDaoMixin _db;
  TasksDaoManager(this._db);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db.attachedDatabase, _db.tasks);
  $$TaskLogsTableTableManager get taskLogs =>
      $$TaskLogsTableTableManager(_db.attachedDatabase, _db.taskLogs);
  $$TaskSessionsTableTableManager get taskSessions =>
      $$TaskSessionsTableTableManager(_db.attachedDatabase, _db.taskSessions);
  $$SyncTombstonesTableTableManager get syncTombstones =>
      $$SyncTombstonesTableTableManager(
        _db.attachedDatabase,
        _db.syncTombstones,
      );
}
