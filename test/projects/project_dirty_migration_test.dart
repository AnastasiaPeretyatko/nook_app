import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';

void main() {
  test('v21 migration preserves pending project intent conservatively', () async {
    final db = AppDatabase.forExecutor(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE tasks (id INTEGER PRIMARY KEY, dirty INTEGER NOT NULL, project_uid TEXT)',
          );
          raw.execute(
            "INSERT INTO tasks VALUES (1, 0, 'project-a'), (2, 1, NULL), (3, 1, 'project-b')",
          );
          raw.execute('PRAGMA user_version = 21');
        },
      ),
    );
    addTearDown(db.close);
    final rows = await db
        .customSelect(
          'SELECT id, project_uid, project_dirty FROM tasks ORDER BY id',
        )
        .get();
    expect(rows.map((row) => row.read<int>('project_dirty')), [0, 1, 1]);
    expect(rows[1].readNullable<String>('project_uid'), isNull);
    expect(rows[2].read<String>('project_uid'), 'project-b');
  });
}
