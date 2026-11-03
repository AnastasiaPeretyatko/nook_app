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
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/widgets/app_dialogs.dart' show AppSheet;
import 'package:todo_app/widgets/cycle/cycle_colors.dart'
    show periodColor, todayBlue;
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

  testWidgets('day circles keep space around their borders', (tester) async {
    await pump(tester);
    final day = find.descendant(
      of: month(DateTime(today.year, today.month)),
      matching: find.text('${today.day}'),
    );
    final margin = find.ancestor(
      of: day,
      matching: find.byWidgetPredicate(
        (w) => w is Padding && w.padding == const EdgeInsets.all(6),
      ),
    );
    expect(margin, findsOneWidget);

    final cellRect = tester.getRect(margin);
    final circleRect = tester.getRect(
      find.descendant(of: margin, matching: find.byType(CustomPaint)).first,
    );
    expect(circleRect.left - cellRect.left, 6);
    expect(circleRect.top - cellRect.top, 6);
    expect(cellRect.right - circleRect.right, 6);
    expect(cellRect.bottom - circleRect.bottom, 6);
  });

  testWidgets('today is labelled and bold without a border', (tester) async {
    await pump(tester);
    final currentMonth = month(DateTime(today.year, today.month));
    final number = find.descendant(
      of: currentMonth,
      matching: find.text('${today.day}'),
    );
    final label = find.descendant(
      of: currentMonth,
      matching: find.text('сегодня'),
    );
    final cell = tester.widget<Container>(
      find.ancestor(of: number, matching: find.byType(Container)).first,
    );
    final circle = find
        .ancestor(of: number, matching: find.byType(CustomPaint))
        .first;

    expect(label, findsOneWidget);
    expect(
      tester.getBottomLeft(label).dy,
      lessThanOrEqualTo(tester.getTopLeft(circle).dy),
    );
    expect(tester.widget<Text>(label).style?.color, Colors.black);
    expect(tester.widget<Text>(number).style?.fontWeight, FontWeight.w700);
    expect(cell.foregroundDecoration, isNull);
  });

  testWidgets('cycle phases have distinct calendar treatments', (tester) async {
    await pump(tester);

    Finder dayIn(DateTime day) => find.descendant(
      of: month(DateTime(day.year, day.month)),
      matching: find.text('${day.day}'),
    );
    Color? fillOf(DateTime day) =>
        (tester
                    .widget<Container>(
                      find
                          .ancestor(
                            of: dayIn(day),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration?)
            ?.color;
    Color? inkOf(DateTime day) => tester.widget<Text>(dayIn(day)).style?.color;
    CustomPainter? painterOf(DateTime day) => tester
        .widget<CustomPaint>(
          find
              .ancestor(of: dayIn(day), matching: find.byType(CustomPaint))
              .first,
        )
        .painter;
    Color? dashOf(DateTime day) {
      final painter = painterOf(day);
      return painter == null ? null : (painter as dynamic).color as Color?;
    }

    final settings = container.read(aboutSettingsProvider.notifier);

    // An arrived period day is solid red with a white number.
    await settings.setLastStart(today);
    await tester.pumpAndSettle();
    expect(fillOf(today), periodColor);
    expect(inkOf(today), Colors.white);
    expect(painterOf(today), isNull);

    // Fertile days have only a blue number.
    await settings.setLastStart(
      DateTime(today.year, today.month, today.day - 8),
    );
    await tester.pumpAndSettle();
    expect(fillOf(today), isNull);
    expect(inkOf(today), todayBlue);
    expect(painterOf(today), isNull);

    // Ovulation has a blue number and a blue dashed outline.
    await settings.setLastStart(
      DateTime(today.year, today.month, today.day - 13),
    );
    await tester.pumpAndSettle();
    expect(fillOf(today), isNull);
    expect(inkOf(today), todayBlue);
    expect(dashOf(today), todayBlue);

    // A period day that has not happened yet stays unfilled and dashed, even
    // when it is still inside the first configured cycle.
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    await settings.setLastStart(today);
    await tester.pumpAndSettle();
    if (month(DateTime(tomorrow.year, tomorrow.month)).evaluate().isEmpty) {
      await tester.dragUntilVisible(
        month(DateTime(tomorrow.year, tomorrow.month)),
        find.byType(CustomScrollView),
        const Offset(0, -300),
      );
    }
    expect(fillOf(tomorrow), isNull);
    expect(inkOf(tomorrow), periodColor);
    expect(dashOf(tomorrow), periodColor);
  });

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

  group('a calendar day tap', () {
    Finder dayIn(DateTime day) => find.descendant(
      of: month(DateTime(day.year, day.month)),
      matching: find.text('${day.day}'),
    );

    testWidgets('leaves only the full-width "Изменить даты" action', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Изменить даты'), findsOneWidget);
      expect(find.text('Отметить день'), findsNothing);
      final action = find.ancestor(
        of: find.text('Изменить даты'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(action).width, greaterThan(700));
    });

    testWidgets('opens the information sheet on the first tap', (tester) async {
      final picked = DateTime(today.year, today.month, 1);
      await pump(tester);
      final barriersBefore = find.byType(ModalBarrier).evaluate().length;
      await tester.tap(dayIn(picked));
      await tester.pumpAndSettle();
      expect(find.byType(ModalBarrier).evaluate().length, barriersBefore);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('${picked.day} '),
        ),
        findsWidgets,
      );
      expect(find.text('Пока ничего не отмечено'), findsOneWidget);
    });

    testWidgets('updates the open panel when another day is tapped', (
      tester,
    ) async {
      final first = DateTime(today.year, today.month, 1);
      final second = DateTime(today.year, today.month, 2);
      String heading(DateTime day) {
        final text = DateFormat('EEEE, d MMMM', 'ru_RU').format(day);
        return text[0].toUpperCase() + text.substring(1);
      }

      await pump(tester);
      await tester.tap(dayIn(first));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(heading(first)), findsOneWidget);
      Color? fillOf(DateTime day) =>
          (tester
                      .widget<Container>(
                        find
                            .ancestor(
                              of: dayIn(day),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration?)
              ?.color;
      expect(fillOf(first), AppPalette.light.chip);

      await tester.tap(dayIn(second));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(heading(first)), findsNothing);
      expect(find.text(heading(second)), findsOneWidget);
      expect(fillOf(first), isNot(AppPalette.light.chip));
      expect(fillOf(second), AppPalette.light.chip);
    });

    testWidgets('shows future information without a mark action', (
      tester,
    ) async {
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      if (tomorrow.month != today.month) return; // last day of the month
      await pump(tester);
      await tester.tap(dayIn(tomorrow));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Отметить день'), findsNothing);
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

    Future<CycleDay?> rowOf(WidgetTester tester, DateTime day) async {
      CycleDay? result;
      await tester.runAsync(() async {
        result = await db.cycleDao.getDay(day);
      });
      return result;
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
      final marked = await rowOf(tester, today);
      expect(marked?.isPeriod, isTrue);
      expect(marked?.flow, 0);
      expect(find.byType(BottomSheet), findsNothing);
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
      expect(fillOf(today), periodColor);

      await tester.tap(dayIn(today));
      await settle(tester);
      final cleared = await rowOf(tester, today);
      expect(cleared?.isPeriod, isFalse);
      expect(cleared?.flow, 0);

      // Done: a tap opens what is on the day again.
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      await tester.tap(dayIn(today));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('a calendar mark has no default intensity', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Изменить даты'));
      await tester.pumpAndSettle();
      await tester.tap(dayIn(today));
      await settle(tester);

      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      await tester.tap(dayIn(today));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Месячные')),
        findsWidgets,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Средние')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.textContaining('Интенсивность'),
        ),
        findsNothing,
      );
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
      expect(fillOf(first), periodColor);

      await tester.tap(find.text('Изменить даты'));
      await tester.pumpAndSettle();
      await tester.tap(dayIn(first));
      await settle(tester);
      expect(fillOf(first), isNot(periodColor), reason: 'the tap takes it off');

      await tester.tap(dayIn(first));
      await settle(tester);
      expect(fillOf(first), periodColor, reason: 'and the next puts it back');
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
        final row = await rowOf(tester, d);
        expect(row?.isPeriod, isTrue, reason: '$d');
        expect(row?.flow, 0, reason: '$d');
      }
      // And no day beyond them.
      final before = DateTime(today.year, today.month, today.day - 5);
      if (before.month == today.month) {
        expect(await rowOf(tester, before), isNull);
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
      expect(await rowOf(tester, tomorrow), isNull);
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
      expect(row!.isPeriod, isTrue);
      expect(row.flow, 0);
      expect(row.mood, 2);
      expect(row.symptoms, '1,3');
      expect(row.note, 'Устала');
    });
  });

  testWidgets('the sheet lists symptoms and discharge side by side', (
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
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Отметить день'),
      ),
    );
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
      expect(find.text('Отметить день'), findsNothing);
    });

    testWidgets('the calendar behind follows the arrows', (tester) async {
      await pump(tester);
      final first = DateTime(today.year, today.month, 1);
      Finder dayIn(DateTime d) => find.descendant(
        of: month(DateTime(d.year, d.month)),
        matching: find.text('${d.day}'),
      );
      // The picked day has a neutral fill and no border.
      bool selected(DateTime d) {
        final cell = tester.widget<Container>(
          find.ancestor(of: dayIn(d), matching: find.byType(Container)).first,
        );
        final fill = (cell.decoration as BoxDecoration?)?.color;
        return fill == AppPalette.light.chip &&
            cell.foregroundDecoration == null;
      }

      await tester.tap(dayIn(first));
      await tester.pumpAndSettle();
      final second = DateTime(today.year, today.month, 2);
      expect(selected(first), isTrue);

      await tester.tap(find.byTooltip('Следующий день'));
      await tester.pumpAndSettle();
      expect(selected(second), isTrue);
      expect(selected(first), isFalse);

      await tester.tap(find.byTooltip('Предыдущий день'));
      await tester.pumpAndSettle();
      expect(selected(first), isTrue);
      expect(selected(second), isFalse);
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
