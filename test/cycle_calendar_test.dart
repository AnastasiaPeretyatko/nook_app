import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/cycle_calendar_page.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/widgets/app_dialogs.dart' show AppSheet;
import 'package:todo_app/widgets/cycle/cycle_colors.dart' show todayBlue;
import 'package:todo_app/widgets/cycle/cycle_day_info.dart' show CycleChip;
import 'package:todo_app/widgets/cycle/cycle_heart.dart';

/// The calendar behind the Cycle tab's button: months without an end either way,
/// and a tap on a day showing what was marked on it.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  setUp(() async {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    await initializeDateFormatting('ru_RU');
    SharedPreferences.setMockInitialValues({'about_gender': 'female'});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
      ],
    );
    await container
        .read(aboutSettingsProvider.notifier)
        .setLastStart(DateTime(today.year, today.month, today.day - 10));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CycleCalendarPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder month(DateTime first) =>
      find.byKey(ValueKey('month-${first.year}-${first.month}'));

  String title(DateTime first) {
    final name = DateFormat.LLLL('ru_RU').format(first);
    final capital = name[0].toUpperCase() + name.substring(1);
    return first.year == today.year ? capital : '$capital ${first.year}';
  }

  testWidgets('the legend and the weekday names stay put while it scrolls', (
    tester,
  ) async {
    await pump(tester);
    final legend = find.text('Секс с защитой');
    // 2026-10-19 is a Monday, the first column unless the week starts on Sunday.
    final monday = find.text(
      DateFormat.E('ru_RU').format(DateTime(2026, 10, 19)),
    );
    final legendTop = tester.getTopLeft(legend).dy;
    final mondayTop = tester.getTopLeft(monday.first).dy;

    // A month and a half down, then back up past today.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(legend).dy, legendTop);
    expect(tester.getTopLeft(monday.first).dy, mondayTop);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 2500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(legend).dy, legendTop);
    expect(tester.getTopLeft(monday.first).dy, mondayTop);
  });

  group('"Отметить день"', () {
    Finder dayIn(DateTime day) => find.descendant(
      of: month(DateTime(day.year, day.month)),
      matching: find.text('${day.day}'),
    );

    testWidgets('sits beside "Изменить даты", on one line', (tester) async {
      await pump(tester);
      final edit = tester.getRect(find.text('Изменить даты'));
      final mark = tester.getRect(find.text('Отметить день'));
      expect(edit.center.dy, mark.center.dy);
      expect(edit.right, lessThan(mark.left));
    });

    testWidgets('opens the sheet of the picked day, not of today', (
      tester,
    ) async {
      final picked = DateTime(today.year, today.month, 1);
      await pump(tester);
      // The first tap only picks the day — nothing opens.
      await tester.tap(dayIn(picked));
      await tester.pumpAndSettle();
      if (picked != today) expect(find.byType(AppSheet), findsNothing);

      await tester.tap(find.text('Отметить день'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppSheet),
          matching: find.text(DateFormat.MMMMd('ru_RU').format(picked)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a tap on the picked day shows what is on it', (tester) async {
      final picked = DateTime(today.year, today.month, 1);
      await pump(tester);
      await tester.tap(dayIn(picked));
      await tester.pumpAndSettle();
      await tester.tap(dayIn(picked));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Пока ничего не отмечено'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('is off for a day that has not come', (tester) async {
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      if (tomorrow.month != today.month) return; // last day of the month
      await pump(tester);
      await tester.tap(dayIn(tomorrow));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Отметить день'));
      await tester.pumpAndSettle();
      expect(find.byType(AppSheet), findsNothing);
    });
  });

  group('"Изменить даты"', () {
    Finder dayIn(DateTime day) => find.descendant(
      of: month(DateTime(day.year, day.month)),
      matching: find.text('${day.day}'),
    );
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    Future<int?> flowOf(WidgetTester tester, DateTime day) async {
      final row = await tester.runAsync(() => db.cycleDao.getDay(day));
      return row?.flow;
    }

    testWidgets('a tap marks a day, another takes the mark back', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Изменить даты'));
      await tester.pumpAndSettle();
      expect(find.text('Готово'), findsOneWidget);

      await tester.tap(dayIn(today));
      await settle(tester);
      expect(await flowOf(tester, today), CycleDao.defaultFlow);
      // Drawn as a solid period day at once, whatever the forecast says.
      Color? fillOf(DateTime d) =>
          (tester
                      .widget<Container>(
                        find
                            .ancestor(
                              of: dayIn(d),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration?)
              ?.color;
      expect(fillOf(today), const Color(0xFFF3DDE6));

      await tester.tap(dayIn(today));
      await settle(tester);
      expect(await flowOf(tester, today), 0);

      // Done: a tap opens what is on the day again.
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      await tester.tap(dayIn(today));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('a period day from the forecast comes off, and back on', (
      tester,
    ) async {
      // The cycle began on the 1st: days 1–5 are period days with no mark of
      // their own, only the settings say so.
      final first = DateTime(today.year, today.month, 1);
      await container.read(aboutSettingsProvider.notifier).setLastStart(first);
      await pump(tester);
      Color? fillOf(DateTime d) =>
          (tester
                      .widget<Container>(
                        find
                            .ancestor(
                              of: dayIn(d),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration?)
              ?.color;
      const period = Color(0xFFF3DDE6);
      expect(fillOf(first), period);

      await tester.tap(find.text('Изменить даты'));
      await tester.pumpAndSettle();
      await tester.tap(dayIn(first));
      await settle(tester);
      expect(fillOf(first), isNot(period), reason: 'the tap takes it off');

      await tester.tap(dayIn(first));
      await settle(tester);
      expect(fillOf(first), period, reason: 'and the next puts it back');
    });

    test(
      'a new start of the cycle forgets what was taken off the old one',
      () async {
        final notifier = container.read(aboutSettingsProvider.notifier);
        await notifier.setPeriodException(today, excluded: true);
        expect(container.read(aboutSettingsProvider).periodExceptions, {today});

        await notifier.setLastStart(DateTime(today.year, today.month, 1));
        expect(container.read(aboutSettingsProvider).periodExceptions, isEmpty);
      },
    );

    testWidgets('each day is its own: five taps, five days', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Изменить даты'));
      await tester.pumpAndSettle();

      // Up to five days back that are still in this month.
      final days = [
        for (var i = 0; i < 5; i++)
          DateTime(today.year, today.month, today.day - i),
      ].where((d) => d.month == today.month).toList();
      for (final d in days) {
        await tester.tap(dayIn(d));
        await settle(tester);
      }
      for (final d in days) {
        expect(await flowOf(tester, d), CycleDao.defaultFlow, reason: '$d');
      }
      // And no day beyond them.
      final before = DateTime(today.year, today.month, today.day - 5);
      if (before.month == today.month) {
        expect(await flowOf(tester, before), isNull);
      }
    });

    testWidgets('a day that has not come cannot be marked', (tester) async {
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      if (tomorrow.month != today.month) return; // last day of the month
      await pump(tester);
      await tester.tap(find.text('Изменить даты'));
      await tester.pumpAndSettle();

      await tester.tap(dayIn(tomorrow));
      await settle(tester);
      expect(await flowOf(tester, tomorrow), isNull);
    });

    testWidgets('marking keeps everything else on the day', (tester) async {
      await db.cycleDao.saveDay(
        today,
        mood: 2,
        symptoms: {1, 3},
        note: 'Устала',
      );
      await pump(tester);
      await tester.tap(find.text('Изменить даты'));
      await tester.pumpAndSettle();

      await tester.tap(dayIn(today));
      await settle(tester);
      final row = await tester.runAsync(() => db.cycleDao.getDay(today));
      expect(row!.flow, CycleDao.defaultFlow);
      expect(row.mood, 2);
      expect(row.symptoms, '1,3');
      expect(row.note, 'Устала');
    });
  });

  testWidgets('the sheet lists symptoms and discharge side by side', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Отметить день'));
    await tester.pumpAndSettle();

    // Each choice is as wide as its own text, so they follow one another along
    // the line and wrap — they are not one under another, a line each.
    Rect rectOf(String text) => tester.getRect(
      find
          .ancestor(of: find.text(text), matching: find.byType(Container))
          .first,
    );
    final pain = rectOf('Боль внизу живота');
    final head = rectOf('Головная боль');
    expect(head.top, pain.top, reason: 'one line');
    expect(head.left, greaterThan(pain.right));
    expect(pain.width, lessThan(400));

    // ("Нет" is also a flow tile, so the discharge is read by its other items.)
    final dry = rectOf('Сухо');
    final sticky = rectOf('Липкие');
    expect(sticky.top, dry.top, reason: 'one line');
    expect(sticky.left, greaterThan(dry.right));
  });

  testWidgets('a day with something marked has a dot under its number', (
    tester,
  ) async {
    // Today carries a mood and an empty-handed neighbour carries nothing.
    await db.cycleDao.saveDay(today, mood: 1);
    // A saved but empty day — a mark taken back — is not "something to read".
    final empty = DateTime(today.year, today.month, 1);
    if (empty != today) await db.cycleDao.saveDay(empty);
    await pump(tester);

    final dots = find.descendant(
      of: month(DateTime(today.year, today.month)),
      matching: find.byKey(const ValueKey('info-dot')),
    );
    expect(dots, findsOneWidget);

    // Under the number of today, in its middle.
    final number = tester.getRect(
      find.descendant(
        of: month(DateTime(today.year, today.month)),
        matching: find.text('${today.day}'),
      ),
    );
    final dot = tester.getRect(dots);
    expect(dot.center.dx, closeTo(number.center.dx, 0.5));
    expect(dot.top, greaterThan(number.bottom - 2));
  });

  testWidgets('each month is a card with its state in the corner', (
    tester,
  ) async {
    await pump(tester);
    final here = DateTime(today.year, today.month);
    Finder inMonth(DateTime first, String text) =>
        find.descendant(of: month(first), matching: find.text(text));

    // Day 11 of the cycle today (it began ten days ago).
    expect(inMonth(here, 'Сейчас · день 11'), findsOneWidget);

    // A month behind: how long a cycle lasts. One ahead: a forecast.
    await tester.dragUntilVisible(
      month(DateTime(today.year, today.month - 1)),
      find.byType(CustomScrollView),
      const Offset(0, 300),
    );
    expect(
      inMonth(DateTime(today.year, today.month - 1), 'Цикл 27 дней'),
      findsOneWidget,
    );
    await tester.dragUntilVisible(
      month(DateTime(today.year, today.month + 1)),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(
      inMonth(DateTime(today.year, today.month + 1), 'Прогноз'),
      findsOneWidget,
    );
  });

  testWidgets("a day's heart sits in the corner of the day", (tester) async {
    await db.cycleDao.saveDay(today, sex: 1);
    await pump(tester);

    final heart = find.descendant(
      of: month(DateTime(today.year, today.month)),
      matching: find.byType(CycleHeart),
    );
    expect(heart, findsOneWidget);
    final cell = find
        .ancestor(of: heart, matching: find.byType(Container))
        .first;
    expect(tester.getRect(heart).right, tester.getRect(cell).right);
    expect(tester.getRect(heart).bottom, tester.getRect(cell).bottom);

    // With a rim in the card's colour, so it does not run into the day's fill.
    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: heart,
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter
            as CycleHeartPainter;
    expect(painter.rim, isNotNull);
  });

  testWidgets('scrolls into the past and the future, far past three months', (
    tester,
  ) async {
    await pump(tester);
    expect(month(DateTime(today.year, today.month)), findsOneWidget);

    // A year back…
    final yearAgo = DateTime(today.year, today.month - 12);
    await tester.dragUntilVisible(
      find.text(title(yearAgo)),
      find.byType(CustomScrollView),
      const Offset(0, 400),
      maxIteration: 200,
    );
    expect(find.text(title(yearAgo)), findsOneWidget);

    // …and back, then a year on.
    await tester.tap(find.byTooltip('Сегодня'));
    await tester.pumpAndSettle();
    expect(month(DateTime(today.year, today.month)), findsOneWidget);

    final yearOn = DateTime(today.year, today.month + 12);
    await tester.dragUntilVisible(
      find.text(title(yearOn)),
      find.byType(CustomScrollView),
      const Offset(0, -400),
      maxIteration: 200,
    );
    expect(find.text(title(yearOn)), findsOneWidget);
  });

  testWidgets('a tap on a day shows what was marked on it', (tester) async {
    await db.cycleDao.saveDay(
      today,
      flow: 2,
      mood: 4,
      symptoms: {0, 5},
      sex: 2,
      note: 'Устала',
    );
    await pump(tester);

    await tester.tap(
      find.descendant(
        of: month(DateTime(today.year, today.month)),
        matching: find.text('${today.day}'),
      ),
    );
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    // Flow, sex, mood and the two symptoms are chips; the note is plain text.
    expect(
      find.descendant(of: sheet, matching: find.byType(CycleChip)),
      findsNWidgets(5),
    );
    // The symptoms sit side by side on a line of their own, under their title —
    // not in a column squeezed beside a label.
    final title = tester.getRect(
      find.descendant(of: sheet, matching: find.text('Симптомы')),
    );
    final first = tester.getRect(
      find.ancestor(
        of: find.text('Боль внизу живота'),
        matching: find.byType(CycleChip),
      ),
    );
    final second = tester.getRect(
      find.ancestor(of: find.text('Акне'), matching: find.byType(CycleChip)),
    );
    expect(title.bottom, lessThanOrEqualTo(first.top));
    expect(first.left, title.left);
    expect(second.top, first.top, reason: 'on one line');
    expect(second.left, greaterThan(first.right));

    expect(
      find.descendant(of: sheet, matching: find.text('Интенсивность 2 из 4')),
      findsOneWidget,
    );

    for (final text in ['Тревога', 'Боль внизу живота', 'Акне']) {
      expect(
        find.ancestor(of: find.text(text), matching: find.byType(CycleChip)),
        findsOneWidget,
        reason: text,
      );
    }
    final weekday = DateFormat('EEEE, d MMMM', 'ru_RU').format(today);
    for (final text in [
      weekday[0].toUpperCase() + weekday.substring(1),
      'День цикла 11 из 27',
      'Фертильный день',
      'Близость',
      'Лёгкие',
      'Тревога',
      'Боль внизу живота',
      'Акне',
      'Без защиты',
      'Устала',
      'Изменить день',
    ]) {
      expect(
        find.descendant(of: sheet, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
  });

  testWidgets('a day with nothing on it says so, and offers to mark it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(
      find.descendant(
        of: month(DateTime(today.year, today.month)),
        matching: find.text('${today.day}'),
      ),
    );
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('Пока ничего не отмечено'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Отметить день')),
      findsOneWidget,
    );
    // Nothing to clear.
    expect(find.byTooltip('Очистить отметки этого дня'), findsNothing);
  });

  group('the info sheet of a day', () {
    Future<void> openToday(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: month(DateTime(today.year, today.month)),
          matching: find.text('${today.day}'),
        ),
      );
      await tester.pumpAndSettle();
    }

    String heading(DateTime d) {
      final text = DateFormat('EEEE, d MMMM', 'ru_RU').format(d);
      return text[0].toUpperCase() + text.substring(1);
    }

    testWidgets('steps to the day before and the day after', (tester) async {
      await db.cycleDao.saveDay(today, mood: 1);
      await pump(tester);
      await openToday(tester);
      expect(find.text(heading(today)), findsOneWidget);
      expect(find.text('Радостное'), findsOneWidget);

      await tester.tap(find.byTooltip('Предыдущий день'));
      await tester.pumpAndSettle();
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      expect(find.text(heading(yesterday)), findsOneWidget);
      // Nothing on the day before: today's mood is not carried over.
      expect(find.text('Радостное'), findsNothing);
      expect(find.text('Пока ничего не отмечено'), findsOneWidget);

      await tester.tap(find.byTooltip('Следующий день'));
      await tester.tap(find.byTooltip('Следующий день'));
      await tester.pumpAndSettle();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      expect(find.text(heading(tomorrow)), findsOneWidget);
      // A day that has not come cannot be marked: no buttons.
      expect(find.text('Отметить день'), findsOneWidget); // the page's own
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Отметить день'),
        ),
        findsNothing,
      );
    });

    testWidgets('the calendar behind follows the arrows', (tester) async {
      await pump(tester);
      final first = DateTime(today.year, today.month, 1);
      Finder dayIn(DateTime d) => find.descendant(
        of: month(DateTime(d.year, d.month)),
        matching: find.text('${d.day}'),
      );
      // The picked day wears the blue ring.
      bool ringed(DateTime d) {
        final cell = tester.widget<Container>(
          find.ancestor(of: dayIn(d), matching: find.byType(Container)).first,
        );
        final border = (cell.foregroundDecoration as BoxDecoration?)?.border;
        return border?.top.color == todayBlue;
      }

      await tester.tap(dayIn(first));
      await tester.pumpAndSettle();
      // The first tap picks the day, the second opens it — unless it was
      // already the picked one (the 1st is today) and the first tap opened it.
      if (find.byType(BottomSheet).evaluate().isEmpty) {
        await tester.tap(dayIn(first));
        await tester.pumpAndSettle();
      }
      final second = DateTime(today.year, today.month, 2);
      expect(ringed(first), isTrue);

      await tester.tap(find.byTooltip('Следующий день'));
      await tester.pumpAndSettle();
      expect(ringed(second), isTrue);
      expect(ringed(first), isFalse);

      await tester.tap(find.byTooltip('Предыдущий день'));
      await tester.pumpAndSettle();
      expect(ringed(first), isTrue);
      expect(ringed(second), isFalse);
    });

    testWidgets('the trash takes every mark off the day, after asking', (
      tester,
    ) async {
      await db.cycleDao.saveDay(today, flow: 3, mood: 2, note: 'Устала');
      await pump(tester);
      await openToday(tester);

      await tester.tap(find.byTooltip('Очистить отметки этого дня'));
      await tester.pumpAndSettle();
      expect(find.text('Очистить отметки дня?'), findsOneWidget);
      await tester.tap(find.text('Очистить'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      final row = await tester.runAsync(() => db.cycleDao.getDay(today));
      expect(row!.flow, 0);
      expect(row.mood, isNull);
      expect(row.note, isNull);
      // The sheet follows the data: nothing left to read.
      expect(find.text('Пока ничего не отмечено'), findsOneWidget);
    });

    testWidgets('"Изменить день" opens the day sheet of that day', (
      tester,
    ) async {
      await db.cycleDao.saveDay(today, mood: 1);
      await pump(tester);
      await openToday(tester);

      await tester.tap(find.text('Изменить день'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppSheet),
          matching: find.text(DateFormat.MMMMd('ru_RU').format(today)),
        ),
        findsOneWidget,
      );
    });
  });
}
