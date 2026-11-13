import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/projects/project.dart';
import 'package:todo_app/projects/projects_state.dart';
import 'package:todo_app/projects/projects_tab.dart';

import '../support/fake_projects_api.dart';

void main() {
  testWidgets('project is created from the actual tab while offline', (
    tester,
  ) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final api = FakeProjectsApi()..error = const ApiException.offline();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          projectsApiProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: Scaffold(body: ProjectsTab())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать проект'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project-name')), 'Офлайн');
    await tester.tap(find.byTooltip('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Офлайн'), findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  test(
    'projects are created and edited locally without contacting server',
    () async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      final api = FakeProjectsApi()..error = const ApiException.offline();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          projectsApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final state = container.read(projectsStateProvider.notifier);
      final project = await state.create(
        const CreateProjectRequest(name: 'Локальный'),
      );
      expect(project, isNotNull);
      await state.update(
        project!.id,
        const UpdateProjectRequest(name: 'Изменённый'),
      );
      expect(
        container.read(projectsStateProvider).projects.single.name,
        'Изменённый',
      );
      expect(api.calls, isEmpty);
    },
  );
}
