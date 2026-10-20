// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tasks_dao.dart';

// ignore_for_file: type=lint
mixin _$TasksDaoMixin on DatabaseAccessor<AppDatabase> {
  $TasksTable get tasks => attachedDatabase.tasks;
  $TaskLogsTable get taskLogs => attachedDatabase.taskLogs;
  $TaskSessionsTable get taskSessions => attachedDatabase.taskSessions;
  $SyncTombstonesTable get syncTombstones => attachedDatabase.syncTombstones;
  $TaskGroupsTable get taskGroups => attachedDatabase.taskGroups;
  $GroupMembersTable get groupMembers => attachedDatabase.groupMembers;
  $GroupMarksTable get groupMarks => attachedDatabase.groupMarks;
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
  $$TaskGroupsTableTableManager get taskGroups =>
      $$TaskGroupsTableTableManager(_db.attachedDatabase, _db.taskGroups);
  $$GroupMembersTableTableManager get groupMembers =>
      $$GroupMembersTableTableManager(_db.attachedDatabase, _db.groupMembers);
  $$GroupMarksTableTableManager get groupMarks =>
      $$GroupMarksTableTableManager(_db.attachedDatabase, _db.groupMarks);
}
