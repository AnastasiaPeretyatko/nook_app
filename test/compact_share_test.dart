import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/share_to_nook/compact_share.dart';
import 'package:todo_app/share_to_nook/editor_lock_bridge.dart';
import 'package:todo_app/utils/shared_note_content.dart';

class _FakeEditorLockBridge implements EditorLockBridge {
  _FakeEditorLockBridge({Set<int>? lockedIds})
    : lockedIds = lockedIds ?? <int>{};

  Set<int> lockedIds;
  bool shouldFail = false;
  bool acquisitionSucceeds = true;
  bool releaseSucceeds = true;
  bool throwOnAcquire = false;
  bool throwOnRelease = false;
  int lockedIdsCalls = 0;
  int acquisitionCalls = 0;
  int releaseCalls = 0;
  final acquiredNoteIds = <int>[];
  final releasedNoteIds = <int>[];

  @override
  Future<List<int>> getLockedIds() async {
    lockedIdsCalls++;
    if (shouldFail) throw StateError('editor lock unavailable');
    return lockedIds.toList();
  }

  @override
  Future<String> newOwner() async => 'share-owner';

  @override
  Future<bool> release({required int noteId, required String ownerId}) async {
    releaseCalls++;
    releasedNoteIds.add(noteId);
    if (throwOnRelease) throw StateError('release failed');
    return releaseSucceeds;
  }

  @override
  Future<int> releaseAll(String ownerId) => throw UnimplementedError();

  @override
  Future<bool> isLocked(int noteId) => throw UnimplementedError();

  @override
  Future<bool> tryAcquire({
    required int noteId,
    required String ownerId,
  }) async {
    acquisitionCalls++;
    acquiredNoteIds.add(noteId);
    if (throwOnAcquire) throw StateError('acquisition failed');
    return acquisitionSucceeds;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('test/compact-share');
  const platform = MethodChannel('flutter/platform', JSONMethodCodec());

  Future<AppDatabase> open(
    WidgetTester tester, {
    List<String>? acknowledgements,
    bool acknowledgementFails = false,
    int acknowledgementFailures = 0,
    Future<ShareEventResult> Function({
      required String eventId,
      required String title,
      required SharedNoteContent content,
    })?
    createForSharedEvent,
    Future<ShareEventResult> Function({
      required String eventId,
      required int noteId,
      required SharedNoteContent content,
    })?
    appendForSharedEvent,
    EditorLockBridge? editorLockBridge,
    AppDatabase? database,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = database ?? AppDatabase.forExecutor(NativeDatabase.memory());
    var remainingAcknowledgementFailures = acknowledgementFailures;
    if (database == null) addTearDown(db.close);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          if (call.method == 'takePending') {
            return [
              {'id': 'event-1', 'text': 'x'},
            ];
          }
          if (call.method == 'acknowledge') {
            if (acknowledgementFails || remainingAcknowledgementFailures > 0) {
              remainingAcknowledgementFailures--;
              throw PlatformException(code: 'acknowledgement-failed');
            }
            if (acknowledgements == null) {
              fail('unexpected native call: ${call.method}');
            }
            acknowledgements.add((call.arguments as Map)['id'] as String);
            return null;
          }
          fail('unexpected native call: ${call.method}');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: CompactShareApp(
          bridge: bridge,
          createForSharedEvent: createForSharedEvent,
          appendForSharedEvent: appendForSharedEvent,
          editorLockBridge: editorLockBridge ?? _FakeEditorLockBridge(),
        ),
      ),
    );
    await tester.pump();
    return db;
  }

