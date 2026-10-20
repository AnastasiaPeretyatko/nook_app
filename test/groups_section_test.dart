import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/groups/groups_repository.dart';
import 'package:todo_app/pages/groups_page.dart';
import 'package:todo_app/sync/providers.dart';

/// Only what the join sheet calls; anything else is a bug in the test.
class _FakeRepo implements GroupsRepository {
  final joined = <String>[];

  /// Set to make the server refuse.
  String? refuse;

  @override
  Future<String> joinGroup(String code) async {
    if (refuse != null) throw GroupActionException(groupErrorText(refuse!));
    joined.add(code);
    return 'g1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The "Группы" block of the settings screen: what it says by account state, the
/// rows of the groups, and joining by six digits.
void main() {
  const me = 'a';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  late AppDatabase db;

  Task groupTask(int id) => Task(
    id: id,
    dirty: false,
    title: 'Задача $id',
    status: TaskStatus.active,
    trackingMode: TrackingMode.checkbox,
    startDate: today,
    createdAt: today,
    updatedAt: today,
    groupUid: 'g1',
    authorUid: me,
  );

  Future<void> open(
    WidgetTester tester, {
    String? signedIn = me,
    bool syncActive = true,
    _FakeRepo? repo,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          myUidProvider.overrideWithValue(signedIn),
          syncActiveProvider.overrideWithValue(syncActive),
          groupsRepositoryProvider.overrideWithValue(
            signedIn == null ? null : (repo ?? _FakeRepo()),
          ),
          groupsProvider.overrideWith(
            (ref) => Stream.value(const [
              TaskGroup(uid: 'g1', name: 'Семья', ownerUid: me),
            ]),
          ),
          groupMembersProvider.overrideWith(
            (ref) => Stream.value(const [
              GroupMember(groupUid: 'g1', userUid: me, displayName: 'Аня'),
              GroupMember(groupUid: 'g1', userUid: 'b', displayName: 'Миша'),
              GroupMember(groupUid: 'g1', userUid: 'c', displayName: 'Оля'),
            ]),
          ),
          allTasksProvider.overrideWith(
            (ref) => Stream.value([groupTask(1), groupTask(2)]),
          ),
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
          home: const Scaffold(
            body: SingleChildScrollView(child: GroupsSection()),
          ),
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

  group('by account state', () {
    testWidgets('signed out: a hint, no actions', (tester) async {
      await open(tester, signedIn: null);

      expect(find.text('ГРУППЫ'), findsOneWidget);
      expect(find.textContaining('Войдите в аккаунт'), findsOneWidget);
      expect(find.text('Создать группу'), findsNothing);
      expect(find.text('Присоединиться'), findsNothing);
    });

    testWidgets('signed in without sync: points to the sync screen', (
      tester,
    ) async {
      await open(tester, syncActive: false);

      expect(find.textContaining('нужна синхронизация'), findsOneWidget);
      expect(find.text('Открыть синхронизацию'), findsOneWidget);
      expect(find.text('Создать группу'), findsNothing);
      expect(find.text('Семья'), findsNothing);
    });

    testWidgets('signed in with sync: the groups and both actions', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Семья'), findsOneWidget);
      expect(find.text('3 участника · 2 задачи'), findsOneWidget);
      expect(find.text('Создать группу'), findsOneWidget);
      expect(find.text('Присоединиться'), findsOneWidget);
    });
  });

  testWidgets('tapping a group opens its screen', (tester) async {
    await open(tester);

    await tester.tap(find.text('Семья'));
    await tester.pumpAndSettle();

    expect(find.text('Группа'), findsOneWidget);
    expect(find.text('Новая задача для группы'), findsNothing);
    expect(find.byTooltip('Новая задача для группы'), findsOneWidget);
  });

  group('joining', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('Присоединиться'));
      await tester.pumpAndSettle();
    }

    Finder cell(String digit) => find.text(digit);

    testWidgets('each digit lands in a cell of its own', (tester) async {
      await open(tester);
      await openSheet(tester);

      expect(find.text('Вступить в группу'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '482');
      await tester.pump();

      for (final digit in ['4', '8', '2']) {
        expect(cell(digit), findsOneWidget);
      }
    });

    testWidgets('only digits are taken, and no more than six', (tester) async {
      await open(tester);
      await openSheet(tester);

      await tester.enterText(find.byType(TextField), '1a2b3-4567890');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '123456');
    });

    testWidgets('the button waits for the sixth digit', (tester) async {
      await open(tester);
      await openSheet(tester);

      FilledButton button() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(button().onPressed, isNotNull);
    });

    testWidgets('the code goes to the server and the sheet closes', (
      tester,
    ) async {
      final repo = _FakeRepo();
      await open(tester, repo: repo);
      await openSheet(tester);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.text('Вступить'));
      await tester.pumpAndSettle();

      expect(repo.joined, ['123456']);
      expect(find.text('Вступить в группу'), findsNothing);
      expect(find.text('Вы в группе'), findsOneWidget);
    });

    testWidgets('a refused code stays on screen with the reason', (
      tester,
    ) async {
      final repo = _FakeRepo()..refuse = 'bad_code';
      await open(tester, repo: repo);
      await openSheet(tester);

      await tester.enterText(find.byType(TextField), '000000');
      await tester.pump();
      await tester.tap(find.text('Вступить'));
      await tester.pumpAndSettle();

      expect(find.text('Вступить в группу'), findsOneWidget);
      expect(find.textContaining('Код не подошёл'), findsOneWidget);

      // Typing again clears the reproach.
      await tester.enterText(find.byType(TextField), '00000');
      await tester.pump();
      expect(find.textContaining('Код не подошёл'), findsNothing);
    });
  });
}
