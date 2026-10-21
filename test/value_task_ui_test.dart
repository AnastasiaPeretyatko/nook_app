import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/widgets/habits/habit_actions_sheet.dart';
import 'package:todo_app/widgets/habits/habits_today.dart';
import 'package:todo_app/widgets/habits/tasks_list.dart';

/// Any moment at all: these tests never read a log's edit time.
final _stamp = DateTime(2026, 1, 1);

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

DateTime _daysAgo(int n) => DateTime(_today.year, _today.month, _today.day - n);

Task _task({
  required int id,
  required String title,
  TrackingMode mode = TrackingMode.value,
  RepeatType? repeatType,
  int startedDaysAgo = 40,
}) => Task(
  dirty: false,
  id: id,
  title: title,
  status: TaskStatus.active,
  repeatType: repeatType,
  trackingMode: mode,
  colorValue: 0xFFFFC1CC,
  startDate: _daysAgo(startedDaysAgo),
  createdAt: _daysAgo(startedDaysAgo),
  updatedAt: _daysAgo(startedDaysAgo),
);

TaskLog _log(int taskId, int daysAgo, {bool completed = true}) => TaskLog(
  dirty: false,
  updatedAt: _stamp,
  id: taskId * 1000 + daysAgo,
  taskId: taskId,
  date: _daysAgo(daysAgo),
  completed: completed,
);

/// The week start, the lateness grace and the "today" switch are read from the
/// store, so anything drawing a habit needs one.
late SharedPreferences _prefs;

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_prefs),
        ...overrides,
      ],
      child: MaterialApp(
        locale: const Locale('ru', 'RU'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru', 'RU')],
        home: Scaffold(body: home),
      ),
    );

/// The habits tab fed from fixed lists. Every stream the list opens is covered,
/// or it would reach for the on-device database.
Widget _grid(List<Task> tasks, List<TaskLog> logs, {AppDatabase? db}) => _app(
  const HabitsToday(),
  overrides: [
    rootTasksProvider.overrideWith((ref) => Stream.value(tasks)),
    logsBetweenProvider.overrideWith((ref, range) => Stream.value(logs)),
    allLogsProvider.overrideWith((ref) => Stream.value(logs)),
    openSessionsProvider.overrideWith((ref) => Stream.value(const [])),
    if (db != null) databaseProvider.overrideWithValue(db),
  ],
);

