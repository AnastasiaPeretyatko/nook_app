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
import 'package:todo_app/utils/task_audience.dart';
import 'package:todo_app/widgets/habits/task_actions_sheet.dart';
import 'package:todo_app/widgets/home/task_timeline.dart';
import 'package:todo_app/widgets/member_avatar.dart';

/// Group tasks on the screens: whose a task is, what the timeline draws for one
/// handed to someone else, what the sheet lets you do, and the form's pickers.
void main() {
  const me = 'a';
  const husband = 'b';
  const third = 'c';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  Task task({
    int id = 1,
    String title = 'Купить хлеб',
    String? group = 'g1',
    String? assignee,
    String? author = me,
    DateTime? startDate,
    int? time,
  }) => Task(
    id: id,
    dirty: false,
    title: title,
    status: TaskStatus.active,
    trackingMode: TrackingMode.checkbox,
    scheduledTimeMinutes: time,
    startDate: startDate ?? today,
    createdAt: today,
    updatedAt: today,
    groupUid: group,
    assigneeUid: assignee,
    authorUid: group == null ? null : author,
  );

  const family = TaskGroup(uid: 'g1', name: 'Семья', ownerUid: me);
  const members = [
    GroupMember(groupUid: 'g1', userUid: me, displayName: 'Аня'),
    GroupMember(groupUid: 'g1', userUid: husband, displayName: 'Миша'),
    GroupMember(groupUid: 'g1', userUid: third, displayName: 'Оля'),
  ];

  Widget app(Widget home, {required List<Override> overrides}) => ProviderScope(
    overrides: [myUidProvider.overrideWithValue(me), ...overrides],
    child: MaterialApp(
      locale: const Locale('ru', 'RU'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU')],
      home: home,
    ),
  );

  setUpAll(() => initializeDateFormatting('ru_RU', null));

  group('whose a task is', () {
    test('personal, for everyone and handed to me are mine', () {
      expect(taskAudience(task(group: null), me), TaskAudience.mine);
      expect(taskAudience(task(), me), TaskAudience.mine);
      expect(
        taskAudience(task(assignee: me, author: husband), me),
        TaskAudience.mine,
      );
    });

    test('handed by me to someone else is delegated', () {
      expect(taskAudience(task(assignee: husband), me), TaskAudience.delegated);
    });

    test("someone else's to someone else is hidden", () {
      expect(
        taskAudience(task(assignee: third, author: husband), me),
        TaskAudience.hidden,
      );
      // Signed out nobody is "me": only what is plainly for everyone shows.
      expect(taskAudience(task(assignee: husband), null), TaskAudience.hidden);
    });

    test('the author and the owner edit, nobody else', () {
      final theirs = task(author: husband);
      expect(canEditTaskAs(theirs, husband), isTrue);
      expect(canEditTaskAs(theirs, me, groupOwnerUid: me), isTrue);
      expect(canEditTaskAs(theirs, third, groupOwnerUid: me), isFalse);
      expect(canEditTaskAs(task(group: null), null), isTrue);
    });

    test('done-by joins my log with the others’ marks of that day', () {
      final t = task();
      final marks = [
        GroupMark(taskId: 1, userUid: husband, date: today, completed: true),
        GroupMark(taskId: 1, userUid: third, date: today, completed: false),
        GroupMark(
          taskId: 1,
          userUid: third,
          date: today.subtract(const Duration(days: 1)),
          completed: true,
        ),
      ];
      expect(groupTaskDoneBy(t, today, me: me, doneByMe: true, marks: marks), {
        me,
        husband,
      });
    });
  });

  group('the timeline', () {
    Widget timeline(List<Task> tasks, {List<GroupMark> marks = const []}) =>
        app(
          Scaffold(body: TaskTimeline(selectedDay: today)),
          overrides: [
            rootTasksProvider.overrideWith((ref) => Stream.value(tasks)),
            allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
            logsForDateProvider.overrideWith(
              (ref, date) => Stream.value(const <TaskLog>[]),
            ),
            groupMembersProvider.overrideWith((ref) => Stream.value(members)),
            groupMarksProvider.overrideWith((ref) => Stream.value(marks)),
          ],
        );

    testWidgets('a task I handed over shows whom and that it waits', (
      tester,
    ) async {
      await tester.pumpWidget(
        timeline([task(assignee: husband, time: 23 * 60 + 58)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Купить хлеб'), findsOneWidget);
      expect(find.text('Для: Миша · ждёт'), findsOneWidget);
      // Their letter where my checkbox would be.
      expect(find.byType(MemberAvatar), findsOneWidget);
    });

    testWidgets('…and that it is done once they tick it', (tester) async {
      await tester.pumpWidget(
        timeline(
          [task(assignee: husband, time: 23 * 60 + 58)],
          marks: [
            GroupMark(
              taskId: 1,
              userUid: husband,
              date: today,
              completed: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Для: Миша · выполнено'), findsOneWidget);
    });

    testWidgets("another member's own task is not on my day", (tester) async {
      await tester.pumpWidget(
        timeline([
          task(title: 'Чужая', assignee: third, author: husband, time: 600),
          task(id: 2, title: 'Общая', time: 700),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Чужая'), findsNothing);
      expect(find.text('Общая'), findsOneWidget);
      expect(find.text('Для всех · 0 из 3'), findsOneWidget);
    });
  });

  group('the sheet', () {
    Widget sheet(Task t, {required bool owner}) => app(
      Scaffold(body: TaskActionsSheet(task: t, completed: false)),
      overrides: [
        subtasksProvider.overrideWith(
          (ref, id) => Stream.value(const <Task>[]),
        ),
        logsForDateProvider.overrideWith(
          (ref, date) => Stream.value(const <TaskLog>[]),
        ),
        groupsProvider.overrideWith(
          (ref) => Stream.value([
            owner
                ? family
                : const TaskGroup(uid: 'g1', name: 'Семья', ownerUid: husband),
          ]),
        ),
        groupMembersProvider.overrideWith((ref) => Stream.value(members)),
        groupMarksProvider.overrideWith(
          (ref) => Stream.value(const <GroupMark>[]),
        ),
      ],
    );

    testWidgets('a task I handed over: edit yes, tick no', (tester) async {
      await tester.pumpWidget(sheet(task(assignee: husband), owner: true));
      await tester.pumpAndSettle();
      expect(find.text('Изменить'), findsOneWidget);
      expect(find.text('Выполнить'), findsNothing);
      expect(find.text('Семья · для: Миша · ждёт'), findsOneWidget);
    });

    testWidgets("someone else's task: neither edit nor delete", (tester) async {
      await tester.pumpWidget(sheet(task(author: husband), owner: false));
      await tester.pumpAndSettle();
      expect(find.text('Изменить'), findsNothing);
      expect(find.text('Удалить'), findsNothing);
      // For everyone, so mine to tick all the same.
      expect(find.text('Выполнить'), findsOneWidget);
    });
  });

  test('a task I handed over is not on my overdue badge', () async {
    final yesterday = today.subtract(const Duration(days: 1));
    final container = ProviderContainer(
      overrides: [
        myUidProvider.overrideWithValue(me),
        allTasksProvider.overrideWith(
          (ref) => Stream.value([
            task(assignee: husband, startDate: yesterday),
            task(id: 2, group: null, startDate: yesterday),
          ]),
        ),
        allLogsProvider.overrideWith((ref) => Stream.value(const <TaskLog>[])),
      ],
    );
    addTearDown(container.dispose);
    await container.read(allTasksProvider.future);
    await container.read(allLogsProvider.future);
    expect([for (final t in container.read(overdueTasksProvider)) t.id], [2]);
  });

  group('the form', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(() async => db.close());
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first;
      view.physicalSize = const Size(1000, 2600);
      view.devicePixelRatio = 1.0;
      addTearDown(view.resetPhysicalSize);
      addTearDown(view.resetDevicePixelRatio);
    });

    testWidgets('picking a group drops repeat, subtasks and "Значение", and '
        'saves the group with me as author', (tester) async {
      await tester.runAsync(
        () => db.tasksDao.replaceGroups(
          [TaskGroupsCompanion.insert(uid: 'g1', name: 'Семья', ownerUid: me)],
          [
            for (final m in members)
              GroupMembersCompanion.insert(
                groupUid: m.groupUid,
                userUid: m.userUid,
                displayName: Value(m.displayName),
              ),
          ],
        ),
      );
      await tester.pumpWidget(
        app(
          const CreateTaskPage(),
          overrides: [databaseProvider.overrideWithValue(db)],
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      // The user is in a group, so the card is there — as a caption and the
      // group chosen, with nobody to pick while the task is personal.
      expect(find.text('КОМУ'), findsOneWidget);
      expect(find.text('Миша'), findsNothing);
      expect(find.text('ПОВТОРЯТЬ'), findsOneWidget);
      expect(find.text('Значение'), findsOneWidget);

      await tester.tap(find.text('Личная задача'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Семья').last);
      await tester.pumpAndSettle();

      expect(find.text('ПОВТОРЯТЬ'), findsNothing);
      expect(find.text('Значение'), findsNothing);
      // Everyone is the default; the members are tiles of their own.
      expect(find.text('Всем'), findsOneWidget);
      expect(find.text('Мне'), findsOneWidget);

      await tester.tap(find.text('Миша'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Купить хлеб');
      await tester.tap(find.byTooltip('Сохранить'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );

      final saved = (await tester.runAsync(db.tasksDao.getRootTasks))!.single;
      expect(saved.groupUid, 'g1');
      expect(saved.assigneeUid, husband);
      expect(saved.authorUid, me);
      expect(saved.repeatType, isNull);
    });
  });
}
