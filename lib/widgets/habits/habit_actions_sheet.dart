import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/habit_day_state.dart';
import 'package:todo_app/widgets/habits/habit_history_sheet.dart';

/// Bottom sheet for a habit (repeating task): title, description, a full-width
/// grid of day squares to mark completion, and edit / archive / delete actions.
Future<void> showHabitActionsSheet(BuildContext context, {required Task task}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (_) => HabitActionsSheet(task: task),
  );
}

class HabitActionsSheet extends ConsumerWidget {
  const HabitActionsSheet({super.key, required this.task});

  final Task task;

  /// Per-action colours: indigo edits, amber archives, red deletes. Read
  /// through [inkOn] so they still read on a dark sheet.
  static const Color _editColor = Color(0xFF4C5CE0);
  static const Color _archiveColor = Color(0xFFB08900);
  static const Color _danger = Color(0xFFE0574C);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sheet = raisedSurface(theme);
    final color = _taskColor(task);

    // Two weeks (previous + current), same window as the small habit card.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentMonday = today.subtract(Duration(days: today.weekday - 1));
    final startMonday = currentMonday.subtract(const Duration(days: 7));
    final days = List.generate(14, (i) => startMonday.add(Duration(days: i)));
    final range = DateRange(
      startMonday,
      startMonday.add(const Duration(days: 14)),
    );

    // The provider streams logs for every task in the window, so filter down to
    // this habit — otherwise the grid shows days completed by other habits.
    final logs =
        ref.watch(logsBetweenProvider(range)).valueOrNull ?? const <TaskLog>[];
    final completedDays = <DateTime>{
      for (final l in logs)
        if (l.taskId == task.id && l.completed)
          DateTime(l.date.year, l.date.month, l.date.day),
    };

    final description = task.description?.trim() ?? '';

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: sheet,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SingleChildScrollView(
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
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'История',
                    onPressed: () => showHabitHistorySheet(context, task: task),
                    icon: Icon(Icons.calendar_month_outlined, color: color),
                    style: IconButton.styleFrom(
                      backgroundColor: color.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _MiniDaysGrid(
                task: task,
                days: days,
                completedDays: completedDays,
                today: today,
                color: color,
                onToggleDay: (day) =>
                    ref.read(tasksDaoProvider).toggleCompletion(task.id, day),
              ),
              const SizedBox(height: 12),
              _DaysLegend(color: color),
              const SizedBox(height: 20),
              Row(
                children: [
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    label: 'Изменить',
                    color: inkOn(sheet, _editColor),
                    onTap: () => _edit(context),
                  ),
                  _ActionButton(
                    icon: Icons.archive_outlined,
                    label: 'Архив',
                    color: inkOn(sheet, _archiveColor),
                    onTap: () => _archive(context, ref),
                  ),
                  _ActionButton(
                    icon: Icons.delete_outline,
                    label: 'Удалить',
                    color: inkOn(sheet, _danger),
                    onTap: () => _confirmDelete(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _edit(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => CreateTaskPage(mode: TaskFormMode.edit, task: task),
      ),
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    await ref
        .read(tasksDaoProvider)
        .updateTaskById(
          task.id,
          TasksCompanion(
            status: const Value(TaskStatus.archived),
            updatedAt: Value(DateTime.now()),
          ),
        );
    navigator.pop();
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить привычку?'),
        content: Text(
          'Привычка «${task.title}» и вся история её выполнения будут удалены '
          'безвозвратно.',
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

class _MiniDaysGrid extends StatelessWidget {
  const _MiniDaysGrid({
    required this.task,
    required this.days,
    required this.completedDays,
    required this.today,
    required this.color,
    required this.onToggleDay,
  });

  final Task task;
  final List<DateTime> days;
  final Set<DateTime> completedDays;
  final DateTime today;
  final Color color;
  final ValueChanged<DateTime> onToggleDay;

  @override
  Widget build(BuildContext context) {
    List<Widget> row(int offset) => [
      for (var i = 0; i < 7; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: _MiniDaySquare(
            state: habitDayState(
              task,
              days[offset + i],
              today: today,
              completedDays: completedDays,
            ),
            markable: isHabitDayMarkable(days[offset + i], today: today),
            color: color,
            onTap: () => onToggleDay(days[offset + i]),
          ),
        ),
      ],
    ];

    return Column(
      children: [
        Row(children: row(0)),
        const SizedBox(height: 6),
        Row(children: row(7)),
      ],
    );
  }
}

class _MiniDaySquare extends StatelessWidget {
  const _MiniDaySquare({
    required this.state,
    required this.markable,
    required this.color,
    required this.onTap,
  });

  final HabitDayState state;
  final bool markable;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final square = state == HabitDayState.off
        ? _offSquare()
        : _scheduledSquare();

    if (!markable) return square;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: square,
    );
  }

  /// A day outside the schedule: just a dot, so an unmarked one never looks like
  /// a miss.
  Widget _offSquare() => AspectRatio(
    aspectRatio: 1,
    child: Center(
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
      ),
    ),
  );

  Widget _scheduledSquare() {
    final (Color fill, Color? border) = switch (state) {
      HabitDayState.done => (color, null),
      HabitDayState.today => (
        color.withValues(alpha: 0.28),
        color.withValues(alpha: 0.9),
      ),
      // Pre-history looks the same as a miss: an empty slot to fill in.
      HabitDayState.missed || HabitDayState.beforeStart => (
        Colors.transparent,
        color.withValues(alpha: 0.5),
      ),
      HabitDayState.upcoming => (color.withValues(alpha: 0.12), null),
      HabitDayState.off => (Colors.transparent, null),
    };

    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(7),
          border: border == null ? null : Border.all(color: border, width: 1.5),
        ),
      ),
    );
  }
}

/// Spells out what the square styles mean, so a hollow day is readable as a miss
/// rather than as an empty slot.
class _DaysLegend extends StatelessWidget {
  const _DaysLegend({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget item(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 5),
        Text(label, style: labelStyle),
      ],
    );

    Widget box({Color? fill, Color? border}) => Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: fill ?? Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: border == null ? null : Border.all(color: border, width: 1.3),
      ),
    );

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(box(fill: color), 'выполнено'),
        item(box(border: color.withValues(alpha: 0.5)), 'пропущено'),
        item(
          Container(
            width: 11,
            alignment: Alignment.center,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
            ),
          ),
          'не в расписании',
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

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
              color: color.withValues(alpha: 0.1),
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
    : Icons.repeat;
