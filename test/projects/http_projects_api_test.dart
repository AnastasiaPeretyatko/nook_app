import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo_app/api/api_client.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/api/token_store.dart';
import 'package:todo_app/projects/http_projects_api.dart';
import 'package:todo_app/projects/project.dart';

void main() {
  Map<String, dynamic> project({bool archived = false}) => {
    'id': 'project-1',
    'name': 'Home',
    'description': null,
    'color': 'violet',
    'created_at': '2026-11-10T09:00:00.000Z',
    'updated_at': '2026-11-10T10:00:00.000Z',
    'archived_at': archived ? '2026-11-11T10:00:00.000Z' : null,
    'total_tasks': 2,
    'completed_tasks': 1,
    'progress': 50,
  };

  late List<http.Request> requests;
  late HttpProjectsApi api;

  setUp(() {
    requests = [];
    api = HttpProjectsApi(
      ApiClient(
        baseUrl: 'https://nook.test',
        tokens: MemoryTokenStore(
          accessToken: 'access',
          refreshToken: 'refresh',
        ),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/projects/project-1/tasks') {
            return http.Response(
              jsonEncode({
                'tasks': [
                  {'id': 'task-1', 'project_id': 'project-1'},
                ],
                'has_more': true,
                'next_offset': 25,
              }),
              200,
            );
          }
          if (request.url.path == '/projects' && request.method == 'GET') {
            return http.Response(
              jsonEncode([
                project(
                  archived: request.url.queryParameters['archived'] == 'true',
                ),
              ]),
              200,
            );
          }
          return http.Response(
            jsonEncode(
              project(archived: request.url.path.endsWith('/archive')),
            ),
            200,
          );
        }),
      ),
    );
  });

  test('uses the authenticated Projects routes and bodies', () async {
    await api.createProject(
      const CreateProjectRequest(name: 'Home', color: 'violet'),
    );
    await api.getProjects();
    await api.getProjects(archived: true);
    await api.getProject('project-1');
    await api.updateProject(
      'project-1',
      const UpdateProjectRequest(description: PatchValue(null)),
    );
    await api.archiveProject('project-1');
    await api.restoreProject('project-1');
    final page = await api.getProjectTasks(
      'project-1',
      completed: true,
      limit: 25,
      offset: 50,
    );

    expect(requests.map((r) => '${r.method} ${r.url.path}').toList(), [
      'POST /projects',
      'GET /projects',
      'GET /projects',
      'GET /projects/project-1',
      'PATCH /projects/project-1',
      'PATCH /projects/project-1/archive',
      'PATCH /projects/project-1/restore',
      'GET /projects/project-1/tasks',
    ]);
    expect(requests.first.headers['authorization'], 'Bearer access');
    expect(requests.first.body, '{"name":"Home","color":"violet"}');
    expect(requests[2].url.queryParameters, {'archived': 'true'});
    expect(requests[4].body, '{"description":null}');
    expect(requests.last.url.queryParameters, {
      'completed': 'true',
      'limit': '25',
      'offset': '50',
    });
    expect(page.tasks.single['project_id'], 'project-1');
    expect(page.hasMore, isTrue);
    expect(page.nextOffset, 25);
  });

  test('keeps API failures available to callers', () async {
    final failing = HttpProjectsApi(
      ApiClient(
        baseUrl: 'https://nook.test',
        tokens: MemoryTokenStore(
          accessToken: 'access',
          refreshToken: 'refresh',
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'code': 'not_found', 'message': 'Project not found'}),
            404,
          ),
        ),
      ),
    );

    await expectLater(
      failing.getProject('missing'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.status, 'status', 404)
            .having((error) => error.code, 'code', 'not_found'),
      ),
    );
  });
}
