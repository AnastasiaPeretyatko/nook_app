import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/home_widget/today_payload.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/color_picker_row.dart';

/// The complete, local snapshot the configurable project widget can render.
///
/// One shared payload holds every project rather than a payload per widget
/// instance. Android stores only the chosen project id for each widget id; this
/// lets any number of widgets use independent selections while Flutter writes
/// and redraws one coherent snapshot after an edit. The rows are deliberately
/// not capped: Android puts them in a collection view, which scrolls when the
/// widget is shorter than the project list.
class ProjectWidgetPayload {
  const ProjectWidgetPayload({
    required this.projects,
    required this.light,
    required this.dark,
    required this.mode,
  });

  final List<ProjectWidgetProject> projects;
  final WidgetPalette light;
  final WidgetPalette dark;
  final String mode;

  static const payloadVersion = 1;

  String encode() => jsonEncode({
    'version': payloadVersion,
    'mode': mode,
    'palettes': {'light': light.toJson(), 'dark': dark.toJson()},
    'projects': [for (final project in projects) project.toJson()],
  });
}

/// One project in [ProjectWidgetPayload].
///
/// An archived project remains in the data, marked unavailable, so a widget
/// already configured for it can explain what happened and offer its chooser.
/// It is excluded from the chooser itself on Android.
class ProjectWidgetProject {
  const ProjectWidgetProject({
    required this.id,
    required this.name,
    required this.available,
    required this.total,
    required this.done,
    required this.tasks,
  });

  final String id;
  final String name;
  final bool available;
  final int total;
  final int done;
  final List<ProjectWidgetTask> tasks;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'available': available,
    'total': total,
    'done': done,
    'tasks': [for (final task in tasks) task.toJson()],
  };
}

/// A task row of the configurable project widget.
class ProjectWidgetTask {
  const ProjectWidgetTask({
    required this.id,
    required this.title,
    required this.day,
    required this.done,
    required this.color,
    required this.checkInk,
  });

  final int id;
  final String title;

  /// The day `TasksDao.toggleCompletion` must write against. It mirrors the
  /// project detail screen: a task is completed at its start date (or creation
  /// date when it is undated), never at whatever date the widget happens to be
  /// viewed.
  final DateTime day;
  final bool done;
  final int color;
  final int checkInk;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'day': DateFormat('yyyy-MM-dd').format(day),
    'done': done,
    'color': color,
    'checkInk': checkInk,
  };
}

/// Builds the native project's widget model from Nook's existing local mirror.
///
/// Project membership belongs to root tasks; subtasks inherit it through their
/// parent and are intentionally represented by that same project task, exactly
/// as the project details screen does. No task state is copied or owned here:
/// completion is read from task logs and a widget tick still goes through the
/// existing DAO action.
ProjectWidgetPayload buildProjectWidgetPayload({
  required List<LocalProject> projects,
  required List<Task> tasks,
  required List<TaskLog> logs,
  required WidgetPalette light,
  required WidgetPalette dark,
  required String mode,
}) {
  final rootTasks = [
    for (final task in tasks)
      if (task.parentId == null) task,
  ];

  final projectsInOrder = [...projects]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return ProjectWidgetPayload(
    projects: [
      for (final project in projectsInOrder)
        _projectPayload(project, rootTasks, logs),
    ],
    light: light,
    dark: dark,
    mode: mode,
  );
}

ProjectWidgetProject _projectPayload(
  LocalProject project,
  List<Task> rootTasks,
  List<TaskLog> logs,
) {
  final members = [
    for (final task in rootTasks)
      if (task.projectUid == project.id) task,
  ]..sort(byTimeThenTitle);

  final rows = [for (final task in members) _taskPayload(task, logs)];
  final done = rows.where((task) => task.done).length;

  return ProjectWidgetProject(
    id: project.id,
    name: project.name,
    available: project.archivedAt == null,
    total: rows.length,
    done: done,
    tasks: rows,
  );
}

ProjectWidgetTask _taskPayload(Task task, List<TaskLog> logs) {
  final sourceDay = task.startDate ?? task.createdAt;
  final day = DateTime(sourceDay.year, sourceDay.month, sourceDay.day);
  final done = logs.any(
    (log) =>
        log.taskId == task.id &&
        log.completed &&
        log.date.year == day.year &&
        log.date.month == day.month &&
        log.date.day == day.day,
  );
  final color = task.colorValue != null
      ? Color(task.colorValue!)
      : ColorPickerRow.colors.first;

  return ProjectWidgetTask(
    id: task.id,
    title: task.title,
    day: day,
    done: done,
    color: color.toARGB32(),
    checkInk: onBrandFill(color).toARGB32(),
  );
}
