import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/settings/calendar_settings.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/habit_labels.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/color_picker_row.dart';

/// The timeline's calendar in the "Иней" style (`Timeline.dc.html`): a week by
/// default, the month on demand. Each day is a rounded cell — weekday over date
/// in the week, date alone in the month under a row of weekday names — the
/// selected one a dark pill, with up to four dots for the tasks it holds.
///
/// The month name and "Сегодня" sit above it on `HomePage`, which owns the
/// format: this widget only reports a vertical swipe through [onFormatChanged].
class TaskCalendar extends ConsumerWidget {
  const TaskCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.calendarFormat,
    required this.onDaySelected,
    required this.onPageChanged,
    this.onFormatChanged,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final CalendarFormat calendarFormat;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final void Function(DateTime focusedDay) onPageChanged;
  final ValueChanged<CalendarFormat>? onFormatChanged;

  static const _maxMarkers = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    // Mine plus the tasks I handed to someone — both are on the day screen.
    final tasks = [
      ...?ref.watch(rootTasksProvider).valueOrNull,
      ...ref.watch(delegatedTasksProvider),
    ];
    // Habits are dots too unless the user has turned them off — see
    // [showHabitsInCalendarProvider]. Off, a repeating task leaves the month
    // view entirely and only the dated one-off ones are left; the day screen
    // below is untouched either way.
    final showHabits = ref.watch(showHabitsInCalendarProvider);
    // Every task the day screen shows gets a dot, timed or not: the timed ones
    // land on the timeline, the rest in "В течение дня". Filtering by time here
    // would under-count the day.
    final activeTasks = tasks
        .where(
          (t) =>
              t.status == TaskStatus.active &&
              (showHabits || t.repeatType == null),
        )
        .toList();

    List<Task> tasksForDay(DateTime day) =>
        activeTasks.where((t) => isTaskScheduledOn(t, day)).toList();

    final week = calendarFormat == CalendarFormat.week;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    Widget cell(DateTime day, {bool outside = false}) => _DayCell(
      day: day,
      selected: isSameDay(selectedDay, day),
      today: isSameDay(today, day),
      future: DateTime(day.year, day.month, day.day).isAfter(today),
      outside: outside,
      showWeekday: week,
    );

    return TableCalendar<Task>(
      locale: 'ru_RU',
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: focusedDay,
      selectedDayPredicate: (day) => isSameDay(selectedDay, day),
      calendarFormat: calendarFormat,
      // A vertical swipe opens and closes the month, as the chevron does.
      availableGestures: AvailableGestures.all,
      startingDayOfWeek: ref.watch(weekStartProvider) == DateTime.sunday
          ? StartingDayOfWeek.sunday
          : StartingDayOfWeek.monday,
      eventLoader: tasksForDay,
      availableCalendarFormats: const {
        CalendarFormat.month: 'Месяц',
        CalendarFormat.week: 'Неделя',
      },
      onFormatChanged: onFormatChanged,
      formatAnimationDuration: const Duration(milliseconds: 200),
      formatAnimationCurve: Curves.easeOutCubic,
      headerVisible: false,
      // The week puts the weekday inside each cell, under the dark pill with the
      // date, as the mock-up does; the month has a row of names instead.
      daysOfWeekVisible: !week,
      daysOfWeekHeight: 22,
      rowHeight: week ? 68 : 50,
      // The package's own defaults are hard-coded greys meant for a white
      // calendar (#4F4F4F headers, #5A5A5A weekends), so every text style the
      // month view uses has to be spelled out against the theme.
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(fontSize: 11, color: p.textSecondary),
        weekendStyle: TextStyle(fontSize: 11, color: p.textSecondary),
        dowTextFormatter: (date, _) => weekdayShort[date.weekday - 1],
      ),
      calendarStyle: const CalendarStyle(cellMargin: EdgeInsets.all(3)),
      calendarBuilders: CalendarBuilders<Task>(
        defaultBuilder: (context, day, _) => cell(day),
        todayBuilder: (context, day, _) => cell(day),
        selectedBuilder: (context, day, _) => cell(day),
        outsideBuilder: (context, day, _) => cell(day, outside: true),
        markerBuilder: (context, day, dayTasks) {
          if (dayTasks.isEmpty) return const SizedBox.shrink();
          return Positioned(bottom: 7, child: _TaskMarkers(tasks: dayTasks));
        },
      ),
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
    );
  }
}

/// One day of the calendar. The selected day is a dark pill — light in the dark
/// theme — the main colour of the interface, not the accent; today, when it is
/// not the one selected, carries its date in the accent.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.future,
    required this.outside,
    required this.showWeekday,
  });

  final DateTime day;
  final bool selected;
  final bool today;
  final bool future;
  final bool outside;
  final bool showWeekday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final onPill = p.background;
    final numberColor = selected
        ? onPill
        : today
        ? inkOn(p.background, theme.colorScheme.primary)
        : outside || future
        ? p.textTertiary
        : p.textPrimary;

    // The whole cell, not just its text: the selected pill is as wide as the
    // day's column.
    return Container(
      width: double.infinity,
      height: double.infinity,
      margin: const EdgeInsets.all(3),
      decoration: selected
          ? BoxDecoration(
              color: p.textPrimary,
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      // Clear of the dots along the bottom, and shrunk rather than cut when a
      // large system font no longer fits the row's fixed height.
      padding: EdgeInsets.only(top: showWeekday ? 8 : 0, bottom: 14),
      child: Align(
        alignment: showWeekday ? Alignment.topCenter : Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showWeekday) ...[
                Text(
                  weekdayShort[day.weekday - 1],
                  style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? onPill.withValues(alpha: 0.75)
                        : p.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected || today
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: numberColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
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
