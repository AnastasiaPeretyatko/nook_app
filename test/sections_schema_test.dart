import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';

void main() {
  test('v23 migration creates sections and preserves existing tasks', () async {
    final db = AppDatabase.forExecutor(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL)',
          );
          raw.execute(
            "INSERT INTO tasks (id, title) VALUES (1, 'Existing task')",
          );
          raw.execute('PRAGMA user_version = 23');
        },
      ),
    );
    addTearDown(db.close);

    final task = await db
        .customSelect('SELECT id, title, section_id FROM tasks')
        .getSingle();
    expect(task.read<int>('id'), 1);
    expect(task.read<String>('title'), 'Existing task');
    expect(task.readNullable<String>('section_id'), isNull);

    final columns = await db.customSelect('PRAGMA table_info(sections)').get();
    expect(
      columns.map((column) => column.read<String>('name')),
      containsAll([
        'id',
        'user_id',
        'project_id',
        'name',
        'position',
        'created_at',
        'updated_at',
      ]),
    );

    final byName = {
      for (final column in columns) column.read<String>('name'): column,
    };
    expect(byName['id']!.read<String>('type'), 'TEXT');
    expect(byName['user_id']!.read<String>('type'), 'TEXT');
    expect(byName['user_id']!.read<int>('notnull'), 1);
    expect(byName['project_id']!.read<String>('type'), 'TEXT');
    expect(byName['project_id']!.read<int>('notnull'), 0);
    expect(byName['position']!.read<String>('type'), 'INTEGER');
    expect(byName['position']!.read<int>('notnull'), 1);
  });
}
