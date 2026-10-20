import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/overdue.dart';

/// What counts as "просрочено", and what the nav bar's badge is therefore
/// counting.
///
/// The rule used to be a `date.isBefore(today)` inside `TasksList.build` and
/// nowhere else. It is out here now because a second reader appeared — the badge
/// — and the number on the icon has to be the length of the section in the list.
/// These tests pin the four things that are deliberately *not* late.
final _fixtureStamp = DateTime(2026, 1, 1);
final _today = DateTime(2026, 9, 1);
final _yesterday = DateTime(2026, 8, 31);
final _tomorrow = DateTime(2026, 9, 2);

Task _task({
  int id = 1,
  int? parentId,
  TaskStatus status = TaskStatus.active,
  RepeatType? repeatType,
  DateTime? startDate,
}) => Task(
  dirty: false,
  id: id,
  title: 'Задача $id',
  parentId: parentId,
  status: status,
  repeatType: repeatType,
  trackingMode: TrackingMode.checkbox,
  startDate: startDate,
  createdAt: _fixtureStamp,
  updatedAt: _fixtureStamp,
);

TaskLog _log({
  required int taskId,
  required DateTime date,
  bool completed = true,
}) => TaskLog(
  dirty: false,
  id: taskId * 100,
  taskId: taskId,
  date: date,
  completed: completed,
  updatedAt: _fixtureStamp,
);

bool _overdue(Task task, {bool completed = false}) =>
    isTaskOverdue(task, completed: completed, today: _today);

void main() {
  group('isTaskOverdue', () {
    test('a dated task left unticked yesterday is overdue', () {
      expect(_overdue(_task(startDate: _yesterday)), isTrue);
    });

    test("a time of day on the date does not change the answer", () {
      // The stored value is a midnight, but nothing guarantees it: the rule
      // strips the time on both sides rather than trusting the column.
      final late = DateTime(2026, 8, 31, 23, 59);
      expect(_overdue(_task(startDate: late)), isTrue);
      final earlyToday = DateTime(2026, 9, 1, 0, 1);
      expect(_overdue(_task(startDate: earlyToday)), isFalse);
    });

    test("today's is not overdue, and neither is tomorrow's", () {
      expect(_overdue(_task(startDate: _today)), isFalse);
      expect(_overdue(_task(startDate: _tomorrow)), isFalse);
    });

    test('a ticked task is not overdue however old it is', () {
      expect(_overdue(_task(startDate: _yesterday), completed: true), isFalse);
    });

    test('a habit is never overdue', () {
      // A day a habit was not marked is a `missed` square in its own grid. Were
      // it counted here, a daily habit would report every day it ever missed.
      expect(
        _overdue(_task(startDate: _yesterday, repeatType: RepeatType.daily)),
        isFalse,
      );
    });

    test('a subtask is never overdue', () {
      // Its parent's tile reports it; counting both counts the same work twice.
      expect(_overdue(_task(startDate: _yesterday, parentId: 7)), isFalse);
    });

    test('a task with no date is not overdue', () {
      // That is the backlog — "Без даты". A day nobody set cannot be missed.
      expect(_overdue(_task()), isFalse);
    });

    test('only an active task is overdue', () {
      for (final status in [TaskStatus.paused, TaskStatus.archived]) {
        expect(
          _overdue(_task(startDate: _yesterday, status: status)),
          isFalse,
          reason: 'status $status',
        );
      }
    });
  });

  group('overdueTasksProvider', () {
    ProviderContainer container({
      required Stream<List<Task>> tasks,
      required Stream<List<TaskLog>> logs,
    }) {
      final c = ProviderContainer(
        overrides: [
          allTasksProvider.overrideWith((ref) => tasks),
          allLogsProvider.overrideWith((ref) => logs),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    /// Yesterday relative to the real clock — the provider reads `DateTime.now()`
    /// itself, so a fixture has to be pinned to that and not to [_today].
    DateTime realYesterday() {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day - 1);
    }

    test('counts the tasks that are late and nothing else', () async {
      final past = realYesterday();
      final c = container(
        tasks: Stream.value([
          _task(id: 1, startDate: past),
          _task(id: 2, startDate: past, repeatType: RepeatType.weekly),
          _task(id: 3),
          _task(id: 4, startDate: DateTime.now()),
        ]),
        logs: Stream.value(const []),
      );
      await c.read(allTasksProvider.future);
      await c.read(allLogsProvider.future);

      expect(c.read(overdueTasksProvider).map((t) => t.id), [1]);
    });

    test('a task ticked on its own day drops out', () async {
      final past = realYesterday();
      final c = container(
        tasks: Stream.value([_task(id: 1, startDate: past)]),
        logs: Stream.value([_log(taskId: 1, date: past)]),
      );
      await c.read(allTasksProvider.future);
      await c.read(allLogsProvider.future);

      expect(c.read(overdueTasksProvider), isEmpty);
    });

    test('a log that is not a tick leaves the task late', () async {
      final past = realYesterday();
      final c = container(
        tasks: Stream.value([_task(id: 1, startDate: past)]),
        logs: Stream.value([_log(taskId: 1, date: past, completed: false)]),
      );
      await c.read(allTasksProvider.future);
      await c.read(allLogsProvider.future);

      expect(c.read(overdueTasksProvider).map((t) => t.id), [1]);
    });

    test('empty until the logs have arrived, not "nothing is ticked"', () async {
      // Otherwise the badge shows a number for the frame between the two streams
      // and takes it back — on every launch.
      final past = realYesterday();
      final c = container(
        tasks: Stream.value([_task(id: 1, startDate: past)]),
        logs: const Stream.empty(),
      );
      await c.read(allTasksProvider.future);

      expect(c.read(overdueTasksProvider), isEmpty);
    });
  });
}
