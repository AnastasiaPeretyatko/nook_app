import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/week.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Read-only calendar showing the full completion history of a habit.
Future<void> showHabitHistorySheet(BuildContext context, {required Task task}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (_) => HabitHistorySheet(task: task),
  );
}

class HabitHistorySheet extends ConsumerStatefulWidget {
  const HabitHistorySheet({super.key, required this.task});

  final Task task;

  @override
  ConsumerState<HabitHistorySheet> createState() => _HabitHistorySheetState();
}

class _HabitHistorySheetState extends ConsumerState<HabitHistorySheet> {
  late DateTime _focusedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
  }

  Color get _color => widget.task.colorValue != null
      ? Color(widget.task.colorValue!)
      : ColorPickerRow.colors.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logs =
        ref.watch(logsForTaskProvider(widget.task.id)).valueOrNull ??
        const <TaskLog>[];
    final completedDays = <DateTime>{
      for (final l in logs)
        if (l.completed) DateTime(l.date.year, l.date.month, l.date.day),
    };

    final late = lateDays(
      widget.task,
      logs,
      ref.watch(lateGraceMinutesProvider),
    );

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final created = DateTime(
      widget.task.createdAt.year,
      widget.task.createdAt.month,
      widget.task.createdAt.day,
    );
    // The actions sheet hands out the previous two weeks to tick, whether or
    // not the habit existed yet, so a tick can land before [created]. Outside
    // `firstDay` table_calendar draws a *disabled* cell and never calls the day
    // builder below, which is what made those ticks vanish here — so the
    // history has to start at the earliest day that actually carries one.
    var firstDay = created.isBefore(today) ? created : today;
    for (final day in completedDays) {
      if (day.isBefore(firstDay)) firstDay = day;
    }

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: raisedSurface(theme),
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(LucideIcons.rotate_ccw_clock, size: 20, color: _color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      'Выполнено: ${completedDays.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TableCalendar<void>(
                locale: 'ru_RU',
                firstDay: firstDay,
                lastDay: today,
                focusedDay: _focusedDay.isAfter(today) ? today : _focusedDay,
                startingDayOfWeek:
                    ref.watch(weekStartProvider) == DateTime.sunday
                    ? StartingDayOfWeek.sunday
                    : StartingDayOfWeek.monday,
                availableGestures: AvailableGestures.horizontalSwipe,
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  weekendStyle: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
                calendarStyle: const CalendarStyle(outsideDaysVisible: false),
                onPageChanged: (day) => setState(() => _focusedDay = day),
                calendarBuilders: CalendarBuilders<void>(
                  defaultBuilder: (context, day, _) =>
                      _dayCell(day, completedDays, late, today),
                  todayBuilder: (context, day, _) =>
                      _dayCell(day, completedDays, late, today),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Календарь только для просмотра',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.75,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayCell(
    DateTime day,
    Set<DateTime> completedDays,
    Set<DateTime> late,
    DateTime today,
  ) {
    final key = DateTime(day.year, day.month, day.day);
    final completed = completedDays.contains(key);
    final isToday = key == today;

    return Container(
      margin: const EdgeInsets.all(5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // A late tick is the same circle, paler.
        color: completed
            ? (late.contains(key) ? _color.withValues(alpha: 0.5) : _color)
            : Colors.transparent,
        shape: BoxShape.circle,
        border: isToday && !completed
            ? Border.all(color: _color, width: 1.5)
            : null,
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: completed
              ? onTaskColor(_color)
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: completed || isToday ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}
