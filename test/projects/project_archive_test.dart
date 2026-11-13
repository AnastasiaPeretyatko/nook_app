import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/projects/project.dart';
import 'package:todo_app/projects/projects_repository.dart';
import 'package:todo_app/projects/projects_state.dart';
import 'package:todo_app/widgets/page_header.dart';
import 'package:todo_app/widgets/habits/tasks_list.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/projects/projects_tab.dart';

import '../support/fake_projects_api.dart';

class RefusingProjectsApi extends FakeProjectsApi {
  bool refuseArchive = false;
  bool refuseRestore = false;

  @override
  Future<Project> archiveProject(String projectId) {
    if (refuseArchive) throw Exception('archive failed');
    return super.archiveProject(projectId);
  }

  @override
  Future<Project> restoreProject(String projectId) {
    if (refuseRestore) throw Exception('restore failed');
    return super.restoreProject(projectId);
  }
}

void main() {
  testWidgets('archive with confirmation and restore from project archive', (
    tester,
  ) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final taskId = await db.tasksDao.insertTask(
      TasksCompanion.insert(title: 'Задача', projectUid: const Value('home')),
    );
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
          databaseProvider.overrideWithValue(db),
          projectsRepositoryProvider.overrideWithValue(ProjectsRepository(api)),
        ],
        child: const MaterialApp(home: Scaffold(body: ProjectsTab())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дом'));
    await tester.pumpAndSettle();
    final archive = find.byTooltip('Архивировать проект');
    final edit = find.byTooltip('Редактировать проект');
    expect(
      find.ancestor(of: archive, matching: find.byType(BackHeader)),
      findsOneWidget,
    );
    expect(tester.getCenter(archive).dy, tester.getCenter(edit).dy);
    expect(tester.getCenter(archive).dx, lessThan(tester.getCenter(edit).dx));
    await tester.tap(find.byTooltip('Архивировать проект'));
    await tester.pumpAndSettle();
    expect(find.text('Архивировать проект?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(api.calls, isNot(contains('archive(home)')));
    await tester.tap(find.byTooltip('Архивировать проект'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Архивировать'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('archive(home)'));
    expect((await db.tasksDao.getTaskById(taskId))!.projectUid, 'home');
    expect(find.text('Пока нет проектов'), findsOneWidget);
    await tester.tap(find.byTooltip('Архив проектов'));
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsOneWidget);
    await tester.tap(find.byTooltip('Восстановить проект Дом'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('restore(home)'));
    expect((await db.tasksDao.getTaskById(taskId))!.projectUid, 'home');
    expect(find.text('Архив проектов пуст'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('failed restore keeps archived project visible for retry', (
    tester,
  ) async {
    final api = RefusingProjectsApi()..refuseRestore = true;
    api.projects['home'] = Project(
      id: 'home',
      name: 'Дом',
      archivedAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      statistics: const ProjectStatistics(total: 2, completed: 1, progress: 50),
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
        child: const MaterialApp(
          home: Scaffold(body: CompletedTasksPage(initialTab: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 из 2 задач выполнено · 50%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .backgroundColor,
      AppPalette.light.chip,
    );
    await tester.tap(find.byTooltip('Восстановить проект Дом'));
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsOneWidget);
    expect(
      find.text('Не удалось восстановить проект. Попробуйте ещё раз.'),
      findsOneWidget,
    );
    api.refuseRestore = false;
    await tester.tap(find.byTooltip('Восстановить проект Дом'));
    await tester.pumpAndSettle();
    expect(find.text('Архив проектов пуст'), findsOneWidget);
  });
}
