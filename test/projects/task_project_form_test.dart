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

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU'));
  testWidgets('task form selects an active project and retains entered title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
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
        child: const MaterialApp(home: CreateTaskPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ПРОЕКТ'), findsOneWidget);
    expect(find.text('Без проекта'), findsOneWidget);
    await tester.tap(find.text('Без проекта'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дом').last);
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
