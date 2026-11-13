import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/projects/project.dart';
import 'package:todo_app/projects/projects_repository.dart';

import '../support/fake_projects_api.dart';

void main() {
  late FakeProjectsApi api;
  late ProjectsRepository repository;

  setUp(() {
    api = FakeProjectsApi();
    repository = ProjectsRepository(api);
  });

  test('forwards each project operation and its pagination options', () async {
    final created = await repository.create(
      const CreateProjectRequest(name: 'Home'),
    );
    await repository.list();
    await repository.list(archived: true);
    await repository.get(created.id);
    await repository.update(
      created.id,
      const UpdateProjectRequest(name: 'Дом'),
    );
    await repository.archive(created.id);
    await repository.restore(created.id);
    await repository.tasks(created.id, completed: false, limit: 10, offset: 20);

    expect(api.calls, [
      'create(Home)',
      'list(archived: false)',
      'list(archived: true)',
      'get(project-1)',
      'update(project-1)',
      'archive(project-1)',
      'restore(project-1)',
      'tasks(project-1)',
    ]);
  });

  test('preserves backend authorization and validation errors', () async {
    api.error = const ApiException(
      ApiFailure.server,
      status: 400,
      code: 'unknown_project',
    );

    await expectLater(
      repository.create(const CreateProjectRequest(name: 'Home')),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'unknown_project',
        ),
      ),
    );
  });
}
