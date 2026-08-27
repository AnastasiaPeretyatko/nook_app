import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';
import 'enums.dart';
import 'tables.dart';
import 'daos/tasks_dao.dart';
import 'daos/events_dao.dart';
import 'daos/diary_dao.dart';
import '../utils/note_labels.dart';
import '../utils/task_icons.dart';
import '../utils/task_palette.dart';

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
    SyncTombstones,
  ],
  daos: [TasksDao, EventsDao, DiaryDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Injects a custom executor (e.g. an in-memory database in tests).
  AppDatabase.forExecutor(super.executor);

  @override
  int get schemaVersion => 14;

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

      // Adds columns to a table other than `tasks`. Re-reads that table rather
      // than trusting the snapshot above, which is `tasks`-only.
      Future<void> addSyncColumns(
        TableInfo<Table, dynamic> table,
        List<GeneratedColumn> columns,
      ) async {
        final present = await _tableColumns(table.actualTableName);
        for (final column in columns) {
          if (!present.contains(column.name)) {
            await m.addColumn(table, column);
          }
        }
      }

      // Guarded, unlike `createTable`: that one issues `IF NOT EXISTS` and
      // `createIndex` does **not**, so on a dev device that got half-way
      // through one of these branches once, a second run would throw "index
      // already exists" and the database would not open at all.
      Future<void> createIndexIfMissing(Index index) async {
        final rows = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
          variables: [Variable<String>(index.entityName)],
        ).get();
        if (rows.isEmpty) await m.createIndex(index);
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
      if (from < 12) {
        // What the diary needs before any of it can leave the device: an
        // identity that means the same thing on two phones, a mark for "changed
        // here and not sent yet", and somewhere to record a deletion — which is
        // the one edit that otherwise leaves nothing behind to notice.
        //
        // Not through `addIfMissing`: that helper closes over the columns of
        // `tasks` and adds to `tasks`. The `from < 9` branch above re-reads the
        // table it is about for the same reason.
        await addSyncColumns(diaryEntries, [
          diaryEntries.uid,
          diaryEntries.dirty,
        ]);
        await addSyncColumns(noteMoods, [noteMoods.uid, noteMoods.dirty]);
        await addSyncColumns(noteTags, [noteTags.uid, noteTags.dirty]);
        await m.createTable(syncTombstones);

        // Order matters: the seeded moods have to claim their fixed uids before
        // the blanket backfill hands them random ones.
        await _adoptSeedMoodUids();
        await _backfillUids([diaryEntries, noteMoods, noteTags]);

        // After the backfill, not before: building the index first would mean
        // maintaining it on every row the backfill writes, and — more to the
        // point — a clash would then surface as a failed UPDATE somewhere in
        // the middle rather than as one clear error here.
        await createIndexIfMissing(diaryEntriesUid);
        await createIndexIfMissing(noteMoodsUid);
        await createIndexIfMissing(noteTagsUid);
      }
      if (from < 13) {
        // A tag's colour becomes a key into the palette instead of a raw ARGB
        // number. The reason is that a tag now travels: `0xFF8B7CF6` means
        // something only inside one version of one palette, while `violet` is
        // the same fact on any device and after any repaint. The very same move
        // the icons made at v10.
        //
        // It also settles a mismatch that could only appear at the boundary: an
        // opaque colour starts with `0xFF` and is therefore above 2^31, which
        // SQLite takes without comment and Postgres `integer` rejects.
        final columns = await _tableColumns(noteTags.actualTableName);
        if (!columns.contains(noteTags.colorKey.name)) {
          await m.addColumn(noteTags, noteTags.colorKey as GeneratedColumn);
        }
        if (columns.contains('color_value')) {
          await _adoptTagColorKeys();
          // Dropped rather than left behind as a legacy column: unlike
          // `tasks.icon_code_point`, which the v10 migration still reads,
          // nothing will ever need this one again, and two spellings of the
          // same colour is precisely the confusion this change removes.
          await m.dropColumn(noteTags, 'color_value');
        }
      }
      if (from < 14) {
        // What tasks, habits and their day marks need before any of them can
        // leave the device. The same three ideas the diary got at v12 — an
        // identity, a "changed here" mark, a record of deletions — except that
        // a log needs no identity of its own: it *is* its task and its day.
        //
        // **The order below is not arrangeable.** Each step is what makes the
        // next one true, and the last of them is a unique index that would
        // otherwise either refuse to build or, worse, build over data it does
        // not actually describe.
        await addIfMissing(tasks.uid);
        await addIfMissing(tasks.dirty);
        await addSyncColumns(taskLogs, [taskLogs.dirty, taskLogs.updatedAt]);

        // 1 & 2. Fold every log onto the local day it is about, merging the
        // rows that turn out to share one. Both halves at once because they are
        // the same pass: normalising is what *reveals* the duplicates.
        await _foldLogsOntoDays();

        // 3. Give the logs an edit time. `date` rather than `now()` on purpose:
        // the day the row is about is a fact about the row, identical on every
        // device that carries it, whereas the moment this migration happened to
        // run differs per phone and would hand the merge an arbitrary winner.
        // Only rows still carrying the column's epoch default, so a dev device
        // that already got half-way through this branch keeps its real stamps.
        await customUpdate(
          'UPDATE task_logs SET updated_at = date WHERE updated_at = 0',
          updates: {taskLogs},
        );

        // 4. Identities for the tasks. After the folding, before the indexes,
        // for the reason spelled out in the v12 branch.
        await _backfillUids([tasks]);

        // 5. The two indexes.
        await createIndexIfMissing(tasksUid);
        await createIndexIfMissing(taskLogsTaskDay);

        // The pull watermark is **not** reset here, and cannot be: it lives in
        // `SharedPreferences`, which a drift migration has no business
        // reaching. `SyncWatermarkNotifier` retires its key instead.
      }
    },
  );

  /// Makes every task log sit on the local midnight of the day it is about, and
  /// leaves exactly one row per `(task, day)`.
  ///
  /// Both jobs in one pass, because they are one job: `task_logs.date` was a
  /// full timestamp whose time-of-day was zero only by convention — `HomePage`
  /// opens on `DateTime.now()` and the timeline writes whatever day it is
  /// handed — so two rows for the same day are not visibly duplicates until
  /// their dates have been stripped.
  ///
  /// Merged rather than picked: the survivor is the lowest `id`, and it takes
  /// `completed = OR(all)` and `value = MAX(all)`. Keeping the first row and
  /// dropping the rest would throw away a tick the user made.
  ///
  /// In Dart rather than in SQL because "the local midnight of this instant" is
  /// a question about the device's time zone, and SQLite's `localtime` modifier
  /// answers it from the OS in a way that is neither testable nor the same on
  /// every platform. `DateTime` already knows. One statement per row is the
  /// same bargain [_backfillUids] strikes: this is a user's habit history, so
  /// hundreds of rows, not millions.
  Future<void> _foldLogsOntoDays() async {
    final rows = await customSelect(
      'SELECT id, task_id, date, completed, value FROM task_logs ORDER BY id',
      readsFrom: {taskLogs},
    ).get();

    // Keyed by task and day. Insertion order is `id` order, so the first row
    // of a group is always the survivor.
    final groups = <String, List<QueryRow>>{};
    for (final row in rows) {
      final raw = row.read<DateTime>('date');
      final day = DateTime(raw.year, raw.month, raw.day);
      final key = '${row.read<int>('task_id')}|${day.millisecondsSinceEpoch}';
      (groups[key] ??= []).add(row);
    }

    for (final group in groups.values) {
      final survivor = group.first;
      final raw = survivor.read<DateTime>('date');
      final day = DateTime(raw.year, raw.month, raw.day);

      // Nothing to say about a lone row that already sits on its day.
      if (group.length == 1 && raw == day) continue;

      var completed = false;
      double? value;
      for (final row in group) {
        completed = completed || row.read<bool>('completed');
        final v = row.read<double?>('value');
        if (v != null && (value == null || v > value)) value = v;
      }

      await customUpdate(
        'UPDATE task_logs SET date = ?, completed = ?, value = ? WHERE id = ?',
        variables: [
          Variable<DateTime>(day),
          Variable<bool>(completed),
          Variable<double>(value),
          Variable<int>(survivor.read<int>('id')),
        ],
        updates: {taskLogs},
      );

      for (final row in group.skip(1)) {
        await customUpdate(
          'DELETE FROM task_logs WHERE id = ?',
          variables: [Variable<int>(row.read<int>('id'))],
          updates: {taskLogs},
        );
      }
    }
  }

  /// Gives the eight seeded moods the fixed uids of [defaultNoteMoods].
  ///
  /// Matched by name, which is the only thing a row seeded before this
  /// migration has in common with its entry in the list. Names are unique in
  /// practice — the picker refuses one it already holds — and nothing in the
  /// app renames a mood, so the match is unambiguous.
  ///
  /// Must run **before** [_backfillUids], or the seeded moods get random uids
  /// like everything else and the two devices never converge.
  ///
  /// **Exactly one row per name**, via `MIN(id)`, and that is not a nicety: a
  /// bare `WHERE name = ?` would hand the same uid to every row that shares the
  /// name, and the unique index built at the end of the migration would then
  /// fail — leaving a database that cannot be opened at all. Names are unique
  /// in practice, but "in practice" is a UI rule, and this runs on devices
  /// whose data nobody has inspected. The lowest id is the seeded row, since
  /// the seeds were written before anything the user added; a duplicate keeps
  /// its NULL and is given an ordinary fresh uid by the backfill.
  Future<void> _adoptSeedMoodUids() async {
    for (final mood in defaultNoteMoods) {
      await customUpdate(
        'UPDATE note_moods SET uid = ? WHERE id = ('
        '  SELECT MIN(id) FROM note_moods WHERE uid IS NULL AND name = ?'
        ')',
        variables: [Variable<String>(mood.uid), Variable<String>(mood.name)],
        updates: {noteMoods},
      );
    }
  }

  /// Rewrites every tag's stored ARGB colour into the palette key naming it.
  ///
  /// One statement per family rather than one per row: there are seven of them
  /// and any number of tags. The same shape as [_backfillIconKeys], which did
  /// this for the icons at v10.
  ///
  /// A colour in no family keeps the column default — every tag the app ever
  /// made came from the palette, so this should find nothing, but a tag with an
  /// unrecognisable colour is better off violet than broken.
  Future<void> _adoptTagColorKeys() async {
    for (final swatch in taskPalette) {
      await customUpdate(
        'UPDATE note_tags SET color_key = ? WHERE color_value = ?',
        variables: [
          Variable<String>(swatch.key),
          Variable<int>(swatch.accent.toARGB32()),
        ],
        updates: {noteTags},
      );
    }
  }

  /// Mints a uid for every row of [tables] that does not have one yet.
  ///
  /// One statement per row rather than one per table: each row needs its *own*
  /// uuid, and SQLite has no function that would generate one. The tables are
  /// one person's diary and task list, so this is tens of rows, not millions.
  ///
  /// The tables are a parameter rather than a fixed list because two migrations
  /// need it now and they must not do each other's work: v12 knows nothing
  /// about tasks, and v14 must not re-walk the diary.
  Future<void> _backfillUids(List<TableInfo<Table, dynamic>> tables) async {
    for (final table in tables) {
      final name = table.actualTableName;
      final rows = await customSelect(
        'SELECT id FROM $name WHERE uid IS NULL',
      ).get();
      for (final row in rows) {
        await customUpdate(
          'UPDATE $name SET uid = ? WHERE id = ?',
          variables: [
            Variable<String>(const Uuid().v4()),
            Variable<int>(row.read<int>('id')),
          ],
          updates: {table},
        );
      }
    }
  }

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
          // The uid comes from the list, not from a generator: the seeding runs
          // on every device separately, and fresh uuids would make the same
          // eight moods eight more rows on the server for each new phone.
          NoteMoodsCompanion.insert(
            name: mood.name,
            emoji: mood.emoji,
            uid: Value(mood.uid),
          ),
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
