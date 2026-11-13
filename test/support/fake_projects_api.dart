import 'package:todo_app/projects/project.dart';
import 'package:todo_app/projects/projects_api.dart';

class FakeProjectsApi implements ProjectsApi {
  final List<String> calls = [];
  final Map<String, Project> projects = {};
  final Map<String, ProjectTasksPage> taskPages = {};
  Object? error;

  Future<T> _call<T>(String call, T value) async {
    calls.add(call);
    if (error != null) throw error!;
    return value;
  }

  @override
  Future<Project> createProject(CreateProjectRequest request) async {
    final project = Project(
      id: 'project-${projects.length + 1}',
      name: request.name,
      description: request.description,
      color: request.color,
      createdAt: DateTime.utc(2026, 11, 10),
      updatedAt: DateTime.utc(2026, 11, 10),
      statistics: const ProjectStatistics(),
    );
    projects[project.id] = project;
    return _call('create(${request.name})', project);
  }

  @override
  Future<Project> getProject(String projectId) =>
      _call('get($projectId)', projects[projectId]!);

  @override
  Future<List<Project>> getProjects({bool archived = false}) => _call(
    'list(archived: $archived)',
    projects.values.where((project) => project.isArchived == archived).toList(),
  );

  @override
  Future<Project> updateProject(
    String projectId,
    UpdateProjectRequest request,
  ) async {
    final old = projects[projectId]!;
    final next = old.copyWith(
      name: request.name,
      description: request.description.present
          ? request.description.value
          : old.description,
      color: request.color.present ? request.color.value : old.color,
    );
    projects[projectId] = next;
    return _call('update($projectId)', next);
  }

  @override
  Future<Project> archiveProject(String projectId) async {
    final next = projects[projectId]!.copyWith(
      archivedAt: DateTime.utc(2026, 11, 11),
    );
    projects[projectId] = next;
    return _call('archive($projectId)', next);
  }

  @override
  Future<Project> restoreProject(String projectId) async {
    final next = projects[projectId]!.copyWith(archivedAt: null);
    projects[projectId] = next;
    return _call('restore($projectId)', next);
  }

  @override
  Future<ProjectTasksPage> getProjectTasks(
    String projectId, {
    bool? completed,
    int? limit,
    int? offset,
  }) => _call(
    'tasks($projectId)',
    taskPages[projectId] ?? const ProjectTasksPage(),
  );
}
