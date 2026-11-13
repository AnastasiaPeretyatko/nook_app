import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/home_widget/project_payload.dart';
import 'package:todo_app/home_widget/today_payload.dart';
import 'package:todo_app/main.dart' show buildAppTheme;

final _stamp = DateTime(2026, 1, 1);
final _light = WidgetPalette.fromScheme(
  buildAppTheme(const Color(0xFF8B7CF6), Brightness.light).colorScheme,
);
final _dark = WidgetPalette.fromScheme(
  buildAppTheme(const Color(0xFF8B7CF6), Brightness.dark).colorScheme,
);

LocalProject _project({
  String id = 'home',
  String name = 'Дом',
  DateTime? archivedAt,
}) => LocalProject(
  id: id,
  name: name,
  createdAt: _stamp,
  updatedAt: _stamp,
  archivedAt: archivedAt,
  dirty: false,
);

Section _section({
  String id = 'chores',
  String name = 'Быт',
  String projectId = 'home',
  int position = 0,
}) => Section(
  id: id,
  userId: 'user-1',
  projectId: projectId,
  name: name,
  position: position,
  createdAt: _stamp,
  updatedAt: _stamp,
  dirty: false,
);

Task _task({
  int id = 1,
  String title = 'Разобрать шкаф',
  String? projectUid = 'home',
  String? sectionId,
  int? parentId,
  int? scheduledTimeMinutes,
  DateTime? startDate,
  int? colorValue,
}) => Task(
  id: id,
  dirty: false,
  title: title,
  projectUid: projectUid,
  sectionId: sectionId,
  parentId: parentId,
  status: TaskStatus.active,
  trackingMode: TrackingMode.checkbox,
  scheduledTimeMinutes: scheduledTimeMinutes,
  colorValue: colorValue,
  startDate: startDate ?? DateTime(2026, 8, 27),
  createdAt: _stamp,
  updatedAt: _stamp,
);

TaskLog _log({int id = 1, int taskId = 1, DateTime? date}) => TaskLog(
  id: id,
  taskId: taskId,
  date: date ?? DateTime(2026, 8, 27),
  completed: true,
  dirty: false,
  updatedAt: _stamp,
);

ProjectWidgetPayload _payload({
  List<LocalProject>? projects,
  List<Section> sections = const [],
  List<Task>? tasks,
  List<TaskLog> logs = const [],
}) => buildProjectWidgetPayload(
  projects: projects ?? [_project()],
  sections: sections,
  tasks: tasks ?? [_task()],
  logs: logs,
  light: _light,
  dark: _dark,
  mode: 'system',
);

