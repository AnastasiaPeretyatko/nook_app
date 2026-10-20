import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/task_audience.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_archive.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/habit_actions_sheet.dart';
import 'package:todo_app/widgets/habits/task_actions_sheet.dart';
import 'package:todo_app/widgets/subtask_progress.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../utils/task_icons.dart';

/// Everything the app is done showing on its own screens, in two groups.
///
/// * "В архиве" — tasks and habits put away by hand, i.e. carrying
///   [TaskStatus.archived]. A habit is the only thing that can get there today:
///   its sheet's "Архив" action. Returning one is a status write and nothing
///   else, so its whole history comes back with it.
/// * "Выполненные" — one-off tasks that are ticked and whose day has passed,
///   see [isTaskArchived]. Nothing was written to put them here, so un-ticking
///   one is all it takes to send it back to the "Задачи" tab.
///
/// Neither group is deleted: the rows and their logs are intact and the
/// timeline still draws a completed task on its day. `deleteTaskCascade`,
/// reachable through both action sheets, is the destructive counterpart.
///
/// Pushed over `MainScreen`, so it covers the bottom navigation bar and the app
/// bar's back arrow is the only way out: the archive is a place you visit, not
/// a fifth tab.
class ArchivePage extends ConsumerWidget {
  const ArchivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Everything, not just roots: the tiles report how many subtasks are done.
    final tasksAsync = ref.watch(allTasksProvider);
    final logsAsync = ref.watch(allLogsProvider);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Scaffold(
      appBar: AppBar(title: const Text('Архив')),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (allTasks) {
          final subtasksByParent = <int, List<Task>>{};
          for (final task in allTasks) {
            final parentId = task.parentId;
            if (parentId != null) {
              subtasksByParent.putIfAbsent(parentId, () => []).add(task);
            }
          }

          final logs = logsAsync.valueOrNull ?? const <TaskLog>[];
          final logByKey = <String, TaskLog>{
            for (final l in logs) _logKey(l.taskId, l.date): l,
          };

          bool isCompleted(Task t) =>
              logByKey[_logKey(t.id, taskAnchorDate(t))]?.completed ?? false;

          // Subtask completion is stored against the parent's anchor date, the
          // same date the tile above it is ticked on.
          int subtasksDone(Task parent) {
            final date = taskAnchorDate(parent);
            return subtasksByParent[parent.id]!
                .where((s) => logByKey[_logKey(s.id, date)]?.completed ?? false)
                .length;
          }

          final me = ref.watch(myUidProvider);
          final roots = allTasks.where(
            (t) => t.parentId == null && isMyTask(t, me),
          );

          final putAway = roots
              .where((t) => t.status == TaskStatus.archived)
              .toList();
          final done = roots
              .where((t) => t.status == TaskStatus.active)
              .where(
                (t) =>
                    isTaskArchived(t, completed: isCompleted(t), today: today),
              )
              .toList();

          if (putAway.isEmpty && done.isEmpty) return const _EmptyState();

          putAway.sort((a, b) => a.title.compareTo(b.title));
          // The most recently finished day first: an archive is read from the
          // top down, unlike the tab it came from.
          done.sort((a, b) {
            final c = taskAnchorDate(b).compareTo(taskAnchorDate(a));
            if (c != 0) return c;
            final ta = a.scheduledTimeMinutes ?? 1 << 30;
            final tb = b.scheduledTimeMinutes ?? 1 << 30;
            final t = ta.compareTo(tb);
            return t != 0 ? t : a.title.compareTo(b.title);
          });

          final children = <Widget>[];

          if (putAway.isNotEmpty) {
            children.add(
              _SectionTitle(title: 'В архиве', count: putAway.length),
            );
            for (final task in putAway) {
              children.add(
                _ArchiveTile(
                  task: task,
                  subtitle: _repeatLabel(task),
                  struckThrough: false,
                  onTap: () => task.repeatType != null || isValueTask(task)
                      ? showHabitActionsSheet(context, task: task)
                      : showTaskActionsSheet(
                          context,
                          task: task,
                          completed: isCompleted(task),
                        ),
                  trailing: _RestoreButton(
                    color: _tileInk(context, task),
                    onTap: () => ref
                        .read(tasksDaoProvider)
                        .setTaskStatus(task.id, TaskStatus.active),
                  ),
                ),
              );
            }
          }

          if (done.isNotEmpty) {
            children.add(
              _SectionTitle(title: 'Выполненные', count: done.length),
            );
            DateTime? heading;
            for (final task in done) {
              final date = taskAnchorDate(task);
              if (heading != date) {
                heading = date;
                children.add(_DateHeading(date: date, today: today));
              }
              final subtasks = subtasksByParent[task.id] ?? const <Task>[];
              children.add(
                _ArchiveTile(
                  task: task,
                  subtitle: _timeLabel(task),
                  struckThrough: true,
                  subtaskTotal: subtasks.length,
                  subtaskDone: subtasks.isEmpty ? 0 : subtasksDone(task),
                  onTap: () => showTaskActionsSheet(
                    context,
                    task: task,
                    completed: true,
                  ),
                  trailing: _RestoreCheckbox(
                    color: _tileInk(context, task),
                    onTap: () => ref
                        .read(tasksDaoProvider)
                        .toggleCompletion(task.id, taskAnchorDate(task)),
                  ),
                ),
              );
            }
          }

          final bottomInset = MediaQuery.paddingOf(context).bottom;
          return ListView(
            padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 24),
            children: children,
          );
        },
      ),
    );
  }
}

