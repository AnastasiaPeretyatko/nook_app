import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_note_page.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// The note editor (`JournalEdit.dc.html`): round close and tick, a pin chip, the
/// title on the page, and a toolbar of five tools. No cover slot for now.
void main() {
  late AppDatabase db;

  Future<void> open(WidgetTester tester, {DiaryEntry? entry}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          locale: const Locale('ru', 'RU'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru', 'RU')],
          home: CreateNotePage(entry: entry),
        ),
      ),
    );
    // Not `pumpAndSettle`: the editor's caret never stops animating.
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Takes the page down and lets the database's stream timers run out.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  setUpAll(() => initializeDateFormatting('ru_RU', null));

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
  });

  testWidgets('has the design\'s header and tools, and no cover slot', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Запись'), findsOneWidget);
    expect(find.byTooltip('Закрыть без сохранения'), findsOneWidget);
    expect(find.byTooltip('Готово'), findsOneWidget);
    for (final tool in [
      'Чек-лист',
      'Маркированный список',
      'Заголовок',
      'Жирный',
      'Отменить',
      'Скрыть клавиатуру',
    ]) {
      expect(find.byTooltip(tool), findsOneWidget, reason: tool);
    }
    expect(find.text('Добавить обложку'), findsNothing);
    await close(tester);
  });

  DiaryEntry note(String text) => DiaryEntry(
    id: 1,
    dirty: false,
    title: 'Цели',
    body: jsonEncode([
      {'insert': '$text\n'},
    ]),
    images: '[]',
    isFavorite: false,
    status: DiaryEntryStatus.normal,
    createdAt: DateTime(2026, 10, 16, 14, 20),
    updatedAt: DateTime(2026, 10, 16, 14, 20),
  );

  FleatherController bodyController(WidgetTester tester) =>
      tester.widget<FleatherEditor>(find.byType(FleatherEditor)).controller;

  testWidgets('a tap on the text puts the cursor where it landed, from the '
      'title too', (tester) async {
    await open(tester, entry: note('Один два три четыре пять'));

    // The cursor starts in the title.
    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    final editor = find.byType(FleatherEditor);
    await tester.tapAt(tester.getTopLeft(editor) + const Offset(6, 8));
    await tester.pump(const Duration(milliseconds: 400));

    final at = bodyController(tester).selection.baseOffset;
    expect(at, lessThan(5), reason: 'near the start, not at the end ($at)');
    await close(tester);
  });

  testWidgets('a tap on the empty page under an empty note opens the text', (
    tester,
  ) async {
    await open(tester);
    expect(find.byTooltip('Скрыть клавиатуру'), findsOneWidget);

    // Well below the first line, where there is no widget of the editor.
    await tester.tapAt(const Offset(200, 420));
    await tester.pump(const Duration(milliseconds: 100));

    final editor = tester.widget<FleatherEditor>(find.byType(FleatherEditor));
    expect(editor.focusNode!.hasFocus, isTrue);
    await close(tester);
  });

  testWidgets('a tap under the text puts the cursor at its end', (
    tester,
  ) async {
    await open(tester, entry: note('Один два три'));
    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    await tester.tapAt(const Offset(200, 420));
    await tester.pump(const Duration(milliseconds: 100));

    final controller = bodyController(tester);
    expect(controller.selection.baseOffset, controller.document.length - 1);
    await close(tester);
  });

  testWidgets('Enter in the title moves the cursor to the text', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Цели на осень');
    // What the keyboard's Enter key sends is whatever the field asks for.
    final action = tester
        .widget<TextField>(find.byType(TextField).first)
        .textInputAction;
    await tester.testTextInput.receiveAction(action ?? TextInputAction.done);
    await tester.pump();

    final body = tester.widget<FleatherEditor>(find.byType(FleatherEditor));
    expect(body.focusNode!.hasFocus, isTrue);
    await close(tester);
  });

  testWidgets('the pin chip is kept with the note', (tester) async {
    await open(tester);

    expect(find.text('Закрепить'), findsOneWidget);
    await tester.tap(find.text('Закрепить'));
    await tester.pump();
    expect(find.text('Закреплена'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Цели на осень');
    await tester.tap(find.byTooltip('Готово'));
    await tester.pump();
    final rows = (await tester.runAsync(
      () => db.select(db.diaryEntries).get(),
    ))!;

    expect(rows, hasLength(1));
    expect(rows.single.title, 'Цели на осень');
    expect(rows.single.isFavorite, isTrue);
    await close(tester);
  });
}
