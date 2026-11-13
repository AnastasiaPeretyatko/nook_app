import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/sync/sync_service.dart';

import 'support/fake_sync_api.dart';

void main() {
  test(
    'pushes sections before tasks and preserves section_id patches',
    () async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final api = FakeSyncApi();
      final section = await db.sectionsDao.createSection(
        userId: 'me',
        name: 'Inbox',
        position: 0,
      );
      await db.tasksDao.insertTask(
        TasksCompanion.insert(title: 'Task', sectionId: Value(section.id)),
      );

      final outcome = await SyncService(
        dao: db.diaryDao,
        tasksDao: db.tasksDao,
        cycleDao: db.cycleDao,
        api: api,
        userId: () => 'me',
      ).sync();

      expect(outcome, SyncOutcome.done);
      final body = api.pushed.single;
      expect(body.keys.toList(), ['sections', 'tasks']);
      expect((body['tasks'] as List).single['section_id'], section.id);
      expect(await db.sectionsDao.pendingSections(), isEmpty);
    },
  );

  test('pulls remote sections before tasks and applies deletion', () async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final api = FakeSyncApi();
    api.pullAnswers
      ..clear()
      ..add({
        'next': null,
        'has_more': false,
        'groups': {'groups': [], 'members': []},
        'sections': [
          {
            'id': 's-1',
            'project_id': null,
            'name': 'Remote',
            'position': 2,
            'created_at': '2026-01-01T00:00:00Z',
            'client_updated_at': '2026-01-02T00:00:00Z',
            'deleted_at': null,
          },
        ],
        'tasks': [],
        'logs': [],
      });

    await SyncService(
      dao: db.diaryDao,
      tasksDao: db.tasksDao,
      cycleDao: db.cycleDao,
      api: api,
      userId: () => 'me',
    ).sync();

    expect((await db.sectionsDao.sectionById('s-1'))!.dirty, isFalse);
  });
}
