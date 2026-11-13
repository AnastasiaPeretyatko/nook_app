import 'package:flutter/material.dart';
import 'package:todo_app/projects/projects_tab.dart';

/// The top-level projects screen, separate from the task list.
class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SafeArea(bottom: false, child: ProjectsTab()));
}
