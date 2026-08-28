import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_archive.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/task_actions_sheet.dart';
import 'package:todo_app/widgets/subtask_progress.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../utils/task_icons.dart';

/// List of regular (non-repeating) tasks for the "Задачи" tab.
///
/// Tasks are grouped by their scheduled date: overdue, today, upcoming and
/// undated (backlog). Repeating tasks live on the "Привычки" tab instead.
class TasksList extends ConsumerWidget {
  const TasksList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Everything, not just roots: the tiles report how many subtasks are done.
    final tasksAsync = ref.watch(allTasksProvider);
    final logsAsync = ref.watch(allLogsProvider);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return tasksAsync.when(
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
            logByKey[_logKey(t.id, _anchorDate(t))]?.completed ?? false;

        // Subtasks are reported by their parent's tile, never listed on their
        // own — even when they carry a date or a time of their own. A done task
        // whose day has passed is gone from here too: it belongs to the archive
        // now, and [isTaskArchived] is the rule both screens read.
        final regular = allTasks
            .where((t) => t.parentId == null)
            .where((t) => t.status == TaskStatus.active)
            .where((t) => t.repeatType == null)
            .where(
              (t) =>
                  !isTaskArchived(t, completed: isCompleted(t), today: today),
            )
            .toList();

        if (regular.isEmpty) return const _EmptyState();

        // Subtask completion is stored per day against the parent's anchor
        // date — the same date the task's sheet reads and writes — so the
        // count here and the ticks in the sheet can never disagree.
        int subtasksDone(Task parent) {
          final date = _anchorDate(parent);
          return subtasksByParent[parent.id]!
              .where((s) => logByKey[_logKey(s.id, date)]?.completed ?? false)
              .length;
        }

        final overdue = <Task>[];
        final todayTasks = <Task>[];
        final upcoming = <Task>[];
        final undated = <Task>[];

        for (final task in regular) {
          if (task.startDate == null) {
            undated.add(task);
            continue;
          }
          final date = _dateOnly(task.startDate!);
          if (date.isBefore(today)) {
            overdue.add(task);
          } else if (date == today) {
            todayTasks.add(task);
          } else {
            upcoming.add(task);
          }
        }

        int byDoneThenTime(Task a, Task b) {
          final doneA = isCompleted(a), doneB = isCompleted(b);
          if (doneA != doneB) return doneA ? 1 : -1;
          final ta = a.scheduledTimeMinutes ?? 1 << 30;
          final tb = b.scheduledTimeMinutes ?? 1 << 30;
          final c = ta.compareTo(tb);
          return c != 0 ? c : a.title.compareTo(b.title);
        }

        int byDateThenTime(Task a, Task b) {
          final c = a.startDate!.compareTo(b.startDate!);
          return c != 0 ? c : byDoneThenTime(a, b);
        }

        overdue.sort(byDateThenTime);
        todayTasks.sort(byDoneThenTime);
        upcoming.sort(byDateThenTime);
        undated.sort(byDoneThenTime);

        final sections = <Widget>[];
        void addSection(
          String title,
          List<Task> group, {
          bool withDate = false,
        }) {
          if (group.isEmpty) return;
          sections.add(_SectionTitle(title: title, count: group.length));
          for (final task in group) {
            final subtasks = subtasksByParent[task.id] ?? const <Task>[];
            sections.add(
              _TaskTile(
                task: task,
                completed: isCompleted(task),
                showDate: withDate,
                subtaskTotal: subtasks.length,
                subtaskDone: subtasks.isEmpty ? 0 : subtasksDone(task),
                onToggle: () => ref
                    .read(tasksDaoProvider)
                    .toggleCompletion(task.id, _anchorDate(task)),
                onTap: () => showTaskActionsSheet(
                  context,
                  task: task,
                  completed: isCompleted(task),
                ),
              ),
            );
          }
        }

        addSection('Просроченные', overdue, withDate: true);
        addSection('Сегодня', todayTasks);
        addSection('Предстоящие', upcoming, withDate: true);
        addSection('Без даты', undated);

        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return ListView(
          padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 24),
          children: sections,
        );
      },
    );
  }
}

String _logKey(int taskId, DateTime date) {
  final d = _dateOnly(date);
  return '${taskId}_${d.year}-${d.month}-${d.day}';
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// The date a one-off task's completion is logged against.
DateTime _anchorDate(Task task) => _dateOnly(task.startDate ?? task.createdAt);

Color _taskColor(Task task) => task.colorValue != null
    ? Color(task.colorValue!)
    : ColorPickerRow.colors.first;

IconData _taskIcon(Task task) =>
    taskIconFor(task.iconKey) ?? LucideIcons.circle_check;

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
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.completed,
    required this.showDate,
    required this.subtaskTotal,
    required this.subtaskDone,
    required this.onToggle,
    required this.onTap,
  });

  final Task task;
  final bool completed;
  final bool showDate;
  final int subtaskTotal;
  final int subtaskDone;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = rowSurface(theme);
    final color = _taskColor(task);
    // The icon sits in the family's light tone, with the accent on top of it.
    final badge = taskBadgeSurface(theme, color, row);
    final iconColor = inkOn(badge, color, minContrast: 3);
    final subtitle = _subtitle();

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
                          color: completed
                              ? theme.colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.75,
                                )
                              : theme.colorScheme.onSurface,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
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
                _Checkbox(
                  color: iconColor,
                  completed: completed,
                  onToggle: onToggle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _subtitle() {
    final parts = <String>[];
    if (showDate && task.startDate != null) {
      parts.add(DateFormat('d MMM', 'ru_RU').format(task.startDate!));
    }
    if (task.scheduledTimeMinutes != null) {
      final start = _fmtTime(task.scheduledTimeMinutes!);
      final end = task.endTimeMinutes;
      parts.add(
        end != null && end > task.scheduledTimeMinutes!
            ? '$start – ${_fmtTime(end)}'
            : start,
      );
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({
    required this.color,
    required this.completed,
    required this.onToggle,
  });

  final Color color;
  final bool completed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: completed
                ? color
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            width: 2,
          ),
          color: completed ? color.withValues(alpha: 0.15) : null,
        ),
        child: completed
            ? Icon(LucideIcons.check, size: 16, color: color)
            : null,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circle_check,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'Нет задач',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Нажмите + чтобы добавить задачу',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
