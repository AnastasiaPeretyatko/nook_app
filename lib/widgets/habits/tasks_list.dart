import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/habit_labels.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/overdue.dart';
import 'package:todo_app/utils/task_audience.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/empty_screen.dart';
import 'package:todo_app/widgets/habits/task_actions_sheet.dart';
import 'package:todo_app/widgets/list_card.dart';
import 'package:todo_app/widgets/page_header.dart';
import 'package:todo_app/widgets/segmented_switch.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The "Задачи" tab (`Tasks.dc.html`): one-off tasks, "Активные" grouped by
/// date — overdue, today, upcoming, undated — and "Выполненные", newest first.
///
/// A task ticked moves to "Выполненные" at once. It used to stay in the list,
/// struck through, until its day passed; with the two tabs that is what the
/// second one is for. Repeating tasks live on the "Привычки" tab instead.
class TasksList extends ConsumerStatefulWidget {
  const TasksList({super.key});

  @override
  ConsumerState<TasksList> createState() => _TasksListState();
}

class _TasksListState extends ConsumerState<TasksList> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    // Everything, not just roots: the rows report how many subtasks are done.
    final tasksAsync = ref.watch(allTasksProvider);
    final logsAsync = ref.watch(allLogsProvider);
    final me = ref.watch(myUidProvider);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final allTasks = tasksAsync.valueOrNull ?? const <Task>[];
    final logs = logsAsync.valueOrNull ?? const <TaskLog>[];

    final subtasksByParent = <int, List<Task>>{};
    for (final task in allTasks) {
      final parentId = task.parentId;
      if (parentId != null) {
        subtasksByParent.putIfAbsent(parentId, () => []).add(task);
      }
    }
    final logByKey = <String, TaskLog>{
      for (final l in logs) _logKey(l.taskId, l.date): l,
    };
    TaskLog? logOf(Task t) => logByKey[_logKey(t.id, _anchorDate(t))];
    bool isCompleted(Task t) => logOf(t)?.completed ?? false;

    // Subtasks are reported by their parent's row, never listed on their own —
    // even when they carry a date or a time of their own.
    final regular = allTasks
        .where((t) => t.parentId == null)
        // Only mine: a task handed to someone else is on the timeline and the
        // group's screen, and must not sit under "Просрочено".
        .where((t) => isMyTask(t, me))
        .where((t) => t.status == TaskStatus.active)
        .where((t) => t.repeatType == null)
        // A "Значение" task has no date to be due on; it lives on the habits
        // tab next to the things it resembles.
        .where((t) => !isValueTask(t))
        .toList();
    final active = regular.where((t) => !isCompleted(t)).toList();
    final done = regular.where(isCompleted).toList();

    // Subtask completion is stored per day against the parent's anchor date —
    // the same date the task's sheet reads and writes — so the count here and
    // the ticks in the sheet can never disagree.
    (int, int)? subtaskCount(Task parent) {
      final subtasks = subtasksByParent[parent.id];
      if (subtasks == null || subtasks.isEmpty) return null;
      final date = _anchorDate(parent);
      final ticked = subtasks
          .where((s) => logByKey[_logKey(s.id, date)]?.completed ?? false)
          .length;
      return (ticked, subtasks.length);
    }

    TaskRow row(Task task, String when, {bool late = false}) {
      final completed = isCompleted(task);
      return TaskRow(
        task: task,
        when: when,
        late: late,
        completed: completed,
        subtasks: subtaskCount(task),
        onToggle: () => ref
            .read(tasksDaoProvider)
            .toggleCompletion(task.id, _anchorDate(task)),
        onTap: () =>
            showTaskActionsSheet(context, task: task, completed: completed),
      );
    }

    final Widget body;
    if (!tasksAsync.hasValue) {
      body = tasksAsync.hasError
          ? Center(child: Text('Ошибка: ${tasksAsync.error}'))
          : const Center(child: CircularProgressIndicator());
    } else if (_showDone) {
      body = done.isEmpty
          ? const EmptyScreen(
              family: 'blue',
              icon: LucideIcons.list_checks,
              title: 'Пока ничего не выполнено',
              body: 'Отмеченные задачи появятся здесь.',
            )
          : _list(context, [
              SectionCaption(title: 'Выполнено', trailing: '${done.length}'),
              RowsCard(
                dividerIndent: 50,
                children: [
                  for (final task
                      in done..sort(
                        (a, b) => _doneAt(
                          logOf(b),
                          b,
                        ).compareTo(_doneAt(logOf(a), a)),
                      ))
                    row(task, _doneLabel(task, logOf(task), today)),
                ],
              ),
            ]);
    } else if (active.isEmpty) {
      body = EmptyScreen(
        family: 'blue',
        icon: LucideIcons.list,
        title: 'На сегодня всё чисто',
        body: 'Задач нет. Добавьте новую или просто отдохните.',
        actionLabel: 'Добавить задачу',
        onAction: () => showCreateTaskSheet(context),
      );
    } else {
      final overdue = <Task>[];
      final todayTasks = <Task>[];
      final upcoming = <Task>[];
      final undated = <Task>[];
      for (final task in active) {
        if (task.startDate == null) {
          undated.add(task);
        } else if (isTaskOverdue(task, completed: false, today: today)) {
          // [isTaskOverdue] and not a comparison of its own: the badge on the
          // nav bar counts with that same rule, and the number there has to be
          // the length of this group.
          overdue.add(task);
        } else if (_dateOnly(task.startDate!) == today) {
          todayTasks.add(task);
        } else {
          upcoming.add(task);
        }
      }
      overdue.sort(_byDateThenTime);
      todayTasks.sort(_byTime);
      upcoming.sort(_byDateThenTime);
      undated.sort(_byTime);

      final p = AppPalette.of(Theme.of(context));
      List<Widget> group(
        String title,
        List<Task> tasks,
        String Function(Task) when, {
        bool late = false,
      }) => [
        if (tasks.isNotEmpty) ...[
          SectionCaption(
            title: title,
            trailing: '${tasks.length}',
            color: late ? p.danger : null,
          ),
          RowsCard(
            dividerIndent: 50,
            children: [
              for (final task in tasks) row(task, when(task), late: late),
            ],
          ),
        ],
      ];

      body = _list(context, [
        ...group(
          'Просрочено',
          overdue,
          (t) => _overdueLabel(t, today),
          late: true,
        ),
        ...group('Сегодня', todayTasks, _todayLabel),
        ...group('Предстоящие', upcoming, _upcomingLabel),
        ...group('Без даты', undated, _timeLabel),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          caption:
              '${active.length} '
              '${pluralRu(active.length, 'активная', 'активные', 'активных')}',
          title: 'Задачи',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: SegmentedSwitch(
            labels: const ['Активные', 'Выполненные'],
            selected: _showDone ? 1 : 0,
            onChanged: (i) => setState(() => _showDone = i == 1),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _list(BuildContext context, List<Widget> children) {
    // Clear of the floating "+" too, which the scaffold's inset does not count.
    final bottomInset = MediaQuery.paddingOf(context).bottom + 88;
    return ListView(
      padding: EdgeInsets.only(bottom: bottomInset),
      children: children,
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

int _byTime(Task a, Task b) {
  final ta = a.scheduledTimeMinutes ?? 1 << 30;
  final tb = b.scheduledTimeMinutes ?? 1 << 30;
  final c = ta.compareTo(tb);
  return c != 0 ? c : a.title.compareTo(b.title);
}

int _byDateThenTime(Task a, Task b) {
  final c = a.startDate!.compareTo(b.startDate!);
  return c != 0 ? c : _byTime(a, b);
}

/// When a done task was done: the moment of the tick where one was recorded
/// (v17 on), else the day it was for.
DateTime _doneAt(TaskLog? log, Task task) =>
    log?.completedAt ?? _anchorDate(task);

/// "30 мин", "2 ч", "1 ч 30 мин" — a ranged task's length, or null.
String? _durationLabel(Task task) {
  final start = task.scheduledTimeMinutes, end = task.endTimeMinutes;
  if (start == null || end == null || end <= start) return null;
  final h = (end - start) ~/ 60, m = (end - start) % 60;
  return [if (h > 0) '$h ч', if (m > 0) '$m мин'].join(' ');
}

/// "15:00 · 30 мин", "19:00", or nothing for a task with no time.
String _timeLabel(Task task) => [
  if (task.scheduledTimeMinutes != null) clockLabel(task.scheduledTimeMinutes!),
  ?_durationLabel(task),
].join(' · ');

String _todayLabel(Task task) {
  final time = _timeLabel(task);
  return time.isEmpty ? 'В течение дня' : time;
}

/// "Пн, 19 окт" or "Ср, 21 окт, 10:00 · 2 ч".
String _upcomingLabel(Task task) {
  final day = task.startDate!;
  final date =
      '${weekdayShort[day.weekday - 1]}, '
      '${DateFormat('d MMM', 'ru_RU').format(day)}';
  final time = _timeLabel(task);
  return time.isEmpty ? date : '$date, $time';
}

/// "Вчера, 18:00" or "14 окт".
String _overdueLabel(Task task, DateTime today) {
  final day = _dateOnly(task.startDate!);
  final date = daysSince(day, today) == 1
      ? 'Вчера'
      : DateFormat('d MMM', 'ru_RU').format(day);
  final time = task.scheduledTimeMinutes == null
      ? null
      : clockLabel(task.scheduledTimeMinutes!);
  return time == null ? date : '$date, $time';
}

/// "Сегодня · выполнено в 14:32". The time only where it was recorded: ticks
/// from before v17 have none.
String _doneLabel(Task task, TaskLog? log, DateTime today) {
  final day = _anchorDate(task);
  final date = switch (daysSince(day, today)) {
    0 when !day.isAfter(today) => 'Сегодня',
    1 => 'Вчера',
    _ => DateFormat('d MMM', 'ru_RU').format(day),
  };
  final at = log?.completedAt;
  return at == null
      ? date
      : '$date · выполнено в ${clockLabel(at.hour * 60 + at.minute)}';
}

/// One one-off task: a ring to tick on the left, title over when it is due,
/// the subtask count, and a dot in the task's colour on the right.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.when,
    required this.completed,
    required this.subtasks,
    required this.onToggle,
    required this.onTap,
    this.late = false,
  });

  final Task task;

  /// The line under the title; nothing is drawn for an empty one.
  final String when;
  final bool completed;

  /// Done and total, or null for a task without subtasks.
  final (int, int)? subtasks;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  /// Overdue: [when] is drawn in `danger`.
  final bool late;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final color = task.colorValue != null
        ? Color(task.colorValue!)
        : ColorPickerRow.colors.first;
    // Ink, not fill: a ring and a dot have to be seen on white, so a pale
    // family is darkened until they are.
    final ink = inkOn(p.surface, color, minContrast: 3);
    final doneFill = taskBadgeInk(theme, color, p.surface);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
        child: Row(
          children: [
            Tooltip(
              message: completed
                  ? 'Отметить «${task.title}» как невыполненную'
                  : 'Отметить «${task.title}» как выполненную',
              child: InkResponse(
                onTap: onToggle,
                radius: 22,
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: completed ? doneFill : Colors.transparent,
                        border: completed
                            ? null
                            : Border.all(color: ink, width: 2),
                      ),
                      child: completed
                          ? Icon(
                              LucideIcons.check,
                              size: 13,
                              color: onTaskColor(doneFill),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: completed ? p.textTertiary : p.textPrimary,
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: p.textTertiary,
                      ),
                    ),
                    if (when.isNotEmpty || subtasks != null) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (when.isNotEmpty)
                            Text(
                              when,
                              style: TextStyle(
                                fontSize: 12,
                                color: late ? p.danger : p.textSecondary,
                                fontWeight: late
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          if (subtasks case (final ticked, final total))
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.corner_down_right,
                                  size: 12,
                                  color: p.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$ticked/$total',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.textSecondary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}
