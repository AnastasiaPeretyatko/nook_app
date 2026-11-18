import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_note_page.dart';
import 'package:todo_app/pages/note_view_page.dart';
import 'package:todo_app/share_to_nook/share_to_nook.dart';
import 'package:todo_app/utils/shared_note_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru_RU', null));

  group('AndroidShareToNookBridge', () {
    const channel = MethodChannel('com.yourname.todo_app/shared_content');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reads and preserves every pending native event', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'takePendingSharedText');
            return ['один', 'один'];
          });
      final bridge = AndroidShareToNookBridge(channel: channel);

      final pending = await bridge.takePending();

      expect(pending.map((content) => content.text), ['один', 'один']);
    });

    test('forwards a warm native availability signal once', () async {
      final bridge = AndroidShareToNookBridge(channel: channel);
      var signals = 0;
      bridge.setOnAvailable(() => signals++);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              const MethodCall('sharedTextAvailable'),
            ),
            (_) {},
          );

      expect(signals, 1);
    });
  });

  group('ShareToNookQueue', () {
    test('processes an initial event and a warm event in order', () async {
      final bridge = _FakeBridge([const SharedNoteContent('initial')]);
      final handled = <String>[];
      final queue = ShareToNookQueue(bridge, (content) async {
        handled.add(content.text);
      });

      await queue.start();
      bridge.add(const SharedNoteContent('warm'));
      await queue.idle;

      expect(handled, ['initial', 'warm']);
    });

    test(
      'a repeated native signal does not repeat an event already drained',
      () async {
        final bridge = _FakeBridge([const SharedNoteContent('only once')]);
        final handled = <String>[];
        final queue = ShareToNookQueue(bridge, (content) async {
          handled.add(content.text);
        });

        await queue.start();
        bridge.signal();
        await queue.idle;

        expect(handled, ['only once']);
      },
    );

    test(
      'keeps identical text from separate shares as separate events',
      () async {
        final bridge = _FakeBridge([
          const SharedNoteContent('same'),
          const SharedNoteContent('same'),
        ]);
        final handled = <String>[];
        final queue = ShareToNookQueue(bridge, (content) async {
          handled.add(content.text);
        });

        await queue.start();

        expect(handled, ['same', 'same']);
      },
    );

    test('waits for one flow before processing the next event', () async {
      final bridge = _FakeBridge([
        const SharedNoteContent('first'),
        const SharedNoteContent('second'),
      ]);
      final firstCompleted = Completer<void>();
      final handled = <String>[];
      final queue = ShareToNookQueue(bridge, (content) async {
        handled.add(content.text);
        if (content.text == 'first') await firstCompleted.future;
      });

      unawaited(queue.start());
      await Future<void>.delayed(Duration.zero);
      expect(handled, ['first']);

      firstCompleted.complete();
      await queue.idle;
      expect(handled, ['first', 'second']);
    });
  });

  testWidgets('cancelling the choice does not write a note', (tester) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [diaryDaoProvider.overrideWithValue(db.diaryDao)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showShareToNookFlow(
                context,
                const SharedNoteContent('cancelled'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Добавить текст в дневник'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(await db.diaryDao.entryCount(), 0);
  });

  testWidgets('new-note choice opens a shared draft without inserting it', (
    tester,
  ) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [diaryDaoProvider.overrideWithValue(db.diaryDao)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showShareToNookFlow(
                context,
                const SharedNoteContent('Черновик из Share'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая заметка'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateNotePage), findsOneWidget);
    expect(await db.diaryDao.entryCount(), 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('an appended note offers a toast that opens that note', (
    tester,
  ) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.diaryDao.insertEntry(
      DiaryEntriesCompanion.insert(
        title: const Value('Куда добавить'),
        body: const Value('[{"insert":"Начало\\n"}]'),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showShareToNookFlow(
                context,
                const SharedNoteContent('Добавленный текст'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить в существующую'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('note-append-$id')));
    await tester.pumpAndSettle();

    expect(find.text('Текст добавлен в заметку'), findsOneWidget);
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteViewPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}

class _FakeBridge implements ShareToNookBridge {
  _FakeBridge(Iterable<SharedNoteContent> pending) : _pending = [...pending];

  final List<SharedNoteContent> _pending;
  void Function()? _listener;

  @override
  Future<List<SharedNoteContent>> takePending() async {
    final pending = List<SharedNoteContent>.from(_pending);
    _pending.clear();
    return pending;
  }

  @override
  void setOnAvailable(void Function()? listener) => _listener = listener;

  void add(SharedNoteContent content) {
    _pending.add(content);
    signal();
  }

  void signal() => _listener?.call();
}
