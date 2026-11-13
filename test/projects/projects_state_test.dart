import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/projects/project.dart';
import 'package:todo_app/projects/projects_repository.dart';
import 'package:todo_app/projects/projects_state.dart';

import '../support/fake_projects_api.dart';

void main() {
  Project project(
    String id, {
    int total = 0,
    int completed = 0,
    DateTime? archivedAt,
  }) => Project(
    id: id,
    name: id,
    createdAt: DateTime.utc(2026, 11, 10),
    updatedAt: DateTime.utc(2026, 11, 10),
    archivedAt: archivedAt,
    statistics: ProjectStatistics(
      total: total,
      completed: completed,
      progress: total == 0 ? 0 : completed * 100 ~/ total,
    ),
  );

  late FakeProjectsApi api;
  late ProviderContainer container;
  late ProjectsNotifier notifier;

  setUp(() {
    api = FakeProjectsApi();
    container = ProviderContainer(
      overrides: [
        projectsRepositoryProvider.overrideWithValue(ProjectsRepository(api)),
      ],
    );
    notifier = container.read(projectsStateProvider.notifier);
  });

  tearDown(() => container.dispose());

  test(
    'starts empty, loads active projects, and represents an empty response',
    () async {
      expect(container.read(projectsStateProvider), const ProjectsState());

      await notifier.load();
      expect(container.read(projectsStateProvider).projects, isEmpty);

      api.projects['home'] = project('home');
      await notifier.refresh();
      expect(container.read(projectsStateProvider).projects.single.id, 'home');
    },
  );

  test(
    'creates, updates, archives and restores without duplicate list entries',
    () async {
      await notifier.create(const CreateProjectRequest(name: 'Home'));
      final created = container.read(projectsStateProvider).projects.single;

      await notifier.update(
        created.id,
        const UpdateProjectRequest(name: 'Дом'),
      );
      expect(container.read(projectsStateProvider).projects.single.name, 'Дом');

      await notifier.archive(created.id);
      expect(container.read(projectsStateProvider).projects, isEmpty);
      expect(
        container.read(projectsStateProvider).archivedProjects.single.id,
        created.id,
      );

      await notifier.restore(created.id);
      expect(
        container.read(projectsStateProvider).projects.single.id,
        created.id,
      );
      expect(container.read(projectsStateProvider).archivedProjects, isEmpty);
    },
  );

  test(
    'reports repository failures while retaining already loaded projects',
    () async {
      api.projects['home'] = project('home');
      await notifier.load();
      api.error = const ApiException.offline();

      await notifier.load();

      final state = container.read(projectsStateProvider);
      expect(state.projects.single.id, 'home');
      expect(state.error, isA<ApiException>());
      expect(state.isLoading, isFalse);
    },
  );

  test(
    'refreshes affected project statistics after a task change and invalidates task pages',
    () async {
      api.projects['home'] = project('home', total: 1);
      api.taskPages['home'] = const ProjectTasksPage(
        tasks: [
          {'id': 'task-1', 'project_id': 'home'},
        ],
      );
      await notifier.load();
      await notifier.loadTasks('home');
      expect(container.read(projectsStateProvider).taskPages, contains('home'));

      api.projects['home'] = project('home', total: 2, completed: 1);
      await notifier.taskChanged(projectId: 'home');

      final state = container.read(projectsStateProvider);
      expect(state.projects.single.statistics.total, 2);
      expect(state.projects.single.statistics.completed, 1);
      expect(state.taskPages, isNot(contains('home')));
    },
  );

  test('refreshes both projects when a task is reassigned', () async {
    api.projects['one'] = project('one', total: 0);
    api.projects['two'] = project('two', total: 1);
    await notifier.load();

    api.projects['one'] = project('one', total: 1);
    api.projects['two'] = project('two', total: 0);
    await notifier.taskChanged(previousProjectId: 'two', projectId: 'one');

    final projects = container.read(projectsStateProvider).projects;
    expect(projects.singleWhere((p) => p.id == 'one').statistics.total, 1);
    expect(projects.singleWhere((p) => p.id == 'two').statistics.total, 0);
  });
}
