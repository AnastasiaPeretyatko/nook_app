// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diary_dao.dart';

// ignore_for_file: type=lint
mixin _$DiaryDaoMixin on DatabaseAccessor<AppDatabase> {
  $DiaryEntriesTable get diaryEntries => attachedDatabase.diaryEntries;
  $NoteMoodsTable get noteMoods => attachedDatabase.noteMoods;
  $NoteTagsTable get noteTags => attachedDatabase.noteTags;
  $DiaryEntryMoodsTable get diaryEntryMoods => attachedDatabase.diaryEntryMoods;
  $DiaryEntryTagsTable get diaryEntryTags => attachedDatabase.diaryEntryTags;
  $SyncTombstonesTable get syncTombstones => attachedDatabase.syncTombstones;
  DiaryDaoManager get managers => DiaryDaoManager(this);
}

class DiaryDaoManager {
  final _$DiaryDaoMixin _db;
  DiaryDaoManager(this._db);
  $$DiaryEntriesTableTableManager get diaryEntries =>
      $$DiaryEntriesTableTableManager(_db.attachedDatabase, _db.diaryEntries);
  $$NoteMoodsTableTableManager get noteMoods =>
      $$NoteMoodsTableTableManager(_db.attachedDatabase, _db.noteMoods);
  $$NoteTagsTableTableManager get noteTags =>
      $$NoteTagsTableTableManager(_db.attachedDatabase, _db.noteTags);
  $$DiaryEntryMoodsTableTableManager get diaryEntryMoods =>
      $$DiaryEntryMoodsTableTableManager(
        _db.attachedDatabase,
        _db.diaryEntryMoods,
      );
  $$DiaryEntryTagsTableTableManager get diaryEntryTags =>
      $$DiaryEntryTagsTableTableManager(
        _db.attachedDatabase,
        _db.diaryEntryTags,
      );
  $$SyncTombstonesTableTableManager get syncTombstones =>
      $$SyncTombstonesTableTableManager(
        _db.attachedDatabase,
        _db.syncTombstones,
      );
}
