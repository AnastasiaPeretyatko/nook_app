import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/diary_page.dart';
import 'package:todo_app/utils/note_images.dart';
import 'package:todo_app/utils/note_search.dart';
import 'package:todo_app/widgets/diary/note_label_chips.dart';

final _day = DateTime(2026, 8, 24);

String _delta(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

DiaryEntry _note({
  required int id,
  required String title,
  String text = '',
  bool favorite = false,
  DiaryEntryStatus status = DiaryEntryStatus.normal,
}) => DiaryEntry(
  id: id,
  title: title,
  body: text.isEmpty ? '' : _delta(text),
  images: '[]',
  isFavorite: favorite,
  status: status,
  createdAt: _day,
  updatedAt: _day,
  // These rows never reach a database, let alone a server; the screen draws
  // them and nothing here reads the sync marks.
  dirty: false,
);

NoteMood _mood(int id, String emoji, String name) =>
    NoteMood(id: id, emoji: emoji, name: name, createdAt: _day, dirty: false);

NoteTag _tag(int id, String name) => NoteTag(
  id: id,
  name: name,
  colorKey: 'violet',
  createdAt: _day,
  dirty: false,
);

late SharedPreferences _prefs;

/// Every provider the diary reads is overridden — including the two label maps,
/// which otherwise reach for a real `AppDatabase` and drift starts warning about
/// two of them sharing an executor.
Widget _diary(
  List<DiaryEntry> notes, {
  Map<int, List<NoteMood>> moods = const {},
  Map<int, List<NoteTag>> tags = const {},
}) => ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(_prefs),
    diaryEntriesProvider.overrideWith((ref) => Stream.value(notes)),
    moodsByEntryProvider.overrideWith((ref) => Stream.value(moods)),
    tagsByEntryProvider.overrideWith((ref) => Stream.value(tags)),
    noteImagesDirectoryProvider.overrideWith((ref) => Directory('/tmp')),
  ],
  child: const MaterialApp(
    locale: Locale('ru', 'RU'),
    localizationsDelegates: [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: [Locale('ru', 'RU')],
    home: DiaryPage(),
  ),
);

