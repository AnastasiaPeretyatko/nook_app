import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/projects/project.dart';
import 'package:todo_app/projects/project_details_page.dart';
import 'package:todo_app/projects/projects_repository.dart';
import 'package:todo_app/projects/projects_state.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/habits/tasks_list.dart';
import 'package:todo_app/widgets/list_card.dart';

import '../support/fake_projects_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU'));

  testWidgets('project subtasks have round leading checks and remain tappable', (
    tester,
  ) async {
    final api = FakeProjectsApi();
    api.projects['home'] = Project(
      id: 'home',
      name: 'Дом',
      color: 'violet',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    const taskTitle =
        'Длинное название задачи проекта, которое занимает несколько строк и проверяет выравнивание чекбокса по первой строке заголовка';
    final parent = await db.tasksDao.insertTask(
      TasksCompanion.insert(title: taskTitle, projectUid: const Value('home')),
    );
    final child = await db.tasksDao.insertTask(
      TasksCompanion.insert(title: 'Первая подзадача', parentId: Value(parent)),
    );
    await db.tasksDao.insertTask(
      TasksCompanion.insert(title: 'Вторая подзадача', parentId: Value(parent)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          projectsRepositoryProvider.overrideWithValue(ProjectsRepository(api)),
        ],
        child: const MaterialApp(home: ProjectDetailsPage(projectId: 'home')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Показать подзадачи'));
    await tester.pumpAndSettle();
    final checks = find.byType(TaskCompletionToggle);
    expect(checks, findsNWidgets(3));
    for (final toggle in tester.widgetList<TaskCompletionToggle>(checks)) {
      expect(toggle.color, taskSwatchForKey('violet')!.accent);
    }
    final ring = find.descendant(
      of: checks.first,
      matching: find.byType(AnimatedContainer),
    );
    final childRing = find.descendant(
      of: checks.at(1),
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(ring), const Size(22, 22));
    expect(
      tester.getTopLeft(ring).dy,
      tester.getTopLeft(find.text(taskTitle)).dy,
    );
    expect(tester.getSize(childRing), tester.getSize(ring));
    expect(
      tester.widget<RowsCard>(find.byType(RowsCard)).children,
      hasLength(1),
    );
    expect(
      tester.getTopLeft(checks.at(1)).dx,
      lessThan(tester.getTopLeft(find.text('Первая подзадача')).dx),
    );
    expect(
      tester.widget<Text>(find.text('Первая подзадача')).style!.fontSize,
      13,
    );
    await tester.tap(find.text('Первая подзадача'));
    await tester.pumpAndSettle();
    final task = (await db.tasksDao.getTaskById(parent))!;
    expect(
      (await db.tasksDao.getLogForDate(
        child,
        task.startDate ?? task.createdAt,
      ))!.completed,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('loads a project and its empty tasks through the repository', (
    tester,
  ) async {
    final api = FakeProjectsApi();
    api.projects['home'] = Project(
      id: 'home',
      name: 'Дом',
      description: 'Дела',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          projectsRepositoryProvider.overrideWithValue(ProjectsRepository(api)),
        ],
        child: const MaterialApp(home: ProjectDetailsPage(projectId: 'home')),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.calls, containsAll(['get(home)', 'tasks(home)']));
    expect(find.text('Дом'), findsOneWidget);
    expect(find.text('Дела'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .backgroundColor,
      AppPalette.light.chip,
    );
    expect(find.text('В проекте пока нет задач'), findsOneWidget);
    expect(find.text('Добавить задачу'), findsNothing);
    await tester.tap(find.byTooltip('Новая задача'));
    await tester.pumpAndSettle();
    expect(find.text('Новая задача'), findsOneWidget);
    expect(
      tester
          .widget<CreateTaskPage>(find.byType(CreateTaskPage))
          .initialProjectUid,
      'home',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'groups project tasks by ordered sections and keeps collapse state',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.utc(2026);
      final api = FakeProjectsApi();
      api.projects['home'] = Project(
        id: 'home',
        name: 'Дом',
        createdAt: now,
        updatedAt: now,
      );
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.localProjects)
          .insert(
            LocalProjectsCompanion.insert(
              id: 'home',
              name: 'Дом',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final first = await db.sectionsDao.createSection(
        userId: 'user-1',
        projectId: 'home',
        name: 'Первый',
        position: 0,
      );
      final empty = await db.sectionsDao.createSection(
        userId: 'user-1',
        projectId: 'home',
        name: 'Пустой',
        position: 1,
      );
      final later = await db.sectionsDao.createSection(
        userId: 'user-1',
        projectId: 'home',
        name: 'Позже',
        position: 2,
      );
      final firstTask = await db.tasksDao.insertTask(
        TasksCompanion.insert(
          title: 'Первая задача',
          projectUid: const Value('home'),
          sectionId: Value(first.id),
        ),
      );
      await db.tasksDao.insertTask(
        TasksCompanion.insert(
          title: 'Вторая задача',
          projectUid: const Value('home'),
          sectionId: Value(first.id),
        ),
      );
      await db.tasksDao.insertTask(
        TasksCompanion.insert(
          title: 'Задача позже',
          projectUid: const Value('home'),
          sectionId: Value(later.id),
        ),
      );
      await db.tasksDao.insertTask(
        TasksCompanion.insert(
          title: 'Без раздела',
          projectUid: const Value('home'),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            myUidProvider.overrideWithValue('user-1'),
            projectsRepositoryProvider.overrideWithValue(
              ProjectsRepository(api),
            ),
          ],
          child: const MaterialApp(home: ProjectDetailsPage(projectId: 'home')),
        ),
      );
      await tester.pumpAndSettle();

      final firstHeader = find.byKey(Key('project-section-${first.id}'));
      final emptyHeader = find.byKey(Key('project-section-${empty.id}'));
      final laterHeader = find.byKey(Key('project-section-${later.id}'));
      final unsectionedHeader = find.byKey(
        const Key('project-section-__unsectioned__'),
      );
      expect(firstHeader, findsOneWidget);
      expect(emptyHeader, findsOneWidget);
      expect(laterHeader, findsOneWidget);
      expect(unsectionedHeader, findsOneWidget);
      expect(
        tester.getTopLeft(firstHeader).dy,
        lessThan(tester.getTopLeft(emptyHeader).dy),
      );
      expect(
        tester.getTopLeft(emptyHeader).dy,
        lessThan(tester.getTopLeft(laterHeader).dy),
      );
      expect(
        tester.getTopLeft(laterHeader).dy,
        lessThan(tester.getTopLeft(unsectionedHeader).dy),
      );
      expect(
        find.descendant(of: firstHeader, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: emptyHeader, matching: find.text('0')),
        findsOneWidget,
      );
      expect(find.text('Первая задача'), findsOneWidget);

      await tester.tap(firstHeader);
      await tester.pumpAndSettle();
      expect(find.text('Первая задача'), findsNothing);
      await db.tasksDao.updateTaskById(
        firstTask,
        const TasksCompanion(title: Value('Первая задача обновлена')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Первая задача обновлена'), findsNothing);
      await db.tasksDao.updateTaskById(
        firstTask,
        TasksCompanion(sectionId: Value(later.id)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Первая задача обновлена'), findsOneWidget);
      expect(
        find.descendant(of: laterHeader, matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.text('Задача позже'), findsOneWidget);

      await tester.tap(find.byKey(const Key('create-project-section')));
      await tester.pumpAndSettle();
      expect(find.text('Новый раздел'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Новый');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();
      expect(find.text('НОВЫЙ'), findsOneWidget);

      await tester.tap(find.byKey(Key('project-section-actions-${empty.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переименовать'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Переименованный');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('ПЕРЕИМЕНОВАННЫЙ'), findsOneWidget);

      await tester.tap(find.byKey(Key('project-section-actions-${empty.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(find.text('Удалить раздел?'), findsOneWidget);
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('project-section-${empty.id}')), findsNothing);
      expect(
        find.byKey(const Key('project-section-actions-__unsectioned__')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
