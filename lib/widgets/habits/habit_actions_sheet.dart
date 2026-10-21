import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/utils/week.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/habit_day_state.dart';
import 'package:todo_app/widgets/habits/habit_history_sheet.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../utils/task_icons.dart';

/// Bottom sheet for a habit (repeating task): title, description, a full-width
/// grid of day squares to mark completion, and edit / archive / delete actions.
/// A habit that is already archived gets "Вернуть" in place of "Архив", so the
/// archive page can hand it back through the very same sheet.
///
/// A "Значение" task opens the same sheet with its body swapped: no day squares
/// — it has no days — but when it was last done, a way to mark today or any other
/// day, and the latest marks to take a wrong one back.
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
    final currentMonday = startOfWeek(today, ref.watch(weekStartProvider));
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
    final late = lateDays(task, logs, ref.watch(lateGraceMinutesProvider));

    final description = task.description?.trim() ?? '';
    final archived = task.status == TaskStatus.archived;
    final isValue = isValueTask(task);

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
                  // The calendar of the history draws a repeat rule's days; a
                  // "Значение" task has none, and lists its marks below instead.
                  if (!isValue) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'История',
                      onPressed: () =>
                          showHabitHistorySheet(context, task: task),
                      icon: Icon(LucideIcons.calendar_days, color: color),
                      style: IconButton.styleFrom(
                        backgroundColor: color.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
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
              if (isValue)
                _ValueBody(task: task, color: color, sheet: sheet, today: today)
              else ...[
                _MiniDaysGrid(
                  task: task,
                  days: days,
                  completedDays: completedDays,
                  lateDays: late,
                  todayStaysOpen: ref.watch(todayStaysOpenProvider),
                  today: today,
                  color: color,
                  onToggleDay: (day) =>
                      ref.read(tasksDaoProvider).toggleCompletion(task.id, day),
                ),
                const SizedBox(height: 12),
                _DaysLegend(
                  color: color,
                  showLate: task.scheduledTimeMinutes != null,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  _ActionButton(
                    icon: LucideIcons.pencil,
                    label: 'Изменить',
                    color: inkOn(sheet, _editColor),
                    onTap: () => _edit(context),
                  ),
                  // The same slot both ways: a habit already in the archive
                  // offers the way back instead of a second trip there.
                  _ActionButton(
                    icon: archived
                        ? LucideIcons.archive_restore
                        : LucideIcons.archive,
                    label: archived ? 'Вернуть' : 'Архив',
                    color: inkOn(sheet, _archiveColor),
                    onTap: () => _setArchived(context, ref, !archived),
                  ),
                  _ActionButton(
                    icon: LucideIcons.trash_2,
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
    Navigator.of(context).pop();
    showCreateTaskSheet(context, mode: TaskFormMode.edit, task: task);
  }

  Future<void> _setArchived(
    BuildContext context,
    WidgetRef ref,
    bool archived,
  ) async {
    final navigator = Navigator.of(context);
    await ref
        .read(tasksDaoProvider)
        .setTaskStatus(
          task.id,
          archived ? TaskStatus.archived : TaskStatus.active,
        );
    navigator.pop();
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    final confirmed = await showConfirmDialog(
      context,
      icon: DialogIcons.delete,
      title: isValueTask(task) ? 'Удалить отслеживание?' : 'Удалить привычку?',
      body: isValueTask(task)
          ? '«${task.title}» и все отметки будут удалены безвозвратно.'
          : 'Привычка «${task.title}» и вся история её выполнения будут '
                'удалены безвозвратно.',
      action: 'Удалить',
    );

    if (confirmed == true) {
      final dao = ref.read(tasksDaoProvider);
      final deleted = await dao.deleteTaskCascade(task.id);
      navigator.pop();
      if (deleted != null) {
        showAppToast(
          overlay,
          message: isValueTask(task)
              ? 'Отслеживание удалено'
              : 'Привычка удалена',
          actionLabel: 'Отменить',
          onAction: () => dao.restoreDeleted(deleted),
        );
      }
    }
  }
}

/// How many of the latest marks the sheet lists. The rest are still stored and
/// still count towards "last done"; the list is only there to undo a slip.
const _recentMarksShown = 5;

/// The body of the sheet for a "Значение" task.
class _ValueBody extends ConsumerWidget {
  const _ValueBody({
    required this.task,
    required this.color,
    required this.sheet,
    required this.today,
  });

  final Task task;
  final Color color;
  final Color sheet;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ink = inkOn(sheet, color, minContrast: 3);
    final logs =
        ref.watch(logsForTaskProvider(task.id)).valueOrNull ??
        const <TaskLog>[];
    final marked = markedDaysNewestFirst(logs, task.id);
    final lastDone = marked.isEmpty ? null : marked.first;
    final doneToday = lastDone == today;
    final fullDate = DateFormat('d MMMM y', 'ru_RU');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          lastDoneLabel(lastDone, today: today),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          lastDone == null
              ? 'Слежу с ${fullDate.format(taskAnchorDate(task))}'
              : fullDate.format(lastDone),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _ActionButton(
              icon: doneToday ? LucideIcons.undo_2 : LucideIcons.check,
              label: doneToday ? 'Снять за сегодня' : 'Отметить сегодня',
              color: ink,
              onTap: () => ref
                  .read(tasksDaoProvider)
                  .setLog(task.id, today, completed: !doneToday),
            ),
            _ActionButton(
              icon: LucideIcons.calendar_plus,
              label: 'Другая дата',
              color: ink,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: today,
                  firstDate: DateTime(2020),
                  lastDate: today,
                  locale: const Locale('ru', 'RU'),
                );
                if (picked != null) {
                  await ref
                      .read(tasksDaoProvider)
                      .setLog(task.id, picked, completed: true);
                }
              },
            ),
          ],
        ),
        if (marked.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Последние отметки',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final day in marked.take(_recentMarksShown))
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${fullDate.format(day)} · '
                    '${lastDoneLabel(day, today: today).toLowerCase()}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Убрать отметку',
                  onPressed: () => ref
                      .read(tasksDaoProvider)
                      .setLog(task.id, day, completed: false),
                  icon: Icon(
                    LucideIcons.x,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
        ],
      ],
    );
  }
}

class _MiniDaysGrid extends StatelessWidget {
  const _MiniDaysGrid({
    required this.task,
    required this.days,
    required this.completedDays,
    required this.lateDays,
    required this.todayStaysOpen,
    required this.today,
    required this.color,
    required this.onToggleDay,
  });

  final Task task;
  final List<DateTime> days;
  final Set<DateTime> completedDays;
  final Set<DateTime> lateDays;
  final bool todayStaysOpen;
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
              lateDays: lateDays,
              todayStaysOpen: todayStaysOpen,
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
      // The same square, paler: ticked, but after the time it was meant for.
      HabitDayState.late => (color.withValues(alpha: 0.5), null),
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
  const _DaysLegend({required this.color, required this.showLate});

  final Color color;

  /// Only a habit with a time can be late.
  final bool showLate;

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
        if (showLate)
          item(box(fill: color.withValues(alpha: 0.5)), 'с опозданием'),
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

IconData _taskIcon(Task task) =>
    taskIconFor(task.iconKey) ?? LucideIcons.repeat;
