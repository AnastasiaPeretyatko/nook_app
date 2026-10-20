import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/widgets/app_bottom_nav_bar.dart';

/// The count on the tasks tab — the only thing on screen that says "something
/// is overdue" while another tab is up.
///
/// The bar itself knows nothing about tasks: it is handed a number through
/// [AppNavItem.badgeCount], which is what these tests drive. Where the number
/// comes from is `overdueTasksProvider` and is pinned by `overdue_test.dart`.
const _tasksIndex = 1;

List<AppNavItem> _items(int badge) => [
  const AppNavItem(icon: LucideIcons.circle_check, label: 'Привычки'),
  AppNavItem(icon: LucideIcons.list, label: 'Задачи', badgeCount: badge),
  const AppNavItem(icon: LucideIcons.git_commit_vertical, label: 'Таймлайн'),
  const AppNavItem(icon: LucideIcons.file_text, label: 'Дневник'),
];

Widget _bar(int badge, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildAppTheme(const Color(0xFF8B7CF6), brightness),
      home: Scaffold(
        bottomNavigationBar: AppBottomNavBar(
          items: _items(badge),
          currentIndex: _tasksIndex,
          onTap: (_) {},
        ),
      ),
    );

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// The bubble: the only `Container` in the bar carrying a border, the ring it
/// draws in the bar's own colour.
BoxDecoration _bubble(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((d) => d.border != null);

void main() {
  testWidgets('the count sits on the tasks tab', (tester) async {
    await tester.pumpWidget(_bar(3));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('nothing is drawn at zero', (tester) async {
    await tester.pumpWidget(_bar(0));
    await tester.pumpAndSettle();

    // No bubble at all, rather than an empty one or a "0".
    expect(find.text('0'), findsNothing);
    expect(
      tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.border != null),
      isEmpty,
    );
  });

  testWidgets('a long count is capped at 9+', (tester) async {
    await tester.pumpWidget(_bar(42));
    await tester.pumpAndSettle();

    // The bubble marks a 22px icon; three digits would be wider than the icon.
    expect(find.text('9+'), findsOneWidget);
    expect(find.text('42'), findsNothing);
  });

  testWidgets('nine still reads as a number', (tester) async {
    await tester.pumpWidget(_bar(9));
    await tester.pumpAndSettle();

    expect(find.text('9'), findsOneWidget);
  });

  testWidgets('a screen reader is told what the number is', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_bar(2));
    await tester.pumpAndSettle();

    // A bare "2" on an icon means nothing read out loud.
    expect(
      find.bySemanticsLabel(RegExp('Просроченных задач: 2')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the bubble stays inside the bar it sits on', (tester) async {
    await tester.pumpWidget(_bar(9));
    await tester.pumpAndSettle();

    // The bubble hangs off the icon's corner out of a `Clip.none` stack, so
    // nothing stops it leaving the bar — it would simply be drawn half over the
    // page behind. Pinned at the phone width the test binding uses.
    final bubble = tester.getRect(find.text('9'));
    final bar = tester.getRect(find.byType(AppBottomNavBar));
    expect(bar.contains(bubble.topRight), isTrue);
    expect(bar.contains(bubble.bottomLeft), isTrue);
  });

  for (final brightness in Brightness.values) {
    testWidgets('the badge reads on the bar in the $brightness theme', (
      tester,
    ) async {
      await tester.pumpWidget(_bar(5, brightness: brightness));
      await tester.pumpAndSettle();

      final bubble = _bubble(tester);
      final fill = bubble.color!;
      // The ring is painted in the bar's own colour, so it is also what the
      // bubble has to stand out against — read from the tree rather than
      // repeated here.
      final barColor = (bubble.border! as Border).top.color;
      final digit = tester.widget<Text>(find.text('5')).style!.color!;

      expect(
        _contrast(fill, barColor),
        greaterThanOrEqualTo(3),
        reason: 'the bubble disappears into the bar',
      );
      expect(
        _contrast(digit, fill),
        greaterThanOrEqualTo(4.5),
        reason: 'the number cannot be read on the bubble',
      );
    });
  }
}