void main() {
  setUpAll(() async => initializeDateFormatting('ru_RU', null));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  group('the matching itself', () {
    test('several words mean all of them, in any order', () {
      final terms = searchTerms('  Молоко   ХЛЕБ ');
      expect(terms, ['молоко', 'хлеб']);
      expect(matchesTerms('купить хлеб и молоко', terms), isTrue);
      expect(matchesTerms('купить только хлеб', terms), isFalse);
      expect(matchesTerms('что угодно', const []), isTrue);
    });

    test('ranges are every occurrence, merged where they touch', () {
      expect(matchRanges('банан банан', searchTerms('бан')), [(0, 3), (6, 9)]);
      expect(matchRanges('заметка', searchTerms('за метка')), [(0, 7)]);
      expect(matchRanges('что угодно', const []), isEmpty);
    });

    test('the excerpt winds forward to the match', () {
      final long = '${'слово ' * 20}игла и хвост';
      final cut = excerptAround(long, searchTerms('игла'));
      expect(cut.startsWith('…'), isTrue);
      expect(cut.contains('игла и хвост'), isTrue);
      expect(cut.length, lessThan(long.length));
      // a match near the start is left alone
      expect(
        excerptAround('игла в начале', searchTerms('игла')),
        'игла в начале',
      );
    });
  });

  group('the screen', () {
    testWidgets('filters the open tab and says so when nothing is left', (
      tester,
    ) async {
      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Список покупок', text: 'молоко и хлеб'),
          _note(id: 2, title: 'Планы', text: 'сходить в спортзал'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Список покупок'), findsOneWidget);
      expect(find.text('Планы'), findsOneWidget);

      await tester.tap(find.byTooltip('Поиск'));
      await tester.pumpAndSettle();
      expect(find.text('Поиск по заметкам'), findsOneWidget);

      // found by its body, not its title
      await tester.enterText(find.byType(TextField), 'молоко');
      await tester.pumpAndSettle();
      expect(find.text('Список покупок'), findsOneWidget);
      expect(find.text('Планы'), findsNothing);

      // found by its title
      await tester.enterText(find.byType(TextField), 'план');
      await tester.pumpAndSettle();
      expect(find.text('Планы'), findsOneWidget);
      expect(find.text('Список покупок'), findsNothing);

      await tester.enterText(find.byType(TextField), 'ничего подобного');
      await tester.pumpAndSettle();
      expect(find.text('Ничего не найдено'), findsOneWidget);

      // closing puts the header and every note back
      await tester.tap(find.byTooltip('Закрыть поиск'));
      await tester.pumpAndSettle();
      expect(find.text('Дневник'), findsOneWidget);
      expect(find.text('Список покупок'), findsOneWidget);
      expect(find.text('Планы'), findsOneWidget);
    });

    testWidgets('the query holds across tabs', (tester) async {
      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Молоко сегодня'),
          _note(
            id: 2,
            title: 'Молоко в архиве',
            status: DiaryEntryStatus.archived,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Поиск'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'молоко');
      await tester.pumpAndSettle();

      expect(find.text('Молоко сегодня'), findsOneWidget);
      expect(find.text('Молоко в архиве'), findsNothing);

      await tester.tap(find.text('Архив'));
      await tester.pumpAndSettle();

      expect(find.text('Молоко в архиве'), findsOneWidget);
      expect(find.text('Молоко сегодня'), findsNothing);
    });
  });

  group('the card', () {
    testWidgets('carries the date, the mood, two lines of text and the tags', (
      tester,
    ) async {
      await tester.pumpWidget(
        _diary(
          [_note(id: 1, title: 'Утро', text: 'кофе и тишина')],
          moods: {
            1: [_mood(1, '🌿', 'Спокойствие')],
          },
          tags: {
            1: [_tag(1, 'дневник'), _tag(2, 'мысли')],
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Утро'), findsOneWidget);
      expect(find.text('кофе и тишина'), findsOneWidget);
      // the mood: emoji and word, and the dot that keeps it off the date
      expect(find.text('🌿'), findsOneWidget);
      expect(find.text('Спокойствие'), findsOneWidget);
      expect(find.text('  ·  '), findsOneWidget);
      // on a row the mood is text, not a filled chip
      expect(tester.widget<MoodChip>(find.byType(MoodChip)).filled, isFalse);
      // a tag carries the "#" its name does not
      expect(find.text('#дневник'), findsOneWidget);
      expect(find.text('#мысли'), findsOneWidget);
      // the text is capped at two lines
      final excerpt = tester.widget<Text>(find.text('кофе и тишина'));
      expect(excerpt.maxLines, 2);
      expect(excerpt.overflow, TextOverflow.ellipsis);
    });

    testWidgets(
      'counts the tags it cannot fit, and drops the dot with no mood',
      (tester) async {
        await tester.pumpWidget(
          _diary(
            [_note(id: 1, title: 'Много', text: 'текст')],
            tags: {
              1: [
                _tag(1, 'один'),
                _tag(2, 'два'),
                _tag(3, 'три'),
                _tag(4, 'четыре'),
                _tag(5, 'пять'),
              ],
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('#один'), findsOneWidget);
        expect(find.text('#три'), findsOneWidget);
        expect(find.text('#четыре'), findsNothing);
        expect(find.text('+2'), findsOneWidget);
        expect(find.text('  ·  '), findsNothing);
      },
    );

    testWidgets('the star says which way it goes', (tester) async {
      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Обычная'),
          _note(id: 2, title: 'Избранная', favorite: true),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('В избранное'), findsOneWidget);
      expect(find.byTooltip('Убрать из избранного'), findsOneWidget);
    });
  });

  group('the view mode', () {
    testWidgets('opens as a list and switches to tiles from the menu', (
      tester,
    ) async {
      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Первая', text: 'текст'),
          _note(id: 2, title: 'Вторая', text: 'текст'),
        ]),
      );
      await tester.pumpAndSettle();

      // the list is the default, and it is a list
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);

      await tester.tap(find.byTooltip('Ещё'));
      await tester.pumpAndSettle();
      expect(find.text('Отображение списком'), findsOneWidget);
      expect(find.text('Отображение плитками'), findsOneWidget);
      // the mode already in force is ticked
      expect(find.byIcon(LucideIcons.check), findsOneWidget);

      await tester.tap(find.text('Отображение плитками'));
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(find.text('Первая'), findsOneWidget);
      expect(find.text('Вторая'), findsOneWidget);
      // two columns
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);

      // and it is remembered
      expect(_prefs.getString('diary_view_mode'), 'grid');
    });

    testWidgets('a stored choice is what the diary opens with', (tester) async {
      SharedPreferences.setMockInitialValues({'diary_view_mode': 'grid'});
      _prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_diary([_note(id: 1, title: 'Плитка')]));
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('search filters the tiles too', (tester) async {
      SharedPreferences.setMockInitialValues({'diary_view_mode': 'grid'});
      _prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Список покупок', text: 'молоко'),
          _note(id: 2, title: 'Планы', text: 'спортзал'),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Поиск'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'молоко');
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('Список покупок'), findsOneWidget);
      expect(find.text('Планы'), findsNothing);
    });
  });
}
