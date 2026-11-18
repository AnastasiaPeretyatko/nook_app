import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/shared_note_content.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DiaryDao dao;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    dao = db.diaryDao;
  });

  tearDown(() => db.close());

  Future<int> addNote(String title, {String body = '[{"insert":"До\\n"}]'}) =>
      dao.insertEntry(
        DiaryEntriesCompanion.insert(title: Value(title), body: Value(body)),
      );

  Future<ProcessedShareEvent?> receipt(String eventId) => (db.select(
    db.processedShareEvents,
  )..where((row) => row.eventId.equals(eventId))).getSingleOrNull();

  test('creates a dirty note and receipt for a first share event', () async {
    final result = await dao.createForSharedEvent(
      eventId: 'create-1',
      title: 'Из Share',
      content: const SharedNoteContent('Текст'),
    );

    final note = await dao.getEntry(result.targetDiaryEntryId);
    expect(result.didMutate, isTrue);
    expect(note!.title, 'Из Share');
    expect(note.body, '[{"insert":"Текст\\n"}]');
    expect(note.dirty, isTrue);
    expect((await receipt('create-1'))!.operation, 'create');
    expect((await receipt('create-1'))!.targetDiaryEntryId, note.id);
  });

  test(
    'repeated create returns its original note without another insert',
    () async {
      final first = await dao.createForSharedEvent(
        eventId: 'create-duplicate',
        title: 'Первый',
        content: const SharedNoteContent('Один'),
      );
      final duplicate = await dao.createForSharedEvent(
        eventId: 'create-duplicate',
        title: 'Другой',
        content: const SharedNoteContent('Два'),
      );

      expect(duplicate.targetDiaryEntryId, first.targetDiaryEntryId);
      expect(duplicate.didMutate, isFalse);
      expect(await dao.entryCount(), 1);
      expect((await dao.getEntry(first.targetDiaryEntryId))!.title, 'Первый');
    },
  );

  test(
    'appends once at the end and preserves existing Delta operations',
    () async {
      final noteId = await addNote(
        'Цель',
        body: '[{"insert":"Жирный\\n","attributes":{"bold":true}}]',
      );
      final result = await dao.appendForSharedEvent(
        eventId: 'append-1',
        noteId: noteId,
        content: const SharedNoteContent('Из Share'),
      );

      final note = (await dao.getEntry(noteId))!;
      expect(result, ShareEventResult(noteId, didMutate: true));
      expect(
        note.body,
        '[{"insert":"Жирный\\n","attributes":{"bold":true}},{"insert":"Из Share\\n"}]',
      );
      expect(note.dirty, isTrue);
      expect((await receipt('append-1'))!.operation, 'append');
      expect((await receipt('append-1'))!.targetDiaryEntryId, noteId);
    },
  );

  test('repeated append does not add the shared text twice', () async {
    final noteId = await addNote('Цель');
    await dao.appendForSharedEvent(
      eventId: 'append-duplicate',
      noteId: noteId,
      content: const SharedNoteContent('Текст'),
    );
    final duplicate = await dao.appendForSharedEvent(
      eventId: 'append-duplicate',
      noteId: noteId,
      content: const SharedNoteContent('Текст'),
    );

    expect(duplicate.didMutate, isFalse);
    expect(
      (await dao.getEntry(noteId))!.body,
      '[{"insert":"До\\n"},{"insert":"Текст\\n"}]',
    );
  });

  test('different event IDs with identical text are independent', () async {
    final noteId = await addNote('Цель');
    await dao.appendForSharedEvent(
      eventId: 'append-a',
      noteId: noteId,
      content: const SharedNoteContent('Одинаковый'),
    );
    await dao.appendForSharedEvent(
      eventId: 'append-b',
      noteId: noteId,
      content: const SharedNoteContent('Одинаковый'),
    );

    expect(
      (await dao.getEntry(noteId))!.body,
      '[{"insert":"До\\n"},{"insert":"Одинаковый\\n"},{"insert":"Одинаковый\\n"}]',
    );
  });

  test(
    'event IDs cannot be reused for another operation or append target',
    () async {
      final first = await addNote('Первая');
      final second = await addNote('Вторая');
      await dao.createForSharedEvent(
        eventId: 'conflict-operation',
        title: 'Создана',
        content: const SharedNoteContent('Текст'),
      );
      await dao.appendForSharedEvent(
        eventId: 'conflict-target',
        noteId: first,
        content: const SharedNoteContent('Текст'),
      );

      await expectLater(
        dao.appendForSharedEvent(
          eventId: 'conflict-operation',
          noteId: first,
          content: const SharedNoteContent('Текст'),
        ),
        throwsA(isA<ShareEventConflict>()),
      );
      await expectLater(
        dao.appendForSharedEvent(
          eventId: 'conflict-target',
          noteId: second,
          content: const SharedNoteContent('Текст'),
        ),
        throwsA(isA<ShareEventConflict>()),
      );
    },
  );

  test('an append failure rolls back its receipt', () async {
    await expectLater(
      dao.appendForSharedEvent(
        eventId: 'missing-target',
        noteId: 404,
        content: const SharedNoteContent('Текст'),
      ),
      throwsA(isA<ShareEventTargetNotFound>()),
    );

    expect(await receipt('missing-target'), isNull);
  });

  test('a simulated insert failure rolls back its receipt', () async {
    await db.customStatement('''
      CREATE TRIGGER reject_shared_create
      BEFORE INSERT ON diary_entries
      BEGIN SELECT RAISE(ABORT, 'simulated insert failure'); END;
    ''');

    await expectLater(
      dao.createForSharedEvent(
        eventId: 'failed-create',
        title: 'Не сохранять',
        content: const SharedNoteContent('Текст'),
      ),
      throwsA(isA<Exception>()),
    );
    expect(await dao.entryCount(), 0);
    expect(await receipt('failed-create'), isNull);
  });

  test('a simulated append failure rolls back its receipt', () async {
    final noteId = await addNote('Цель');
    await db.customStatement('''
      CREATE TRIGGER reject_shared_append
      BEFORE UPDATE ON diary_entries
      BEGIN SELECT RAISE(ABORT, 'simulated append failure'); END;
    ''');

    await expectLater(
      dao.appendForSharedEvent(
        eventId: 'failed-append',
        noteId: noteId,
        content: const SharedNoteContent('Текст'),
      ),
      throwsA(isA<Exception>()),
    );
    expect((await dao.getEntry(noteId))!.body, '[{"insert":"До\\n"}]');
    expect(await receipt('failed-append'), isNull);
  });

  test('duplicate create survives database reopening', () async {
    final directory = await Directory.systemTemp.createTemp('nook_share_event');
    final file = File('${directory.path}/database.sqlite');
    final firstDb = AppDatabase.forExecutor(NativeDatabase(file));
    final first = await firstDb.diaryDao.createForSharedEvent(
      eventId: 'reopen',
      title: 'Сохранённая',
      content: const SharedNoteContent('Текст'),
    );
    await firstDb.close();
    final reopened = AppDatabase.forExecutor(NativeDatabase(file));
    addTearDown(() async {
      await reopened.close();
      await directory.delete(recursive: true);
    });

    final duplicate = await reopened.diaryDao.createForSharedEvent(
      eventId: 'reopen',
      title: 'Не создавать',
      content: const SharedNoteContent('Другой текст'),
    );
    expect(duplicate.targetDiaryEntryId, first.targetDiaryEntryId);
    expect(duplicate.didMutate, isFalse);
    expect(await reopened.diaryDao.entryCount(), 1);
  });

  test('duplicate create is safe under concurrent requests', () async {
    final results = await Future.wait([
      dao.createForSharedEvent(
        eventId: 'concurrent',
        title: 'Одна',
        content: const SharedNoteContent('Текст'),
      ),
      dao.createForSharedEvent(
        eventId: 'concurrent',
        title: 'Другая',
        content: const SharedNoteContent('Текст'),
      ),
    ]);

    expect(await dao.entryCount(), 1);
    expect(results.where((result) => result.didMutate), hasLength(1));
    expect(
      results.map((result) => result.targetDiaryEntryId).toSet(),
      hasLength(1),
    );
  });

  test('duplicate append is safe under concurrent requests', () async {
    final noteId = await addNote('Цель');

    final results = await Future.wait([
      dao.appendForSharedEvent(
        eventId: 'concurrent-append',
        noteId: noteId,
        content: const SharedNoteContent('Текст'),
      ),
      dao.appendForSharedEvent(
        eventId: 'concurrent-append',
        noteId: noteId,
        content: const SharedNoteContent('Текст'),
      ),
    ]);

    expect(results.where((result) => result.didMutate), hasLength(1));
    expect(
      (await dao.getEntry(noteId))!.body,
      '[{"insert":"До\\n"},{"insert":"Текст\\n"}]',
    );
  });

  test(
    'a duplicate create remains a duplicate after its note is deleted',
    () async {
      final first = await dao.createForSharedEvent(
        eventId: 'deleted-target',
        title: 'Удаляемая',
        content: const SharedNoteContent('Текст'),
      );
      await dao.deleteEntry(first.targetDiaryEntryId);

      final duplicate = await dao.createForSharedEvent(
        eventId: 'deleted-target',
        title: 'Не создавать',
        content: const SharedNoteContent('Другой текст'),
      );
      expect(duplicate.targetDiaryEntryId, first.targetDiaryEntryId);
      expect(duplicate.didMutate, isFalse);
      expect(await dao.entryCount(), 0);
    },
  );

  test(
    'a duplicate append remains a duplicate after its target is deleted',
    () async {
      final noteId = await addNote('Удаляемая');
      await dao.appendForSharedEvent(
        eventId: 'deleted-append-target',
        noteId: noteId,
        content: const SharedNoteContent('Текст'),
      );
      await dao.deleteEntry(noteId);

      final duplicate = await dao.appendForSharedEvent(
        eventId: 'deleted-append-target',
        noteId: noteId,
        content: const SharedNoteContent('Другой текст'),
      );
      expect(duplicate, ShareEventResult(noteId, didMutate: false));
      expect(await dao.entryCount(), 0);
    },
  );
}
