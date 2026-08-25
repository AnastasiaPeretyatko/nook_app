import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';

late AppDatabase db;

Widget _form({TaskFormMode mode = TaskFormMode.create, Task? task}) =>
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        locale: const Locale('ru', 'RU'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru', 'RU')],
        home: CreateTaskPage(mode: mode, task: task),
      ),
    );

Finder _addButton() => find.text('Добавить подзадачу');

/// The title input, matched on its hint so it stays findable once typed into.
Finder _titleField() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Что нужно сделать?',
);

/// The white plates the form is built from — a [DecoratedBox] carrying a shadow.
Finder _cards() => find.byWidgetPredicate(
  (w) => w is DecoratedBox && (w.decoration as BoxDecoration).boxShadow != null,
);

/// The card [of] sits in.
Rect _cardAround(WidgetTester tester, Finder of) =>
    tester.getRect(find.ancestor(of: of, matching: _cards()).first);

/// Subtask inputs, matched on the widget's own hint rather than on rendered text
/// so a row stays findable after it has been typed into. Plain [TextField]s —
/// the title and description are [TextFormField]s.
Finder _subtaskFields() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Подзадача',
);

/// Pumps a bounded number of frames instead of settling: the save button shows a
/// [CircularProgressIndicator] while it works, and that animation never ends, so
/// `pumpAndSettle` would wait for it forever.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Lets real database work finish. Inside `testWidgets` time is faked, so drift's
/// futures never complete unless they run through [WidgetTester.runAsync].
Future<void> _flushDatabase(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await _settle(tester);
}

Future<void> _openForm(
  WidgetTester tester, {
  TaskFormMode mode = TaskFormMode.create,
  Task? task,
}) async {
  await tester.pumpWidget(_form(mode: mode, task: task));
  await _settle(tester);
  if (task != null) await _flushDatabase(tester);
}

Future<void> _typeSubtask(WidgetTester tester, int index, String text) async {
  await tester.enterText(_subtaskFields().at(index), text);
  await _settle(tester);
}

Future<void> _saveForm(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await _settle(tester);
  await _flushDatabase(tester);
}

/// Runs a database call on the real event loop and hands back its result. Every
/// query in a test body needs this — under fake time a drift future, and a stream
/// even more so, simply never completes.
Future<T> _db<T>(WidgetTester tester, Future<T> Function() body) async {
  late T result;
  await tester.runAsync(() async => result = await body());
  return result;
}

/// One-shot reads only: `watch*` streams never emit inside `testWidgets`.
Future<List<Task>> _allTasks() => db.select(db.tasks).get();
Future<List<TaskLog>> _allLogs() => db.select(db.taskLogs).get();

