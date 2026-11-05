import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/cycle_page.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/task_colors.dart' show onTaskColor;
import 'package:todo_app/widgets/app_bottom_nav_bar.dart';
import 'package:todo_app/widgets/app_dialogs.dart' show AppSheet;
import 'package:todo_app/widgets/cycle/cycle_colors.dart';
import 'package:todo_app/widgets/cycle/cycle_heart.dart';
import 'package:todo_app/widgets/cycle/period_start_sheet.dart';
import 'package:todo_app/widgets/habits/habits_week.dart' show DashedBox;

/// The Cycle tab: the day picked in the week, the button and the quick marks
/// that follow it, the hearts, and the figures worked out from the marks.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  /// A day of the current week that is not today and has already come — the
  /// strip shows it whichever weekday the test runs on, because the week starts
  /// on Sunday when today is a Monday.
  final yesterday = DateTime(today.year, today.month, today.day - 1);

  setUp(() async {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    await initializeDateFormatting('ru_RU');
    SharedPreferences.setMockInitialValues({
      'about_gender': 'female',
      if (today.weekday == DateTime.monday) 'week_start_day': DateTime.sunday,
    });
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
      ],
    );
    // Cycle day 11 today.
    await container
        .read(aboutSettingsProvider.notifier)
        .setLastStart(DateTime(today.year, today.month, today.day - 10));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    // A tall screen: the list builds only what is on it.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CyclePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The strip comes first in the tree, so its number is the first match.
  Finder stripDay(DateTime day) => find.text('${day.day}').first;

  testWidgets('period started uses the custom range sheet and applies days', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Месячные начались'));
    await tester.pumpAndSettle();

    expect(find.byType(PeriodStartSheet), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);

    final start = DateTime(today.year, today.month, today.day - 10);
    final end = DateTime(start.year, start.month, start.day + 2);
    String keyOf(DateTime day) =>
        'date-${DateFormat('yyyy-MM-dd').format(day)}';

    await tester.tap(find.byKey(ValueKey(keyOf(start))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('period-start-reset')));
    await tester.pumpAndSettle();
    expect(find.byType(PeriodStartSheet), findsNothing);

    await tester.tap(find.text('Месячные начались'));
    await tester.pumpAndSettle();
    expect(
      (tester.widget<Container>(find.byKey(ValueKey(keyOf(start)))).decoration
              as BoxDecoration?)
          ?.color,
      isNull,
    );
    await tester.tap(find.byKey(ValueKey(keyOf(start))));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(keyOf(end))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('period-start-apply')));
    await tester.pumpAndSettle();

    expect(find.byType(PeriodStartSheet), findsNothing);
    expect(container.read(aboutSettingsProvider).lastStart, start);
    for (var offset = 0; offset <= 2; offset++) {
      final day = DateTime(start.year, start.month, start.day + offset);
      final row = await db.cycleDao.getDay(day);
      expect(row?.isPeriod, isTrue, reason: '$day');
      expect(row?.flow, 0, reason: '$day');
    }

    await tester.tap(find.text('Месячные начались'));
    await tester.pumpAndSettle();
    for (var offset = 0; offset <= 2; offset++) {
      final day = DateTime(start.year, start.month, start.day + offset);
      final cell = tester.widget<Container>(find.byKey(ValueKey(keyOf(day))));
      expect(
        (cell.decoration as BoxDecoration?)?.color,
        isNull,
        reason: '$day is saved but temporary selection starts empty',
      );
      final row = await db.cycleDao.getDay(day);
      expect(row?.isPeriod, isTrue, reason: '$day remains saved');
    }
  });

  testWidgets('a picked day is what a quick mark opens', (tester) async {
    await pump(tester);
    await tester.tap(stripDay(yesterday));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Настроение'));
    await tester.pumpAndSettle();

    // The card under the ring says the date too, so look in the sheet.
    expect(
      find.descendant(
        of: find.byType(AppSheet),
        matching: find.text(DateFormat.MMMMd('ru_RU').format(yesterday)),
      ),
      findsOneWidget,
    );
    expect(find.text('День цикла 10'), findsOneWidget);
  });

  testWidgets('there is no "Отметить" bar on the tab any more', (tester) async {
    await pump(tester);
    expect(find.text('Отметить'), findsNothing);
    // The four quick marks are how a day is marked here.
    for (final label in ['Месячные', 'Секс', 'Настроение', 'Симптомы']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('and with nothing picked it is today', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Настроение'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppSheet),
        matching: find.text(DateFormat.MMMMd('ru_RU').format(today)),
      ),
      findsOneWidget,
    );
    expect(find.text('День цикла 11'), findsOneWidget);
  });

  testWidgets('the week keeps its original compact day geometry', (
    tester,
  ) async {
    await pump(tester);
    final cell = find.byKey(
      ValueKey('week-day-${DateFormat('yyyy-MM-dd').format(today)}'),
    );
    final widget = tester.widget<Container>(cell);
    final decoration = widget.decoration as BoxDecoration;
    final weekday = tester.widget<Text>(
      find.descendant(
        of: cell,
        matching: find.text(DateFormat.E('ru_RU').format(today)),
      ),
    );
    final number = tester.widget<Text>(
      find.descendant(of: cell, matching: find.text('${today.day}')),
    );

    expect(tester.getSize(cell).height, 68);
    expect(decoration.borderRadius, BorderRadius.circular(14));
    expect(decoration.color, AppPalette.light.textPrimary);
    expect(weekday.style?.fontSize, 11);
    expect(number.style?.fontSize, 15);
    expect(number.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('today is dashed in the week once another day is picked', (
    tester,
  ) async {
    await pump(tester);
    final todayCell = find.byKey(
      ValueKey('week-day-${DateFormat('yyyy-MM-dd').format(today)}'),
    );
    CustomPainter? todayBorder() => tester
        .widget<CustomPaint>(
          find
              .ancestor(of: todayCell, matching: find.byType(CustomPaint))
              .first,
        )
        .foregroundPainter;
    expect(todayBorder(), isNull);

    await tester.tap(stripDay(yesterday));
    await tester.pumpAndSettle();
    expect(todayBorder(), isA<DashedBox>());

    await tester.tap(find.text('Сегодня'));
    await tester.pumpAndSettle();
    expect(todayBorder(), isNull);
  });

  testWidgets('the ring follows the picked day', (tester) async {
    await pump(tester);
    // Today: day 11 of the cycle in the centre.
    expect(find.text('11'), findsWidgets);

    await tester.tap(stripDay(yesterday));
    await tester.pumpAndSettle();
    // Day 10 is the big number now, and the badge says 10 as well.
    expect(find.text('10'), findsWidgets);
    expect(find.text('/ 27'), findsOneWidget);
  });

  testWidgets("today's number on the ring is never cut off", (tester) async {
    await pump(tester);
    final badge = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).borderRadius ==
              BorderRadius.circular(11) &&
          w.constraints?.minWidth == 22,
    );

    // Days all the way round: the badge sits right of its dot, so it is the
    // right-hand and the lower ones that used to run past the ring's square.
    for (final d in [2, 6, 8, 13, 15, 20, 25]) {
      await container
          .read(aboutSettingsProvider.notifier)
          .setLastStart(DateTime(today.year, today.month, today.day - (d - 1)));
      await tester.pumpAndSettle();

      final stack = tester.widget<Stack>(
        find.ancestor(of: badge, matching: find.byType(Stack)).first,
      );
      expect(stack.clipBehavior, Clip.none, reason: 'day $d');

      final card = find
          .ancestor(
            of: badge,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).border != null,
            ),
          )
          .first;
      // On the line from the centre through the day's dot, clear of its rim.
      final ringRect = tester.getRect(
        find.ancestor(of: badge, matching: find.byType(Stack)).first,
      );
      final marker = tester.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border?.top.width == 3,
        ),
      );
      final badgeRect = tester.getRect(badge);
      final numberRect = tester.getRect(
        find.descendant(of: badge, matching: find.text('$d')),
      );
      expect(
        numberRect.center.dx,
        closeTo(badgeRect.center.dx, 0.01),
        reason: 'day $d: the number is not centred in its badge',
      );
      expect(badgeRect.overlaps(marker), isFalse, reason: 'day $d');
      final toMarker = marker.center - ringRect.center;
      final toBadge = badgeRect.center - ringRect.center;
      final cross = toMarker.dx * toBadge.dy - toMarker.dy * toBadge.dx;
      expect(
        cross.abs() / (toMarker.distance * toBadge.distance),
        lessThan(0.02),
        reason: 'day $d: the number is not outwards from its dot',
      );
      expect(toBadge.distance, greaterThan(toMarker.distance));

      final inside = tester
          .getRect(card)
          .contains(tester.getRect(badge).topLeft);
      expect(inside, isTrue, reason: 'day $d: the badge leaves its card');
      expect(
        tester.getRect(card).contains(tester.getRect(badge).bottomRight),
        isTrue,
        reason: 'day $d',
      );
    }
  });

  testWidgets('the picked ring day uses its phase colour', (tester) async {
    await pump(tester);
    final badge = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).borderRadius ==
              BorderRadius.circular(11) &&
          w.constraints?.minWidth == 22,
    );
    final marker = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border?.top.width == 3,
    );

    for (final (day, expected, expectedInk) in [
      (2, periodColor, Colors.white),
      (11, fertileColor, Colors.white),
      (14, ovulationColor, Colors.white),
      (
        20,
        otherDayColor(AppPalette.light),
        onTaskColor(otherDayColor(AppPalette.light)),
      ),
    ]) {
      await container
          .read(aboutSettingsProvider.notifier)
          .setLastStart(
            DateTime(today.year, today.month, today.day - (day - 1)),
          );
      await tester.pumpAndSettle();

      expect(
        (tester.widget<Container>(badge).decoration as BoxDecoration).color,
        expected,
        reason: 'day $day badge',
      );
      expect(
        (tester.widget<Container>(marker).decoration as BoxDecoration)
            .border
            ?.top
            .color,
        expected,
        reason: 'day $day marker',
      );
      final number = tester.widget<Text>(
        find.descendant(of: badge, matching: find.text('$day')),
      );
      expect(
        number.style?.color,
        expectedInk,
        reason: 'day $day number contrast',
      );
    }
  });

  testWidgets('a day that has not come can be looked at, not marked', (
    tester,
  ) async {
    await pump(tester);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    // Only reachable while tomorrow is in the shown week.
    final shown = find.text('${tomorrow.day}');
    if (shown.evaluate().isEmpty) return;
    await tester.tap(shown.first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Настроение'));
    await tester.pumpAndSettle();
    expect(find.text('Сохранить'), findsNothing);
    expect(find.byTooltip('Сохранить'), findsNothing);
  });

  testWidgets('a quick mark opens only its own choices, and keeps the rest', (
    tester,
  ) async {
    await db.cycleDao.saveDay(today, flow: 3, symptoms: {3});
    await pump(tester);

    await tester.tap(find.text('Настроение'));
    await tester.pumpAndSettle();
    // The moods are there; the symptoms and the flow are not.
    final sheet = find.byType(AppSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('Спокойное')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Вздутие')),
      findsNothing,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Обильные')),
      findsNothing,
    );

    await tester.tap(find.text('Тревога'));
    await tester.pump();
    await tester.tap(find.byTooltip('Сохранить'));
    await tester.pumpAndSettle();

    final saved = (await db.cycleDao.getDay(today))!;
    expect(saved.mood, 4);
    expect(saved.flow, 3);
    expect(saved.symptoms, '3');
  });

  testWidgets('hearts: solid with protection, an outline without', (
    tester,
  ) async {
    await db.cycleDao.saveDay(today, sex: 2);
    await db.cycleDao.saveDay(yesterday, sex: 1);
    final noSex = DateTime(today.year, today.month, today.day - 2);
    await db.cycleDao.saveDay(noSex, sex: 0);
    await pump(tester);

    // In the strip only — the block of the picked day draws one as well.
    Finder heart(int sex) => find.descendant(
      of: find.byType(PageView),
      matching: find.byWidgetPredicate((w) => w is CycleHeart && w.sex == sex),
    );
    expect(heart(1), findsOneWidget);
    expect(heart(2), findsOneWidget);
    expect(heart(0), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PageView).first,
        matching: find.byKey(const ValueKey('info-dot')),
      ),
      findsNothing,
    );
  });

  testWidgets('the week mirrors cycle phases, selection and mixed indicators', (
    tester,
  ) async {
    await db.cycleDao.saveDay(yesterday, isPeriod: true);
    await db.cycleDao.saveDay(today, sex: 1, mood: 2);
    await pump(tester);

    Finder weekDay(DateTime day) => find.byKey(
      ValueKey('week-day-${DateFormat('yyyy-MM-dd').format(day)}'),
    );
    Finder weekPaint(DateTime day) => find
        .ancestor(of: weekDay(day), matching: find.byType(CustomPaint))
        .first;
    Color? fillOf(DateTime day) =>
        (tester.widget<Container>(weekDay(day)).decoration as BoxDecoration?)
            ?.color;

    final mixed = weekDay(today);
    expect(
      find.descendant(of: mixed, matching: find.byType(CycleHeart)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: mixed,
        matching: find.byKey(const ValueKey('info-dot')),
      ),
      findsOneWidget,
    );

    expect(fillOf(yesterday), periodColor);

    await tester.tap(stripDay(yesterday));
    await tester.pumpAndSettle();
    expect(fillOf(yesterday), AppPalette.light.textPrimary);
    expect(
      tester.widget<CustomPaint>(weekPaint(yesterday)).foregroundPainter,
      isNull,
    );

    final model = container.read(aboutSettingsProvider).model!;
    final configuredWeekStart = today.weekday == DateTime.monday
        ? DateTime.sunday
        : DateTime.monday;
    DateTime firstOfWeek(DateTime day) => DateTime(
      day.year,
      day.month,
      day.day - (day.weekday - configuredWeekStart + 7) % 7,
    );
    Future<void> showWeek(DateTime day) async {
      final offset =
          firstOfWeek(day).difference(firstOfWeek(today)).inDays ~/ 7;
      final page = tester.widget<PageView>(find.byType(PageView).first);
      page.controller!.jumpToPage(5000 + offset);
      await tester.pumpAndSettle();
    }

    final ovulation = model.nextOvulation(today);
    await showWeek(ovulation);
    final ovulationPaint = tester.widget<CustomPaint>(weekPaint(ovulation));
    expect((ovulationPaint.foregroundPainter as DashedBox).color, todayBlue);

    final nextPeriod = model.nextPeriodStart(today);
    await showWeek(nextPeriod);
    final periodPaint = tester.widget<CustomPaint>(weekPaint(nextPeriod));
    expect((periodPaint.foregroundPainter as DashedBox).color, periodColor);
    expect(fillOf(nextPeriod), isNull);
  });

  testWidgets('the figures are worked out from the marks', (tester) async {
    // Periods starting 84, 57 and 29 days ago: cycles of 27 and 28.
    for (final ago in [84, 57, 29]) {
      for (var i = 0; i < 3; i++) {
        await db.cycleDao.saveDay(
          DateTime(today.year, today.month, today.day - ago + i),
          flow: 2,
        );
      }
    }
    await container
        .read(aboutSettingsProvider.notifier)
        .setLastStart(DateTime(today.year, today.month, today.day - 29));
    await pump(tester);

    expect(find.text('Разброс циклов'), findsOneWidget);
    expect(find.text('±1 д.'), findsOneWidget);
  });

  testWidgets('with no history the spread is a dash', (tester) async {
    await pump(tester);
    expect(find.text('Разброс циклов'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('the week strip swipes to the next and the previous week', (
    tester,
  ) async {
    await pump(tester);
    // The ring says which day of the cycle it shows: 11 today, 27 in all.
    Finder ringDay(int n) => find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label?.startsWith('День $n из 27') ?? false),
    );
    expect(ringDay(11), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    // The pick moved to the same weekday a week on, and "Сегодня" is the way back.
    expect(ringDay(18), findsOneWidget);
    expect(find.text('Сегодня'), findsOneWidget);

    await tester.tap(find.text('Сегодня'));
    await tester.pumpAndSettle();
    expect(ringDay(11), findsOneWidget);
    expect(find.text('Сегодня'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(ringDay(4), findsOneWidget);
  });

  testWidgets('the picked day shows what was marked on it', (tester) async {
    await db.cycleDao.saveDay(
      today,
      flow: 4,
      mood: 1,
      symptoms: {3},
      discharge: 4,
      sex: 1,
      note: 'Устала',
    );
    await pump(tester);

    // Today is picked: all of it is there, as chips under the buttons...
    for (final text in [
      'Месячные · обильные',
      'Радостное',
      'Вздутие',
      'Выделения · тягучие',
      'Секс · с защитой',
      'Устала',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    // ...and a tick on each of the four buttons whose group is marked.
    expect(find.byIcon(LucideIcons.check), findsNWidgets(4));

    // Another day, with nothing on it.
    await tester.tap(stripDay(yesterday));
    await tester.pumpAndSettle();
    expect(find.text('Месячные · обильные'), findsNothing);
    expect(find.text('Устала'), findsNothing);
    expect(find.byIcon(LucideIcons.check), findsNothing);
  });

  testWidgets('a button is ticked only for its own group', (tester) async {
    await db.cycleDao.saveDay(today, mood: 2);
    await pump(tester);

    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.text('Энергичное'), findsOneWidget);
    // The ring card holds the ring, the forecast and the marks together.
    expect(find.text('БЫСТРО ОТМЕТИТЬ'), findsOneWidget);
    expect(find.text('Овуляция'), findsWidgets);
    expect(find.text('Заметка'), findsNothing);
  });

  testWidgets('the tags on the ring and in the cards fit their text', (
    tester,
  ) async {
    await pump(tester);

    // The test font is wide, so "narrow" is measured against the words: the
    // pill is its text and its padding, not the ring's or the card's width.
    void fits(Finder text) {
      final pill = find
          .ancestor(of: text, matching: find.byType(Container))
          .first;
      expect(
        tester.getSize(pill).width,
        lessThanOrEqualTo(tester.getSize(text).width + 26),
      );
    }

    // Day 11 of the cycle is a fertile one.
    fits(find.text('Фертильные дни'));
  });

  testWidgets('the forecasts are two blocks with a hairline between them', (
    tester,
  ) async {
    await pump(tester);
    final ovulation = find.textContaining('Овуляция · ');
    final period = find.textContaining('Месячные · ≈ ');
    expect(ovulation, findsOneWidget);
    expect(period, findsOneWidget);

    // Side by side: one line, the ovulation on the left.
    final o = tester.getRect(ovulation);
    final m = tester.getRect(period);
    expect(m.top, o.top);
    expect(m.left, greaterThan(o.right));
    // With a vertical hairline between them, and the days to each in large type.
    final divider = tester.getRect(
      find.descendant(
        of: find.byType(IntrinsicHeight),
        matching: find.byType(VerticalDivider),
      ),
    );
    expect(divider.left, greaterThan(o.right - 1));
    expect(divider.right, lessThan(m.left + 1));
    expect(find.textContaining('через'), findsNWidgets(2));
    expect(find.text('Ожидается 5 дней'), findsOneWidget);
    expect(find.textContaining('Фертильное окно '), findsWidgets);
  });

  testWidgets('the list ends clear of the bar', (tester) async {
    // A short screen, so the page has to scroll to reach its last note.
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    // A phone with a gesture bar: the system inset sits under the nav bar.
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CyclePage()),
      ),
    );
    await tester.pumpAndSettle();

    final note = find.textContaining('Прогнозы — это примерная оценка');
    // The page's own scrollable — the week strip has one of its own.
    final list = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(note, 300, scrollable: list);
    await tester.drag(list, const Offset(0, -2000));
    await tester.pumpAndSettle();

    // The bar of the real app is `barHeight` tall plus the inset under it, and
    // the note must end above that with some air to spare.
    expect(
      tester.getBottomLeft(note).dy,
      lessThanOrEqualTo(900 - 34 - AppBottomNavBar.barHeight - 16),
    );
  });
}
