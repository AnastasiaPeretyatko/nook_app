import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/projects/project.dart';
import 'package:todo_app/projects/projects_repository.dart';
import 'package:todo_app/projects/projects_state.dart';
import 'package:todo_app/projects/projects_tab.dart';
import 'package:todo_app/theme/app_palette.dart';

import '../support/fake_projects_api.dart';

class DelayedProjectsApi extends FakeProjectsApi {
  final loading = Completer<void>();
  final saving = Completer<void>();

  @override
  Future<List<Project>> getProjects({bool archived = false}) async {
    await loading.future;
    return super.getProjects(archived: archived);
  }

  @override
  Future<Project> createProject(CreateProjectRequest request) async {
    await saving.future;
    return super.createProject(request);
  }
}

void main() {
  late FakeProjectsApi api;

  setUp(() => api = FakeProjectsApi());

  Future<void> open(WidgetTester tester) async {
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
  }

  testWidgets('empty state creates a project with a required name', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Пока нет проектов'), findsOneWidget);
    await tester.tap(find.text('Создать проект'));
    await tester.pumpAndSettle();
    expect(find.text('Сохранить'), findsNothing);
    expect(find.text('Отмена'), findsNothing);
    expect(
      tester.getCenter(find.byTooltip('Закрыть')).dy,
      tester.getCenter(find.byTooltip('Сохранить')).dy,
    );
    expect(
      tester.getTopLeft(find.byTooltip('Сохранить')).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('project-name'))).dy),
    );
    await tester.tap(find.byTooltip('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Введите название'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('project-name')), '  Дом  ');
    await tester.tap(find.byTooltip('Сохранить'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('create(Дом)'));
    expect(find.text('Дом'), findsOneWidget);
  });

  testWidgets('a new project form closes when the scrim is tapped', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Создать проект'));
    await tester.pumpAndSettle();
    expect(find.text('Новый проект'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Новый проект'), findsNothing);
    expect(find.text('Пока нет проектов'), findsOneWidget);
  });

  testWidgets('cards show statistics and edit saves changed fields', (
    tester,
  ) async {
    api.projects['home'] = Project(
      id: 'home',
      name: 'Дом',
      description: 'старое',
      color: 'violet',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      statistics: const ProjectStatistics(total: 8, completed: 3, progress: 38),
    );
    await open(tester);
    expect(find.text('3 из 8 задач выполнено'), findsOneWidget);
    expect(find.text('38%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .backgroundColor,
      AppPalette.light.chip,
    );
    await tester.tap(find.text('Дом'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Редактировать проект'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('project-description')))
          .controller!
          .text,
      'старое',
    );
    await tester.enterText(find.byKey(const Key('project-name')), 'Работа');
    await tester.enterText(
      find.byKey(const Key('project-description')),
      'новое',
    );
    await tester.tap(find.byTooltip('Сохранить'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('update(home)'));
    expect(find.text('Работа'), findsOneWidget);
    expect(api.projects['home']!.description, 'новое');
  });

  testWidgets('failed load exposes retry', (tester) async {
    api.error = Exception('offline');
    await open(tester);
    expect(find.text('Не удалось загрузить проекты'), findsOneWidget);
    api.error = null;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Пока нет проектов'), findsOneWidget);
  });

  testWidgets('failed save keeps the form and entered values for retry', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Создать проект'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project-name')), 'Мой проект');
    await tester.enterText(
      find.byKey(const Key('project-description')),
      'Описание',
    );
    api.error = Exception('offline');
    await tester.tap(find.byTooltip('Сохранить'));
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось сохранить проект. Попробуйте ещё раз.'),
      findsOneWidget,
    );
    expect(find.text('Мой проект'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('project-description')))
          .controller!
          .text,
      'Описание',
    );
  });

  testWidgets('canceling an edit does not update the project', (tester) async {
    api.projects['home'] = Project(
      id: 'home',
      name: 'Дом',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await open(tester);
    await tester.tap(find.text('Дом'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Редактировать проект'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project-name')), 'Другое');
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    expect(api.calls.where((call) => call.startsWith('update')), isEmpty);
    expect(find.text('Дом'), findsOneWidget);
  });

  testWidgets('loading is shown and repeated save is disabled', (tester) async {
    final delayed = DelayedProjectsApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsRepositoryProvider.overrideWithValue(
            ProjectsRepository(delayed),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ProjectsTab())),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    delayed.loading.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать проект'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project-name')), 'Дом');
    await tester.tap(find.byTooltip('Сохранить'));
    await tester.pump();
    expect(find.byTooltip('Сохранить'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pump();
    expect(find.text('Новый проект'), findsOneWidget);
    delayed.saving.complete();
    await tester.pumpAndSettle();
    expect(delayed.calls.where((call) => call == 'create(Дом)'), hasLength(1));
  });
}
