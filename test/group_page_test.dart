import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/groups/groups_repository.dart';
import 'package:todo_app/pages/groups_page.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/sync_controller.dart';
import 'package:todo_app/sync/sync_service.dart';

/// Only the two calls the invite sheet makes; anything else is a bug in the test.
class _FakeRepo implements GroupsRepository {
  String code = '123456';

  @override
  Future<String?> inviteCode(String groupUid) async => code;

  @override
  Future<String> regenerateInvite(String groupUid) async => code = '987650';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts the manual syncs; the real controller would reach for the server.
class _FakeSync extends SyncController {
  _FakeSync(super.ref);

  int runs = 0;

  @override
  Future<SyncOutcome> syncNow() async {
    runs++;
    return SyncOutcome.done;
  }
}

/// The group screen (`Group.dc.html`): members, the filter, the list, the invite.
void main() {
  const me = 'a';
  const husband = 'b';
  const third = 'c';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  late AppDatabase db;
  late SharedPreferences prefs;

  Task task(
    int id,
    String title, {
    String? assignee,
    DateTime? date,
    int? time,
  }) => Task(
    id: id,
    dirty: false,
    title: title,
    status: TaskStatus.active,
    trackingMode: TrackingMode.checkbox,
    scheduledTimeMinutes: time,
    startDate: date ?? today,
    createdAt: today,
    updatedAt: today,
    groupUid: 'g1',
    assigneeUid: assignee,
    authorUid: me,
  );

  final tasks = [
    task(1, 'Купить продукты', time: 19 * 60),
    task(2, 'Оплатить коммуналку', assignee: me),
    task(3, 'Забрать посылку', assignee: husband),
    task(4, 'Вынести мусор', assignee: third),
  ];

  Future<void> open(
    WidgetTester tester, {
    String owner = me,
    _FakeRepo? repo,
    List<Override> extra = const [],
  }) async {
    // The rows the ring writes to: ids line up with [tasks].
    await tester.runAsync(() async {
      for (final t in tasks) {
        await db.tasksDao.insertTask(
          TasksCompanion.insert(
            title: t.title,
            groupUid: Value(t.groupUid),
            assigneeUid: Value(t.assigneeUid),
            authorUid: Value(t.authorUid),
            startDate: Value(t.startDate),
          ),
        );
      }
    });
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...extra,
          databaseProvider.overrideWithValue(db),
          myUidProvider.overrideWithValue(me),
          groupsRepositoryProvider.overrideWithValue(repo),
          groupsProvider.overrideWith(
            (ref) => Stream.value([
              TaskGroup(uid: 'g1', name: 'Семья', ownerUid: owner),
            ]),
          ),
          groupMembersProvider.overrideWith(
            (ref) => Stream.value(const [
              GroupMember(groupUid: 'g1', userUid: me, displayName: 'Аня'),
              GroupMember(
                groupUid: 'g1',
                userUid: husband,
                displayName: 'Миша',
              ),
              GroupMember(groupUid: 'g1', userUid: third, displayName: 'Оля'),
            ]),
          ),
          allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
          allLogsProvider.overrideWith(
            (ref) => Stream.value(const <TaskLog>[]),
          ),
          groupMarksProvider.overrideWith(
            (ref) => Stream.value(const <GroupMark>[]),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ru', 'RU'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru', 'RU')],
          home: const GroupPage(groupUid: 'g1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUpAll(() => initializeDateFormatting('ru_RU', null));

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1170, 2400);
    view.devicePixelRatio = 3;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets('shows the group, its members and every task', (tester) async {
    await open(tester);

    expect(find.text('Группа'), findsOneWidget);
    expect(find.text('Семья'), findsOneWidget);
    expect(find.textContaining('На этой неделе'), findsOneWidget);
    // Members: me as "Я", the others by name — each with a count. The first
    // task is for everyone, so it counts for all three.
    expect(find.text('Я'), findsOneWidget);
    expect(find.text('2 задачи'), findsNWidgets(3));
    for (final title in [
      'Купить продукты',
      'Оплатить коммуналку',
      'Забрать посылку',
      'Вынести мусор',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Все'), findsNWidgets(2)); // the chip and the pill
    expect(find.text('Сегодня, 19:00 · ждёт'), findsOneWidget);
  });

  testWidgets('a member chip keeps their tasks and the shared ones', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.widgetWithText(InkWell, 'Миша').last);
    await tester.pumpAndSettle();

    expect(find.text('Забрать посылку'), findsOneWidget);
    expect(find.text('Купить продукты'), findsOneWidget);
    expect(find.text('Вынести мусор'), findsNothing);
    expect(find.text('Оплатить коммуналку'), findsNothing);

    await tester.tap(find.text('Мои'));
    await tester.pumpAndSettle();
    expect(find.text('Оплатить коммуналку'), findsOneWidget);
    expect(find.text('Забрать посылку'), findsNothing);

    await tester.tap(find.text('Все').first);
    await tester.pumpAndSettle();
    expect(find.text('Вынести мусор'), findsOneWidget);
  });

  testWidgets('pulling the page down syncs now', (tester) async {
    late _FakeSync sync;
    await open(
      tester,
      extra: [
        syncControllerProvider.overrideWith((ref) => sync = _FakeSync(ref)),
      ],
    );

    await tester.fling(find.text('Семья'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(sync.runs, 1);
  });

  testWidgets('"Все задачи на таймлайне" is off, and switching it on is kept', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Только назначенные на вас и на всех'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(
      find.text('В таймлайне и календаре — все задачи группы'),
      findsOneWidget,
    );
    expect(prefs.getStringList('groups_show_all'), ['g1']);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(prefs.getStringList('groups_show_all'), isEmpty);
  });

  testWidgets('the ring ticks a task that is mine', (tester) async {
    await open(tester);

    await tester.tap(
      find.byTooltip('Отметить выполненной: Оплатить коммуналку'),
    );
    // Under fake time a drift write never finishes on its own.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();

    final logs = (await tester.runAsync(() => db.select(db.taskLogs).get()))!;
    expect(logs.single.taskId, 2);
    expect(logs.single.completed, isTrue);
  });

  group('the invite', () {
    testWidgets('the owner sees the code as six digits', (tester) async {
      await open(tester, repo: _FakeRepo());

      await tester.tap(find.text('Пригласить'));
      await tester.pumpAndSettle();

      expect(find.text('Код приглашения'), findsOneWidget);
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        expect(find.text(digit), findsOneWidget, reason: 'digit $digit');
      }
      expect(find.text('Скопировать'), findsOneWidget);
    });

    testWidgets('a new code replaces the old one', (tester) async {
      await open(tester, repo: _FakeRepo());
      await tester.tap(find.text('Пригласить'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Сменить код'));
      await tester.pumpAndSettle();

      expect(find.text('9'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('a member who is not the owner has no invite', (tester) async {
      await open(tester, owner: husband, repo: _FakeRepo());

      expect(find.text('Пригласить'), findsNothing);
    });
  });

  testWidgets('"+" opens the form already in this group', (tester) async {
    await open(tester, repo: _FakeRepo());

    await tester.tap(find.byTooltip('Новая задача для группы'));
    await tester.pumpAndSettle();

    expect(find.text('Новая задача'), findsOneWidget);
    // The group is chosen, so the "who" card offers the members.
    expect(find.text('КОМУ'), findsOneWidget);
    expect(find.text('Всем'), findsOneWidget);
  });
}
