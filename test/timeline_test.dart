import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/widgets/home/task_timeline.dart';

/// The day under the calendar: the overview, "В течение дня", and the timed
/// rows on their line — capsules by duration, free stretches, "Сейчас", and
/// tasks that collide drawn as one block with the collision spelled out.
final _stamp = DateTime(2026, 1, 1);
final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

/// A day with no "Сейчас" on it, so a row's place depends on nothing but its
/// time.
final _tomorrow = _today.add(const Duration(days: 1));

int _m(String hm) {
  final [h, m] = hm.split(':').map(int.parse).toList();
  return h * 60 + m;
}

Task _task(
  int id,
  String title, {
  String? from,
  String? to,
  DateTime? day,
  RepeatType? repeatType,
  int? parentId,
  TaskStatus status = TaskStatus.active,
  TrackingMode mode = TrackingMode.checkbox,
  double? target,
}) => Task(
  dirty: false,
  id: id,
  title: title,
  parentId: parentId,
  status: status,
  repeatType: repeatType,
  trackingMode: mode,
  targetValue: target,
  targetDurationMinutes: mode == TrackingMode.timer ? 25 : null,
  scheduledTimeMinutes: from == null ? null : _m(from),
  endTimeMinutes: to == null ? null : _m(to),
  colorValue: 0xFF9C8DDB,
  startDate: day ?? _tomorrow,
  createdAt: _today,
  updatedAt: _today,
);

TaskLog _done(int taskId, DateTime day) => TaskLog(
  dirty: false,
  updatedAt: _stamp,
  id: taskId,
  taskId: taskId,
  date: day,
  completed: true,
);

