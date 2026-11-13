import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/projects/project.dart';
import 'package:todo_app/projects/projects_repository.dart';
import 'package:todo_app/projects/projects_state.dart';

import '../support/fake_projects_api.dart';

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Сохранить'));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU'));

  testWidgets('task form scopes, creates, and saves a section', (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026);
    await db.into(db.localProjects).insert(
      LocalProjectsCompanion.insert(
        id: 'home',
        name: 'Дом',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.localProjects).insert(
      LocalProjectsCompanion.insert(
        id: 'work',
        name: 'Работа',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.sectionsDao.createSection(
      userId: 'user-1',
      name: 'Личное',
      position: 0,
    );
    await db.sectionsDao.createSection(
      userId: 'user-1',
      projectId: 'home',
      name: 'Домашнее',
      position: 0,
    );
    final api = FakeProjectsApi()
      ..projects['home'] = Project(
        id: 'home',
        name: 'Дом',
        createdAt: now,
        updatedAt: now,
      )
      ..projects['work'] = Project(
        id: 'work',
        name: 'Работа',
        createdAt: now,
        updatedAt: now,
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          myUidProvider.overrideWithValue('user-1'),
          projectsRepositoryProvider.overrideWithValue(ProjectsRepository(api)),
        ],
        child: const MaterialApp(home: CreateTaskPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Купить хлеб');
    await tester.tap(find.text('Без проекта'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дом').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Без раздела'));
    await tester.pumpAndSettle();
    expect(find.text('Домашнее'), findsOneWidget);
    expect(find.text('Личное'), findsNothing);
    await tester.tap(find.text('Домашнее'));
    await tester.pumpAndSettle();
    expect(find.text('Домашнее'), findsOneWidget);

    await tester.tap(find.text('Дом'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Работа').last);
    await tester.pumpAndSettle();
    expect(find.text('Без раздела'), findsOneWidget);

    await tester.tap(find.text('Без раздела'));
    await tester.pumpAndSettle();
    expect(find.text('Домашнее'), findsNothing);

    await tester.tap(find.text('+ Создать раздел'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Покупки');
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();

    expect(find.text('Покупки'), findsOneWidget);
    expect(find.text('Купить хлеб'), findsOneWidget);
    await _save(tester);

    final task = (await db.tasksDao.getRootTasks()).single;
    expect(task.projectUid, 'work');
    expect(task.sectionId, isNotNull);
    expect((await db.sectionsDao.sectionById(task.sectionId!))!.name, 'Покупки');
  });

  testWidgets('editing a task preselects and can remove its section', (
    tester,
  ) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final section = await db.sectionsDao.createSection(
      userId: 'user-1',
      name: 'Мой раздел',
      position: 0,
    );
    final id = await db.tasksDao.insertTask(
      TasksCompanion.insert(title: 'Задача', sectionId: Value(section.id)),
    );
    final task = (await db.tasksDao.getTaskById(id))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          myUidProvider.overrideWithValue('user-1'),
        ],
        child: MaterialApp(
          home: CreateTaskPage(mode: TaskFormMode.edit, task: task),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Мой раздел'), findsOneWidget);
    await tester.tap(find.text('Мой раздел'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Без раздела'));
    await tester.pumpAndSettle();
    await _save(tester);

    expect((await db.tasksDao.getTaskById(id))!.sectionId, isNull);
  });
}
