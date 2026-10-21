import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_note_page.dart';
import 'package:todo_app/pages/note_view_page.dart';
import 'package:todo_app/utils/note_delta.dart';
import 'package:todo_app/utils/note_images.dart';

/// The open note (`JournalRead.dc.html`): the header with pin and "Ещё", the date
/// and title, the check-list's progress, and the menu with copy / archive /
/// delete. Runs on a real in-memory database so the buttons are seen to write.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() async => initializeDateFormatting('ru_RU', null));

  // Two boxes, one ticked, and a plain line above them.
  final listBody = jsonEncode([
    {'insert': 'Главное'},
    {'insert': '\n'},
    {'insert': 'Бегать'},
    {
      'insert': '\n',
      'attributes': {'block': 'cl', 'checked': true},
    },
    {'insert': 'Читать'},
    {
      'insert': '\n',
      'attributes': {'block': 'cl'},
    },
  ]);

  late AppDatabase db;

  setUp(() => db = AppDatabase.forExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> insertNote({String title = 'Цели на осень', String? body}) => db
      .into(db.diaryEntries)
      .insert(
        DiaryEntriesCompanion.insert(
          title: Value(title),
          body: Value(
            body ??
                jsonEncode([
                  {'insert': 'Текст заметки\n'},
                ]),
          ),
          createdAt: Value(DateTime(2026, 10, 16, 9, 0)),
          updatedAt: Value(DateTime(2026, 10, 16, 14, 20)),
        ),
      );

  Future<int> note(WidgetTester tester, {String? body}) async =>
      (await tester.runAsync(() => insertNote(body: body)))!;

  // Drift answers on real timers, which the test clock never fires on its own:
  // let real time pass, then let the frames catch up. `pumpAndSettle` would wait
  // forever on the open stream.
  Future<void> settle(WidgetTester tester) async {
    // Several rounds: a handler can wait on real I/O, then on the database, and
    // each hop needs the real clock and then a frame in turn.
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  // A widget test that ends with a database stream still open reports its
  // closing timer as pending; taking the page down first lets it fire.
  void page(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      });

  Future<void> open(WidgetTester tester, int id) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          noteImagesDirectoryProvider.overrideWith((ref) => Directory('/tmp')),
        ],
        child: MaterialApp(
          locale: const Locale('ru', 'RU'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru', 'RU')],
          // Pushed rather than the home, so that closing it has somewhere to go.
          home: const SizedBox(),
        ),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(builder: (_) => NoteViewPage(entryId: id)),
        );
    await settle(tester);
  }

  test('the check-list is counted from the stored text', () {
    expect(checklistProgress(jsonDecode(listBody) as List), (1, 2));
    expect(
      checklistProgress([
        {'insert': 'просто текст\n'},
      ]),
      (0, 0),
    );
  });

  page('the date line, the title and the text', (tester) async {
    await open(tester, await note(tester));

    expect(find.text('Пятница, 16 октября · изменено в 14:20'), findsOneWidget);
    expect(find.text('Цели на осень'), findsOneWidget);
    // The text is drawn by the editor, not by a `Text`.
    expect(
      find.textContaining('Текст заметки', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('ЧЕК-ЛИСТ'), findsNothing);
  });

  page('a note with boxes says how many are ticked', (tester) async {
    await open(tester, await note(tester, body: listBody));

    expect(find.text('ЧЕК-ЛИСТ'), findsOneWidget);
    expect(find.text('1 из 2'), findsOneWidget);
  });

  page('the pin pins and unpins', (tester) async {
    final id = await note(tester);
    await open(tester, id);

    await tester.tap(find.byTooltip('Закрепить'));
    await settle(tester);
    expect(
      (await tester.runAsync(() => db.diaryDao.getEntry(id)))!.isFavorite,
      isTrue,
    );

    await tester.tap(find.byTooltip('Открепить'));
    await settle(tester);
    expect(
      (await tester.runAsync(() => db.diaryDao.getEntry(id)))!.isFavorite,
      isFalse,
    );
  });

  page('"Ещё" offers copy, archive and delete', (tester) async {
    await open(tester, await note(tester));

    await tester.tap(find.byTooltip('Ещё'));
    await settle(tester);

    expect(find.text('Скопировать текст'), findsOneWidget);
    expect(find.text('В архив'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
  });

  page('archive puts the note away, and the menu offers it back', (
    tester,
  ) async {
    final id = await note(tester);
    await open(tester, id);

    await tester.tap(find.byTooltip('Ещё'));
    await settle(tester);
    await tester.tap(find.text('В архив'));
    await settle(tester);
    expect(
      (await tester.runAsync(() => db.diaryDao.getEntry(id)))!.status,
      DiaryEntryStatus.archived,
    );

    await tester.tap(find.byTooltip('Ещё'));
    await settle(tester);
    expect(find.text('Вернуть из архива'), findsOneWidget);
  });

  page('copy puts the title and the text on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await open(tester, await note(tester));

    await tester.tap(find.byTooltip('Ещё'));
    await settle(tester);
    await tester.tap(find.text('Скопировать текст'));
    await settle(tester);

    expect(copied, 'Цели на осень\n\nТекст заметки');
    expect(find.text('Текст заметки скопирован'), findsOneWidget);
  });

  page('delete asks first, then removes the note and closes', (tester) async {
    // Deleting asks where the note's pictures live, even when it has none.
    const files = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      files,
      (call) async => Directory.systemTemp.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        files,
        null,
      ),
    );
    final id = await note(tester);
    await open(tester, id);

    await tester.tap(find.byTooltip('Ещё'));
    await settle(tester);
    await tester.tap(find.text('Удалить'));
    await settle(tester);
    expect(find.text('Удалить заметку?'), findsOneWidget);
    expect(await tester.runAsync(() => db.diaryDao.getEntry(id)), isNotNull);

    await tester.tap(find.text('Удалить').last);
    await settle(tester);
    expect(await tester.runAsync(() => db.diaryDao.getEntry(id)), isNull);
  });

  page('the pencil opens the editor on this note', (tester) async {
    await open(tester, await note(tester));

    await tester.tap(find.byTooltip('Редактировать'));
    await settle(tester);

    expect(find.byType(CreateNotePage), findsOneWidget);
  });
}
