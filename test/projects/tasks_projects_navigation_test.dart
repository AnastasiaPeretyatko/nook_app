import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/tasks_page.dart';
import 'package:todo_app/projects/projects_tab.dart';
import 'package:todo_app/projects/projects_repository.dart';
import 'package:todo_app/projects/projects_state.dart';
import 'package:todo_app/projects/project.dart';

import '../support/fake_projects_api.dart';

void main() {
  testWidgets('task list opens its archive without a projects switch', (
    tester,
  ) async {
    final api = FakeProjectsApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allTasksProvider.overrideWith((ref) => Stream<List<Task>>.value([])),
          allLogsProvider.overrideWith(
            (ref) => Stream<List<TaskLog>>.value([]),
          ),
          projectsRepositoryProvider.overrideWithValue(ProjectsRepository(api)),
        ],
        child: const MaterialApp(home: TasksPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Проекты'), findsNothing);
    expect(find.text('Выполненные'), findsNothing);
    expect(find.byTooltip('Выполненные задачи'), findsOneWidget);
    await tester.tap(find.byTooltip('Выполненные задачи'));
    await tester.pumpAndSettle();
    expect(find.text('Пока ничего не выполнено'), findsOneWidget);
    expect(find.text('Архив'), findsOneWidget);
    await tester.tap(find.text('Проекты').last);
    await tester.pumpAndSettle();
    expect(find.text('Архив проектов пуст'), findsOneWidget);
    await tester.tap(find.text('Задачи').last);
    await tester.pumpAndSettle();
    expect(find.text('Пока ничего не выполнено'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Задачи'), findsOneWidget);
  });

  testWidgets('projects tab puts create action before archive', (tester) async {
    final api = FakeProjectsApi();
    api.projects['home'] = Project(
      id: 'home',
      name: 'Дом',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allTasksProvider.overrideWith((ref) => Stream<List<Task>>.value([])),
          allLogsProvider.overrideWith(
            (ref) => Stream<List<TaskLog>>.value([]),
          ),
          projectsRepositoryProvider.overrideWithValue(ProjectsRepository(api)),
        ],
        child: const MaterialApp(home: Scaffold(body: ProjectsTab())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsOneWidget);
    expect(find.text('Создать проект'), findsNothing);
    final create = find.byTooltip('Создать проект');
    final archive = find.byTooltip('Архив проектов');
    expect(create, findsOneWidget);
    expect(archive, findsOneWidget);
    expect(tester.getCenter(create).dx, lessThan(tester.getCenter(archive).dx));
    expect(api.calls, ['list(archived: false)']);
  });
}
