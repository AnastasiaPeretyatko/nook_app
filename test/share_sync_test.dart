import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/projects/projects_state.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/sync_controller.dart';
import 'package:todo_app/sync/sync_service.dart';
import 'package:todo_app/utils/shared_note_content.dart';

import 'support/fake_sync_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SyncService service(AppDatabase db, FakeSyncApi api) => SyncService(
    dao: db.diaryDao,
    tasksDao: db.tasksDao,
    cycleDao: db.cycleDao,
    api: api,
    userId: () => 'sync-user',
  );

  Future<ProcessedShareEvent?> receipt(AppDatabase db, String eventId) =>
      (db.select(
        db.processedShareEvents,
      )..where((event) => event.eventId.equals(eventId))).getSingleOrNull();

  test(
    'a share-created note is pushed once and cleared only after success',
    () async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final api = FakeSyncApi();

      final result = await db.diaryDao.createForSharedEvent(
        eventId: 'share-create-sync',
        title: 'Из Share',
        content: const SharedNoteContent('Текст'),
      );
      final created = (await db.diaryDao.getEntry(result.targetDiaryEntryId))!;

      expect(created.uid, isNotEmpty);
      expect(created.dirty, isTrue);
      expect(await service(db, api).sync(), SyncOutcome.done);

      final entries = api.pushed.single['entries'] as List<dynamic>;
      expect(entries, hasLength(1));
      expect(entries.single['id'], created.uid);
      expect(entries.single['body'], '[{"insert":"Текст\\n"}]');
      expect(api.pushed.single.containsKey('processed_share_events'), isFalse);
      expect((await db.diaryDao.getEntry(created.id))!.dirty, isFalse);
      expect(await receipt(db, 'share-create-sync'), isNotNull);

      expect(await service(db, api).sync(), SyncOutcome.done);
      expect(api.pushed, hasLength(1));
      expect(await db.diaryDao.entryCount(), 1);
    },
  );

  test(
    'a share append preserves identity and enters the sync payload',
    () async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final api = FakeSyncApi();
      final noteId = await db.diaryDao.insertEntry(
        DiaryEntriesCompanion.insert(
          title: const Value('Цель'),
          body: const Value('[{"insert":"До\\n"}]'),
        ),
      );
      final before = (await db.diaryDao.getEntry(noteId))!;
      await db.diaryDao.clearEntryDirty({before.uid!: before.updatedAt});

      await db.diaryDao.appendForSharedEvent(
        eventId: 'share-append-sync',
        noteId: noteId,
        content: const SharedNoteContent('Из Share'),
      );
      final appended = (await db.diaryDao.getEntry(noteId))!;

      expect(appended.uid, before.uid);
      expect(appended.updatedAt.isAfter(before.updatedAt), isTrue);
      expect(appended.dirty, isTrue);
      expect(appended.body, '[{"insert":"До\\n"},{"insert":"Из Share\\n"}]');
      expect(await service(db, api).sync(), SyncOutcome.done);

      final entry = (api.pushed.single['entries'] as List<dynamic>).single;
      expect(entry['id'], before.uid);
      expect(entry['body'], appended.body);
      expect((await db.diaryDao.getEntry(noteId))!.dirty, isFalse);
    },
  );

  test(
    'an offline share survives reopening and retries without repeating it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nook_share_sync',
      );
      final file = File('${directory.path}/database.sqlite');
      final first = AppDatabase.forExecutor(NativeDatabase(file));
      final created = await first.diaryDao.createForSharedEvent(
        eventId: 'offline-share',
        title: 'Офлайн',
        content: const SharedNoteContent('Текст'),
      );
      await first.close();

      final reopened = AppDatabase.forExecutor(NativeDatabase(file));
      addTearDown(() async {
        await reopened.close();
        await directory.delete(recursive: true);
      });
      final api = FakeSyncApi()..error = const ApiException.offline();

      expect(
        (await reopened.diaryDao.getEntry(created.targetDiaryEntryId))!.dirty,
        isTrue,
      );
      expect(await service(reopened, api).sync(), SyncOutcome.offline);
      expect(
        (await reopened.diaryDao.getEntry(created.targetDiaryEntryId))!.dirty,
        isTrue,
      );

      api.error = null;
      expect(await service(reopened, api).sync(force: true), SyncOutcome.done);
      expect(
        (await reopened.diaryDao.getEntry(created.targetDiaryEntryId))!.dirty,
        isFalse,
      );

      final duplicate = await reopened.diaryDao.createForSharedEvent(
        eventId: 'offline-share',
        title: 'Не создавать',
        content: const SharedNoteContent('Другой текст'),
      );
      expect(duplicate.didMutate, isFalse);
      expect(await reopened.diaryDao.entryCount(), 1);
    },
  );

  testWidgets('MainActivity reopens diary providers when it resumes', (
    tester,
  ) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({'sync_enabled': false});
    final prefs = await SharedPreferences.getInstance();
    var diarySubscriptions = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          diaryEntriesProvider.overrideWith((ref) {
            diarySubscriptions++;
            return Stream.value(const <DiaryEntry>[]);
          }),
          allTasksProvider.overrideWith((ref) => Stream.value(const [])),
          allLogsProvider.overrideWith((ref) => Stream.value(const [])),
          cycleDaysProvider.overrideWith((ref) => Stream.value(const [])),
          localProjectsChangesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: const SyncScope(child: SizedBox()),
      ),
    );
    await tester.pump();
    expect(diarySubscriptions, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(diarySubscriptions, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
