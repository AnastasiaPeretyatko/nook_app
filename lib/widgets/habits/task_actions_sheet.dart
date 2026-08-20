import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';

/// Shows the bottom action sheet for a single task: full title, its subtasks
/// (if any) and the edit / delete / clone / done actions.
Future<void> showTaskActionsSheet(
  BuildContext context, {
  required Task task,
  required bool completed,
  DateTime? completionDate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => TaskActionsSheet(
      task: task,
      completed: completed,
      completionDate: completionDate,
    ),
  );
}

class TaskActionsSheet extends ConsumerWidget {
  const TaskActionsSheet({
    super.key,
    required this.task,
    required this.completed,
    this.completionDate,
  });

  final Task task;
  final bool completed;

  /// Date the "done" action toggles completion for. Defaults to the task's
  /// own anchor date; screens showing a specific day (e.g. Home) pass it in.
  final DateTime? completionDate;

  /// Per-action colours: indigo edits, red deletes, green confirms. Read through
  /// [inkOn] so they still read on a dark sheet.
  static const Color _accent = Color(0xFF4C5CE0);
  static const Color _danger = Color(0xFFE0574C);
  static const Color _done = Color(0xFF3EA34B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sheet = raisedSurface(theme);
    final accent = inkOn(sheet, _accent);
    final danger = inkOn(sheet, _danger);
    final color = _taskColor(task);
    final subtasksAsync = ref.watch(subtasksProvider(task.id));
    final subtasks = subtasksAsync.valueOrNull ?? const <Task>[];

    // Subtask completion is stored per day, exactly like the parent's, so the
    // ticks read from the same date the sheet acts on.
    final date = completionDate ?? _anchorDate(task);
    final logs =
        ref.watch(logsForDateProvider(date)).valueOrNull ?? const <TaskLog>[];
    final doneSubtaskIds = <int>{
      for (final log in logs)
        if (log.completed) log.taskId,
    };

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: raisedSurface(theme),
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: taskBadgeSurface(theme, color, sheet),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _taskIcon(task),
                    size: 22,
                    color: inkOn(
                      taskBadgeSurface(theme, color, sheet),
                      color,
                      minContrast: 3,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    task.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            if (subtasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SubtasksList(
                subtasks: subtasks,
                accent: color,
                doneIds: doneSubtaskIds,
                onToggle: (subtask) => ref
                    .read(tasksDaoProvider)
                    .toggleCompletion(subtask.id, date),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                _ActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Изменить',
                  color: accent,
                  onTap: () => _openForm(context, TaskFormMode.edit),
                ),
                _ActionButton(
                  icon: Icons.copy_all_outlined,
                  label: 'Копия',
                  color: accent,
                  onTap: () => _openForm(context, TaskFormMode.clone),
                ),
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: 'Удалить',
                  color: danger,
                  onTap: () => _confirmDelete(context, ref),
                ),
                _ActionButton(
                  icon: completed
                      ? Icons.check_circle
                      : Icons.check_circle_outline,
                  label: completed ? 'Готово' : 'Выполнить',
                  color: completed ? inkOn(sheet, _done) : accent,
                  filled: !completed,
                  onTap: () => _toggleDone(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openForm(BuildContext context, TaskFormMode mode) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => CreateTaskPage(mode: mode, task: task),
      ),
    );
  }

  Future<void> _toggleDone(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final date = completionDate ?? _anchorDate(task);
    await ref.read(tasksDaoProvider).toggleCompletion(task.id, date);
    navigator.pop();
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text(
          'Задача «${task.title}» и её подзадачи будут удалены безвозвратно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: _danger),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(tasksDaoProvider).deleteTaskCascade(task.id);
      navigator.pop();
    }
  }
}

class _SubtasksList extends StatelessWidget {
  const _SubtasksList({
    required this.subtasks,
    required this.accent,
    required this.doneIds,
    required this.onToggle,
  });

  final List<Task> subtasks;
  final Color accent;
  final Set<int> doneIds;
  final ValueChanged<Task> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: insetSurface(theme),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final subtask in subtasks)
            _SubtaskTile(
              subtask: subtask,
              accent: accent,
              done: doneIds.contains(subtask.id),
              onToggle: () => onToggle(subtask),
              style: theme.textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}

/// One subtask, tickable straight from the sheet. The whole row is the target, so
/// the tap does not have to land on the small box.
class _SubtaskTile extends StatelessWidget {
  const _SubtaskTile({
    required this.subtask,
    required this.accent,
    required this.done,
    required this.onToggle,
    required this.style,
  });

  final Task subtask;
  final Color accent;
  final bool done;
  final VoidCallback onToggle;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: done
                      ? accent
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.55,
                        ),
                  width: 1.6,
                ),
              ),
              child: done
                  ? Icon(Icons.check, size: 14, color: onTaskColor(accent))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subtask.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(
                  color: done
                      ? theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        )
                      : theme.colorScheme.onSurface,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: filled
                  ? color.withValues(alpha: 0.12)
                  : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _taskColor(Task task) => task.colorValue != null
    ? Color(task.colorValue!)
    : ColorPickerRow.colors.first;

IconData _taskIcon(Task task) => task.iconCodePoint != null
    // ignore: non_const_argument_for_const_parameter
    ? IconData(task.iconCodePoint!, fontFamily: 'MaterialIcons')
    : Icons.check_circle_outline;

DateTime _anchorDate(Task task) {
  final d = task.startDate ?? task.createdAt;
  return DateTime(d.year, d.month, d.day);
}