Future<List<String>> _subtaskTitles(int parentId) async =>
    (await db.tasksDao.getSubtasks(parentId)).map((t) => t.title).toList();

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
  });

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1000, 2600);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  tearDown(() async => db.close());

  group('adding rows', () {
    testWidgets('the form starts with the button and no rows', (tester) async {
      await _openForm(tester);

      expect(_addButton(), findsOneWidget);
      expect(_subtaskFields(), findsNothing);
    });

    testWidgets('each tap adds one row', (tester) async {
      await _openForm(tester);

      await tester.tap(_addButton());
      await _settle(tester);
      expect(_subtaskFields(), findsOneWidget);

      await tester.tap(_addButton());
      await _settle(tester);
      expect(_subtaskFields(), findsNWidgets(2));
    });

    testWidgets('a row can be taken back out', (tester) async {
      await _openForm(tester);
      await tester.tap(_addButton());
      await _settle(tester);

      await tester.tap(find.byTooltip('Убрать подзадачу'));
      await _settle(tester);

      expect(_subtaskFields(), findsNothing);
    });

    testWidgets('the label heads the block and the button closes it', (
      tester,
    ) async {
      await _openForm(tester);
      await tester.tap(_addButton());
      await _settle(tester);
      await _typeSubtask(tester, 0, 'Подшаг');

      final label = tester.getRect(find.text('Описание'));
      final row = tester.getRect(_subtaskFields().first);
      final description = tester.getRect(find.text('Дополнительные детали'));
      final button = tester.getRect(_addButton());

      expect(label.bottom, lessThanOrEqualTo(row.top));
      expect(row.bottom, lessThanOrEqualTo(description.top));
      expect(description.bottom, lessThanOrEqualTo(button.top));
    });

    testWidgets('the label appears once, not twice', (tester) async {
      await _openForm(tester);

      // It used to float inside the description field as well.
      expect(find.text('Описание'), findsOneWidget);
    });

    testWidgets('the button spans the block', (tester) async {
      await _openForm(tester);
      await tester.tap(_addButton());
      await _settle(tester);
      await _typeSubtask(tester, 0, 'Подшаг');

      // As wide as the description input it sits above.
      final buttonBox = tester.getRect(
        find.ancestor(of: _addButton(), matching: find.byType(InkWell)).first,
      );
      final field = tester.getRect(_subtaskFields().first);
      expect(buttonBox.width, greaterThan(field.width));
    });

    testWidgets('no divider separates the rows from the description', (
      tester,
    ) async {
      await _openForm(tester);
      await tester.tap(_addButton());
      await _settle(tester);
      await _typeSubtask(tester, 0, 'Подшаг');

      final row = tester.getRect(_subtaskFields().first);
      final description = tester.getRect(find.text('Дополнительные детали'));
      // Positions come off the render objects: the dividers are identical
      // widgets, so a finder cannot tell them apart.
      final dividerTops = find.byType(Divider).evaluate().map((e) {
        final box = e.renderObject! as RenderBox;
        return box.localToGlobal(Offset.zero).dy;
      }).toList();

      expect(dividerTops, isNotEmpty, reason: 'the card keeps its own rules');
      expect(
        dividerTops.where((y) => y > row.bottom && y < description.top),
        isEmpty,
      );
    });
  });

  group('description block', () {
    testWidgets('the label is flush with the left edge, not centred', (
      tester,
    ) async {
      await _openForm(tester);

      final label = tester.getRect(find.text('Описание'));
      final card = _cardAround(tester, find.text('Описание'));

      // Left-aligned inside its card: the padding is the only thing between it
      // and the edge, and it stops well short of the middle.
      expect(label.left - card.left, lessThan(24));
      expect(label.right, lessThan(card.center.dx));
    });

    testWidgets('the label lines up with the description input', (
      tester,
    ) async {
      await _openForm(tester);

      final label = tester.getRect(find.text('Описание'));
      final hint = tester.getRect(find.text('Дополнительные детали'));

      expect(label.left, moreOrLessEquals(hint.left, epsilon: 1));
    });

    testWidgets('the title and the description are separate cards', (
      tester,
    ) async {
      await _openForm(tester);

      final titleCard = _cardAround(tester, _titleField());
      final descriptionCard = _cardAround(tester, find.text('Описание'));

      expect(titleCard, isNot(descriptionCard));
      // A real gap between the plates, not a divider inside one.
      expect(descriptionCard.top, greaterThan(titleCard.bottom));
    });

    testWidgets('no divider sits between the title and the label', (
      tester,
    ) async {
      await _openForm(tester);

      final title = tester.getRect(_titleField());
      final label = tester.getRect(find.text('Описание'));
      // Positions come off the render objects: the dividers are identical
      // widgets, so a finder cannot tell them apart.
      final dividerTops = find.byType(Divider).evaluate().map((e) {
        final box = e.renderObject! as RenderBox;
        return box.localToGlobal(Offset.zero).dy;
      }).toList();

      expect(
        dividerTops.where((y) => y > title.bottom && y < label.top),
        isEmpty,
      );
    });
  });

  group('saving', () {
    testWidgets('subtasks are stored under the new task', (tester) async {
      await _openForm(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Переезд');
      await tester.tap(_addButton());
      await _settle(tester);
      await _typeSubtask(tester, 0, 'Собрать коробки');
      await tester.tap(_addButton());
      await _settle(tester);
      await _typeSubtask(tester, 1, 'Заказать машину');

      await _saveForm(tester, 'Сохранить');

      final tasks = await _db(tester, _allTasks);
      final root = tasks.singleWhere((t) => t.parentId == null);
      expect(root.title, 'Переезд');
      expect(await _db(tester, () => _subtaskTitles(root.id)), [
        'Собрать коробки',
        'Заказать машину',
      ]);
    });

    testWidgets('a blank row is not saved', (tester) async {
      await _openForm(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Задача');
      await tester.tap(_addButton());
      await _settle(tester);
      await _typeSubtask(tester, 0, 'Реальная');
      // A second row, left untouched.
      await tester.tap(_addButton());
      await _settle(tester);

      await _saveForm(tester, 'Сохранить');

      final tasks = await _db(tester, _allTasks);
      final root = tasks.singleWhere((t) => t.parentId == null);
      expect(await _db(tester, () => _subtaskTitles(root.id)), ['Реальная']);
    });

    testWidgets('a ticked subtask is stored as completed', (tester) async {
      await _openForm(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Задача');
      await tester.tap(_addButton());
      await _settle(tester);
      await _typeSubtask(tester, 0, 'Уже сделана');

      // The checkbox is the row's own square, just left of its field.
      final field = tester.getRect(_subtaskFields().first);
      await tester.tapAt(Offset(field.left - 16, field.center.dy));
      await _settle(tester);

      await _saveForm(tester, 'Сохранить');

      final tasks = await _db(tester, _allTasks);
      final subtask = tasks.singleWhere((t) => t.parentId != null);
      final logs = await _db(tester, _allLogs);
      expect(logs.single.taskId, subtask.id);
      expect(logs.single.completed, isTrue);
    });
  });

  group('an existing task', () {
    Future<Task> seed(WidgetTester tester) => _db(tester, () async {
      final id = await db.tasksDao.insertTask(
        TasksCompanion.insert(title: 'Переезд'),
      );
      await db.tasksDao.insertTask(
        TasksCompanion.insert(title: 'Собрать коробки', parentId: Value(id)),
      );
      return (await db.tasksDao.getTaskById(id))!;
    });

    testWidgets('its subtasks open as editable rows', (tester) async {
      final task = await seed(tester);
      await _openForm(tester, mode: TaskFormMode.edit, task: task);

      expect(_subtaskFields(), findsOneWidget);
      expect(find.text('Собрать коробки'), findsOneWidget);
    });

    testWidgets('a renamed row updates the subtask', (tester) async {
      final task = await seed(tester);
      await _openForm(tester, mode: TaskFormMode.edit, task: task);

      await _typeSubtask(tester, 0, 'Разобрать коробки');
      await _saveForm(tester, 'Сохранить');

      expect(await _db(tester, () => _subtaskTitles(task.id)), [
        'Разобрать коробки',
      ]);
    });

    testWidgets('a removed row deletes the subtask', (tester) async {
      final task = await seed(tester);
      await _openForm(tester, mode: TaskFormMode.edit, task: task);

      await tester.tap(find.byTooltip('Убрать подзадачу'));
      await _settle(tester);
      await _saveForm(tester, 'Сохранить');

      expect(await _db(tester, () => _subtaskTitles(task.id)), isEmpty);
    });

    testWidgets('duplicating copies the subtasks instead of moving them', (
      tester,
    ) async {
      final task = await seed(tester);
      await _openForm(tester, mode: TaskFormMode.clone, task: task);

      await _saveForm(tester, 'Сохранить');

      final tasks = await _db(tester, _allTasks);
      final roots = tasks.where((t) => t.parentId == null).toList();
      expect(roots.length, 2);
      // The original keeps its child and the copy gets one of its own.
      for (final root in roots) {
        expect(await _db(tester, () => _subtaskTitles(root.id)), [
          'Собрать коробки',
        ]);
      }
    });
  });
}
