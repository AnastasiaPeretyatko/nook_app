import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/color_picker_row.dart';

class TaskCalendar extends ConsumerWidget {
  const TaskCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.calendarFormat,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.onTodayPressed,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final CalendarFormat calendarFormat;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final void Function(DateTime focusedDay) onPageChanged;
  final VoidCallback onTodayPressed;

  static const _maxMarkers = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedDayColor = neutralChip(theme);
    final tasks = ref.watch(rootTasksProvider).valueOrNull ?? const <Task>[];
    // Every task the day screen shows gets a dot, timed or not: the timed ones
    // land on the timeline, the rest in the strip above it. Filtering by time
    // here would under-count the day.
    final activeTasks = tasks
        .where((t) => t.status == TaskStatus.active)
        .toList();

    List<Task> tasksForDay(DateTime day) =>
        activeTasks.where((t) => isTaskScheduledOn(t, day)).toList();

    return TableCalendar<Task>(
      locale: 'ru_RU',
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: focusedDay,
      selectedDayPredicate: (day) => isSameDay(selectedDay, day),
      calendarFormat: calendarFormat,
      availableGestures: AvailableGestures.horizontalSwipe,
      startingDayOfWeek: StartingDayOfWeek.monday,
      eventLoader: tasksForDay,
      availableCalendarFormats: const {
        CalendarFormat.month: 'Месяц',
        // A step between the two, so the drag handle has something to land on
        // half-way instead of flipping straight from one week to the month.
        CalendarFormat.twoWeeks: 'Две недели',
        CalendarFormat.week: 'Неделя',
      },
      // The height change happens while the finger is still moving, so it has
      // to land quickly and ease out instead of crawling there linearly.
      formatAnimationDuration: const Duration(milliseconds: 140),
      formatAnimationCurve: Curves.easeOutCubic,
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: false,
        leftChevronVisible: false,
        rightChevronVisible: false,
        headerPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      // The package's own defaults are hard-coded greys meant for a white
      // calendar (#4F4F4F headers, #5A5A5A weekends), so every text style the
      // month view uses has to be spelled out against the theme.
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        weekendStyle: TextStyle(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
      calendarStyle: CalendarStyle(
        defaultTextStyle: TextStyle(color: theme.colorScheme.onSurface),
        weekendTextStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        outsideTextStyle: TextStyle(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        todayDecoration: const BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
        selectedDecoration: BoxDecoration(
          color: selectedDayColor,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: TextStyle(color: onTaskColor(selectedDayColor)),
      ),
      calendarBuilders: CalendarBuilders<Task>(
        headerTitleBuilder: (context, day) =>
            _CalendarHeaderTitle(day: day, onTodayPressed: onTodayPressed),
        markerBuilder: (context, day, dayTasks) {
          if (dayTasks.isEmpty) return const SizedBox.shrink();
          return Positioned(bottom: 1, child: _TaskMarkers(tasks: dayTasks));
        },
      ),
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
    );
  }
}

class _CalendarHeaderTitle extends StatelessWidget {
  const _CalendarHeaderTitle({required this.day, required this.onTodayPressed});

  final DateTime day;
  final VoidCallback onTodayPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = DateFormat.MMMM('ru_RU').format(day);
    final monthLabel = month.isEmpty
        ? month
        : '${month[0].toUpperCase()}${month.substring(1)}';

    return Row(
      children: [
        // The header title is handed the whole row (both chevrons and the format
        // button are off), so the month has to give the button its width rather
        // than take it all and overflow.
        Expanded(
          // The year is set smaller than the month, so the two only read as one
          // line when they share a baseline rather than a centre.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  monthLabel,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${day.year}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _TodayButton(onTap: onTodayPressed),
      ],
    );
  }
}

/// Sends the calendar back to today, and carries today's date as its label so it
/// reads as the day it lands on.
class _TodayButton extends StatelessWidget {
  const _TodayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: insetSurface(theme),
      borderRadius: BorderRadius.circular(12),
      // The ink has to be clipped to the same shape, or a tap flashes square
      // corners over the rounded ones.
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: 'Сегодня',
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Text(
                '${DateTime.now().day}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskMarkers extends StatelessWidget {
  const _TaskMarkers({required this.tasks});

  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    // A day cell is too narrow for an unbounded row of dots, so the tail is
    // replaced by one neutral dot. Without it four dots would read as "exactly
    // four tasks" on a day that holds more.
    final overflowing = tasks.length > TaskCalendar._maxMarkers;
    final shown = overflowing ? TaskCalendar._maxMarkers - 1 : tasks.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final task in tasks.take(shown))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.2),
            child: _TaskDot(task: task),
          ),
        if (overflowing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 1.2),
            child: _MoreDot(),
          ),
      ],
    );
  }
}

/// Stands in for the tasks that did not fit the cell.
class _MoreDot extends StatelessWidget {
  const _MoreDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _TaskDot extends StatelessWidget {
  const _TaskDot({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final color = task.colorValue != null
        ? Color(task.colorValue!)
        : ColorPickerRow.colors.first;

    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        // A 5px dot only has to be seen, so 3:1 is enough — but a pale swatch
        // such as mint sits at 1.6:1 on white and has to be brought down.
        color: inkOn(
          Theme.of(context).colorScheme.surface,
          color,
          minContrast: 3,
        ),
        shape: BoxShape.circle,
      ),
    );
  }
}
