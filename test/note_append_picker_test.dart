import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/shared_note_content.dart';
import 'package:todo_app/widgets/diary/note_append_picker_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru_RU', null));

  late AppDatabase db;

  Future<int> addNote({
    required String title,
    required String body,
    required DateTime updatedAt,
  }) => db.diaryDao.insertEntry(
    DiaryEntriesCompanion.insert(
      title: Value(title),
      body: Value(body),
      createdAt: Value(updatedAt),
      updatedAt: Value(updatedAt),
    ),
  );

  Future<void> open(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showNoteAppendPickerSheet(
              context,
              content: const SharedNoteContent('Текст из Share'),
            ),
            child: const Text('Открыть выбор'),
          ),
        ),
      ),
    ),
  );

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
  });

  testWidgets('shows recent notes in the watchEntries order without previews', (
    tester,
  ) async {
    final older = await addNote(
      title: 'Старшая заметка',
      body: '[{"insert":"скрытое старое тело\\n"}]',
      updatedAt: DateTime(2026, 1, 1),
    );
    final newer = await addNote(
      title: 'Новая заметка',
      body: '[{"insert":"скрытое новое тело\\n"}]',
      updatedAt: DateTime(2026, 2, 1),
    );
    await open(tester);

    await tester.tap(find.text('Открыть выбор'));
    await tester.pumpAndSettle();

    expect(find.text('Последние заметки'), findsOneWidget);
    expect(find.byKey(ValueKey('note-append-$newer')), findsOneWidget);
    final rows = find.byKey(const Key('note-append-row'));
    expect(tester.widgetList(rows).length, 2);
    expect(
      tester.getTopLeft(find.byKey(ValueKey('note-append-$newer'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(ValueKey('note-append-$older'))).dy,
      ),
    );
    expect(find.text('скрытое старое тело'), findsNothing);
    expect(find.text('скрытое новое тело'), findsNothing);
    expect(find.byKey(ValueKey('note-append-$older')), findsOneWidget);
    await close(tester);
  });

  testWidgets('searches both title and body without showing a body preview', (
    tester,
  ) async {
    await addNote(
      title: 'Планы',
      body: '[{"insert":"Найти иглу в стоге\\n"}]',
      updatedAt: DateTime(2026, 2, 1),
    );
    await addNote(
      title: 'Покупки',
      body: '[{"insert":"молоко\\n"}]',
      updatedAt: DateTime(2026, 1, 1),
    );
    await open(tester);

    await tester.tap(find.text('Открыть выбор'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-append-search')), 'иглу');
    await tester.pump();

    expect(find.text('Результаты поиска'), findsOneWidget);
    expect(find.text('Планы'), findsOneWidget);
    expect(find.text('Покупки'), findsNothing);
    expect(find.text('Найти иглу в стоге'), findsNothing);
    await close(tester);
  });

  testWidgets('cancelling leaves the database untouched', (tester) async {
    final id = await addNote(
      title: 'Не менять',
      body: '[{"insert":"Исходный текст\\n"}]',
      updatedAt: DateTime(2026, 1, 1),
    );
    await open(tester);

    await tester.tap(find.text('Открыть выбор'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(
      (await db.diaryDao.getEntry(id))!.body,
      '[{"insert":"Исходный текст\\n"}]',
    );
    await close(tester);
  });

  testWidgets('selecting a note appends shared text at its end', (
    tester,
  ) async {
    final id = await addNote(
      title: 'Целевая заметка',
      body: '[{"insert":"Исходный текст\\n"}]',
      updatedAt: DateTime(2026, 1, 1),
    );
    await open(tester);

    await tester.tap(find.text('Открыть выбор'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('note-append-$id')));
    await tester.pumpAndSettle();

    expect(
      (await db.diaryDao.getEntry(id))!.body,
      '[{"insert":"Исходный текст\\n"},{"insert":"Текст из Share\\n"}]',
    );
    await close(tester);
  });
}
