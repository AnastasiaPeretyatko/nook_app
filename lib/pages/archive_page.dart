import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/task_audience.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/habit_actions_sheet.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../utils/task_icons.dart';

/// The habits put away by hand, i.e. carrying [TaskStatus.archived]: its
/// sheet's "Архив" action. Returning one is a status write and nothing else, so
/// its whole history comes back with it.
///
/// Habits only — a repeating task, and a "Значение" task, which lives on the
/// habits tab too. A one-off task that is ticked belongs to "Выполненные" of the
/// "Задачи" tab, which is where it is looked for.
///
/// Nothing is deleted: the rows and their logs are intact.
/// `deleteTaskCascade`, reachable through the action sheet, is the destructive
/// counterpart.
///
/// Pushed over `MainScreen`, so it covers the bottom navigation bar and the app
/// bar's back arrow is the only way out: the archive is a place you visit, not
/// a fifth tab.
class ArchivePage extends ConsumerWidget {
  const ArchivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(allTasksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Архив')),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (allTasks) {
          final me = ref.watch(myUidProvider);
          final putAway = allTasks
              .where(
                (t) =>
                    t.parentId == null &&
                    isMyTask(t, me) &&
                    t.status == TaskStatus.archived &&
                    (t.repeatType != null || isValueTask(t)),
              )
              .toList();

          if (putAway.isEmpty) return const _EmptyState();

          putAway.sort((a, b) => a.title.compareTo(b.title));
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          return ListView(
            padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 24),
            children: [
              _SectionTitle(title: 'В архиве', count: putAway.length),
              for (final task in putAway)
                _ArchiveTile(
                  task: task,
                  subtitle: _repeatLabel(task),
                  onTap: () => showHabitActionsSheet(context, task: task),
                  trailing: _RestoreButton(
                    color: _tileInk(context, task),
                    onTap: () => ref
                        .read(tasksDaoProvider)
                        .setTaskStatus(task.id, TaskStatus.active),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

Color _taskColor(Task task) => task.colorValue != null
    ? Color(task.colorValue!)
    : ColorPickerRow.colors.first;

IconData _taskIcon(Task task) =>
    taskIconFor(task.iconKey) ?? LucideIcons.circle_check;

/// The task's own colour, darkened until it reads as ink on a row — the same
/// value the tile uses for its icon, so the trailing control matches it.
Color _tileInk(BuildContext context, Task task) {
  final theme = Theme.of(context);
  final row = rowSurface(theme);
  final color = _taskColor(task);
  return inkOn(taskBadgeSurface(theme, color, row), color, minContrast: 3);
}

/// What a put-away row repeats on.
String _repeatLabel(Task task) {
  if (isValueTask(task)) return 'Значение';
  final interval = (task.repeatInterval == null || task.repeatInterval! < 1)
      ? 1
      : task.repeatInterval!;
  return switch (task.repeatType) {
    RepeatType.daily => 'Ежедневно',
    RepeatType.weekly => interval > 1 ? 'Раз в $interval нед.' : 'Еженедельно',
    RepeatType.monthly => interval > 1 ? 'Раз в $interval мес.' : 'Ежемесячно',
    RepeatType.custom => 'Каждые $interval дн.',
    null => 'Разовая задача',
  };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 12, bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppPalette.of(theme).textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.task,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final Task task;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = rowSurface(theme);
    final color = _taskColor(task);
    // The icon sits in the family's light tone, with the accent on top of it.
    final badge = taskBadgeSurface(theme, color, row);
    final iconColor = inkOn(badge, color, minContrast: 3);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: row,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badge,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_taskIcon(task), size: 20, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Takes a put-away task or habit out of the archive: a status write, so the
/// habit lands back on its grid with every logged day still on it.
class _RestoreButton extends StatelessWidget {
  const _RestoreButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Вернуть',
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(LucideIcons.archive_restore, size: 22, color: color),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.archive,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'Архив пуст',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Сюда попадают привычки, убранные в архив',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
