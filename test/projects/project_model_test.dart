import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/projects/project.dart';

void main() {
  const created = '2026-11-10T09:15:00.000Z';
  const updated = '2026-11-10T10:30:00.000Z';

  Map<String, dynamic> row({
    Object? description = 'Household tasks',
    Object? color = 'violet',
    Object? archivedAt,
    Object? total = 4,
    Object? completed = 3,
    Object? progress = 75,
  }) => {
    'id': 'project-1',
    'name': 'Home',
    'description': description,
    'color': color,
    'created_at': created,
    'updated_at': updated,
    'archived_at': archivedAt,
    'total_tasks': total,
    'completed_tasks': completed,
    'progress': progress,
  };

  group('Project', () {
    test('deserializes the full backend project and its statistics', () {
      final project = Project.fromJson(row());

      expect(project.id, 'project-1');
      expect(project.name, 'Home');
      expect(project.description, 'Household tasks');
      expect(project.color, 'violet');
      expect(project.createdAt, DateTime.parse(created));
      expect(project.updatedAt, DateTime.parse(updated));
      expect(project.archivedAt, isNull);
      expect(
        project.statistics,
        const ProjectStatistics(total: 4, completed: 3, progress: 75),
      );
    });

    test('accepts nullable and missing optional fields', () {
      final project = Project.fromJson(
        {...row(description: null, color: null)}..remove('archived_at'),
      );

      expect(project.description, isNull);
      expect(project.color, isNull);
      expect(project.archivedAt, isNull);
    });

    test('parses archived dates and numeric statistics', () {
      final project = Project.fromJson(
        row(
          archivedAt: '2026-11-11T12:00:00.000Z',
          total: 4.0,
          completed: 3.0,
          progress: 75.0,
        ),
      );

      expect(project.archivedAt, DateTime.parse('2026-11-11T12:00:00.000Z'));
      expect(project.statistics.progress, 75);
    });

    test(
      'rejects malformed required fields instead of making up a project',
      () {
        expect(
          () => Project.fromJson({...row(), 'created_at': 'not-a-date'}),
          throwsFormatException,
        );
        expect(
          () => Project.fromJson({...row(), 'total_tasks': 'four'}),
          throwsFormatException,
        );
      },
    );
  });

  group('project requests', () {
    test('serializes a create request without inventing optional values', () {
      expect(const CreateProjectRequest(name: 'Home').toJson(), {
        'name': 'Home',
      });
      expect(
        const CreateProjectRequest(
          name: 'Home',
          description: 'Household tasks',
          color: 'violet',
        ).toJson(),
        {'name': 'Home', 'description': 'Household tasks', 'color': 'violet'},
      );
    });

    test('distinguishes an omitted update field from an explicit null', () {
      expect(const UpdateProjectRequest(name: 'Renamed').toJson(), {
        'name': 'Renamed',
      });
      expect(
        const UpdateProjectRequest(
          description: PatchValue(null),
          color: PatchValue('green'),
        ).toJson(),
        {'description': null, 'color': 'green'},
      );
    });
  });
}