Widget _sheet(Task task, List<TaskLog> logs, {AppDatabase? db}) => _app(
  HabitActionsSheet(task: task),
  overrides: [
    logsForTaskProvider.overrideWith((ref, id) => Stream.value(logs)),
    logsBetweenProvider.overrideWith((ref, range) => Stream.value(logs)),
    if (db != null) databaseProvider.overrideWithValue(db),
  ],
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1000, 2600);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  group('the habits tab', () {
    testWidgets('shows how long ago a value task was last done', (
      tester,
    ) async {
      await tester.pumpWidget(
        _grid([_task(id: 1, title: 'Смена белья')], [_log(1, 12), _log(1, 30)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Смена белья'), findsOneWidget);
      expect(find.text('12 дней назад'), findsOneWidget);
      expect(find.byTooltip('Отметить сегодня'), findsOneWidget);
    });

    testWidgets('a task never marked says so, and since when', (tester) async {
      await tester.pumpWidget(
        _grid([_task(id: 1, title: 'Смена белья', startedDaysAgo: 3)], []),
      );
      await tester.pumpAndSettle();

      expect(find.text('Нет отметок'), findsOneWidget);
      expect(find.textContaining('Слежу с'), findsOneWidget);
    });

    testWidgets('marked today reads "Сегодня" and shows the row as done', (
      tester,
    ) async {
      await tester.pumpWidget(
        _grid([_task(id: 1, title: 'Смена белья')], [_log(1, 0), _log(1, 9)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Сегодня'), findsOneWidget);
      expect(find.byTooltip('Снять отметку за сегодня'), findsOneWidget);
      expect(find.byTooltip('Отметить сегодня'), findsNothing);
      expect(
        tester.widget<Text>(find.text('Смена белья')).style?.decoration,
        TextDecoration.lineThrough,
      );
    });

    testWidgets('a mark that was taken back does not count', (tester) async {
      await tester.pumpWidget(
        _grid(
          [_task(id: 1, title: 'Смена белья')],
          [_log(1, 0, completed: false), _log(1, 4)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('4 дня назад'), findsOneWidget);
      expect(find.byTooltip('Отметить сегодня'), findsOneWidget);
    });

    testWidgets('sits after the habits, whatever order they come in', (
      tester,
    ) async {
      await tester.pumpWidget(
        _grid([
          _task(id: 1, title: 'Белье'),
          _task(
            id: 2,
            title: 'Зарядка',
            mode: TrackingMode.checkbox,
            repeatType: RepeatType.daily,
          ),
          _task(
            id: 3,
            title: 'Вода',
            mode: TrackingMode.checkbox,
            repeatType: RepeatType.daily,
          ),
        ], const []),
      );
      await tester.pumpAndSettle();

      // Top to bottom: both habits, then a block of its own for the value task
      // — which is not counted among today's.
      expect(find.text('ЗНАЧЕНИЯ'), findsOneWidget);
      expect(find.text('0 из 2'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('ЗНАЧЕНИЯ')).dy,
        lessThan(tester.getTopLeft(find.text('Белье')).dy),
      );
      final value = tester.getTopLeft(find.text('Белье')).dy;
      expect(value, greaterThan(tester.getTopLeft(find.text('Зарядка')).dy));
      expect(value, greaterThan(tester.getTopLeft(find.text('Вода')).dy));
    });

    testWidgets('tapping the plate marks today, once', (tester) async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final task = await tester.runAsync(() async {
        final id = await db.tasksDao.insertTask(
          TasksCompanion.insert(title: 'Смена белья'),
        );
        return (await db.tasksDao.getTaskById(id))!;
      });

      await tester.pumpWidget(
        _grid(
          [task!.copyWith(trackingMode: TrackingMode.value)],
          const [],
          db: db,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Отметить сегодня'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );

      final logs = (await tester.runAsync(() => db.select(db.taskLogs).get()))!;
      expect(logs, hasLength(1));
      expect(logs.single.taskId, task.id);
      expect(logs.single.date, _today);
      expect(logs.single.completed, isTrue);
    });
  });

  group('the row', () {
    // A flutter_test overflow is a test failure, so rendering is the assertion.
    for (final scale in [1.0, 1.6]) {
      testWidgets('fits a phone at text scale $scale', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ru', 'RU'),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 360,
                        child: HabitRow(
                          task: _task(
                            id: 1,
                            title: 'Сменить постельное белье в спальне',
                          ),
                          today: _today,
                          completedDays: const {},
                          todayLog: null,
                          lastDone: _daysAgo(21),
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
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('21 день назад'), findsOneWidget);
      });
    }
  });

  group('the tasks tab', () {
    testWidgets('does not list a value task, however old its date', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const TasksList(),
          overrides: [
            allTasksProvider.overrideWith(
              (ref) => Stream.value([
                _task(id: 1, title: 'Смена белья'),
                _task(id: 2, title: 'Позвонить', mode: TrackingMode.checkbox),
              ]),
            ),
            allLogsProvider.overrideWith((ref) => Stream.value(const [])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Позвонить'), findsOneWidget);
      expect(find.text('Смена белья'), findsNothing);
      // The same old date would have put it under "Просрочено".
      expect(find.text('ПРОСРОЧЕНО'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('the sheet', () {
    testWidgets('tells when it was last done and lists the latest marks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _sheet(_task(id: 1, title: 'Смена белья'), [
          for (final n in [2, 9, 16, 23, 30, 37]) _log(1, n),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 дня назад'), findsOneWidget);
      expect(find.text('Отметить сегодня'), findsOneWidget);
      expect(find.text('Другая дата'), findsOneWidget);
      expect(find.text('Последние отметки'), findsOneWidget);
      // Five of the six; the older ones stay stored and still count.
      expect(find.byTooltip('Убрать отметку'), findsNWidgets(5));
      // No day squares and no history calendar: it has no days.
      expect(find.byType(AspectRatio), findsNothing);
      expect(find.byTooltip('История'), findsNothing);
    });

    testWidgets('marked today offers to take it back', (tester) async {
      await tester.pumpWidget(
        _sheet(_task(id: 1, title: 'Смена белья'), [_log(1, 0)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Снять за сегодня'), findsOneWidget);
      expect(find.text('Отметить сегодня'), findsNothing);
    });

    testWidgets('a task never marked has no list to show', (tester) async {
      await tester.pumpWidget(_sheet(_task(id: 1, title: 'Смена белья'), []));
      await tester.pumpAndSettle();

      expect(find.text('Нет отметок'), findsOneWidget);
      expect(find.text('Последние отметки'), findsNothing);
    });

    testWidgets('removing a mark writes it as not done', (tester) async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final task = await tester.runAsync(() async {
        final id = await db.tasksDao.insertTask(
          TasksCompanion.insert(title: 'Смена белья'),
        );
        await db.tasksDao.setLog(id, _daysAgo(3), completed: true);
        return (await db.tasksDao.getTaskById(id))!;
      });

      await tester.pumpWidget(
        _sheet(task!.copyWith(trackingMode: TrackingMode.value), [
          _log(task.id, 3),
        ], db: db),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Убрать отметку'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );

      final logs = (await tester.runAsync(() => db.select(db.taskLogs).get()))!;
      expect(logs.single.completed, isFalse);
    });

    testWidgets('a habit keeps its day squares', (tester) async {
      await tester.pumpWidget(
        _sheet(
          _task(
            id: 1,
            title: 'Зарядка',
            mode: TrackingMode.checkbox,
            repeatType: RepeatType.daily,
          ),
          const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AspectRatio), findsWidgets);
      expect(find.byTooltip('История'), findsOneWidget);
      expect(find.text('Последние отметки'), findsNothing);
    });
  });
}
