import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/note_labels.dart';
import 'package:todo_app/utils/task_palette.dart';

/// The schema v12 migration: the identity every synced row needs before any of
/// it can leave the device.
///
/// The upgrade is exercised against a **real v11 database** rather than a fresh
/// one. `NativeDatabase.memory(setup:)` hands over the raw connection before
/// drift touches it, so the old schema can be built by hand and `user_version`
/// set to 11 — which is what makes the next query run `onUpgrade` for real.
/// Testing the migration by inspecting a freshly created v12 database would
/// prove nothing about the devices that already carry notes.
void main() {
  // Two `AppDatabase` instances at once is the point of the convergence test,
  // and drift warns about it because sharing one executor between two would
  // corrupt the database. These hold an in-memory executor each, so there is
  // nothing to race over.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// `diary_entries`, `note_moods` and `note_tags` exactly as schema 11 left
  /// them: no `uid`, no `dirty`.
  ///
  /// `tasks` and `task_logs` are here too, empty, and **not** because the v12
  /// branch looks at them — it does not. A device arriving from 11 runs every
  /// branch after it, and v14 alters both of those tables, so a fixture without
  /// them stops being a v11 database and starts being an impossible one. The
  /// remaining tables are still left out: nothing between 12 and 14 touches
  /// them, and `PRAGMA table_info` on a table that is not there simply returns
  /// nothing.
  const v11Schema = '''
CREATE TABLE tasks (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  parent_id INTEGER NULL REFERENCES tasks (id),
  title TEXT NOT NULL,
  description TEXT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  repeat_type TEXT NULL,
  repeat_interval INTEGER NULL,
  repeat_days_mask INTEGER NULL,
  tracking_mode TEXT NOT NULL DEFAULT 'checkbox',
  target_duration_minutes INTEGER NULL,
  target_value REAL NULL,
  icon_key TEXT NULL,
  icon_code_point INTEGER NULL,
  color_value INTEGER NULL,
  scheduled_time_minutes INTEGER NULL,
  end_time_minutes INTEGER NULL,
  start_date INTEGER NULL,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);
CREATE TABLE task_logs (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL REFERENCES tasks (id),
  date INTEGER NOT NULL,
  completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1)),
  value REAL NULL
);
CREATE TABLE diary_entries (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL DEFAULT '',
  body TEXT NOT NULL DEFAULT '',
  cover_image TEXT NULL,
  images TEXT NOT NULL DEFAULT '[]',
  is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)),
  status TEXT NOT NULL DEFAULT 'normal',
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);
CREATE TABLE note_moods (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  emoji TEXT NOT NULL,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);
CREATE TABLE note_tags (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  color_value INTEGER NOT NULL,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);
''';

  /// A device sitting on schema 11 with a diary already on it.
  AppDatabase openV11() {
    return AppDatabase.forExecutor(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(v11Schema);
          raw.execute(
            "INSERT INTO diary_entries (title) VALUES ('Старая заметка')",
          );
          // The eight moods as the v11 migration wrote them — by name and
          // emoji, with nothing to identify them beyond a local id.
          for (final mood in defaultNoteMoods) {
            raw.execute('INSERT INTO note_moods (name, emoji) VALUES (?, ?)', [
              mood.name,
              mood.emoji,
            ]);
          }
          raw.execute(
            "INSERT INTO note_moods (name, emoji) VALUES ('Своё', '🎈')",
          );
          // Colours as v11 stored them: raw ARGB. The first is the violet
          // accent, the second is nothing the palette knows.
          raw.execute(
            'INSERT INTO note_tags (name, color_value) VALUES (?, ?)',
            ['идеи', 0xFF8B7CF6],
          );
          raw.execute(
            'INSERT INTO note_tags (name, color_value) VALUES (?, ?)',
            ['старый', 0xFF123456],
          );
          raw.execute('PRAGMA user_version = 11');
        },
      ),
    );
  }

  group('upgrading a device that already has a diary', () {
    late AppDatabase db;

    setUp(() => db = openV11());
    tearDown(() => db.close());

    test('a note written before the migration is given a uid', () async {
      final notes = await db.select(db.diaryEntries).get();

      expect(notes, hasLength(1));
      expect(notes.single.title, 'Старая заметка');
      expect(notes.single.uid, isNotNull);
      expect(notes.single.uid, isNotEmpty);
    });

    test('a tag written before the migration is given a uid', () async {
      final tags = await db.select(db.noteTags).get();

      expect(tags, hasLength(2));
      for (final tag in tags) {
        expect(tag.uid, isNotNull);
        expect(tag.uid, isNotEmpty);
      }
    });

    test('a stored colour becomes the key naming its family', () async {
      // The point of the change: `0xFF8B7CF6` is a fact about one version of
      // one palette, `violet` is a fact about the tag. It also stops an opaque
      // ARGB — always above 2^31 — from being offered to a Postgres `integer`.
      final tags = await db.select(db.noteTags).get();
      final byName = {for (final tag in tags) tag.name: tag.colorKey};

      expect(byName['идеи'], 'violet');
    });

    test('a colour in no family falls back rather than breaking', () async {
      // Nothing in the app could have produced it, but a migration runs on data
      // nobody has inspected, and a tag is better off violet than unreadable.
      final tags = await db.select(db.noteTags).get();
      final byName = {for (final tag in tags) tag.name: tag.colorKey};

      expect(byName['старый'], fallbackTaskColorKey);
    });

    test('the old colour column is gone', () async {
      // Dropped, not left behind: two spellings of the same colour is exactly
      // the confusion the key was meant to remove.
      final columns = await db
          .customSelect('PRAGMA table_info(note_tags)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        isNot(contains('color_value')),
      );
    });

    test('the seeded moods adopt the fixed uids, matched by name', () async {
      final moods = await db.select(db.noteMoods).get();
      final byName = {for (final mood in moods) mood.name: mood.uid};

      for (final seed in defaultNoteMoods) {
        expect(
          byName[seed.name],
          seed.uid,
          reason: 'the seeded "${seed.name}" must carry its fixed uid',
        );
      }
    });

    test('a mood the user invented gets a uid of its own', () async {
      final moods = await db.select(db.noteMoods).get();
      final invented = moods.firstWhere((mood) => mood.name == 'Своё');

      expect(invented.uid, isNotNull);
      expect(
        defaultNoteMoods.map((seed) => seed.uid),
        isNot(contains(invented.uid)),
      );
    });

    test('every uid is distinct', () async {
      final moods = await db.select(db.noteMoods).get();
      final uids = moods.map((mood) => mood.uid).toList();

      expect(uids.toSet(), hasLength(uids.length));
    });

    test('a duplicate of a seeded name does not break the migration', () async {
      // The picker refuses a name it already holds, so this should not exist —
      // but "should not" is a rule of the UI, and the migration runs on data
      // nobody has inspected. Handing both rows the seeded uid would fail the
      // unique index and leave a database that cannot be opened at all.
      final db = AppDatabase.forExecutor(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute(v11Schema);
            raw.execute(
              "INSERT INTO note_moods (name, emoji) VALUES ('Радость', '😊')",
            );
            raw.execute(
              "INSERT INTO note_moods (name, emoji) VALUES ('Радость', '😊')",
            );
            raw.execute('PRAGMA user_version = 11');
          },
        ),
      );
      addTearDown(db.close);

      final moods = await db.select(db.noteMoods).get();
      final uids = moods.map((mood) => mood.uid).toList();

      expect(uids, hasLength(2));
      expect(uids.toSet(), hasLength(2), reason: 'the two must not collide');
      // The older row is the seeded one and keeps the shared identity; the
      // duplicate becomes an ordinary mood of this device's own.
      expect(uids.first, defaultNoteMoods.first.uid);
      expect(uids.last, isNot(defaultNoteMoods.first.uid));
    });

    test('the tombstone table arrives with the migration', () async {
      // Nothing is deleted yet, so the point is only that the table is there to
      // be written to — a delete with nowhere to record itself is a note that
      // comes back on the next pull.
      expect(await db.select(db.syncTombstones).get(), isEmpty);
    });
  });

  group('two devices independently', () {
    test('seed the same eight moods with the same uids', () async {
      // The whole reason the uids are written out in `defaultNoteMoods` instead
      // of generated: seeding runs once per install, so without fixed values
      // one account would collect eight more moods for every phone added.
      final first = AppDatabase.forExecutor(NativeDatabase.memory());
      final second = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(first.close);
      addTearDown(second.close);

      Future<Map<String, String?>> seeded(AppDatabase db) async {
        final moods = await db.select(db.noteMoods).get();
        return {for (final mood in moods) mood.name: mood.uid};
      }

      expect(await seeded(first), await seeded(second));
      expect(
        await seeded(first),
        {for (final seed in defaultNoteMoods) seed.name: seed.uid},
      );
    });
  });
}