  Future<int> addNote(
    AppDatabase db, {
    required String title,
    required String body,
    DiaryEntryStatus status = DiaryEntryStatus.normal,
    DateTime? updatedAt,
  }) => db.diaryDao.insertEntry(
    DiaryEntriesCompanion.insert(
      title: Value(title),
      body: Value(body),
      status: Value(status),
      updatedAt: updatedAt == null ? const Value.absent() : Value(updatedAt),
    ),
  );

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'opens a prefilled create form and preserves local edits on rebuild',
    (tester) async {
      await open(tester);
      expect(find.text('Сохранить в Nook'), findsOneWidget);
      expect(find.text('Создать новую заметку'), findsOneWidget);
      expect(find.text('Добавить к существующей'), findsOneWidget);

      await tester.tap(find.text('Создать новую заметку'));
      await tester.pump();
      await tester.tap(find.text('Продолжить'));
      await tester.pump();

      expect(find.text('Новая заметка'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        'x',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Сохранить'),
            )
            .onPressed,
        isNotNull,
      );

      await tester.enterText(find.byType(TextField).at(0), 'Заголовок');
      await tester.enterText(find.byType(TextField).at(1), 'Изменённый текст');
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        'Заголовок',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        'Изменённый текст',
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Сохранить в Nook'), findsOneWidget);

      // A back action only changes compact navigation; the bridge mock fails
      // this test if the app tries to acknowledge the pending event.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Сохранить в Nook'), findsOneWidget);
    },
  );

  testWidgets(
    'append backs to start and outside tap exits without acknowledgement',
    (tester) async {
      var exits = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (call) async {
            if (call.method == 'SystemNavigator.pop') {
              exits++;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(platform, null),
      );
      await open(tester);
      await tester.tap(find.text('Добавить к существующей'));
      await tester.pump();
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      expect(find.text('Последние заметки'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Сохранить в Nook'), findsOneWidget);

      await tester.tap(find.text('Добавить к существующей'));
      await tester.pump();
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Назад'));
      await tester.pump();
      expect(find.text('Сохранить в Nook'), findsOneWidget);
      await tester.tapAt(const Offset(1, 1));
      await tester.pump();
      expect(exits, 1);
      await disposeTree(tester);
    },
  );

  testWidgets('close from the create form requests Activity exit', (
    tester,
  ) async {
    var exits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'SystemNavigator.pop') {
            exits++;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null),
    );
    await open(tester);
    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.tapAt(const Offset(1, 1));
    await tester.pump();
    expect(exits, 1);
  });

  testWidgets('close from the start screen requests Activity exit', (
    tester,
  ) async {
    var exits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'SystemNavigator.pop') {
            exits++;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null),
    );
    await open(tester);
    await tester.tapAt(const Offset(1, 1));
    await tester.pump();
    expect(exits, 1);
  });

  testWidgets('saves title and body as a dirty Delta then acknowledges', (
    tester,
  ) async {
    final acknowledgements = <String>[];
    final db = await open(tester, acknowledgements: acknowledgements);

    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'Моя заметка');
    await tester.enterText(find.byType(TextField).at(1), 'Текст заметки');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final entry = await db.diaryDao.getEntry(1);
    expect(entry, isNotNull);
    expect(entry!.title, 'Моя заметка');
    expect(jsonDecode(entry.body), [
      {'insert': 'Текст заметки\n'},
    ]);
    expect(entry.dirty, isTrue);
    expect(entry.uid, isNotEmpty);
    expect(entry.coverImage, isNull);
    expect(entry.images, '[]');
    expect(entry.isFavorite, isFalse);
    expect(entry.status, DiaryEntryStatus.normal);
    expect(acknowledgements, ['event-1']);
  });

  testWidgets('saves a note without a title', (tester) async {
    final acknowledgements = <String>[];
    final db = await open(tester, acknowledgements: acknowledgements);

    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final entry = await db.diaryDao.getEntry(1);
    expect(entry!.title, isEmpty);
    expect(jsonDecode(entry.body), [
      {'insert': 'x\n'},
    ]);
    expect(acknowledgements, ['event-1']);
  });

  testWidgets(
    'keeps form content and skips acknowledgement after a write error',
    (tester) async {
      final acknowledgements = <String>[];
      await open(
        tester,
        acknowledgements: acknowledgements,
        createForSharedEvent:
            ({required eventId, required title, required content}) =>
                Future<ShareEventResult>.error(StateError('database failed')),
      );

      await tester.tap(find.text('Создать новую заметку'));
      await tester.pump();
      await tester.tap(find.text('Продолжить'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'Черновик');
      await tester.enterText(find.byType(TextField).at(1), 'Не терять');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(find.text('Не удалось сохранить заметку'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        'Черновик',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        'Не терять',
      );
      expect(acknowledgements, isEmpty);
    },
  );

  testWidgets('does not insert twice when acknowledgement fails', (
    tester,
  ) async {
    final db = await open(tester, acknowledgementFails: true);

    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(await db.diaryDao.entryCount(), 1);
    expect(find.text('Заметка сохранена, но не подтверждена'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('disables repeated Save while an insertion is active', (
    tester,
  ) async {
    final insertion = Completer<ShareEventResult>();
    final acknowledgements = <String>[];
    var writes = 0;
    await open(
      tester,
      acknowledgements: acknowledgements,
      createForSharedEvent:
          ({required eventId, required title, required content}) {
            writes++;
            return insertion.future;
          },
    );

    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(FilledButton));
    expect(writes, 1);
    insertion.complete(const ShareEventResult(1, didMutate: true));
    await tester.pumpAndSettle();
    expect(writes, 1);
  });

  testWidgets('shows completion then exits once after persistence and ack', (
    tester,
  ) async {
    var exits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null),
    );
    final acknowledgements = <String>[];
    await open(tester, acknowledgements: acknowledgements);

    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Заметка сохранена'), findsOneWidget);
    expect(acknowledgements, ['event-1']);
    expect(exits, 0);
    await tester.pump(const Duration(milliseconds: 799));
    expect(exits, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(exits, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(exits, 1);
  });

  testWidgets('disposing the confirmation cancels its delayed exit', (
    tester,
  ) async {
    var exits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null),
    );
    await open(tester, acknowledgements: <String>[]);

    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Заметка сохранена'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(exits, 0);
  });

  testWidgets('retries acknowledgement without inserting the note again', (
    tester,
  ) async {
    final acknowledgements = <String>[];
    final db = await open(
      tester,
      acknowledgements: acknowledgements,
      acknowledgementFailures: 1,
    );

    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(await db.diaryDao.entryCount(), 1);
    expect(find.text('Заметка сохранена, но не подтверждена'), findsOneWidget);
    await tester.tap(find.text('Повторить подтверждение'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Заметка сохранена'), findsOneWidget);
    expect(await db.diaryDao.entryCount(), 1);
    expect(acknowledgements, ['event-1']);
  });

  testWidgets(
    'recreated compact root acknowledges a redelivered event without a duplicate note',
    (tester) async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);

      await open(tester, database: db, acknowledgementFailures: 1);
      await tester.tap(find.text('Создать новую заметку'));
      await tester.pump();
      await tester.tap(find.text('Продолжить'));
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(await db.diaryDao.entryCount(), 1);
      expect(
        find.text('Заметка сохранена, но не подтверждена'),
        findsOneWidget,
      );

      // This recreates Flutter objects only; it is not an Android process-death
      // simulation. The durable receipt in the shared database is the boundary
      // under test.
      await disposeTree(tester);

      final acknowledgements = <String>[];
      await open(tester, database: db, acknowledgements: acknowledgements);
      await tester.tap(find.text('Создать новую заметку'));
      await tester.pump();
      await tester.tap(find.text('Продолжить'));
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(await db.diaryDao.entryCount(), 1);
      expect(acknowledgements, ['event-1']);
      expect(find.text('Заметка сохранена'), findsOneWidget);
      await disposeTree(tester);
    },
  );

  testWidgets('shows non-archived notes with an empty-title fallback', (
    tester,
  ) async {
    final db = await open(tester);
    final visible = await addNote(
      db,
      title: 'Видимая',
      body: '[{"insert":"тело\\n"}]',
      updatedAt: DateTime(2026, 2, 1),
    );
    final unnamed = await addNote(
      db,
      title: '',
      body: '[{"insert":"без имени\\n"}]',
      updatedAt: DateTime(2026, 1, 1),
    );
    await addNote(
      db,
      title: 'Архивная',
      body: '[{"insert":"не показывать\\n"}]',
      status: DiaryEntryStatus.archived,
    );
    await tester.pump();

    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('compact-note-$visible')), findsOneWidget);
    expect(find.byKey(ValueKey('compact-note-$unnamed')), findsOneWidget);
    expect(find.text('Без названия'), findsOneWidget);
    expect(find.text('Архивная'), findsNothing);
    expect(find.text('тело'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(ValueKey('compact-note-$visible'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(ValueKey('compact-note-$unnamed'))).dy,
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await disposeTree(tester);
  });

  testWidgets('searches titles and bodies and reports empty results', (
    tester,
  ) async {
    final db = await open(tester);
    await addNote(
      db,
      title: 'Планы',
      body: '[{"insert":"Найти иглу в стоге\\n"}]',
    );
    await addNote(db, title: 'Покупки', body: '[{"insert":"молоко\\n"}]');
    await tester.pump();
    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('compact-note-search')),
      'иглу',
    );
    await tester.pump();
    expect(find.text('Результаты поиска'), findsOneWidget);
    expect(find.text('Планы'), findsOneWidget);
    expect(find.text('Покупки'), findsNothing);
    expect(find.text('Найти иглу в стоге'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('compact-note-search')),
      'отсутствует',
    );
    await tester.pump();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets(
    'keeps exactly one selected note through a rebuild without writes',
    (tester) async {
      final db = await open(tester);
      final first = await addNote(
        db,
        title: 'Первая',
        body: '[{"insert":"Первое тело\\n"}]',
      );
      final second = await addNote(
        db,
        title: 'Вторая',
        body: '[{"insert":"Второе тело\\n"}]',
      );
      await tester.pump();
      await tester.tap(find.text('Добавить к существующей'));
      await tester.pump();
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('compact-note-$first')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('compact-note-$second')));
      await tester.pump();
      await tester.pump();
      expect(
        (await db.diaryDao.getEntry(second))!.body,
        '[{"insert":"Второе тело\\n"}]',
      );
      await disposeTree(tester);
    },
  );

  testWidgets('shows locked notes but only permits selecting unlocked notes', (
    tester,
  ) async {
    final locks = _FakeEditorLockBridge();
    final db = await open(tester, editorLockBridge: locks);
    final locked = await addNote(
      db,
      title: 'Открытая заметка',
      body: '[{"insert":"тело\\n"}]',
    );
    final available = await addNote(
      db,
      title: 'Доступная заметка',
      body: '[{"insert":"тело\\n"}]',
    );
    locks.lockedIds = {locked};
    await tester.pump();

    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    final lockedTile = find.byKey(ValueKey('compact-note-$locked'));
    expect(lockedTile, findsOneWidget);
    expect(
      find.descendant(
        of: lockedTile,
        matching: find.byIcon(Icons.lock_outline),
      ),
      findsOneWidget,
    );
    expect(find.text('Открыта в редакторе'), findsOneWidget);
    await tester.tap(lockedTile);
    await tester.pump();

    final availableTile = find.byKey(ValueKey('compact-note-$available'));
    await tester.tap(availableTile);
    await tester.pump();
    await disposeTree(tester);
  });

  testWidgets('refresh clears a selection that becomes locked', (tester) async {
    final locks = _FakeEditorLockBridge();
    final db = await open(tester, editorLockBridge: locks);
    final note = await addNote(
      db,
      title: 'Меняющаяся заметка',
      body: '[{"insert":"тело\\n"}]',
    );
    await tester.pump();
    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    final tile = find.byKey(ValueKey('compact-note-$note'));
    await tester.tap(tile);
    await tester.pump();

    locks.lockedIds = {note};
    await tester.tap(find.byKey(const Key('compact-note-lock-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('Открыта в редакторе'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets(
    'fails closed and offers retry when editor locks are unavailable',
    (tester) async {
      final locks = _FakeEditorLockBridge()..shouldFail = true;
      final db = await open(tester, editorLockBridge: locks);
      final note = await addNote(
        db,
        title: 'Заметка',
        body: '[{"insert":"тело\\n"}]',
      );
      await tester.pump();
      await tester.tap(find.text('Добавить к существующей'));
      await tester.pump();
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();

      expect(
        find.text('Не удалось проверить открытые заметки'),
        findsOneWidget,
      );
      final tile = find.byKey(ValueKey('compact-note-$note'));
      await tester.tap(tile);
      await tester.pump();

      locks.shouldFail = false;
      await tester.tap(find.byKey(const Key('compact-note-lock-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Не удалось проверить открытые заметки'), findsNothing);
      await tester.tap(tile);
      await tester.pump();
      await disposeTree(tester);
    },
  );

  testWidgets('appends at the end, preserves Delta formatting, and exits', (
    tester,
  ) async {
    var exits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null),
    );
    final locks = _FakeEditorLockBridge();
    final acknowledgements = <String>[];
    final db = await open(
      tester,
      acknowledgements: acknowledgements,
      editorLockBridge: locks,
    );
    final note = await addNote(
      db,
      title: 'Форматированная',
      body: '[{"insert":"Жирный текст\\n","attributes":{"bold":true}}]',
    );
    await tester.pump();
    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('compact-note-$note')));
    await tester.pump();
    await tester.tap(find.text('Добавить в заметку'));
    await tester.pump();
    await tester.pump();

    final updated = (await db.diaryDao.getEntry(note))!;
    expect(
      updated.body,
      '[{"insert":"Жирный текст\\n","attributes":{"bold":true}},{"insert":"x\\n"}]',
    );
    expect(updated.dirty, isTrue);
    expect(locks.acquiredNoteIds, [note]);
    expect(locks.releasedNoteIds, [note]);
    expect(acknowledgements, ['event-1']);
    expect(find.text('Добавлено в заметку'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(exits, 1);
    await disposeTree(tester);
  });

  testWidgets('refuses append when authoritative lock acquisition is denied', (
    tester,
  ) async {
    final locks = _FakeEditorLockBridge()..acquisitionSucceeds = false;
    final acknowledgements = <String>[];
    final db = await open(
      tester,
      acknowledgements: acknowledgements,
      editorLockBridge: locks,
    );
    final note = await addNote(
      db,
      title: 'Стала открытой',
      body: '[{"insert":"До\\n"}]',
    );
    await tester.pump();
    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('compact-note-$note')));
    await tester.pump();
    await tester.tap(find.text('Добавить в заметку'));
    await tester.pumpAndSettle();

    expect(find.text('Заметка открыта в редакторе'), findsOneWidget);
    expect((await db.diaryDao.getEntry(note))!.body, '[{"insert":"До\\n"}]');
    expect(locks.acquiredNoteIds, [note]);
    expect(locks.releaseCalls, 0);
    expect(acknowledgements, isEmpty);
    await disposeTree(tester);
  });

  testWidgets(
    'releases the lock after an append failure without acknowledging',
    (tester) async {
      final locks = _FakeEditorLockBridge();
      final acknowledgements = <String>[];
      final db = await open(
        tester,
        acknowledgements: acknowledgements,
        editorLockBridge: locks,
        appendForSharedEvent:
            ({required eventId, required noteId, required content}) =>
                Future<ShareEventResult>.error(StateError('database failed')),
      );
      final note = await addNote(
        db,
        title: 'Не менять',
        body: '[{"insert":"До\\n"}]',
      );
      await tester.pump();
      await tester.tap(find.text('Добавить к существующей'));
      await tester.pump();
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('compact-note-$note')));
      await tester.pump();
      await tester.tap(find.text('Добавить в заметку'));
      await tester.pumpAndSettle();

      expect(find.text('Не удалось добавить текст в заметку'), findsOneWidget);
      expect((await db.diaryDao.getEntry(note))!.body, '[{"insert":"До\\n"}]');
      expect(locks.releasedNoteIds, [note]);
      expect(acknowledgements, isEmpty);
      await disposeTree(tester);
    },
  );

  testWidgets('does not append again when acknowledgement initially fails', (
    tester,
  ) async {
    final locks = _FakeEditorLockBridge();
    final acknowledgements = <String>[];
    final db = await open(
      tester,
      acknowledgements: acknowledgements,
      acknowledgementFailures: 1,
      editorLockBridge: locks,
    );
    final note = await addNote(
      db,
      title: 'Подтверждение',
      body: '[{"insert":"До\\n"}]',
    );
    await tester.pump();
    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('compact-note-$note')));
    await tester.pump();
    await tester.tap(find.text('Добавить в заметку'));
    await tester.pumpAndSettle();

    expect(find.text('Текст добавлен, но не подтверждён'), findsOneWidget);
    expect(
      (await db.diaryDao.getEntry(note))!.body,
      '[{"insert":"До\\n"},{"insert":"x\\n"}]',
    );
    expect(locks.acquisitionCalls, 1);
    await tester.tap(find.text('Повторить подтверждение'));
    await tester.pump();
    await tester.pump();
    expect(locks.acquisitionCalls, 1);
    expect(
      (await db.diaryDao.getEntry(note))!.body,
      '[{"insert":"До\\n"},{"insert":"x\\n"}]',
    );
    expect(acknowledgements, ['event-1']);
    await disposeTree(tester);
  });

  testWidgets('fails closed when native lock acquisition throws', (
    tester,
  ) async {
    final locks = _FakeEditorLockBridge()..throwOnAcquire = true;
    final acknowledgements = <String>[];
    final db = await open(
      tester,
      acknowledgements: acknowledgements,
      editorLockBridge: locks,
    );
    final note = await addNote(
      db,
      title: 'Недоступная блокировка',
      body: '[{"insert":"До\\n"}]',
    );
    await tester.pump();
    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('compact-note-$note')));
    await tester.pump();
    await tester.tap(find.text('Добавить в заметку'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось проверить доступ к заметке'), findsOneWidget);
    expect((await db.diaryDao.getEntry(note))!.body, '[{"insert":"До\\n"}]');
    expect(locks.releaseCalls, 0);
    expect(acknowledgements, isEmpty);
    await disposeTree(tester);
  });

  testWidgets('blocks navigation while an append is active', (tester) async {
    final append = Completer<ShareEventResult>();
    final db = await open(
      tester,
      acknowledgements: <String>[],
      appendForSharedEvent:
          ({required eventId, required noteId, required content}) =>
              append.future,
    );
    final note = await addNote(
      db,
      title: 'Ожидание',
      body: '[{"insert":"До\\n"}]',
    );
    await tester.pump();
    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('compact-note-$note')));
    await tester.pump();
    await tester.tap(find.text('Добавить в заметку'));
    await tester.pump();

    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Назад'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Выбрать заметку'), findsOneWidget);
    append.complete(ShareEventResult(note, didMutate: true));
    await tester.pumpAndSettle();
    await disposeTree(tester);
  });

  testWidgets('redelivered create acknowledges without creating another note', (
    tester,
  ) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final original = await db.diaryDao.createForSharedEvent(
      eventId: 'event-1',
      title: 'Первоначальная',
      content: const SharedNoteContent('Первый текст'),
    );
    final acknowledgements = <String>[];
    await open(tester, database: db, acknowledgements: acknowledgements);

    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'Не создавать');
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    await tester.pump();

    expect(await db.diaryDao.entryCount(), 1);
    expect(
      (await db.diaryDao.getEntry(original.targetDiaryEntryId))!.title,
      'Первоначальная',
    );
    expect(acknowledgements, ['event-1']);
    expect(find.text('Заметка сохранена'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('redelivered append acknowledges without appending twice', (
    tester,
  ) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final noteId = await addNote(
      db,
      title: 'Цель',
      body: '[{"insert":"До\\n"}]',
    );
    await db.diaryDao.appendForSharedEvent(
      eventId: 'event-1',
      noteId: noteId,
      content: const SharedNoteContent('x'),
    );
    final acknowledgements = <String>[];
    await open(tester, database: db, acknowledgements: acknowledgements);

    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('compact-note-$noteId')));
    await tester.pump();
    await tester.tap(find.text('Добавить в заметку'));
    await tester.pump();
    await tester.pump();

    expect(
      (await db.diaryDao.getEntry(noteId))!.body,
      '[{"insert":"До\\n"},{"insert":"x\\n"}]',
    );
    expect(acknowledgements, ['event-1']);
    expect(find.text('Добавлено в заметку'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('event conflict is not acknowledged or retried', (tester) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await db.diaryDao.createForSharedEvent(
      eventId: 'event-1',
      title: 'Уже создана',
      content: const SharedNoteContent('x'),
    );
    final target = await addNote(
      db,
      title: 'Другая заметка',
      body: '[{"insert":"До\\n"}]',
    );
    final acknowledgements = <String>[];
    await open(tester, database: db, acknowledgements: acknowledgements);

    await tester.tap(find.text('Добавить к существующей'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('compact-note-$target')));
    await tester.pump();
    await tester.tap(find.text('Добавить в заметку'));
    await tester.pumpAndSettle();

    expect(
      find.text('Это событие уже обработано для другой заметки'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Добавить в заметку'),
          )
          .onPressed,
      isNull,
    );
    expect((await db.diaryDao.getEntry(target))!.body, '[{"insert":"До\\n"}]');
    expect(acknowledgements, isEmpty);
    await disposeTree(tester);
  });

  testWidgets('create conflict is not acknowledged or retried', (tester) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final target = await addNote(
      db,
      title: 'Уже выбранная',
      body: '[{"insert":"До\\n"}]',
    );
    await db.diaryDao.appendForSharedEvent(
      eventId: 'event-1',
      noteId: target,
      content: const SharedNoteContent('x'),
    );
    final acknowledgements = <String>[];
    await open(tester, database: db, acknowledgements: acknowledgements);

    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(
      find.text('Это событие уже обработано другим действием'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'))
          .onPressed,
      isNull,
    );
    expect(await db.diaryDao.entryCount(), 1);
    expect(acknowledgements, isEmpty);
    await disposeTree(tester);
  });

  testWidgets('a deleted durable create target still acknowledges redelivery', (
    tester,
  ) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final original = await db.diaryDao.createForSharedEvent(
      eventId: 'event-1',
      title: 'Удалённая',
      content: const SharedNoteContent('x'),
    );
    await db.diaryDao.deleteEntry(original.targetDiaryEntryId);
    final acknowledgements = <String>[];
    await open(tester, database: db, acknowledgements: acknowledgements);

    await tester.tap(find.text('Создать новую заметку'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    await tester.pump();

    expect(await db.diaryDao.entryCount(), 0);
    expect(acknowledgements, ['event-1']);
    expect(find.text('Заметка сохранена'), findsOneWidget);
    await disposeTree(tester);
  });
}
