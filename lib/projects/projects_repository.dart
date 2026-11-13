import 'project.dart';
import 'projects_api.dart';
import 'local_projects_store.dart';

/// Project operations with one testable dependency on the server contract.
///
/// Unlike task edits, Project endpoints are immediately server-backed. Their
/// returned project includes authoritative live statistics, so the repository
/// deliberately does not duplicate them in a local cache.
class ProjectsRepository {
  ProjectsRepository(this._api, {this.local});

  final ProjectsApi _api;
  final LocalProjectsStore? local;

  Future<Project> create(CreateProjectRequest request) =>
      local?.create(request) ?? _api.createProject(request);

  Future<List<Project>> list({bool archived = false}) =>
      local?.list(archived: archived) ?? _api.getProjects(archived: archived);

  Future<Project> get(String projectId) =>
      local?.get(projectId) ?? _api.getProject(projectId);

  Future<Project> update(String projectId, UpdateProjectRequest request) =>
      local?.update(projectId, request) ??
      _api.updateProject(projectId, request);

  Future<Project> archive(String projectId) =>
      local?.archive(projectId) ?? _api.archiveProject(projectId);

  Future<Project> restore(String projectId) =>
      local?.restore(projectId) ?? _api.restoreProject(projectId);

  Future<ProjectTasksPage> tasks(
    String projectId, {
    bool? completed,
    int? limit,
    int? offset,
  }) => local != null
      ? Future.value(const ProjectTasksPage())
      : _api.getProjectTasks(
          projectId,
          completed: completed,
          limit: limit,
          offset: offset,
        );
}
