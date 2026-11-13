import 'project.dart';

/// The authenticated Projects endpoints, isolated for repository tests.
///
/// The concrete implementation delegates authentication, retries and API error
/// parsing to the app's existing [ApiClient].
abstract class ProjectsApi {
  Future<Project> createProject(CreateProjectRequest request);

  Future<List<Project>> getProjects({bool archived = false});

  Future<Project> getProject(String projectId);

  Future<Project> updateProject(String projectId, UpdateProjectRequest request);

  Future<Project> archiveProject(String projectId);

  Future<Project> restoreProject(String projectId);

  Future<ProjectTasksPage> getProjectTasks(
    String projectId, {
    bool? completed,
    int? limit,
    int? offset,
  });
}
