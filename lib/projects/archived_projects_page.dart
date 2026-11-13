import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/empty_screen.dart';
import 'package:todo_app/widgets/list_card.dart';

import 'projects_state.dart';

class ArchivedProjectsList extends ConsumerStatefulWidget {
  const ArchivedProjectsList({super.key});

  @override
  ConsumerState<ArchivedProjectsList> createState() =>
      _ArchivedProjectsListState();
}

class _ArchivedProjectsListState extends ConsumerState<ArchivedProjectsList> {
  String? _restoring;
  bool _loading = true;
  Object? _error;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _loadError = false;
    });
    await ref.read(projectsStateProvider.notifier).load(archived: true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = ref.read(projectsStateProvider).error;
      _loadError = _error != null;
    });
  }

  Future<void> _restore(String id) async {
    if (_restoring != null) return;
    setState(() {
      _restoring = id;
      _error = null;
      _loadError = false;
    });
    await ref.read(projectsStateProvider.notifier).restore(id);
    if (!mounted) return;
    setState(() {
      _restoring = null;
      _error = ref.read(projectsStateProvider).error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref
        .watch(projectsStateProvider)
        .archivedProjects
        .where((p) => p.isArchived)
        .toList();
    final Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_loadError) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить архив проектов'),
            TextButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      );
    } else if (projects.isEmpty) {
      content = const EmptyScreen(
        family: 'blue',
        icon: LucideIcons.archive,
        title: 'Архив проектов пуст',
        body: 'Здесь будут храниться архивированные проекты.',
      );
    } else {
      content = ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: projects.length + (_error == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (_error != null && index == 0) {
            return const Text(
              'Не удалось восстановить проект. Попробуйте ещё раз.',
            );
          }
          final project = projects[index - (_error == null ? 0 : 1)];
          final stats = project.statistics;
          final color =
              taskSwatchForKey(project.color)?.accent ??
              Theme.of(context).colorScheme.primary;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RowsCard(
              horizontalMargin: 0,
              children: [
                ListTile(
                  leading: Icon(LucideIcons.folder, color: color),
                  title: Text(
                    project.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${stats.completed} из ${stats.total} задач выполнено · ${stats.progress}%',
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (stats.progress / 100).clamp(0.0, 1.0),
                        color: color,
                        backgroundColor: AppPalette.of(Theme.of(context)).chip,
                      ),
                    ],
                  ),
                  trailing: _restoring == project.id
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: 'Восстановить проект ${project.name}',
                          onPressed: _restoring == null
                              ? () => _restore(project.id)
                              : null,
                          icon: const Icon(LucideIcons.rotate_ccw),
                        ),
                ),
              ],
            ),
          );
        },
      );
    }
    return content;
  }
}
