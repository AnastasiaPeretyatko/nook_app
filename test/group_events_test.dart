import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/group_events.dart';

/// Who is told what when another member does something in a group.
void main() {
  const me = 'me';
  const anya = 'anya';
  const misha = 'misha';
  final now = DateTime(2026, 10, 21, 12);
  final day = DateTime(2026, 10, 21);

  const members = [
    GroupMember(groupUid: 'g', userUid: me, displayName: 'Я'),
    GroupMember(groupUid: 'g', userUid: anya, displayName: 'Аня'),
    GroupMember(groupUid: 'g', userUid: misha, displayName: 'Миша'),
  ];
  const groups = [TaskGroup(uid: 'g', name: 'Семья', ownerUid: anya)];

  Task task(
    int id, {
    required String author,
    String? assignee,
    Duration age = const Duration(minutes: 1),
  }) => Task(
    id: id,
    uid: 't$id',
    dirty: false,
    title: 'Задача $id',
    status: TaskStatus.active,
    trackingMode: TrackingMode.checkbox,
    createdAt: now.subtract(age),
    updatedAt: now,
    groupUid: 'g',
    assigneeUid: assignee,
    authorUid: author,
  );

  GroupMark mark(int taskId, String by) =>
      GroupMark(taskId: taskId, userUid: by, date: day, completed: true);

  ({List<GroupEvent> events, GroupSeen seen}) run(
    List<Task> tasks, {
    List<GroupMark> marks = const [],
    GroupSeen seen = const GroupSeen(),
  }) => groupEventsSince(
    seen,
    me: me,
    now: now,
    tasks: tasks,
    marks: marks,
    members: members,
    groups: groups,
  );

  group('a new task', () {
    test('handed to me by someone else is news, with their name', () {
      final r = run([task(1, author: anya, assignee: me)]);

      expect(r.events, hasLength(1));
      expect(r.events.single.headline, 'Новая задача от Аня');
      expect(r.events.single.subline, 'Задача 1 · Семья');
    });

    test('for everyone is news too', () {
      final r = run([task(1, author: anya)]);

      expect(r.events.single.headline, 'Новая задача для всех от Аня');
    });

    test('is never news to its own author', () {
      expect(run([task(1, author: me)]).events, isEmpty);
      expect(run([task(1, author: me, assignee: anya)]).events, isEmpty);
    });

    test('handed to somebody else is not mine to hear about', () {
      expect(run([task(1, author: anya, assignee: misha)]).events, isEmpty);
    });

    test('that is old is the backlog coming down, not news', () {
      final old = task(1, author: anya, age: const Duration(days: 3));

      expect(run([old]).events, isEmpty);
    });

    test('is told once', () {
      final tasks = [task(1, author: anya, assignee: me)];
      final first = run(tasks);

      expect(run(tasks, seen: first.seen).events, isEmpty);
    });

    test('an old task handed to me later is news', () {
      final before = task(
        1,
        author: anya,
        assignee: misha,
        age: const Duration(days: 3),
      );
      final seen = run([before]).seen;
      final after = task(
        1,
        author: anya,
        assignee: me,
        age: const Duration(days: 3),
      );

      expect(run([after], seen: seen).events, hasLength(1));
    });
  });

  group('a mark by someone else', () {
    final shared = task(1, author: anya, age: const Duration(days: 3));
    final seenShared = run([shared]).seen;

    test('on a task for everyone is news', () {
      final r = run([shared], marks: [mark(1, misha)], seen: seenShared);

      expect(r.events.single.headline, 'Выполнено: Миша');
      expect(r.events.single.subline, 'Задача 1 · Семья');
    });

    test('is not news to the one who ticked it', () {
      final r = run([shared], marks: [mark(1, me)], seen: seenShared);

      expect(r.events, isEmpty);
    });

    test('on a task I handed out is news', () {
      final mine = task(
        2,
        author: me,
        assignee: misha,
        age: const Duration(days: 3),
      );
      final seen = run([mine]).seen;

      final r = run([mine], marks: [mark(2, misha)], seen: seen);

      expect(r.events.single.headline, 'Выполнено: Миша');
    });

    test('on a task handed from one member to another is not mine to hear', () {
      final theirs = task(
        3,
        author: anya,
        assignee: misha,
        age: const Duration(days: 3),
      );
      final seen = run([theirs]).seen;

      expect(
        run([theirs], marks: [mark(3, misha)], seen: seen).events,
        isEmpty,
      );
    });

    test('is told once', () {
      final first = run([shared], marks: [mark(1, misha)], seen: seenShared);

      final again = run([shared], marks: [mark(1, misha)], seen: first.seen);
      expect(again.events, isEmpty);
    });

    test('on a task that has only just come down is not announced', () {
      final fresh = task(4, author: anya);

      final r = run([fresh], marks: [mark(4, misha)]);

      expect(r.events.map((e) => e.completed), [false]);
    });
  });
}
