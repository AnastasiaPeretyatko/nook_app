import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'enums.dart';
import 'tables.dart';
import 'daos/tasks_dao.dart';
import 'daos/events_dao.dart';

export 'enums.dart';
export 'tables.dart';
export 'daos/tasks_dao.dart';
export 'daos/events_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Tasks, TaskLogs, TaskSessions, Events],
  daos: [TasksDao, EventsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Injects a custom executor (e.g. an in-memory database in tests).
  AppDatabase.forExecutor(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
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
    },
  );

  Future<Set<String>> _tableColumns(String table) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'todo_app');
}
