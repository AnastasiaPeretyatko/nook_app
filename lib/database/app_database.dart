import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'enums.dart';
import 'tables.dart';
import 'daos/tasks_dao.dart';
import 'daos/events_dao.dart';
import 'daos/diary_dao.dart';
import '../utils/note_labels.dart';
import '../utils/task_icons.dart';

export 'enums.dart';
export 'tables.dart';
export 'daos/tasks_dao.dart';
export 'daos/events_dao.dart';
export 'daos/diary_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Tasks,
    TaskLogs,
    TaskSessions,
    Events,
    DiaryEntries,
    NoteMoods,
    NoteTags,
    DiaryEntryMoods,
    DiaryEntryTags,
  ],
  daos: [TasksDao, EventsDao, DiaryDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Injects a custom executor (e.g. an in-memory database in tests).
  AppDatabase.forExecutor(super.executor);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // A fresh install has to arrive with the eight moods already in it: the
      // picker offers rows, and an empty table is an empty picker.
      await _seedNoteMoods();
    },
    onUpgrade: (m, from, to) async {
      // Defensive against schema drift accumulated during development: only
      // add a column if it isn't already present in the on-device table.
      final existing = await _tableColumns('tasks');

      Future<void> addIfMissing(GeneratedColumn column) async {
        if (!existing.contains(column.name)) {
          await m.addColumn(tasks, column);
        }
      }

      if (from < 2) {
        await addIfMissing(tasks.iconCodePoint);
        await addIfMissing(tasks.colorValue);
      }
      if (from < 3) {
        await addIfMissing(tasks.scheduledTimeMinutes);
      }
      if (from < 4) {
        await addIfMissing(tasks.endTimeMinutes);
      }
      if (from < 5) {
        await addIfMissing(tasks.startDate);
      }
      if (from < 6) {
        await addIfMissing(tasks.targetValue);
      }
      if (from < 7) {
        await addIfMissing(tasks.repeatDaysMask);
      }
      if (from < 8) {
        // A whole table this time, not a column. Same defensiveness: a dev
        // device may already carry it.
        await m.createTable(diaryEntries);
      }
      if (from < 9) {
        // A device that arrives here from 7 has just had the table created
        // above, complete with this column — so ask before adding it.
        final diaryColumns = await _tableColumns('diary_entries');
        if (!diaryColumns.contains(diaryEntries.images.name)) {
          await m.addColumn(diaryEntries, diaryEntries.images);
        }
      }
      if (from < 10) {
        // Icons moved from a Material Icons code point to a key into
        // `taskIcons`, because a code point only means something inside one
        // font. Translate every row that carries one; a code point outside the
        // old picker's set has no key to become and is left as a task with no
        // icon rather than a wrong one.
        await addIfMissing(tasks.iconKey);
        await _backfillIconKeys();
      }
      if (from < 11) {
        // The moods and tags of a note, and the two join tables that link them
        // to it. `createTable` issues `CREATE TABLE IF NOT EXISTS`, so a dev
        // device that already carries them is left alone.
        await m.createTable(noteMoods);
        await m.createTable(noteTags);
        await m.createTable(diaryEntryMoods);
        await m.createTable(diaryEntryTags);
        await _seedNoteMoods();
      }
    },
  );

  /// Writes the moods of [defaultNoteMoods] into `note_moods`, once.
  ///
  /// Guarded on the table being empty rather than on the row not being there:
  /// the seeds are what the diary *opens* with, not a set it has to keep — a
  /// mood the user deleted must not come back on the next migration, and the
  /// only way to tell "deleted" from "never written" without a column for it is
  /// to stop asking once anything at all is in the table.
  Future<void> _seedNoteMoods() async {
    final rows = await customSelect(
      'SELECT COUNT(*) AS mood_count FROM note_moods',
    ).get();
    if (rows.first.read<int>('mood_count') > 0) return;

    await batch((b) {
      b.insertAll(noteMoods, [
        for (final mood in defaultNoteMoods)
          NoteMoodsCompanion.insert(name: mood.name, emoji: mood.emoji),
      ]);
    });
  }

  /// Rewrites `tasks.iconCodePoint` into `tasks.iconKey` for the schema v10
  /// migration. One statement per key rather than one per row: the mapping is a
  /// fixed 48 entries, the table is not.
  Future<void> _backfillIconKeys() async {
    for (final entry in legacyTaskIconKeys.entries) {
      await customUpdate(
        'UPDATE tasks SET icon_key = ? '
        'WHERE icon_key IS NULL AND icon_code_point = ?',
        variables: [Variable<String>(entry.value), Variable<int>(entry.key)],
        updates: {tasks},
      );
    }
  }

  Future<Set<String>> _tableColumns(String table) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'todo_app');
}
