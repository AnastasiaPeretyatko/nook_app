import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';

void main() {
  test(
    'fresh database contains the local processed-share-events table',
    () async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);

      final columns = await db
          .customSelect('PRAGMA table_info(processed_share_events)')
          .get();
      final byName = {
        for (final column in columns) column.read<String>('name'): column,
      };
      expect(
        byName.keys,
        containsAll([
          'event_id',
          'operation',
          'target_diary_entry_id',
          'processed_at',
        ]),
      );
      expect(byName['event_id']!.read<int>('pk'), 1);
      expect(byName['target_diary_entry_id']!.read<int>('notnull'), 0);
    },
  );

  test('v25 migration preserves diary rows and creates the receipt table', () async {
    final db = AppDatabase.forExecutor(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE diary_entries (id INTEGER PRIMARY KEY, title TEXT NOT NULL)',
          );
          raw.execute(
            "INSERT INTO diary_entries (id, title) VALUES (1, 'Существующая заметка')",
          );
          raw.execute('PRAGMA user_version = 25');
        },
      ),
    );
    addTearDown(db.close);

    final diary = await db
        .customSelect('SELECT id, title FROM diary_entries')
        .getSingle();
    expect(diary.read<int>('id'), 1);
    expect(diary.read<String>('title'), 'Существующая заметка');
    final table = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'processed_share_events'",
        )
        .getSingleOrNull();
    expect(table, isNotNull);
  });

  test(
    'receipts are unique, local-only, and may outlive their target note',
    () async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final receipt = ProcessedShareEventsCompanion.insert(
        eventId: 'share-event-1',
        operation: 'append',
        targetDiaryEntryId: const Value(999),
      );

      await db.into(db.processedShareEvents).insert(receipt);
      final stored = await db.select(db.processedShareEvents).getSingle();
      expect(stored.eventId, 'share-event-1');
      expect(stored.operation, 'append');
      expect(stored.targetDiaryEntryId, 999);
      expect(stored.processedAt, isA<DateTime>());
      await expectLater(
        db.into(db.processedShareEvents).insert(receipt),
        throwsA(isA<Exception>()),
      );

      final foreignKeys = await db
          .customSelect('PRAGMA foreign_key_list(processed_share_events)')
          .get();
      final columns = await db
          .customSelect('PRAGMA table_info(processed_share_events)')
          .get();
      expect(foreignKeys, isEmpty);
      expect(
        columns.map((column) => column.read<String>('name')),
        isNot(containsAll(['uid', 'dirty'])),
      );
      expect(await db.select(db.syncTombstones).get(), isEmpty);
    },
  );
}
