import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/value_detail_page.dart';
import 'package:todo_app/widgets/date_range_calendar.dart';
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

TaskLog _datedLog(int taskId, DateTime date, {required int id}) => TaskLog(
  dirty: false,
  updatedAt: _stamp,
  id: id,
  taskId: taskId,
  date: date,
  completed: true,
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

Widget _valuePage(Task task, List<TaskLog> logs, {AppDatabase? db}) => _app(
  ValueDetailPage(taskId: task.id),
  overrides: [
    rootTasksProvider.overrideWith((ref) => Stream.value([task])),
    logsForTaskProvider.overrideWith((ref, id) => Stream.value(logs)),
    if (db != null) databaseProvider.overrideWithValue(db),
  ],
);

Widget _liveValuePage(Task task, AppDatabase db) => _app(
  ValueDetailPage(taskId: task.id),
  overrides: [
    rootTasksProvider.overrideWith((ref) => Stream.value([task])),
    databaseProvider.overrideWithValue(db),
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

  group('averageCompletionIntervalDays', () {
    test('averages consecutive unique calendar dates', () {
      final result = averageCompletionIntervalDays([
        DateTime(2026, 10, 12, 23, 30),
        DateTime(2026, 10, 1, 8),
        DateTime(2026, 10, 5, 17),
        DateTime(2026, 10, 5, 21),
      ]);

      expect(result, 5.5);
    });

    test('returns null with fewer than two unique dates', () {
      expect(averageCompletionIntervalDays(const []), isNull);
      expect(
        averageCompletionIntervalDays([
          DateTime(2026, 10, 5, 8),
          DateTime(2026, 10, 5, 21),
        ]),
        isNull,
      );
    });
  });

  group('sortCompletionDates', () {
    final dates = [
      DateTime(2026, 10, 5, 23),
      DateTime(2026, 10, 1, 8),
      DateTime(2026, 10, 12, 12),
    ];

    test('sorts newest first by completion date', () {
      expect(sortCompletionDates(dates, CompletionSortOrder.newestFirst), [
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 1),
      ]);
    });

    test('sorts oldest first by completion date', () {
      expect(sortCompletionDates(dates, CompletionSortOrder.oldestFirst), [
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 12),
      ]);
    });
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

    testWidgets('tapping a value opens its details page, not a modal', (
      tester,
    ) async {
      await tester.pumpWidget(
        _grid([_task(id: 1, title: 'Смена белья')], [_log(1, 2)]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Смена белья'));
      await tester.pumpAndSettle();

      expect(find.byType(ValueDetailPage), findsOneWidget);
      expect(find.text('Значение'), findsOneWidget);
      expect(find.byTooltip('Назад'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.byType(ValueDetailPage), findsNothing);
      expect(find.text('Смена белья'), findsOneWidget);
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

  group('the value details page', () {
    testWidgets('uses the custom single-date sheet for another date', (
      tester,
    ) async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final task = await tester.runAsync(() async {
        final id = await db.tasksDao.insertTask(
          TasksCompanion.insert(title: 'Смена белья'),
        );
        return (await db.tasksDao.getTaskById(id))!;
      });

      await tester.pumpWidget(
        _liveValuePage(task!.copyWith(trackingMode: TrackingMode.value), db),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Другая дата'));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangeCalendar), findsOneWidget);
      expect(find.byType(DatePickerDialog), findsNothing);

      final apply = find.byKey(const ValueKey('value-date-apply'));
      InkWell applyInk() => tester.widget<InkWell>(
        find.descendant(of: apply, matching: find.byType(InkWell)),
      );
      expect(applyInk().onTap, isNull);

      final todayKey = ValueKey(
        'date-${DateFormat('yyyy-MM-dd').format(_today)}',
      );
      await tester.tap(find.byKey(todayKey));
      await tester.pump();
      expect(applyInk().onTap, isNotNull);

      await tester.tap(apply);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DateRangeCalendar), findsNothing);
      var logs = (await tester.runAsync(() => db.select(db.taskLogs).get()))!;
      expect(logs, hasLength(1));
      expect(logs.single.date, _today);
      expect(logs.single.completed, isTrue);

      await tester.tap(find.text('Другая дата'));
      await tester.pumpAndSettle();
      final dayDecoration =
          tester.widget<Container>(find.byKey(todayKey)).decoration
              as BoxDecoration;
      expect(dayDecoration.color, isNull);
      expect(applyInk().onTap, isNull);

      await tester.tap(find.byKey(const ValueKey('value-date-reset')));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangeCalendar), findsNothing);
      logs = (await tester.runAsync(() => db.select(db.taskLogs).get()))!;
      expect(logs.single.completed, isTrue);

      // Let Drift dispose the watched query before the in-memory executor is
      // closed by tearDown.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('shows the value calendar above recent completions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _valuePage(_task(id: 1, title: 'Смена белья'), [_log(1, 0)]),
      );
      await tester.pumpAndSettle();

      final calendar = find.byKey(
        ValueKey('value-calendar-${_today.year}-${_today.month}'),
      );
      final recent = find.byKey(const ValueKey('value-recent-completions'));
      expect(calendar, findsOneWidget);
      expect(recent, findsOneWidget);
      expect(
        tester.getTopLeft(calendar).dy,
        lessThan(tester.getTopLeft(recent).dy),
      );
    });

    testWidgets('highlights only completed dates and keeps today outlined', (
      tester,
    ) async {
      final otherDay = _today.day == 1 ? 2 : 1;
      await tester.pumpWidget(
        _valuePage(_task(id: 1, title: 'Смена белья'), [
          _datedLog(1, DateTime(_today.year, _today.month, otherDay), id: 7001),
        ]),
      );
      await tester.pumpAndSettle();

      BoxDecoration decoration(int day) =>
          tester
                  .widget<Container>(
                    find.byKey(
                      ValueKey(
                        'value-calendar-day-${_today.year}-${_today.month}-$day',
                      ),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      final completed = decoration(otherDay);
      final today = decoration(_today.day);
      final theme = Theme.of(
        tester.element(
          find.byKey(
            ValueKey(
              'value-calendar-day-${_today.year}-${_today.month}-$otherDay',
            ),
          ),
        ),
      );
      expect(completed.color, theme.colorScheme.primary);
      expect(completed.border, isNull);
      expect(today.color, isNull);
      expect(today.border, isNotNull);
    });

    testWidgets('navigates months and shows completions by actual date', (
      tester,
    ) async {
      final previous = DateTime(_today.year, _today.month - 1);
      final completed = DateTime(previous.year, previous.month, 1);
      await tester.pumpWidget(
        _valuePage(_task(id: 1, title: 'Смена белья'), [
          _datedLog(1, completed, id: 7101),
          _datedLog(1, completed.add(const Duration(hours: 8)), id: 7102),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Предыдущий месяц'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          ValueKey('value-calendar-${previous.year}-${previous.month}'),
        ),
        findsOneWidget,
      );
      final day = find.byKey(
        ValueKey('value-calendar-day-${previous.year}-${previous.month}-1'),
      );
      expect(day, findsOneWidget);
      final decoration =
          tester.widget<Container>(day).decoration as BoxDecoration;
      expect(
        decoration.color,
        Theme.of(tester.element(day)).colorScheme.primary,
      );
    });

    testWidgets('sorts completions by their completion date', (tester) async {
      await tester.pumpWidget(
        _valuePage(_task(id: 1, title: 'Смена белья'), [
          _log(1, 2),
          _log(1, 9),
          _log(1, 16),
        ]),
      );
      await tester.pumpAndSettle();

      final section = find.byKey(const ValueKey('value-recent-completions'));
      Finder date(int daysAgo) => find.descendant(
        of: section,
        matching: find.textContaining(
          DateFormat('d MMMM y', 'ru_RU').format(_daysAgo(daysAgo)),
        ),
      );
      expect(
        tester.getTopLeft(date(2)).dy,
        lessThan(tester.getTopLeft(date(16)).dy),
      );

      await tester.tap(find.byKey(const ValueKey('value-completion-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сначала старые'));
      await tester.pumpAndSettle();

      expect(find.text('Сначала старые'), findsOneWidget);
      expect(
        tester.getTopLeft(date(16)).dy,
        lessThan(tester.getTopLeft(date(2)).dy),
      );
    });

    testWidgets('shows equal statistics cards and the average interval', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(
        _valuePage(_task(id: 1, title: 'Смена белья'), [
          _log(1, 12),
          _log(1, 5),
          _log(1, 1),
        ]),
      );
      await tester.pumpAndSettle();

      final totalCard = find.byKey(const ValueKey('value-total-stat-card'));
      final averageCard = find.byKey(const ValueKey('value-average-stat-card'));
      expect(totalCard, findsOneWidget);
      expect(averageCard, findsOneWidget);
      expect(tester.getSize(totalCard), tester.getSize(averageCard));
      expect(find.text('5,5 дня'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a dash when an average cannot be calculated', (
      tester,
    ) async {
      await tester.pumpWidget(
        _valuePage(_task(id: 1, title: 'Смена белья'), [_log(1, 3)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('tells when it was last done and lists the latest marks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _valuePage(_task(id: 1, title: 'Смена белья'), [
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
        _valuePage(_task(id: 1, title: 'Смена белья'), [_log(1, 0)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Снять за сегодня'), findsOneWidget);
      expect(find.text('Отметить сегодня'), findsNothing);
    });

    testWidgets('a task never marked has no list to show', (tester) async {
      await tester.pumpWidget(
        _valuePage(_task(id: 1, title: 'Смена белья'), []),
      );
      await tester.pumpAndSettle();

      expect(find.text('Нет отметок'), findsOneWidget);
      expect(find.text('Последние отметки'), findsNothing);
    });

    testWidgets('asks before removing only the selected mark', (tester) async {
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
        _valuePage(task!.copyWith(trackingMode: TrackingMode.value), [
          _log(task.id, 3),
        ], db: db),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Убрать отметку'));
      await tester.pumpAndSettle();

      expect(find.text('Удалить выполнение?'), findsOneWidget);
      expect(
        find.text(
          'Вы уверены, что хотите удалить это выполнение? '
          'Это действие нельзя отменить.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      var logs = (await tester.runAsync(() => db.select(db.taskLogs).get()))!;
      expect(logs.single.completed, isTrue);

      await tester.tap(find.byTooltip('Убрать отметку'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );

      logs = (await tester.runAsync(() => db.select(db.taskLogs).get()))!;
      expect(logs.single.completed, isFalse);
    });
  });

  group('the habit actions sheet', () {
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