String _logKey(int taskId, DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return '${taskId}_${d.year}-${d.month}-${d.day}';
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

/// What a put-away row repeats on, so a habit is told apart from a one-off task
/// inside the same group.
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

String? _timeLabel(Task task) {
  final start = task.scheduledTimeMinutes;
  if (start == null) return null;
  final end = task.endTimeMinutes;
  return end != null && end > start
      ? '${_fmtTime(start)} – ${_fmtTime(end)}'
      : _fmtTime(start);
}

String _fmtTime(int minutes) {
  final normalized = minutes % (24 * 60);
  final h = (normalized ~/ 60).toString().padLeft(2, '0');
  final m = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m';
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

/// The day a group of completed tasks belongs to — a rung below
/// [_SectionTitle], so the two levels stay apart. The year is spelled out only
/// when it is not the current one, so a fresh archive stays short.
class _DateHeading extends StatelessWidget {
  const _DateHeading({required this.date, required this.today});

  final DateTime date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pattern = date.year == today.year ? 'd MMMM' : 'd MMMM yyyy';
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
      child: Text(
        DateFormat(pattern, 'ru_RU').format(date),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.task,
    required this.subtitle,
    required this.struckThrough,
    required this.trailing,
    required this.onTap,
    this.subtaskTotal = 0,
    this.subtaskDone = 0,
  });

  final Task task;
  final String? subtitle;

  /// Set for a task that is here because it is done. A habit put away by hand
  /// is not crossed out — it was never finished, only shelved.
  final bool struckThrough;
  final Widget trailing;
  final VoidCallback onTap;
  final int subtaskTotal;
  final int subtaskDone;

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
                          color: struckThrough
                              ? theme.colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.75,
                                )
                              : theme.colorScheme.onSurface,
                          decoration: struckThrough
                              ? TextDecoration.lineThrough
                              : null,
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
                      if (subtaskTotal > 0) ...[
                        const SizedBox(height: 6),
                        SubtaskProgress(done: subtaskDone, total: subtaskTotal),
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

/// Un-ticks a completed task, which is all it takes to send it back to the tab
/// it came from — being done is the only thing that put it here.
class _RestoreCheckbox extends StatelessWidget {
  const _RestoreCheckbox({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          color: color.withValues(alpha: 0.15),
        ),
        child: Icon(LucideIcons.check, size: 16, color: color),
      ),
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
              'Сюда попадают привычки, убранные в архив, и выполненные задачи, '
              'чей день уже прошёл',
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
