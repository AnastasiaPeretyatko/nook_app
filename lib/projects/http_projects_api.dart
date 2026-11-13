import 'package:todo_app/api/api_client.dart';

import 'project.dart';
import 'projects_api.dart';

/// Projects transport backed by the app's shared authenticated JSON client.
class HttpProjectsApi implements ProjectsApi {
  HttpProjectsApi(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> _map(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final response = await _api.request(method, path, query: query, body: body);
    if (response is! Map) {
      throw const FormatException('Expected response object');
    }
    try {
      return Map<String, dynamic>.from(response);
    } on TypeError {
      throw const FormatException('Expected response object');
    }
  }

  Future<List<Map<String, dynamic>>> _list(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _api.request('GET', path, query: query);
    if (response is! List) {
      throw const FormatException('Expected response list');
    }
    final rows = <Map<String, dynamic>>[];
    for (final item in response) {
      if (item is! Map) {
        throw const FormatException('Expected response object');
      }
      try {
        rows.add(Map<String, dynamic>.from(item));
      } on TypeError {
        throw const FormatException('Expected response object');
      }
    }
    return rows;
  }

  @override
  Future<Project> createProject(CreateProjectRequest request) async =>
      Project.fromJson(await _map('POST', '/projects', body: request.toJson()));

  @override
  Future<List<Project>> getProjects({bool archived = false}) async => [
    for (final row in await _list(
      '/projects',
      query: archived ? const {'archived': 'true'} : null,
    ))
      Project.fromJson(row),
  ];

  @override
  Future<Project> getProject(String projectId) async =>
      Project.fromJson(await _map('GET', '/projects/$projectId'));

  @override
  Future<Project> updateProject(
    String projectId,
    UpdateProjectRequest request,
  ) async => Project.fromJson(
    await _map('PATCH', '/projects/$projectId', body: request.toJson()),
  );

  @override
  Future<Project> archiveProject(String projectId) async =>
      Project.fromJson(await _map('PATCH', '/projects/$projectId/archive'));

  @override
  Future<Project> restoreProject(String projectId) async =>
      Project.fromJson(await _map('PATCH', '/projects/$projectId/restore'));

  @override
  Future<ProjectTasksPage> getProjectTasks(
    String projectId, {
    bool? completed,
    int? limit,
    int? offset,
  }) async => ProjectTasksPage.fromJson(
    await _map(
      'GET',
      '/projects/$projectId/tasks',
      query: {
        if (completed != null) 'completed': '$completed',
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
      },
    ),
  );
}
