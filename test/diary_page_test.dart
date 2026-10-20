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
    testWidgets(
      'counts the notes and searches from a box that is always there',
      (tester) async {
        await tester.pumpWidget(
          _diary([
            _note(id: 1, title: 'Список покупок', text: 'молоко и хлеб'),
            _note(id: 2, title: 'Планы', text: 'сходить в спортзал'),
          ]),
        );
        await tester.pumpAndSettle();

        expect(find.text('2 записи'), findsOneWidget);
        expect(find.text('Дневник'), findsOneWidget);
        expect(find.text('Поиск по записям'), findsOneWidget);
        expect(find.text('Список покупок'), findsOneWidget);
        expect(find.text('Планы'), findsOneWidget);

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

        // the cross empties the box and puts every note back
        await tester.tap(find.byIcon(LucideIcons.x));
        await tester.pumpAndSettle();
        expect(find.text('Список покупок'), findsOneWidget);
        expect(find.text('Планы'), findsOneWidget);
      },
    );

    testWidgets('keeps the archive out of the list, and out of the count', (
      tester,
    ) async {
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

      expect(find.text('1 запись'), findsOneWidget);
      expect(find.text('Молоко в архиве'), findsNothing);

      // not even when it would match
      await tester.enterText(find.byType(TextField), 'молоко');
      await tester.pumpAndSettle();
      expect(find.text('Молоко сегодня'), findsOneWidget);
      expect(find.text('Молоко в архиве'), findsNothing);
    });

    testWidgets('has no tabs any more, and shows drafts with a mark', (
      tester,
    ) async {
      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Готовая'),
          _note(id: 2, title: 'Набросок', status: DiaryEntryStatus.draft),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Избранное'), findsNothing);
      expect(find.text('Черновики'), findsNothing);
      expect(find.text('Набросок'), findsOneWidget);
      expect(find.text('Черновик'), findsOneWidget);
    });

    testWidgets('the archive button opens the archive page', (tester) async {
      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Живая'),
          _note(id: 2, title: 'Старая', status: DiaryEntryStatus.archived),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Архив'));
      await tester.pumpAndSettle();

      expect(find.text('Старая'), findsOneWidget);
      expect(find.text('Живая'), findsNothing);
    });

    testWidgets('an empty archive says so', (tester) async {
      await tester.pumpWidget(_diary([_note(id: 1, title: 'Живая')]));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Архив'));
      await tester.pumpAndSettle();

      expect(find.text('В архиве пусто'), findsOneWidget);
    });
  });

  group('pinned notes', () {
    testWidgets('are tiles above the list, and not in it twice', (
      tester,
    ) async {
      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Обычная'),
          _note(id: 2, title: 'Важная', favorite: true),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('ЗАКРЕПЛЁННЫЕ'), findsOneWidget);
      expect(find.text('Важная'), findsOneWidget);
      expect(find.text('Обычная'), findsOneWidget);
      expect(find.textContaining('Изменено'), findsOneWidget);
    });

    testWidgets('no block without a pinned note', (tester) async {
      await tester.pumpWidget(_diary([_note(id: 1, title: 'Обычная')]));
      await tester.pumpAndSettle();

      expect(find.text('ЗАКРЕПЛЁННЫЕ'), findsNothing);
    });

    testWidgets('a search lists them with the rest', (tester) async {
      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Молоко обычное'),
          _note(id: 2, title: 'Молоко важное', favorite: true),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'молоко');
      await tester.pumpAndSettle();

      expect(find.text('ЗАКРЕПЛЁННЫЕ'), findsNothing);
      expect(find.text('Молоко обычное'), findsOneWidget);
      expect(find.text('Молоко важное'), findsOneWidget);
    });

    testWidgets('a long press offers to pin or unpin', (tester) async {
      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Обычная'),
          _note(id: 2, title: 'Важная', favorite: true),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Обычная'));
      await tester.pumpAndSettle();
      expect(find.text('Закрепить'), findsOneWidget);
      expect(find.text('В архив'), findsOneWidget);
    });
  });

  group('the list', () {
    testWidgets('is cut into sections by date, newest first', (tester) async {
      final now = DateTime.now();
      DiaryEntry at(int id, String title, DateTime date) =>
          _note(id: id, title: title).copyWith(updatedAt: date);
      final old = DateTime(now.year - 1, 3, 15);
      await tester.pumpWidget(
        _diary([at(1, 'Свежая', now), at(2, 'Давняя', old)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('ЭТА НЕДЕЛЯ'), findsOneWidget);
      expect(find.text('МАРТ ${old.year}'), findsOneWidget);
      // the day and the weekday stand to the left of a note
      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('a row carries the text and the labels', (tester) async {
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
      expect(find.text('🌿'), findsOneWidget);
      expect(find.text('Спокойствие'), findsOneWidget);
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

    testWidgets('counts the tags it cannot fit', (tester) async {
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
    });
  });

  group('the view mode', () {
    testWidgets('opens as rows and switches to tiles from the button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _diary([
          _note(id: 1, title: 'Первая', text: 'текст'),
          _note(id: 2, title: 'Вторая', text: 'текст'),
        ]),
      );
      await tester.pumpAndSettle();

      // rows are the default, and they are not a grid
      expect(find.byType(SliverGrid), findsNothing);

      await tester.tap(find.byTooltip('Вид: список'));
      await tester.pumpAndSettle();
      expect(find.text('Отображение списком'), findsOneWidget);
      expect(find.text('Отображение плитками'), findsOneWidget);
      // the mode already in force is ticked
      expect(find.byIcon(LucideIcons.check), findsOneWidget);

      await tester.tap(find.text('Отображение плитками'));
      await tester.pumpAndSettle();

      expect(find.text('Первая'), findsOneWidget);
      expect(find.text('Вторая'), findsOneWidget);
      // two columns
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);
      expect(find.byTooltip('Вид: плитки'), findsOneWidget);

      // and it is remembered
      expect(_prefs.getString('diary_view_mode'), 'grid');
    });

    testWidgets('a stored choice is what the diary opens with', (tester) async {
      SharedPreferences.setMockInitialValues({'diary_view_mode': 'grid'});
      _prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_diary([_note(id: 1, title: 'Плитка')]));
      await tester.pumpAndSettle();

      expect(find.byType(SliverGrid), findsOneWidget);
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

      await tester.enterText(find.byType(TextField), 'молоко');
      await tester.pumpAndSettle();

      expect(find.byType(SliverGrid), findsOneWidget);
      expect(find.text('Список покупок'), findsOneWidget);
      expect(find.text('Планы'), findsNothing);
    });
  });
}
