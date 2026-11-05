import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/task_icons.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/app_toast.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/date_range_calendar.dart';
import 'package:todo_app/widgets/habits/month_calendar_grid.dart';
import 'package:todo_app/widgets/page_header.dart';

/// The arithmetic mean of the calendar-day gaps between consecutive marks.
///
/// Time components are discarded and duplicate dates count as one completion.
/// UTC calendar dates keep the result independent of daylight-saving changes.
double? averageCompletionIntervalDays(Iterable<DateTime> completionDates) {
  final dates = <DateTime>{
    for (final date in completionDates)
      DateTime.utc(date.year, date.month, date.day),
  }.toList()..sort();
  if (dates.length < 2) return null;

  var totalDays = 0;
  for (var index = 1; index < dates.length; index++) {
    totalDays += dates[index].difference(dates[index - 1]).inDays;
  }
  return totalDays / (dates.length - 1);
}

enum CompletionSortOrder { newestFirst, oldestFirst }

/// Completion dates ordered by their calendar date, never by log metadata.
List<DateTime> sortCompletionDates(
  Iterable<DateTime> completionDates,
  CompletionSortOrder order,
) {
  final dates = <DateTime>{
    for (final date in completionDates)
      DateTime(date.year, date.month, date.day),
  }.toList();
  dates.sort(
    order == CompletionSortOrder.newestFirst
        ? (a, b) => b.compareTo(a)
        : (a, b) => a.compareTo(b),
  );
  return dates;
}

const _recentMarksShown = 5;

/// Details and marks for a task tracked as a "Value".
///
/// Unlike a habit, a value has no schedule or completion statistics. Its
/// history answers one question: when was this action performed last?
class ValueDetailPage extends ConsumerWidget {
  const ValueDetailPage({super.key, required this.taskId});

  final int taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final task = ref
        .watch(rootTasksProvider)
        .valueOrNull
        ?.where((task) => task.id == taskId)
        .firstOrNull;

    if (task == null) {
      return Scaffold(
        backgroundColor: palette.background,
        body: const SafeArea(child: BackHeader(title: 'Значение')),
      );
    }

    final logs =
        ref.watch(logsForTaskProvider(taskId)).valueOrNull ?? const <TaskLog>[];
    final marked = markedDaysNewestFirst(logs, taskId);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDone = marked.firstOrNull;
    final averageInterval = averageCompletionIntervalDays(marked);
    final doneToday = lastDone == today;
    final color = task.colorValue != null
        ? Color(task.colorValue!)
        : ColorPickerRow.colors.first;
    final badge = taskBadgeSurface(theme, color, palette.surface);
    final ink = taskBadgeInk(theme, color, badge);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            BackHeader(
              title: 'Значение',
              trailing: RoundIconButton(
                icon: LucideIcons.pencil,
                tooltip: 'Редактировать',
                onPressed: () => showCreateTaskSheet(
                  context,
                  mode: TaskFormMode.edit,
                  task: task,
                ),
              ),
            ),
            _ValueTitle(task: task, badge: badge, ink: ink),
            const SizedBox(height: 16),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'С последнего выполнения',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastDoneLabel(lastDone, today: today),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        color: palette.textSecondary,
                        size: 17.0,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lastDone == null
                              ? 'Слежу с ${_fullDate.format(taskAnchorDate(task))}'
                              : _fullDate.format(lastDone),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _MarkButton(
                        icon: doneToday
                            ? LucideIcons.undo_2
                            : LucideIcons.check,
                        label: doneToday
                            ? 'Снять за сегодня'
                            : 'Отметить сегодня',
                        color: ink,
                        onTap: () => ref
                            .read(tasksDaoProvider)
                            .setLog(taskId, today, completed: !doneToday),
                      ),
                      const SizedBox(width: 8),
                      _MarkButton(
                        icon: LucideIcons.calendar_plus,
                        label: 'Другая дата',
                        color: ink,
                        onTap: () => _pickDate(context, ref, today),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatisticsCard(
                        key: const ValueKey('value-total-stat-card'),
                        title: 'Всего выполнений',
                        value: marked.length.toString(),
                        caption: 'За всё время',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatisticsCard(
                        key: const ValueKey('value-average-stat-card'),
                        title: 'Средний интервал',
                        value: _averageIntervalLabel(averageInterval),
                        caption: 'Между отметками',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ValueMonthCalendar(completedDates: marked, today: today),
            _RecentCompletions(taskId: taskId, dates: marked, today: today),
            const SizedBox(height: 12),
            _ValueActions(task: task),
          ],
        ),
      ),
    );
  }

  static final DateFormat _fullDate = DateFormat('d MMMM y', 'ru_RU');

  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    DateTime today,
  ) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ValueDateSheet(
        today: today,
        weekStart: ref.read(weekStartProvider),
        onApply: (day) async {
          try {
            await ref
                .read(tasksDaoProvider)
                .setLog(taskId, day, completed: true);
            return true;
          } catch (_) {
            showAppToast(
              overlay,
              message: 'Не удалось сохранить отметку',
              detail: 'Попробуйте ещё раз',
              isError: true,
            );
            return false;
          }
        },
      ),
    );
  }
}

