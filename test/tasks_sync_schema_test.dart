import 'package:drift/drift.dart'
    show driftRuntimeOptions, BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';

/// The schema v14 migration: what tasks, habits and their day marks need before
/// any of them can leave the device.
///
/// Run against a **real v13 database with rows in it**, the way
/// `sync_schema_test.dart` does for v12: `NativeDatabase.memory(setup:)` hands
/// over the raw connection before drift touches it, so the old schema is built
/// by hand and `user_version` set to 13, which is what makes the next query run
/// `onUpgrade` for real.
///
/// "With rows in it" is the load-bearing half here, not a nicety. Two of the
/// three things this migration does are invisible on an empty table:
///
///   * `ALTER TABLE ... ADD COLUMN` is refused by SQLite when the default is
///     not a constant — and refused **only** when the table already has rows.
///     An empty one accepts `CURRENT_TIMESTAMP` without complaint. So the
///     obvious spelling of `task_logs.updated_at` migrates a developer's phone
///     and bricks every phone that has ever ticked a day.
///   * Folding the logs onto their days, and merging the rows that turn out to
///     share one, has nothing to do on a table with no history.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// `tasks` and `task_logs` exactly as schema 13 left them: no `uid`, no
  /// `dirty`, no `updated_at` on a log, and **no unique index** over the pair
  /// that identifies one. The diary's tables are left out — the v14 branch
  /// never looks at them, and `PRAGMA table_info` on a table that is not there
  /// simply returns nothing.
  const v13Schema = '''
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
''';

  /// A day, as the old schema stored one: whole seconds since the epoch.
  int stored(DateTime moment) => moment.millisecondsSinceEpoch ~/ 1000;

  final cleanDay = DateTime(2026, 8, 20);
  final splitDay = DateTime(2026, 8, 21);
  final subtaskDay = DateTime(2026, 8, 22);

  /// A device on schema 13 with a habit, a subtask and four logged days — one
  /// of which is two rows wearing different times of day.
  AppDatabase openV13() {
    return AppDatabase.forExecutor(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(v13Schema);
          raw.execute(
            "INSERT INTO tasks (title, repeat_type) VALUES ('Зарядка', 'daily')",
          );
          raw.execute(
            "INSERT INTO tasks (parent_id, title) VALUES (1, 'Разминка')",
          );

          void log(int taskId, DateTime at, bool completed, double? value) {
            raw.execute(
              'INSERT INTO task_logs (task_id, date, completed, value) '
              'VALUES (?, ?, ?, ?)',
              [taskId, stored(at), completed ? 1 : 0, value],
            );
          }

          // id 1 — already a day, nothing to do to it.
          log(1, cleanDay, true, null);

          // id 2 and id 3 are the same calendar day arriving twice, which is
          // what the timeline could produce: `HomePage` opens on
          // `DateTime.now()`, so the first tick of a session carried a time.
          // Deliberately the lower id is the one wearing a time **and** the one
          // that is not ticked, so the test can tell a rewrite from a merge:
          // the survivor has to move to midnight *and* pick up the tick and the
          // larger value from the row that is dropped.
          log(1, splitDay.add(const Duration(hours: 14, minutes: 32)), false,
              3.0);
          log(1, splitDay, true, 1.0);

          // A subtask logs against its parent's anchor, and it too could carry
          // a time.
          log(2, subtaskDay.add(const Duration(hours: 9, minutes: 15)), true,
              null);

          raw.execute('PRAGMA user_version = 13');
        },
      ),
    );
  }

  group('upgrading a device that already has habits', () {
    late AppDatabase db;

    setUp(() => db = openV13());
    tearDown(() => db.close());

    test('the migration runs at all on tables that have rows', () async {
      // The whole point of the epoch default on `task_logs.updated_at`. If the
      // column were declared the obvious way — `withDefault(currentDateAndTime)`
      // — this first query would throw "Cannot add a column with non-constant
      // default" and the database would never open. On an empty task_logs it
      // would pass.
      final logs = await db.select(db.taskLogs).get();
      expect(logs, isNotEmpty);
    });

    test('every log sits on the local midnight of its day', () async {
      final logs = await db.select(db.taskLogs).get();

      for (final log in logs) {
        expect(
          log.date,
          DateTime(log.date.year, log.date.month, log.date.day),
          reason: 'a log still carries a time of day: ${log.date}',
        );
      }
    });

    test('two rows for one day are merged, not picked between', () async {
      final logs = await (db.select(db.taskLogs)
            ..where((l) => l.taskId.equals(1) & l.date.equals(splitDay)))
          .get();

      expect(logs, hasLength(1), reason: 'the duplicate survived');
      // Both halves of the merge: the tick came from the row that was dropped
      // and the value is the larger of the two.
      expect(logs.single.completed, isTrue);
      expect(logs.single.value, 3.0);
    });

    test('a day that was never duplicated is left as it was', () async {
      final logs = await (db.select(db.taskLogs)
            ..where((l) => l.taskId.equals(1) & l.date.equals(cleanDay)))
          .get();

      expect(logs, hasLength(1));
      expect(logs.single.completed, isTrue);
      expect(logs.single.value, isNull);
    });

    test('getLogForDate no longer throws on the day that had two rows',
        () async {
      // The reason the index matters at all: the read goes through
      // `getSingleOrNull()`, which throws on a second row — and with it
      // `setLog`, `incrementCounter`, `toggleCompletion` and the task form.
      final log = await db.tasksDao.getLogForDate(1, splitDay);

      expect(log, isNotNull);
      expect(log!.completed, isTrue);
    });

    test('a log is stamped with the day it is about, not with the epoch',
        () async {
      final logs = await db.select(db.taskLogs).get();

      for (final log in logs) {
        expect(
          log.updatedAt,
          log.date,
          reason: 'a log kept the column default instead of being stamped',
        );
      }
    });

    test('a task written before the migration is given a uid', () async {
      final rows = await db.select(db.tasks).get();

      expect(rows, hasLength(2));
      for (final task in rows) {
        expect(task.uid, isNotNull);
        expect(task.uid, isNotEmpty);
      }
      // A subtask is a row of its own on the server, so it needs its own
      // identity — not its parent's.
      expect(rows.first.uid, isNot(rows.last.uid));
    });

    test('everything already here counts as unsent', () async {
      // Nothing has been offered to a server yet, so every row is waiting. What
      // happens to it is the first-sync question's business, not the schema's.
      final rows = await db.select(db.tasks).get();
      final logs = await db.select(db.taskLogs).get();

      expect(rows.every((t) => t.dirty), isTrue);
      expect(logs.every((l) => l.dirty), isTrue);
    });

    test('the pair of a log is unique from now on', () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name IN ('task_logs_task_day', 'tasks_uid')",
          )
          .get();

      expect(
        indexes.map((r) => r.read<String>('name')).toSet(),
        {'task_logs_task_day', 'tasks_uid'},
      );
    });
  });
}
