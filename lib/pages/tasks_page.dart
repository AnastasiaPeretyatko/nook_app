import 'package:flutter/material.dart';
import 'package:todo_app/widgets/habits/tasks_list.dart';

/// The "Задачи" tab: the one-off tasks. It used to be the second tab inside the
/// habits screen; the "Иней" navigation gives it a tab of its own. The header
/// lives in [TasksList], which is what counts the active tasks it names.
class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SafeArea(bottom: false, child: TasksList()));
  }
}