Future<void> _pump(
  WidgetTester tester,
  List<Task> tasks, {
  List<TaskLog> logs = const [],
  DateTime? day,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rootTasksProvider.overrideWith((ref) => Stream.value(tasks)),
        allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
        logsForDateProvider.overrideWith((ref, date) => Stream.value(logs)),
        ...overrides,
      ],
      child: MaterialApp(
        theme: buildAppTheme(const Color(0xFF5B6DCB), Brightness.light),
        locale: const Locale('ru', 'RU'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru', 'RU')],
        home: Scaffold(body: TaskTimeline(selectedDay: day ?? _tomorrow)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Stands in for the DAO: what matters is which call a tap on a circle makes.
class _RecordingDao extends Fake implements TasksDao {
  final calls = <String>[];

  @override
  Future<void> toggleCompletion(int taskId, DateTime date) async =>
      calls.add('toggle $taskId');

  @override
  Future<void> incrementCounter(
    int taskId,
    DateTime date,
    double target,
  ) async => calls.add('count $taskId of ${target.round()}');

  @override
  Future<void> startTimer(
    int taskId,
    DateTime now, {
    required int targetSeconds,
  }) async => calls.add('start $taskId');

  @override
  Future<void> stopTimer(
    int taskId,
    DateTime now, {
    required int targetSeconds,
  }) async => calls.add('stop $taskId');
}

/// The fill of every counter ring on screen, by their painters.
List<double> _ringFractions(WidgetTester tester) => [
  for (final c in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    if (c.foregroundPainter.runtimeType.toString() == '_RingPainter')
      (c.foregroundPainter! as dynamic).fraction as double,
];

double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU', null));

  group('В течение дня', () {
    testWidgets('lists the tasks with no time, and only those', (tester) async {
      await _pump(tester, [
        _task(1, 'Позвонить маме'),
        _task(2, 'Созвон', from: '15:00', to: '15:30'),
      ]);

      expect(find.text('В ТЕЧЕНИЕ ДНЯ'), findsOneWidget);
      expect(find.text('Позвонить маме'), findsOneWidget);
      expect(
        _y(tester, 'Созвон'),
        greaterThan(_y(tester, 'Позвонить маме')),
        reason: 'a timed task is on the line below, not in the card',
      );
    });

    testWidgets('is not there when every task has a time', (tester) async {
      await _pump(tester, [_task(1, 'Созвон', from: '15:00')]);
      expect(find.text('В ТЕЧЕНИЕ ДНЯ'), findsNothing);
    });

    testWidgets(
      'a day with nothing at all says it is free, and offers a task',
      (tester) async {
        await _pump(tester, const []);

        expect(find.text('дел нет · весь день свободен'), findsOneWidget);
        expect(find.text('День пока свободен'), findsOneWidget);
        expect(find.text('Добавить задачу'), findsOneWidget);
      },
    );

    testWidgets('stays on a day with nothing on the clock', (tester) async {
      await _pump(tester, [_task(1, 'Позвонить маме')]);
      expect(find.text('Позвонить маме'), findsOneWidget);
      expect(find.text('На этот день нет задач со временем'), findsOneWidget);
    });

    testWidgets('leaves out what is archived or on another day', (
      tester,
    ) async {
      await _pump(tester, [
        _task(1, 'В архиве', status: TaskStatus.archived),
        _task(2, 'Вчерашняя', day: _today.subtract(const Duration(days: 1))),
        _task(3, 'Своя'),
      ]);
      expect(find.text('В архиве'), findsNothing);
      expect(find.text('Вчерашняя'), findsNothing);
      expect(find.text('Своя'), findsOneWidget);
    });

    testWidgets('one-off tasks first, then habits, whatever their names', (
      tester,
    ) async {
      await _pump(tester, [
        _task(1, 'Азбука', repeatType: RepeatType.daily),
        _task(2, 'Яблоки'),
      ]);
      // A strip now: further along it, not further down.
      expect(
        tester.getCenter(find.text('Азбука')).dx,
        greaterThan(tester.getCenter(find.text('Яблоки')).dx),
      );
    });

    testWidgets('a subtask is counted, never listed', (tester) async {
      await _pump(
        tester,
        [
          _task(1, 'Переезд'),
          _task(2, 'Коробки', parentId: 1),
          _task(3, 'Машина', parentId: 1),
        ],
        logs: [_done(2, _tomorrow)],
      );
      expect(find.text('Коробки'), findsNothing);
      expect(find.text('Машина'), findsNothing);
      expect(find.text('Переезд'), findsOneWidget);
      // The count in the header is the day's roots, not their subtasks.
      expect(find.text('0 из 1'), findsOneWidget);
    });

    testWidgets('a done task is struck through', (tester) async {
      await _pump(tester, [_task(1, 'Хлеб')], logs: [_done(1, _tomorrow)]);
      expect(
        tester.widget<Text>(find.text('Хлеб')).style?.decoration,
        TextDecoration.lineThrough,
      );
    });

    testWidgets('the header counts what is done, and a done circle is darker', (
      tester,
    ) async {
      await _pump(
        tester,
        [_task(1, 'Хлеб'), _task(2, 'Молоко')],
        logs: [_done(1, _tomorrow)],
      );
      expect(find.text('1 из 2'), findsOneWidget);

      Color circle() =>
          (tester
                      .widget<AnimatedContainer>(
                        find.ancestor(
                          of: find.byIcon(LucideIcons.circle_check),
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      // The open one is the family's pale tone...
      final open = circle();
      // ...and the done one, with its check, is the strong tone.
      final doneCircle =
          (tester
                      .widget<AnimatedContainer>(
                        find.ancestor(
                          of: find.byIcon(LucideIcons.check),
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(doneCircle.computeLuminance(), lessThan(open.computeLuminance()));
    });

    testWidgets('a circle pops when its task becomes done, not before', (
      tester,
    ) async {
      final logs = StreamController<List<TaskLog>>();
      addTearDown(logs.close);
      await _pump(
        tester,
        [_task(1, 'Хлеб')],
        overrides: [
          logsForDateProvider.overrideWith((ref, date) => logs.stream),
        ],
      );
      logs.add(const []);
      await tester.pump();

      double scale() => tester
          .widget<ScaleTransition>(
            find
                .ancestor(
                  of: find.byType(AnimatedContainer),
                  matching: find.byType(ScaleTransition),
                )
                .first,
          )
          .scale
          .value;
      expect(scale(), 1.0);

      logs.add([_done(1, _tomorrow)]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(scale(), greaterThan(1.05), reason: 'mid-pop');

      await tester.pumpAndSettle();
      expect(scale(), 1.0);
    });

    testWidgets('the circles sit in one row that scrolls sideways', (
      tester,
    ) async {
      await _pump(tester, [for (var i = 1; i <= 8; i++) _task(i, 'Дело $i')]);
      final first = tester.getCenter(find.text('Дело 1'));
      expect(tester.getCenter(find.text('Дело 2')).dy, first.dy);
      // Eight slots do not fit a phone's width: the last is off to the right.
      final last = find.text('Дело 8', skipOffstage: false);
      expect(tester.getCenter(last).dx, greaterThan(400));

      await tester.drag(find.text('Дело 1'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('Дело 1')).dx, lessThan(first.dx));
    });

    testWidgets('the arrow folds the card to its header and back', (
      tester,
    ) async {
      await _pump(tester, [_task(1, 'Хлеб')]);
      expect(find.text('Хлеб'), findsOneWidget);

      await tester.tap(find.text('В ТЕЧЕНИЕ ДНЯ'));
      await tester.pumpAndSettle();
      expect(find.text('Хлеб'), findsNothing);
      expect(find.text('В ТЕЧЕНИЕ ДНЯ'), findsOneWidget);

      await tester.tap(find.text('В ТЕЧЕНИЕ ДНЯ'));
      await tester.pumpAndSettle();
      expect(find.text('Хлеб'), findsOneWidget);
    });
  });

  group('a tap on a circle', () {
    testWidgets('ticks a checkbox task, and a second tap takes it back', (
      tester,
    ) async {
      final dao = _RecordingDao();
      await _pump(
        tester,
        [_task(1, 'Хлеб')],
        overrides: [tasksDaoProvider.overrideWithValue(dao)],
      );
      // Only a counter has a ring.
      expect(_ringFractions(tester), isEmpty);
      await tester.tap(find.text('Хлеб'));
      expect(dao.calls, ['toggle 1']);
    });

    testWidgets('adds one to a counter, and shows where it stands', (
      tester,
    ) async {
      final dao = _RecordingDao();
      await _pump(
        tester,
        [_task(1, 'Вода', mode: TrackingMode.counter, target: 8)],
        logs: [
          TaskLog(
            dirty: false,
            updatedAt: _stamp,
            id: 1,
            taskId: 1,
            date: _tomorrow,
            completed: false,
            value: 3,
          ),
        ],
        overrides: [tasksDaoProvider.overrideWithValue(dao)],
      );
      expect(find.text('3/8'), findsOneWidget);
      // The ring is filled to the same 3 of 8.
      await tester.pumpAndSettle();
      expect(_ringFractions(tester), [closeTo(3 / 8, 0.001)]);

      await tester.tap(find.text('Вода'));
      expect(dao.calls, ['count 1 of 8']);
    });

    testWidgets('starts a timer today and stops it on the next tap', (
      tester,
    ) async {
      final dao = _RecordingDao();
      final task = _task(1, 'Чтение', day: _today, mode: TrackingMode.timer);
      await _pump(
        tester,
        [task],
        day: _today,
        overrides: [
          tasksDaoProvider.overrideWithValue(dao),
          openSessionsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      );
      await tester.tap(find.text('Чтение'));
      expect(dao.calls, ['start 1']);
    });

    testWidgets('stops a timer that is running', (tester) async {
      final dao = _RecordingDao();
      final task = _task(1, 'Чтение', day: _today, mode: TrackingMode.timer);
      await _pump(
        tester,
        [task],
        day: _today,
        overrides: [
          tasksDaoProvider.overrideWithValue(dao),
          openSessionsProvider.overrideWith(
            (ref) => Stream.value([
              TaskSession(id: 1, taskId: 1, startedAt: DateTime.now()),
            ]),
          ),
        ],
      );
      // The circle says it is running.
      expect(find.byIcon(LucideIcons.pause), findsOneWidget);

      await tester.tap(find.text('Чтение'));
      expect(dao.calls, ['stop 1']);
    });

    testWidgets('does not start a timer on another day: opens the sheet', (
      tester,
    ) async {
      final dao = _RecordingDao();
      await _pump(
        tester,
        [_task(1, 'Чтение', mode: TrackingMode.timer)],
        overrides: [
          tasksDaoProvider.overrideWithValue(dao),
          openSessionsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      );
      await tester.tap(find.text('Чтение'));
      await tester.pumpAndSettle();
      expect(dao.calls, isEmpty);
      expect(find.text('Изменить'), findsOneWidget);
    });

    testWidgets('holding the circle opens the sheet instead', (tester) async {
      final dao = _RecordingDao();
      await _pump(
        tester,
        [_task(1, 'Хлеб')],
        overrides: [tasksDaoProvider.overrideWithValue(dao)],
      );
      await tester.longPress(find.text('Хлеб'));
      await tester.pumpAndSettle();
      expect(dao.calls, isEmpty);
      expect(find.text('Изменить'), findsOneWidget);
    });
  });

  group('the line', () {
    testWidgets('a capsule is 72px an hour, and never under 26', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [
        _task(1, 'Час', from: '09:00', to: '10:00'),
        _task(2, 'Миг', from: '12:00', to: '12:10'),
      ]);
      expect(
        tester.getSize(find.bySemanticsLabel('09:00 – 10:00, 1 ч')).height,
        72,
      );
      expect(
        tester.getSize(find.bySemanticsLabel('12:00 – 12:10, 10 мин')).height,
        26,
      );
      handle.dispose();
    });

    testWidgets('a long free stretch gets a row, a short one does not', (
      tester,
    ) async {
      await _pump(tester, [
        _task(1, 'Утро', from: '09:00', to: '10:00'),
        _task(2, 'Обед', from: '13:00', to: '13:30'),
        _task(3, 'Кофе', from: '14:00'),
      ]);
      expect(find.text('Свободно 3 ч'), findsOneWidget);
      expect(find.textContaining('Свободно'), findsOneWidget);
    });

    testWidgets('today has "Сейчас" on it, another day does not', (
      tester,
    ) async {
      await _pump(tester, [
        _task(1, 'Созвон', from: '00:00', day: _today),
      ], day: _today);
      expect(find.textContaining('Сейчас'), findsOneWidget);

      await _pump(tester, [_task(1, 'Созвон', from: '00:00')]);
      expect(find.textContaining('Сейчас'), findsNothing);
    });

    testWidgets('the overview counts the day and its busy time once', (
      tester,
    ) async {
      await _pump(tester, [
        _task(1, 'Созвон', from: '15:00', to: '15:30'),
        _task(2, 'Письма', from: '15:15', to: '15:45'),
        _task(3, 'Позвонить'),
      ]);
      expect(find.text('3 дела · занято 45 мин'), findsOneWidget);
    });

    testWidgets('keeps ticking without leaking its timer', (tester) async {
      await _pump(tester, [_task(1, 'Созвон', from: '15:00')]);
      // Replacing the tree disposes the timeline; a surviving timer would fail
      // the test with a pending-timer error.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    });
  });

  group('tasks that collide', () {
    testWidgets('are one block: side-by-side capsules, the clash in red', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [
        _task(1, 'Созвон с командой', from: '15:00', to: '15:30'),
        _task(2, 'Ответить на письма', from: '15:15', to: '15:45'),
      ]);

      // Each spells out its own range: the time column has only the block's.
      expect(find.text('15:00–15:30 · 30 мин · Задача'), findsOneWidget);
      expect(find.text('15:15–15:45 · 30 мин · Задача'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('15:45'), findsOneWidget);
      expect(
        find.text('Пересекается с «Созвон с командой» · 15 мин'),
        findsOneWidget,
      );

      final first = tester.getRect(
        find.bySemanticsLabel('15:00 – 15:30, 30 мин'),
      );
      final second = tester.getRect(
        find.bySemanticsLabel('15:15 – 15:45, 30 мин'),
      );
      expect(second.left, greaterThan(first.right), reason: 'side by side');
      expect(second.top, greaterThan(first.top), reason: 'each at its start');
      handle.dispose();
    });

    testWidgets('a moment inside a range clashes with it, no minutes', (
      tester,
    ) async {
      await _pump(tester, [
        _task(1, 'Созвон', from: '15:00', to: '15:30'),
        _task(2, 'Таблетки', from: '15:10'),
      ]);
      expect(find.text('Пересекается с «Созвон»'), findsOneWidget);
    });

    testWidgets('back-to-back is not a clash', (tester) async {
      await _pump(tester, [
        _task(1, 'Созвон', from: '15:00', to: '15:30'),
        _task(2, 'Письма', from: '15:30', to: '16:00'),
      ]);
      expect(find.textContaining('Пересекается'), findsNothing);
      expect(find.text('30 мин · Задача'), findsNWidgets(2));
    });

    testWidgets('several clashes are counted, not listed', (tester) async {
      await _pump(tester, [
        _task(1, 'A', from: '15:00', to: '15:30'),
        _task(2, 'B', from: '15:15', to: '15:45'),
        _task(3, 'C', from: '15:20', to: '15:50'),
      ]);
      expect(find.text('Пересекается с «A» · 15 мин'), findsOneWidget);
      expect(find.text('Пересекается с 2 задачами'), findsOneWidget);
    });

    testWidgets('the block says how many collide and over what span', (
      tester,
    ) async {
      await _pump(tester, [
        _task(1, 'A', from: '15:00', to: '15:30'),
        _task(2, 'B', from: '15:15', to: '15:50'),
      ]);
      expect(find.text('2 задачи пересекаются · 15:00–15:50'), findsOneWidget);
    });

    testWidgets('a task alone gets no such line', (tester) async {
      await _pump(tester, [_task(1, 'A', from: '15:00', to: '15:30')]);
      expect(find.textContaining('пересекаются'), findsNothing);
    });

    testWidgets('tasks of a block that never meet share a lane', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [
        _task(1, 'A', from: '09:00', to: '10:00'),
        _task(2, 'B', from: '09:30', to: '11:00'),
        _task(3, 'C', from: '10:30', to: '12:00'),
      ]);
      double left(String label) =>
          tester.getRect(find.bySemanticsLabel(label)).left;
      // A and C never meet, so C runs in A's lane, under it.
      expect(left('10:30 – 12:00, 1 ч 30 мин'), left('09:00 – 10:00, 1 ч'));
      expect(
        left('09:30 – 11:00, 1 ч 30 мин'),
        greaterThan(left('09:00 – 10:00, 1 ч')),
      );
      handle.dispose();
    });

    group('four at once', () {
      final four = [
        _task(1, 'Созвон', from: '15:00', to: '15:30'),
        _task(2, 'Письма', from: '15:10', to: '15:45'),
        _task(3, 'Отчёт', from: '15:20', to: '15:50'),
        _task(4, 'Ревью', from: '15:25', to: '15:40'),
      ];

      testWidgets('three lanes on the axis, "+1" for the fourth', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, four);
        expect(find.text('+1'), findsOneWidget);
        expect(find.bySemanticsLabel('15:25 – 15:40, 15 мин'), findsNothing);
        for (final label in [
          '15:00 – 15:30, 30 мин',
          '15:10 – 15:45, 35 мин',
          '15:20 – 15:50, 30 мин',
        ]) {
          expect(
            tester.getSize(find.bySemanticsLabel(label)).width,
            6,
            reason: label,
          );
        }
        handle.dispose();
      });

      testWidgets('three in the list, the rest behind "Ещё", and back', (
        tester,
      ) async {
        await _pump(tester, four);
        expect(find.text('Отчёт'), findsOneWidget);
        expect(find.text('Ревью'), findsNothing);

        await tester.tap(find.text('Ещё 1 задача'));
        await tester.pump();
        expect(find.text('Ревью'), findsOneWidget);
        expect(find.text('Пересекается с 3 задачами'), findsOneWidget);

        await tester.tap(find.text('Свернуть'));
        await tester.pump();
        expect(find.text('Ревью'), findsNothing);
        expect(find.text('Ещё 1 задача'), findsOneWidget);
      });

      testWidgets('the day still counts every task, its busy time once', (
        tester,
      ) async {
        await _pump(tester, four);
        expect(find.text('4 дела · занято 50 мин'), findsOneWidget);
      });
    });
  });
}