void main() {
  group('project home widget payload', () {
    test('keeps every root task in its section without a row cap', () {
      final payload = _payload(
        tasks: [
          for (var id = 1; id <= 25; id++)
            _task(id: id, title: 'Задача $id', scheduledTimeMinutes: id),
          _task(id: 26, title: 'Подзадача', parentId: 1),
          _task(id: 27, title: 'Другой проект', projectUid: 'work'),
        ],
      );

      final tasks = payload.projects.single.sections.single.tasks;
      expect(tasks, hasLength(25));
      expect(tasks.map((task) => task.id), [
        for (var id = 1; id <= 25; id++) id,
      ]);
    });

    test('uses each task anchor date for completion and its toggle action', () {
      final secondDay = DateTime(2026, 8, 28);
      final payload = _payload(
        tasks: [
          _task(id: 1, title: 'Сегодня'),
          _task(id: 2, title: 'Завтра', startDate: secondDay),
        ],
        logs: [_log(taskId: 2, date: secondDay)],
      );

      final project = payload.projects.single;
      expect(project.done, 1);
      expect(project.total, 2);
      expect(project.sections.single.tasks.map((task) => task.id), [2, 1]);
      expect(project.sections.single.tasks.first.done, isTrue);
    });

    test('raises progress when a task is marked complete', () {
      final tasks = [
        _task(id: 1, title: 'Первая'),
        _task(id: 2, title: 'Вторая'),
      ];
      final before = _payload(tasks: tasks).projects.single;
      final after = _payload(
        tasks: tasks,
        logs: [_log(taskId: 2)],
      ).projects.single;

      expect((before.done, before.total), (0, 2));
      expect((after.done, after.total), (1, 2));
      expect(after.sections.single.tasks.map((task) => task.id), [2, 1]);
      expect(after.sections.single.tasks.first.done, isTrue);

      final json =
          jsonDecode(_payload(tasks: tasks, logs: [_log(taskId: 2)]).encode())
              as Map<String, Object?>;
      final project = (json['projects'] as List).single as Map<String, Object?>;
      expect((project['done'], project['total']), (1, 2));
    });

    test('keeps task order unchanged when another task completes', () {
      final tasks = [
        _task(id: 1, title: 'Раньше', scheduledTimeMinutes: 9 * 60),
        _task(id: 2, title: 'Позже', scheduledTimeMinutes: 10 * 60),
        _task(id: 3, title: 'Без времени'),
      ];

      final before = _payload(
        tasks: tasks,
      ).projects.single.sections.single.tasks;
      final after = _payload(
        tasks: tasks,
        logs: [_log(taskId: 2)],
      ).projects.single.sections.single.tasks;

      expect(before.map((task) => task.id), [1, 2, 3]);
      expect(after.map((task) => task.id), [1, 2, 3]);
      expect(after[1].done, isTrue);
    });

    test(
      'retains an archived project as unavailable for an existing widget',
      () {
        final payload = _payload(
          projects: [
            _project(),
            _project(
              id: 'old',
              name: 'Архив',
              archivedAt: DateTime(2026, 8, 1),
            ),
          ],
          tasks: [_task(projectUid: 'old')],
        );

        final archived = payload.projects.singleWhere(
          (project) => project.id == 'old',
        );
        expect(archived.available, isFalse);
        expect(archived.sections.single.tasks, hasLength(1));
      },
    );

    test('encodes a stable native payload with palettes and task metadata', () {
      final json =
          jsonDecode(_payload(tasks: [_task(colorValue: 0xFFF4C95D)]).encode())
              as Map<String, Object?>;
      final project = (json['projects'] as List).single as Map<String, Object?>;
      final section =
          (project['sections'] as List).single as Map<String, Object?>;
      final task = (section['tasks'] as List).single as Map<String, Object?>;

      expect(json['version'], ProjectWidgetPayload.payloadVersion);
      expect(
        (json['palettes'] as Map<String, Object?>).keys,
        containsAll(['light', 'dark']),
      );
      expect(project['available'], isTrue);
      expect(project['total'], 1);
      expect(task, containsPair('day', '2026-08-27'));
      expect(task, containsPair('color', 0xFFF4C95D));
      expect(task, contains('checkInk'));
    });

    test('shows every named section and all its root tasks', () {
      final project = _payload(
        sections: [
          _section(id: 'later', name: 'Позже', position: 1),
          _section(id: 'now', name: 'Сейчас'),
          _section(id: 'empty', name: 'Пусто', position: 2),
        ],
        tasks: [
          _task(id: 1, title: 'Открытая', sectionId: 'now'),
          _task(id: 2, title: 'Закрытая', sectionId: 'now'),
          _task(id: 3, title: 'Без раздела'),
          _task(id: 4, title: 'В другом проекте', projectUid: 'work'),
          _task(id: 5, title: 'Подзадача', parentId: 1, sectionId: 'now'),
        ],
        logs: [_log(taskId: 2)],
      ).projects.single;

      expect(project.sections.map((section) => section.name), [
        'Сейчас',
        'Позже',
        'Пусто',
        'Без раздела',
      ]);
      expect(project.sections[0].tasks.map((task) => task.title), [
        'Закрытая',
        'Открытая',
      ]);
      expect(project.sections[0].tasks.first.done, isTrue);
      expect(project.sections[1].tasks, isEmpty);
      expect(project.sections[2].tasks, isEmpty);
      expect(project.sections[3].tasks.map((task) => task.title), [
        'Без раздела',
      ]);
    });
  });
}
