import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/widgets/habits/tasks_list.dart';

/// Any moment at all: these tests never read a log's edit time. It exists
/// because the sync needs one and the column is therefore not nullable.
final _fixtureStamp = DateTime(2026, 1, 1);

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

Task _task({
  required int id,
  required String title,
  int? parentId,
  int? scheduledTimeMinutes,
  TaskStatus status = TaskStatus.active,
  RepeatType? repeatType,
  DateTime? startDate,
}) => Task(
  dirty: false,
  id: id,
  title: title,
  parentId: parentId,
  status: status,
  repeatType: repeatType,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: scheduledTimeMinutes,
  colorValue: 0xFFFFC1CC,
  startDate: startDate ?? _today,
  createdAt: _today,
  updatedAt: _today,
);

Widget _list(List<Task> tasks, {List<TaskLog> logs = const []}) =>
    ProviderScope(
      overrides: [
        allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
        allLogsProvider.overrideWith((ref) => Stream.value(logs)),
      ],
      child: MaterialApp(
        locale: const Locale('ru', 'RU'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru', 'RU')],
        home: const Scaffold(body: TasksList()),
      ),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
  });

  group('subtask counter', () {
    testWidgets('a task with subtasks reports how many are done', (
      tester,
    ) async {
      await tester.pumpWidget(
        _list(
          [
            _task(id: 1, title: 'Переезд'),
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

    testWidgets('none done reads as zero, not as a missing counter', (
      tester,
    ) async {
      await tester.pumpWidget(
        _list([
          _task(id: 1, title: 'Переезд'),
          _task(id: 2, title: 'Коробки', parentId: 1),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('0/1'), findsOneWidget);
    });

    testWidgets('every subtask done reads as the full count', (tester) async {
      await tester.pumpWidget(
        _list(
          [
            _task(id: 1, title: 'Переезд'),
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
            TaskLog(
              dirty: false,
              updatedAt: _fixtureStamp,
              id: 2,
              taskId: 3,
              date: _today,
              completed: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('a task without subtasks shows no counter', (tester) async {
      await tester.pumpWidget(_list([_task(id: 1, title: 'Одиночка')]));
      await tester.pumpAndSettle();

      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets('an incomplete log is not counted as done', (tester) async {
      await tester.pumpWidget(
        _list(
          [
            _task(id: 1, title: 'Переезд'),
            _task(id: 2, title: 'Коробки', parentId: 1),
          ],
          logs: [
            TaskLog(
              dirty: false,
              updatedAt: _fixtureStamp,
              id: 1,
              taskId: 2,
              date: _today,
              completed: false,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0/1'), findsOneWidget);
    });

    testWidgets('a tick on another day does not count', (tester) async {
      final yesterday = _today.subtract(const Duration(days: 1));
      await tester.pumpWidget(
        _list(
          [
            _task(id: 1, title: 'Переезд'),
            _task(id: 2, title: 'Коробки', parentId: 1),
          ],
          logs: [
            TaskLog(
              dirty: false,
              updatedAt: _fixtureStamp,
              id: 1,
              taskId: 2,
              date: yesterday,
              completed: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0/1'), findsOneWidget);
    });

    testWidgets('the count follows the parent\'s date, not today', (
      tester,
    ) async {
      final tomorrow = _today.add(const Duration(days: 1));
      await tester.pumpWidget(
        _list(
          [
            _task(id: 1, title: 'Переезд', startDate: tomorrow),
            _task(id: 2, title: 'Коробки', parentId: 1, startDate: tomorrow),
          ],
          logs: [
            TaskLog(
              dirty: false,
              updatedAt: _fixtureStamp,
              id: 1,
              taskId: 2,
              date: tomorrow,
              completed: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1/1'), findsOneWidget);
    });
  });

  group('subtasks are not tasks of their own', () {
    testWidgets('they never appear as list rows', (tester) async {
      await tester.pumpWidget(
        _list([
          _task(id: 1, title: 'Переезд'),
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

    testWidgets('they are not counted in the section header', (tester) async {
      await tester.pumpWidget(
        _list([
          _task(id: 1, title: 'Переезд'),
          _task(id: 2, title: 'Коробки', parentId: 1),
          _task(id: 3, title: 'Машина', parentId: 1),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Сегодня'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('a list holding only subtasks still shows the empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _list([_task(id: 2, title: 'Сирота', parentId: 99)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Нет задач'), findsOneWidget);
    });
  });

  testWidgets('a repeating parent stays on the habits tab', (tester) async {
    await tester.pumpWidget(
      _list([
        _task(id: 1, title: 'Зарядка', repeatType: RepeatType.daily),
        _task(id: 2, title: 'Разминка', parentId: 1),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Зарядка'), findsNothing);
    expect(find.text('Нет задач'), findsOneWidget);
  });
}
