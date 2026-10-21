import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/widgets/app_toast.dart';
import 'package:todo_app/widgets/habits/task_actions_sheet.dart';

late AppDatabase db;

final _today = DateTime(2026, 8, 18);

Widget _sheet(Task task) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp(
    locale: const Locale('ru', 'RU'),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ru', 'RU')],
    home: Scaffold(
      body: TaskActionsSheet(
        task: task,
        completed: false,
        completionDate: _today,
      ),
    ),
  ),
);

/// A page with one button that opens the sheet as a real modal, so the sheet's
/// own `pop` has a route to close.
Widget _launcher(Task task, {bool completed = false}) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp(
    locale: const Locale('ru', 'RU'),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ru', 'RU')],
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => TaskActionsSheet(
              task: task,
              completed: completed,
              completionDate: _today,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

/// Real database work needs the real event loop; `testWidgets` fakes time.
Future<T> _db<T>(WidgetTester tester, Future<T> Function() body) async {
  late T result;
  await tester.runAsync(() async => result = await body());
  return result;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await _settle(tester);
}

/// Unmounts the tree inside the test body: drift schedules a stream-cleanup
/// timer when its providers are disposed, and if that happens after the body
/// the framework reports it as a pending timer and fails the test.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Elapsing time is what runs that timer; a bare pump only draws a frame.
  await _settle(tester);
}

/// Tick boxes in the subtask list: 20dp rounded squares.
Iterable<BoxDecoration> _boxes(WidgetTester tester) => tester
    .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
    .where((c) => c.constraints?.maxWidth == 20)
    .map((c) => c.decoration)
    .whereType<BoxDecoration>();

int _tickedBoxes(WidgetTester tester) =>
    _boxes(tester).where((d) => d.color != Colors.transparent).length;

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
    view.physicalSize = const Size(1000, 2200);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  tearDown(() async => db.close());

  Future<Task> seed(WidgetTester tester, {int children = 2}) =>
      _db(tester, () async {
        final id = await db.tasksDao.insertTask(
          TasksCompanion.insert(title: 'Переезд', startDate: Value(_today)),
        );
        for (var i = 1; i <= children; i++) {
          await db.tasksDao.insertTask(
            TasksCompanion.insert(title: 'Шаг $i', parentId: Value(id)),
          );
        }
        return (await db.tasksDao.getTaskById(id))!;
      });

  testWidgets('every subtask gets a tick box', (tester) async {
    final task = await seed(tester);
    await tester.pumpWidget(_sheet(task));
    await _flush(tester);

    expect(find.text('Шаг 1'), findsOneWidget);
    expect(find.text('Шаг 2'), findsOneWidget);
    expect(_boxes(tester).length, 2);
    expect(_tickedBoxes(tester), 0);
    await _close(tester);
  });

  testWidgets('tapping a subtask marks it done', (tester) async {
    final task = await seed(tester);
    await tester.pumpWidget(_sheet(task));
    await _flush(tester);

    await tester.tap(find.text('Шаг 1'));
    await _flush(tester);

    final logs = await _db(tester, () => db.select(db.taskLogs).get());
    expect(logs.single.completed, isTrue);
    expect(_tickedBoxes(tester), 1);
    await _close(tester);
  });

  testWidgets('tapping it again clears the tick', (tester) async {
    final task = await seed(tester, children: 1);
    await tester.pumpWidget(_sheet(task));
    await _flush(tester);

    await tester.tap(find.text('Шаг 1'));
    await _flush(tester);
    await tester.tap(find.text('Шаг 1'));
    await _flush(tester);

    final logs = await _db(tester, () => db.select(db.taskLogs).get());
    expect(logs.single.completed, isFalse);
    expect(_tickedBoxes(tester), 0);
    await _close(tester);
  });

  testWidgets('a tick on another day does not show here', (tester) async {
    final task = await seed(tester, children: 1);
    await _db(tester, () async {
      final subtasks = await db.tasksDao.getSubtasks(task.id);
      await db.tasksDao.toggleCompletion(
        subtasks.single.id,
        _today.subtract(const Duration(days: 1)),
      );
    });

    await tester.pumpWidget(_sheet(task));
    await _flush(tester);

    expect(_tickedBoxes(tester), 0);
    await _close(tester);
  });

  testWidgets('deleting shows a toast that takes it back', (tester) async {
    final task = await seed(tester);
    await tester.pumpWidget(
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => TaskActionsSheet(
                    task: task,
                    completed: false,
                    completionDate: _today,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _flush(tester);

    await tester.tap(find.text('Удалить'));
    await _flush(tester);
    await tester.tap(find.text('Удалить').last);
    await _flush(tester);

    expect(find.text('Задача удалена'), findsOneWidget);
    expect(await _db(tester, () => db.tasksDao.getTaskById(task.id)), isNull);

    await tester.tap(find.text('Отменить'));
    await _flush(tester);

    expect(find.text('Задача удалена'), findsNothing);
    expect(
      await _db(tester, () => db.tasksDao.getTaskById(task.id)),
      isNotNull,
    );
    expect(
      await _db(tester, () => db.tasksDao.getSubtasks(task.id)),
      hasLength(2),
    );
    await _close(tester);
  });

  /// A bare app with a button that shows the toast, to test it on its own.
  Future<void> pumpToastApp(WidgetTester tester, {String? action}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppToast(
                  Overlay.of(context, rootOverlay: true),
                  message: 'Задача удалена',
                  actionLabel: action,
                  onAction: () {},
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );

  testWidgets('the toast goes by itself after its time', (tester) async {
    await pumpToastApp(tester, action: 'Отменить');
    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Задача удалена'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Задача удалена'), findsNothing);
  });

  testWidgets('the toast can be swiped away', (tester) async {
    await pumpToastApp(tester);
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.fling(find.text('Задача удалена'), const Offset(600, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Задача удалена'), findsNothing);
  });

  testWidgets('the toast sits at the bottom edge of the screen', (
    tester,
  ) async {
    await pumpToastApp(tester, action: 'Отменить');
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final pill = tester.getRect(find.byType(Dismissible));
    expect(screen.height - pill.bottom, 12);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('"На завтра" moves the task and its ticked subtasks', (
    tester,
  ) async {
    final task = await seed(tester);
    final subs = await _db(tester, () => db.tasksDao.getSubtasks(task.id));
    await _db(
      tester,
      () => db.tasksDao.setLog(subs.first.id, _today, completed: true),
    );
    await tester.pumpWidget(_launcher(task));
    await tester.tap(find.text('open'));
    await _flush(tester);
    expect(find.text('Выполнено'), findsOneWidget);
    expect(find.text('Изменить'), findsOneWidget);
    expect(find.text('Дублировать'), findsOneWidget);

    await tester.tap(find.text('На завтра'));
    await _flush(tester);

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final moved = await _db(tester, () => db.tasksDao.getTaskById(task.id));
    expect(moved!.startDate, tomorrow);
    expect(moved.dirty, isTrue);
    // The tick went along: set on the new day, cleared on the old.
    final logs = await _db(tester, () => db.select(db.taskLogs).get());
    expect(logs.where((l) => l.completed).map((l) => (l.taskId, l.date)), [
      (subs.first.id, tomorrow),
    ]);
    expect(find.text('На завтра'), findsNothing, reason: 'the sheet closed');
    await _close(tester);
  });

  testWidgets('"На завтра" is not offered for a habit or a ticked task', (
    tester,
  ) async {
    final task = await seed(tester, children: 0);
    final habit = task.copyWith(repeatType: const Value(RepeatType.daily));

    await tester.pumpWidget(_launcher(habit));
    await tester.tap(find.text('open'));
    await _flush(tester);
    expect(find.text('На завтра'), findsNothing);
    expect(find.text('Изменить'), findsOneWidget);
    await _close(tester);

    await tester.pumpWidget(_launcher(task, completed: true));
    await tester.tap(find.text('open'));
    await _flush(tester);
    expect(find.text('На завтра'), findsNothing);
    await _close(tester);
  });

  testWidgets('the title block says when the task is', (tester) async {
    final base = await seed(tester, children: 0);
    final task = base.copyWith(
      scheduledTimeMinutes: const Value(15 * 60),
      endTimeMinutes: const Value(15 * 60 + 30),
    );
    // The sheet reads the day it was opened for: 18 August in these tests.
    await tester.pumpWidget(_launcher(task));
    await tester.tap(find.text('open'));
    await _flush(tester);

    expect(find.text('18 августа, 15:00 – 15:30'), findsOneWidget);
    await _close(tester);
  });
}
