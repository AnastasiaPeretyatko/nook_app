// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cycle_dao.dart';

// ignore_for_file: type=lint
mixin _$CycleDaoMixin on DatabaseAccessor<AppDatabase> {
  $CycleDaysTable get cycleDays => attachedDatabase.cycleDays;
  CycleDaoManager get managers => CycleDaoManager(this);
}

class CycleDaoManager {
  final _$CycleDaoMixin _db;
  CycleDaoManager(this._db);
  $$CycleDaysTableTableManager get cycleDays =>
      $$CycleDaysTableTableManager(_db.attachedDatabase, _db.cycleDays);
}
