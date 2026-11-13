import 'package:flutter/material.dart';
import 'package:todo_app/projects/projects_tab.dart';
import 'package:todo_app/widgets/habits/tasks_list.dart';
import 'package:todo_app/widgets/segmented_switch.dart';

/// The "Задачи" tab, with one-off tasks and projects under its own switch.
/// Each view owns its header and content state; this page only owns the chosen
/// segment.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.onProjectsViewChanged});

  final ValueChanged<bool>? onProjectsViewChanged;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  int _view = 0;

  void _setView(int view) {
    setState(() => _view = view);
    widget.onProjectsViewChanged?.call(view == 1);
  }

  Widget _switch() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
    child: SegmentedSwitch(
      labels: const ['Задачи', 'Проекты'],
      selected: _view,
      onChanged: _setView,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: _view == 0
          ? TasksList(headerFooter: _switch())
          : ProjectsTab(headerFooter: _switch()),
    ),
  );
}
