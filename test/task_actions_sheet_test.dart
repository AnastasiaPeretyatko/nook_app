import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
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
}
