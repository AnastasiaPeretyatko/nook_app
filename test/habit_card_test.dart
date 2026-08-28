import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/widgets/habits/habits_grid.dart';

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);
final _monday = _today.subtract(Duration(days: _today.weekday - 1 + 7));
final _days = List.generate(14, (i) => _monday.add(Duration(days: i)));

Task _habit(String title, {DateTime? startDate}) => Task(
  dirty: false,
  id: 1,
  title: title,
  status: TaskStatus.active,
  repeatType: RepeatType.daily,
  trackingMode: TrackingMode.checkbox,
  colorValue: 0xFFFFC1CC,
  startDate: startDate ?? _today.subtract(const Duration(days: 30)),
  createdAt: _today,
  updatedAt: _today,
);

/// Day squares drawn as an empty outline — a miss, or a day before the habit
/// started. Both are slots the user can still fill in.
int _hollowSquares(WidgetTester tester) => tester
    .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
    .map((c) => c.decoration as BoxDecoration?)
    .where((d) => d?.color == Colors.transparent && d?.border != null)
    .length;

/// Days outside the schedule, drawn as a small dot.
int _dots(WidgetTester tester) => find
    .descendant(of: find.byType(AspectRatio), matching: find.byType(Container))
    .evaluate()
    .where(
      (e) =>
          ((e.widget as Container).decoration as BoxDecoration?)?.shape ==
          BoxShape.circle,
    )
    .length;

/// Renders a card at the width a habit column actually gets on a phone. The
/// scroll view matters: it leaves the height unbounded, exactly as [HabitsGrid]
/// does, so the card shrink-wraps its content instead of stretching to fill.
/// Fill colour of the card itself — the outermost animated box inside the card.
Color? _cardColor(WidgetTester tester) {
  final card = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byType(HabitCard),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return (card.decoration as BoxDecoration?)?.color;
}

Future<double> _cardHeight(
  WidgetTester tester,
  String title, {
  DateTime? startDate,
  Set<DateTime> completedDays = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 164,
                child: HabitCard(
                  task: _habit(title, startDate: startDate),
                  days: _days,
                  today: _today,
                  completedDays: completedDays,
                  todayLog: null,
                  timerRunningSince: null,
                  onTap: () {},
                  onMark: () {},
                  onTimerStart: () {},
                  onTimerStop: () {},
                  onCounterInc: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(HabitCard)).height;
}

void main() {
  testWidgets('a long title does not make the card taller', (tester) async {
    final short = await _cardHeight(tester, 'Зал');
    final twoLines = await _cardHeight(tester, 'Утренняя зарядка дома');
    final overflowing = await _cardHeight(
      tester,
      'Очень длинное название привычки, которое точно не влезает в карточку',
    );

    expect(twoLines, short);
    expect(overflowing, short);
  });

  testWidgets('a habit created today still draws the previous week', (
    tester,
  ) async {
    await _cardHeight(tester, 'Зал', startDate: _today);

    // Everything before today is pre-history: the whole previous week plus the
    // current week up to yesterday. All of it must be an outlined slot, never a
    // blank gap in the strip.
    expect(_hollowSquares(tester), 7 + (_today.weekday - 1));
    // A daily habit falls on every day, so nothing is drawn as a dot.
    expect(_dots(tester), 0);
  });

  group('done for today', () {
    const habitColor = Color(0xFFFFC1CC);
    const doneGrey = Color(0xFFD1D1D6);

    testWidgets('turns the card grey', (tester) async {
      await _cardHeight(tester, 'Зал', completedDays: {_today});

      expect(_cardColor(tester), doneGrey);
    });

    testWidgets('an open habit keeps its own colour', (tester) async {
      await _cardHeight(tester, 'Зал');

      expect(_cardColor(tester), habitColor);
    });

    testWidgets('a day done earlier does not grey out today', (tester) async {
      await _cardHeight(
        tester,
        'Зал',
        completedDays: {_today.subtract(const Duration(days: 1))},
      );

      expect(_cardColor(tester), habitColor);
    });
  });

  testWidgets('the title still shows two lines before clipping', (
    tester,
  ) async {
    await _cardHeight(tester, 'Утренняя зарядка дома');

    final title = tester.widget<Text>(find.text('Утренняя зарядка дома'));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
  });
}
