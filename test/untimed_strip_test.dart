import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/widgets/home/task_timeline.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Any moment at all: these tests never read a log's edit time. It exists
/// because the sync needs one and the column is therefore not nullable.
final _fixtureStamp = DateTime(2026, 1, 1);

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

const _taskColor = Color(0xFFFFC1CC);

Task _task({
  required int id,
  required String title,
  int? scheduledTimeMinutes,
  String? iconKey,
  TaskStatus status = TaskStatus.active,
  DateTime? startDate,
  int? parentId,
}) => Task(
  dirty: false,
  id: id,
  title: title,
  parentId: parentId,
  status: status,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: scheduledTimeMinutes,
  iconKey: iconKey,
  colorValue: 0xFFFFC1CC, // == _taskColor
  startDate: startDate ?? _today,
  createdAt: _today,
  updatedAt: _today,
);

Widget _timeline(List<Task> tasks, {List<TaskLog> logs = const []}) =>
    ProviderScope(
      overrides: [
        rootTasksProvider.overrideWith((ref) => Stream.value(tasks)),
        allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
        logsForDateProvider.overrideWith((ref, date) => Stream.value(logs)),
      ],
      child: MaterialApp(
        locale: const Locale('ru', 'RU'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru', 'RU')],
        home: Scaffold(body: TaskTimeline(selectedDay: _today)),
      ),
    );

/// Circle finder scoped to the strip — the timeline itself also draws round
/// nodes in the task colour, so an unscoped search would count those too.
Finder _stripCircles() => find.descendant(
  of: _horizontalScroll(),
  matching: find.byWidgetPredicate(
    (w) =>
        w is Container &&
        (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
  ),
);

int _circles(WidgetTester tester) => _stripCircles().evaluate().length;

Finder _horizontalScroll() => find.byWidgetPredicate(
  (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
  });

  testWidgets('shows a circle and a title per timeless task', (tester) async {
    await tester.pumpWidget(
      _timeline([
        _task(id: 1, title: 'Купить хлеб'),
        _task(id: 2, title: 'Позвонить маме'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_circles(tester), 2);
    expect(find.text('Купить хлеб'), findsOneWidget);
    expect(find.text('Позвонить маме'), findsOneWidget);
  });

  testWidgets('tasks with a time stay on the timeline, not in the strip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _timeline([
        _task(id: 1, title: 'Без времени'),
        _task(id: 2, title: 'Со временем', scheduledTimeMinutes: 9 * 60),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_circles(tester), 1);
    expect(find.text('Без времени'), findsOneWidget);
    // The timed one is rendered by the timeline itself: it keeps its clock
    // label, which the timeline prints both in the time column and on the row.
    expect(find.text('Со временем'), findsOneWidget);
    expect(find.text('09:00'), findsWidgets);
  });

  testWidgets('the strip survives a day with no timed tasks at all', (
    tester,
  ) async {
    await tester.pumpWidget(_timeline([_task(id: 1, title: 'Просто дело')]));
    await tester.pumpAndSettle();

    expect(_circles(tester), 1);
    // The empty state still explains that nothing is on the clock.
    expect(find.text('На этот день нет задач со временем'), findsOneWidget);
  });

  testWidgets('no strip when every task has a time', (tester) async {
    await tester.pumpWidget(
      _timeline([_task(id: 1, title: 'Утро', scheduledTimeMinutes: 8 * 60)]),
    );
    await tester.pumpAndSettle();

    expect(_circles(tester), 0);
    expect(_horizontalScroll(), findsNothing);
  });

  testWidgets('archived tasks are left out', (tester) async {
    await tester.pumpWidget(
      _timeline([
        _task(id: 1, title: 'Активная'),
        _task(id: 2, title: 'В архиве', status: TaskStatus.archived),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_circles(tester), 1);
    expect(find.text('В архиве'), findsNothing);
  });

  testWidgets('a task from another day is left out', (tester) async {
    await tester.pumpWidget(
      _timeline([
        _task(id: 1, title: 'Сегодня'),
        _task(
          id: 2,
          title: 'Завтра',
          startDate: _today.add(const Duration(days: 1)),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_circles(tester), 1);
    expect(find.text('Завтра'), findsNothing);
  });

  testWidgets('the circle wears the task colour, not a neutral grey', (
    tester,
  ) async {
    await tester.pumpWidget(_timeline([_task(id: 1, title: 'Дело')]));
    await tester.pumpAndSettle();

    final circle = tester.widget<Container>(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
      ),
    );
    expect((circle.decoration as BoxDecoration).color, _taskColor);
  });

  testWidgets('the first title clears the left edge, not the circle', (
    tester,
  ) async {
    await tester.pumpWidget(_timeline([_task(id: 1, title: 'Дело')]));
    await tester.pumpAndSettle();

    // This used to assert the circle sat at x=12, "the margin the timeline's own
    // rows use", and it had been failing since the strip was designed. Both
    // halves of that were wrong: the rows use `TaskTimeline.contentPad`, which
    // is **4**, and they put a 56px time column to the left of their markers, so
    // there was never a column for the circles to line up with.
    //
    // What the strip actually decides — spelled out on `_UntimedStrip.sideMargin`
    // — is that the *title* owns the margin. A slot is 72 wide and centres a
    // 52 circle in it, so pulling the circle out to the sheet's edge would drag
    // the title 10px past it, against the wall. The margin is therefore kept by
    // the slot, and the circle sits inside it.
    final slot = tester.getRect(find.byType(SizedBox).at(0));
    final circle = tester.getRect(_stripCircles());

    expect(circle.left, greaterThan(slot.left));
    expect(
      circle.left,
      12 + (72 - 52) / 2,
      reason: 'sideMargin plus the slack the slot leaves around its circle',
    );
  });

  testWidgets('the title is what keeps clear of the sheet edge', (
    tester,
  ) async {
    await tester.pumpWidget(_timeline([_task(id: 1, title: 'Дело')]));
    await tester.pumpAndSettle();

    // The point of the margin, asserted as the thing it is for rather than as
    // the number it happens to be.
    final sheet = tester.getRect(find.byType(TaskTimeline));
    final title = tester.getRect(find.text('Дело'));

    expect(title.left - sheet.left, greaterThanOrEqualTo(12));
  });

  testWidgets('neighbouring titles are kept apart', (tester) async {
    await tester.pumpWidget(
      _timeline([
        _task(id: 1, title: 'Очень длинное название первой задачи'),
        _task(id: 2, title: 'Очень длинное название второй задачи'),
      ]),
    );
    await tester.pumpAndSettle();

    // Both titles fill their slot, so the clear space between them is the gap.
    // Sorted by position, because the strip orders slots alphabetically and the
    // titles here do not happen to line up with that.
    final titles = [
      tester.getRect(find.text('Очень длинное название первой задачи')),
      tester.getRect(find.text('Очень длинное название второй задачи')),
    ]..sort((a, b) => a.left.compareTo(b.left));
    expect(titles[1].left - titles[0].right, greaterThanOrEqualTo(16));

    // The circles keep the same rhythm: one slot plus one gap apart.
    final circles = _stripCircles();
    expect(
      tester.getTopLeft(circles.at(1)).dx - tester.getTopLeft(circles.at(0)).dx,
      72 + 16,
    );
  });

  group('subtask counter', () {
    testWidgets('a task with subtasks reports how many are done', (
      tester,
    ) async {
      await tester.pumpWidget(
        _timeline(
          [
            _task(id: 1, title: 'Переезд', scheduledTimeMinutes: 9 * 60),
            _task(id: 2, title: 'Коробки', parentId: 1),
            _task(id: 3, title: 'Машина', parentId: 1),
          ],
          logs: [
            TaskLog(
              dirty: false,
              updatedAt: _fixtureStamp,
              id: 1,
              taskId: 2,
              date: _today,
              completed: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('a task without subtasks shows no counter', (tester) async {
      await tester.pumpWidget(
        _timeline([
          _task(id: 1, title: 'Одиночка', scheduledTimeMinutes: 9 * 60),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets('subtasks do not become timeline rows of their own', (
      tester,
    ) async {
      await tester.pumpWidget(
        _timeline([
          _task(id: 1, title: 'Переезд', scheduledTimeMinutes: 9 * 60),
          // A subtask with a time of its own must still stay a subtask.
          _task(
            id: 2,
            title: 'Коробки',
            parentId: 1,
            scheduledTimeMinutes: 10 * 60,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Переезд'), findsOneWidget);
      expect(find.text('Коробки'), findsNothing);
      expect(find.text('0/1'), findsOneWidget);
    });
  });

  testWidgets('the strip is not glued to the first timeline row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _timeline([
        _task(id: 1, title: 'Без времени'),
        _task(id: 2, title: 'Со временем', scheduledTimeMinutes: 9 * 60),
      ]),
    );
    await tester.pumpAndSettle();

    final stripBottom = tester.getRect(find.text('Без времени')).bottom;
    final firstRowTop = tester.getRect(find.text('09:00').first).top;
    expect(firstRowTop - stripBottom, greaterThanOrEqualTo(20));
  });

  testWidgets('a completed task is struck through and ticked', (tester) async {
    await tester.pumpWidget(
      _timeline(
        [_task(id: 1, title: 'Сделано')],
        logs: [
          TaskLog(
            dirty: false,
            updatedAt: _fixtureStamp,
            id: 1,
            taskId: 1,
            date: _today,
            completed: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Сделано'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
  });

  testWidgets('many tasks scroll sideways instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      // Zero-padded so the strip's alphabetical order matches the numbering and
      // "Дело 12" really is the rightmost slot.
      _timeline([
        for (var i = 1; i <= 12; i++)
          _task(id: i, title: 'Дело ${i.toString().padLeft(2, '0')}'),
      ]),
    );
    await tester.pumpAndSettle();

    // Reaching this line at all means 12 slots laid out without a RenderFlex
    // overflow, which is the point of the horizontal scroll view.
    expect(_circles(tester), 12);

    final scroll = _horizontalScroll();
    expect(scroll, findsOneWidget);

    // The scroll view builds every child eagerly, so the last one exists in the
    // tree from the start — its position is what says it is off screen.
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final before = tester.getTopLeft(find.text('Дело 12')).dx;
    expect(before, greaterThan(screenWidth));

    await tester.drag(scroll, const Offset(-600, 0));
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(find.text('Дело 12')).dx;
    expect(after, lessThan(before));
    expect(after, lessThan(screenWidth));
  });
}