class _ValueDateSheet extends StatefulWidget {
  const _ValueDateSheet({
    required this.today,
    required this.weekStart,
    required this.onApply,
  });

  final DateTime today;
  final int weekStart;
  final Future<bool> Function(DateTime day) onApply;

  @override
  State<_ValueDateSheet> createState() => _ValueDateSheetState();
}

class _ValueDateSheetState extends State<_ValueDateSheet> {
  DateTime? _selected;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return AppSheet(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Отметить выполнение',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Выберите дату',
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ],
          ),
        ),
        DateRangeCalendar(
          firstDate: DateTime(2020),
          lastDate: widget.today,
          initialMonth: widget.today,
          selectedDates: _selected == null ? const {} : {_selected!},
          selectionMode: DateSelectionMode.single,
          weekStart: widget.weekStart,
          onSelectionChanged: (dates) =>
              setState(() => _selected = dates.isEmpty ? null : dates.single),
        ),
        Row(
          children: [
            Expanded(
              child: _CalendarActionButton(
                key: const ValueKey('value-date-reset'),
                label: 'Сбросить',
                fill: palette.chip,
                ink: palette.textPrimary,
                onTap: _saving ? null : _reset,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CalendarActionButton(
                key: const ValueKey('value-date-apply'),
                label: 'Применить',
                fill: palette.textPrimary,
                ink: palette.background,
                onTap: _selected == null || _saving ? null : _apply,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _reset() {
    setState(() => _selected = null);
    Navigator.of(context).pop();
  }

  Future<void> _apply() async {
    final selected = _selected;
    if (selected == null || _saving) return;
    setState(() => _saving = true);
    final saved = await widget.onApply(selected);
    if (!mounted) return;
    if (saved) {
      setState(() => _selected = null);
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }
}

class _CalendarActionButton extends StatelessWidget {
  const _CalendarActionButton({
    super.key,
    required this.label,
    required this.fill,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final Color fill;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.45 : 1,
    child: Material(
      color: fill,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ValueMonthCalendar extends StatefulWidget {
  const _ValueMonthCalendar({
    required this.completedDates,
    required this.today,
  });

  final List<DateTime> completedDates;
  final DateTime today;

  @override
  State<_ValueMonthCalendar> createState() => _ValueMonthCalendarState();
}

class _ValueMonthCalendarState extends State<_ValueMonthCalendar> {
  late DateTime _month = DateTime(widget.today.year, widget.today.month);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final completed = <DateTime>{
      for (final date in widget.completedDates)
        DateTime(date.year, date.month, date.day),
    };
    final title = DateFormat('LLLL y', 'ru_RU').format(_month);
    final capitalizedTitle = title.isEmpty
        ? title
        : '${title[0].toUpperCase()}${title.substring(1)}';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _MonthButton(
                key: const ValueKey('value-calendar-previous-month'),
                icon: LucideIcons.chevron_left,
                tooltip: 'Предыдущий месяц',
                onPressed: () => _stepMonth(-1),
              ),
              Expanded(
                child: Text(
                  capitalizedTitle,
                  key: const ValueKey('value-calendar-month-title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              _MonthButton(
                key: const ValueKey('value-calendar-next-month'),
                icon: LucideIcons.chevron_right,
                tooltip: 'Следующий месяц',
                onPressed: () => _stepMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 14),
          HabitMonthCalendarGrid(
            key: ValueKey('value-calendar-${_month.year}-${_month.month}'),
            month: _month,
            dayBuilder: (context, day) => _ValueCalendarDay(
              day: day,
              completed: completed.contains(day),
              today: day == widget.today,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Выполнено',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _stepMonth(int step) {
    setState(() => _month = DateTime(_month.year, _month.month + step));
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 18, color: palette.textPrimary),
    );
  }
}

class _ValueCalendarDay extends StatelessWidget {
  const _ValueCalendarDay({
    required this.day,
    required this.completed,
    required this.today,
  });

  final DateTime day;
  final bool completed;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final accent = theme.colorScheme.primary;
    return Container(
      key: ValueKey('value-calendar-day-${day.year}-${day.month}-${day.day}'),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: completed ? accent : null,
        border: !completed && today
            ? Border.all(color: accent, width: 1.5)
            : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: completed || today ? FontWeight.w600 : FontWeight.w400,
          color: completed
              ? theme.colorScheme.onPrimary
              : today
              ? palette.textPrimary
              : palette.iconMuted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _RecentCompletions extends ConsumerStatefulWidget {
  const _RecentCompletions({
    required this.taskId,
    required this.dates,
    required this.today,
  });

  final int taskId;
  final List<DateTime> dates;
  final DateTime today;

  @override
  ConsumerState<_RecentCompletions> createState() => _RecentCompletionsState();
}

class _RecentCompletionsState extends ConsumerState<_RecentCompletions> {
  CompletionSortOrder _order = CompletionSortOrder.newestFirst;

  @override
  Widget build(BuildContext context) {
    if (widget.dates.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final dates = sortCompletionDates(widget.dates, _order);
    final orderLabel = _order == CompletionSortOrder.newestFirst
        ? 'Сначала новые'
        : 'Сначала старые';

    return Padding(
      key: const ValueKey('value-recent-completions'),
      padding: const EdgeInsets.only(top: 12),
      child: _Card(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Последние отметки',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('value-completion-sort'),
                  onPressed: _selectOrder,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(LucideIcons.arrow_down_up, size: 16),
                  label: Text(orderLabel),
                ),
              ],
            ),
            for (final day in dates.take(_recentMarksShown))
              Row(
                key: ValueKey('value-completion-${day.toIso8601String()}'),
                children: [
                  Expanded(
                    child: Text(
                      '${ValueDetailPage._fullDate.format(day)} · '
                      '${lastDoneLabel(day, today: widget.today).toLowerCase()}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Убрать отметку',
                    onPressed: () => _confirmDelete(day),
                    icon: Icon(
                      LucideIcons.x,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectOrder() async {
    final selected = await showOptionsSheet<CompletionSortOrder>(
      context,
      title: 'Порядок отметок',
      options: const [
        (CompletionSortOrder.newestFirst, 'Сначала новые'),
        (CompletionSortOrder.oldestFirst, 'Сначала старые'),
      ],
      selected: _order,
    );
    if (selected != null && mounted) {
      setState(() => _order = selected.$1);
    }
  }

  Future<void> _confirmDelete(DateTime day) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: DialogIcons.delete,
      title: 'Удалить выполнение?',
      body:
          'Вы уверены, что хотите удалить это выполнение? '
          'Это действие нельзя отменить.',
      action: 'Удалить',
    );
    if (!confirmed || !mounted) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await ref
          .read(tasksDaoProvider)
          .setLog(widget.taskId, day, completed: false);
    } catch (_) {
      showAppToast(
        overlay,
        message: 'Не удалось удалить отметку',
        detail: 'Попробуйте ещё раз',
        isError: true,
      );
    }
  }
}

String _averageIntervalLabel(double? average) {
  if (average == null) return '—';
  final rounded = (average * 10).round() / 10;
  final whole = rounded == rounded.roundToDouble();
  final number = whole
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1).replaceAll('.', ',');
  final unit = whole ? pluralRu(rounded.toInt(), 'день', 'дня', 'дней') : 'дня';
  return '$number $unit';
}

class _StatisticsCard extends StatelessWidget {
  const _StatisticsCard({
    super.key,
    required this.title,
    required this.value,
    required this.caption,
  });

  final String title;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 4),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueTitle extends StatelessWidget {
  const _ValueTitle({
    required this.task,
    required this.badge,
    required this.ink,
  });

  final Task task;
  final Color badge;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    final description = task.description?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: badge,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              taskIconFor(task.iconKey) ?? LucideIcons.repeat,
              size: 20,
              color: ink,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description.isEmpty
                      ? 'Отслеживание последнего выполнения'
                      : description,
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: child,
      ),
    );
  }
}

class _MarkButton extends StatelessWidget {
  const _MarkButton({
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
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ValueActions extends ConsumerWidget {
  const _ValueActions({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(Theme.of(context));
    Widget row(String label, VoidCallback onTap, {Color? color}) => InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: color ?? palette.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );

    return _Card(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          row(
            task.status == TaskStatus.archived ? 'Вернуть' : 'Архивировать',
            () =>
                _setArchived(context, ref, task.status != TaskStatus.archived),
          ),
          Container(height: 1, color: palette.divider),
          row('Удалить', () => _delete(context, ref), color: palette.danger),
        ],
      ),
    );
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

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    final confirmed = await showConfirmDialog(
      context,
      icon: DialogIcons.delete,
      title: 'Удалить отслеживание?',
      body: '«${task.title}» и все отметки будут удалены безвозвратно.',
      action: 'Удалить',
    );
    if (confirmed != true) return;

    final dao = ref.read(tasksDaoProvider);
    final deleted = await dao.deleteTaskCascade(task.id);
    navigator.pop();
    if (deleted != null) {
      showAppToast(
        overlay,
        message: 'Отслеживание удалено',
        actionLabel: 'Отменить',
        onAction: () => dao.restoreDeleted(deleted),
      );
    }
  }
}
