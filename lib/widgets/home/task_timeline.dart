import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/task_actions_sheet.dart';
import 'package:todo_app/widgets/subtask_progress.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';

/// Vertical, time-proportional timeline of the tasks scheduled for [selectedDay].
///
/// Only tasks that have a start time (`scheduledTimeMinutes`) are shown here.
class TaskTimeline extends ConsumerStatefulWidget {
  const TaskTimeline({
    super.key,
    required this.selectedDay,
    this.scrollController,
  });

  final DateTime selectedDay;
  final ScrollController? scrollController;

  // Layout tuning constants.
  static const double pxPerMin = 1.4;
  static const double timeColWidth = 56;
  static const double markerColWidth = 52;
  static const double pointNodeSize = 46;
  static const double pointRowHeight = 74;
  static const double pillWidth = 48;
  static const double pillMinHeight = 62;
  static const int solidGapMaxMinutes = 120;
  /// The vertical line the rows hang on. Theme-driven: the timeline sits on a
  /// sheet, so it has to read on both a white and a near-black surface.
  static Color lineColorOf(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  /// Room a row needs for its subtask counter, on top of its usual height.
  static const double subtaskRowExtra = 22;

  /// Height of [task]'s row. A point task has a fixed one, a ranged task grows
  /// with its duration, and either gains [subtaskRowExtra] when it has subtasks
  /// to report. Shared with the gap rows, which measure the row above them.
  static double rowHeightFor(Task task, {required bool hasSubtasks}) {
    final start = task.scheduledTimeMinutes ?? 0;
    final end = task.endTimeMinutes;
    final extra = hasSubtasks ? subtaskRowExtra : 0.0;
    if (end != null && end > start) {
      return math.max(pillMinHeight + extra, (end - start) * pxPerMin);
    }
    return pointRowHeight + extra;
  }

  @override
  ConsumerState<TaskTimeline> createState() => _TaskTimelineState();
}

class _TaskTimelineState extends ConsumerState<TaskTimeline> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  /// Rebuilds once per minute, aligned to the minute boundary, so the "now"
  /// marker and the in-progress pill fill keep up with the clock. A minute is
  /// the timeline's own resolution — 1.4px — so anything finer buys nothing.
  void _scheduleTick() {
    final now = DateTime.now();
    final toNextMinute = Duration(
      milliseconds: 60000 - (now.second * 1000 + now.millisecond),
    );
    _tick = Timer(toNextMinute, () {
      if (!mounted) return;
      // Only today's timeline moves; other days are static.
      if (_isSameDay(DateTime.now(), widget.selectedDay)) setState(() {});
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDay = widget.selectedDay;
    final scrollController = widget.scrollController;
    // Everything, not just roots: the rows show how many subtasks a task has.
    final tasksAsync = ref.watch(allTasksProvider);
    final logsAsync = ref.watch(logsForDateProvider(selectedDay));

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
        final tasks = allTasks.where((t) => t.parentId == null).toList();

        final timed =
            tasks
                .where((t) => t.status == TaskStatus.active)
                .where((t) => isTaskScheduledOn(t, selectedDay))
                .where((t) => t.scheduledTimeMinutes != null)
                .toList()
              ..sort((a, b) {
                final c = a.scheduledTimeMinutes!.compareTo(
                  b.scheduledTimeMinutes!,
                );
                if (c != 0) return c;
                final ae = a.endTimeMinutes ?? a.scheduledTimeMinutes!;
                final be = b.endTimeMinutes ?? b.scheduledTimeMinutes!;
                return ae.compareTo(be);
              });

        // Tasks that belong to this day but carry no time of their own. They
        // cannot be placed on a time axis, so they live in a strip above it.
        final untimed =
            tasks
                .where((t) => t.status == TaskStatus.active)
                .where((t) => isTaskScheduledOn(t, selectedDay))
                .where((t) => t.scheduledTimeMinutes == null)
                .toList()
              ..sort((a, b) => a.title.compareTo(b.title));

        final logs = logsAsync.valueOrNull ?? const <TaskLog>[];
        final logsByTaskId = {for (final l in logs) l.taskId: l};

        final strip = untimed.isEmpty
            ? null
            : _UntimedStrip(
                tasks: untimed,
                logsByTaskId: logsByTaskId,
                onTapTask: (task) => showTaskActionsSheet(
                  context,
                  task: task,
                  completed: logsByTaskId[task.id]?.completed ?? false,
                  completionDate: selectedDay,
                ),
              );

        // The strip stays even with nothing on the clock — a day may hold only
        // timeless tasks, and the empty state below says exactly that.
        if (timed.isEmpty) {
          return Column(
            // Stretch, or the strip shrinks to its content and gets centred by
            // the column — which also leaves its scroll viewport too narrow.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?strip,
              const Expanded(child: _EmptyState()),
            ],
          );
        }

        final now = DateTime.now();
        final isToday = _isSameDay(now, selectedDay);
        final nowMin = now.hour * 60 + now.minute;

        final items = <Widget>[];

        for (var i = 0; i < timed.length; i++) {
          final task = timed[i];
          final startMin = task.scheduledTimeMinutes!;
          final startDt = DateTime(
            selectedDay.year,
            selectedDay.month,
            selectedDay.day,
            startMin ~/ 60,
            startMin % 60,
          );
          final upcoming = startDt.isAfter(now);
          final subtasks = subtasksByParent[task.id] ?? const <Task>[];
          items.add(
            _TaskRow(
              task: task,
              log: logsByTaskId[task.id],
              upcoming: upcoming,
              nowMinutes: isToday ? nowMin : null,
              subtaskTotal: subtasks.length,
              subtaskDone: subtasks
                  .where((s) => logsByTaskId[s.id]?.completed ?? false)
                  .length,
              showLineBelow: i < timed.length - 1,
              onToggle: () => ref
                  .read(tasksDaoProvider)
                  .toggleCompletion(task.id, selectedDay),
              onTap: () => showTaskActionsSheet(
                context,
                task: task,
                completed: logsByTaskId[task.id]?.completed ?? false,
                completionDate: selectedDay,
              ),
            ),
          );

          if (i < timed.length - 1) {
            final gapStart = task.endTimeMinutes ?? task.scheduledTimeMinutes!;
            final gapEnd = timed[i + 1].scheduledTimeMinutes!;
            final gapMin = gapEnd - gapStart;
            final nowInGap = isToday && nowMin >= gapStart && nowMin < gapEnd;
            // How far the previous node's row extends below its node (only
            // point nodes have empty space below them within their own row).
            final aboveHasRange =
                task.endTimeMinutes != null &&
                task.endTimeMinutes! > task.scheduledTimeMinutes!;
            final aboveOverhang = aboveHasRange
                ? 0.0
                : TaskTimeline.rowHeightFor(
                        task,
                        hasSubtasks: subtasks.isNotEmpty,
                      ) -
                      TaskTimeline.pointNodeSize;
            items.add(
              _GapRow(
                gapMinutes: gapMin,
                nowInGap: nowInGap,
                nowMinutes: nowMin,
                gapStart: gapStart,
                gapEnd: gapEnd,
                aboveOverhang: aboveOverhang,
              ),
            );
          }
        }

        // With `extendBody: true` the bottom inset reported here includes the
        // floating nav bar height, so the last task clears it while the white
        // sheet still extends underneath.
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?strip,
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(12, 8, 12, bottomInset + 24),
                children: items,
              ),
            ),
          ],
        );
      },
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _fmtTime(int minutes) {
  final normalized = minutes % (24 * 60);
  final h = (normalized ~/ 60).toString().padLeft(2, '0');
  final m = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

List<InlineSpan> _endTimeSpans(int minutes, TextStyle? style) {
  final spans = <InlineSpan>[TextSpan(text: _fmtTime(minutes))];
  if (minutes >= 24 * 60) {
    final base = style?.fontSize ?? 12;
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        child: Padding(
          padding: const EdgeInsets.only(left: 1),
          child: Text(
            '+1',
            style: style?.copyWith(
              fontSize: base * 0.65,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
  return spans;
}

String _fmtDuration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

Color _taskColor(Task task) => task.colorValue != null
    ? Color(task.colorValue!)
    : ColorPickerRow.colors.first;

IconData _taskIcon(Task task) => task.iconCodePoint != null
    // ignore: non_const_argument_for_const_parameter
    ? IconData(task.iconCodePoint!, fontFamily: 'MaterialIcons')
    : Icons.check_circle_outline;

/// Horizontal strip of the day's tasks that have no time of their own: a circle
/// in the task's own colour with its icon, and the title underneath. Scrolls
/// sideways when the circles no longer fit the screen width.
class _UntimedStrip extends StatelessWidget {
  const _UntimedStrip({
    required this.tasks,
    required this.logsByTaskId,
    required this.onTapTask,
  });

  final List<Task> tasks;
  final Map<int, TaskLog> logsByTaskId;
  final ValueChanged<Task> onTapTask;

  static const double circleSize = 52;
  static const double slotWidth = 72;

  /// Clear space between two slots, so neighbouring titles cannot touch.
  static const double slotGap = 16;

  /// Horizontal margin the timeline uses for its own rows.
  static const double contentPad = 12;

  /// A slot centres its circle, which would push the first one inwards. Padding
  /// the strip by that much less lines the circle up with [contentPad] again.
  static const double leadingPad = contentPad - (slotWidth - circleSize) / 2;

  /// Clear space below the strip, so the titles do not sit on top of the first
  /// timeline row. The list adds its own 8 of top padding underneath this.
  static const double bottomGap = 16;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: bottomGap),
      // Vertically unbounded here, so the row sizes itself to a slot's height.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: leadingPad, right: contentPad),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tasks.length; i++) ...[
              if (i > 0) const SizedBox(width: slotGap),
              _UntimedTask(
                task: tasks[i],
                completed: logsByTaskId[tasks[i].id]?.completed ?? false,
                onTap: () => onTapTask(tasks[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UntimedTask extends StatelessWidget {
  const _UntimedTask({
    required this.task,
    required this.completed,
    required this.onTap,
  });

  final Task task;
  final bool completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // A finished task keeps its own colour but recedes as a whole.
      child: Opacity(
        opacity: completed ? 0.5 : 1,
        child: SizedBox(
          // A fixed slot keeps the circles evenly spaced whatever the titles say.
          width: _UntimedStrip.slotWidth,
          child: Column(
            // Centred within the slot; the strip's leading padding is what keeps
            // the first circle flush with the screen's left margin.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: _UntimedStrip.circleSize,
                height: _UntimedStrip.circleSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _taskColor(task),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  completed ? Icons.check_rounded : _taskIcon(task),
                  size: 24,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                task.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  height: 1.2,
                  color: theme.colorScheme.onSurfaceVariant,
                  decoration: completed ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.log,
    required this.upcoming,
    required this.nowMinutes,
    required this.subtaskTotal,
    required this.subtaskDone,
    required this.showLineBelow,
    required this.onToggle,
    required this.onTap,
  });

  final Task task;
  final TaskLog? log;
  final bool upcoming;

  /// Minutes since midnight, or null when the row is not on today's timeline.
  final int? nowMinutes;
  final int subtaskTotal;
  final int subtaskDone;
  final bool showLineBelow;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  /// Grey for a task the day has not reached yet: light theme reads it as a
  /// dimmed circle on white, dark theme needs it lighter than the sheet.
  static Color _upcomingColorOf(ThemeData theme) =>
      theme.brightness == Brightness.light
      ? const Color(0xFFBDBDBD)
      : const Color(0xFF4F4F52);

  /// How much of a ranged task has already elapsed: 0 before it starts, 1 once
  /// it is over, in between while it runs. Null for tasks without a range, which
  /// have nothing to fill.
  double? get _elapsedFraction {
    final start = task.scheduledTimeMinutes!;
    final end = task.endTimeMinutes;
    if (end == null || end <= start) return null;

    final now = nowMinutes;
    if (now == null) return upcoming ? 0 : 1;
    if (now <= start) return 0;
    if (now >= end) return 1;
    return (now - start) / (end - start);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = task.scheduledTimeMinutes!;
    final end = task.endTimeMinutes;
    final hasRange = end != null && end > start;
    final duration = hasRange ? end - start : 0;
    // A ranged task carries its own progress fill, so the pill is not painted a
    // flat "upcoming" grey — the fill level says where it stands.
    // The task's own accent carries the marker; the light tone of the same
    // family is what the pill's body is painted with.
    final accent = _taskColor(task);
    final color = (upcoming && !hasRange) ? _upcomingColorOf(theme) : accent;
    final lightTone = taskLightTone(accent);
    final icon = _taskIcon(task);
    final completed = log?.completed ?? false;

    final rowHeight = TaskTimeline.rowHeightFor(
      task,
      hasSubtasks: subtaskTotal > 0,
    );

    final muted = theme.colorScheme.onSurfaceVariant;
    final rangeStyle = theme.textTheme.labelSmall?.copyWith(color: muted);
    final endColStyle = theme.textTheme.bodySmall?.copyWith(
      color: muted.withValues(alpha: 0.75),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Where the "now" line crosses this row, when the clock is inside its range.
    final now = nowMinutes;
    final nowTop = (hasRange && now != null && now > start && now < end)
        ? ((now - start) / duration) * rowHeight
        : null;

    return SizedBox(
      height: rowHeight,
      child: Stack(
        // The marker may sit right at the edge of the interval; let it spill over
        // the row instead of being cut off.
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: TaskTimeline.timeColWidth,
                  height: rowHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Text(
                          _fmtTime(start),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (hasRange) ...[
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2, right: 8),
                          child: Text.rich(
                            TextSpan(children: _endTimeSpans(end, endColStyle)),
                            style: endColStyle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: TaskTimeline.markerColWidth,
                  height: rowHeight,
                  child: _Marker(
                    color: color,
                    // White on the accent, but the neutral grey of a task the
                    // day has not reached yet is asked what fits it.
                    iconColor: (upcoming && !hasRange)
                        ? onTaskColor(color)
                        : Colors.white,
                    lightTone: lightTone,
                    icon: icon,
                    hasRange: hasRange,
                    rowHeight: rowHeight,
                    elapsedFraction: _elapsedFraction,
                    showLineBelow: showLineBelow,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10, top: 2, right: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text.rich(
                                TextSpan(
                                  style: rangeStyle,
                                  children: hasRange
                                      ? [
                                          TextSpan(
                                            text: '${_fmtTime(start)} - ',
                                          ),
                                          ..._endTimeSpans(end, rangeStyle),
                                          TextSpan(
                                            text:
                                                ' (${_fmtDuration(duration)})',
                                          ),
                                        ]
                                      : [TextSpan(text: _fmtTime(start))],
                                ),
                              ),
                            ),
                            if (task.repeatType != null) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.repeat,
                                size: 12,
                                color: muted.withValues(alpha: 0.75),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: completed
                                ? muted.withValues(alpha: 0.75)
                                : theme.colorScheme.onSurface,
                            decoration: completed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (subtaskTotal > 0) ...[
                          const SizedBox(height: 6),
                          SubtaskProgress(
                            done: subtaskDone,
                            total: subtaskTotal,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (task.trackingMode == TrackingMode.checkbox)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: _Checkbox(
                      color: color,
                      completed: completed,
                      onToggle: onToggle,
                    ),
                  ),
              ],
            ),
          ),
          if (nowTop != null)
            Positioned(
              top: nowTop - _NowMarker.height / 2,
              left: 0,
              child: _NowMarker(minutes: now!),
            ),
        ],
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.color,
    required this.iconColor,
    required this.lightTone,
    required this.icon,
    required this.hasRange,
    required this.rowHeight,
    required this.elapsedFraction,
    required this.showLineBelow,
  });

  final Color color;

  /// What the glyph inside the marker is painted in.
  final Color iconColor;

  /// The light tone of the task's family: the pill's body before it fills.
  final Color lightTone;
  final IconData icon;
  final bool hasRange;
  final double rowHeight;

  /// Share of a ranged task already elapsed; null for tasks without a range.
  final double? elapsedFraction;
  final bool showLineBelow;

  @override
  Widget build(BuildContext context) {
    final nodeBottom = hasRange ? rowHeight : TaskTimeline.pointNodeSize;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        if (showLineBelow)
          Positioned(
            top: nodeBottom,
            bottom: 0,
            child: Container(
              width: 2,
              color: TaskTimeline.lineColorOf(context),
            ),
          ),
        Positioned(
          top: 0,
          child: hasRange
              ? SizedBox(
                  width: TaskTimeline.pillWidth,
                  height: rowHeight,
                  child: _PillFill(
                    color: color,
                    iconColor: iconColor,
                    icon: icon,
                    // No range means nothing to fill; treat it as fully elapsed.
                    fraction: elapsedFraction ?? 1,
                    pendingColor: lightTone,
                  ),
                )
              : Container(
                  width: TaskTimeline.pointNodeSize,
                  height: TaskTimeline.pointNodeSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
        ),
      ],
    );
  }
}

/// The inside of a ranged task's pill: a pale base that fills with the task's
/// colour from the top as the interval elapses. Before the task starts the pill
/// reads as empty, while it runs the fill line marks the current moment, and once
/// it is over the pill is solid colour.
class _PillFill extends StatelessWidget {
  const _PillFill({
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.fraction,
    required this.pendingColor,
  });

  final Color color;
  final Color iconColor;
  final IconData icon;
  final double fraction;
  final Color pendingColor;

  @override
  Widget build(BuildContext context) {
    final filled = fraction.clamp(0.0, 1.0);
    // The icon has to stay legible against both halves of the pill: above ~a
    // third it sits on the accent fill and is white, below it on the family's
    // light tone, where white would disappear — there it is the accent itself,
    // darkened only if the two tones sit too close together.
    final glyphColor = filled >= 0.35
        ? iconColor
        : inkOn(pendingColor, color, minContrast: 3);

    return ClipRRect(
      borderRadius: BorderRadius.circular(TaskTimeline.pillWidth / 2),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: pendingColor),
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: filled,
              widthFactor: 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                color: color,
              ),
            ),
          ),
          Center(child: Icon(icon, color: glyphColor, size: 24)),
        ],
      ),
    );
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
        child: completed ? Icon(Icons.check, size: 16, color: color) : null,
      ),
    );
  }
}

class _GapRow extends StatelessWidget {
  const _GapRow({
    required this.gapMinutes,
    required this.nowInGap,
    required this.nowMinutes,
    required this.gapStart,
    required this.gapEnd,
    required this.aboveOverhang,
  });

  final int gapMinutes;
  final bool nowInGap;
  final int nowMinutes;
  final int gapStart;
  final int gapEnd;
  final double aboveOverhang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (gapMinutes <= 0) {
      return SizedBox(
        height: 14,
        child: Stack(
          children: [
            Positioned(
              left:
                  TaskTimeline.timeColWidth +
                  TaskTimeline.markerColWidth / 2 -
                  1,
              top: 0,
              bottom: 0,
              child: _line(context, dashed: false, height: 14),
            ),
          ],
        ),
      );
    }

    final solid = gapMinutes <= TaskTimeline.solidGapMaxMinutes;
    final height = solid
        ? (gapMinutes * TaskTimeline.pxPerMin).clamp(30.0, 180.0)
        : 84.0;

    double? nowTop;
    if (nowInGap && gapEnd > gapStart) {
      nowTop = ((nowMinutes - gapStart) / (gapEnd - gapStart)) * height;
      // Centred on the moment, and free to overhang the gap at either end.
      nowTop = nowTop.clamp(0.0, height) - _NowMarker.height / 2;
    }

    // Center the label within the *visual* gap between the two task nodes,
    // which also includes the empty space below the previous node's row.
    const labelHalfHeight = 8.0;
    final labelTop = ((height - aboveOverhang) / 2 - labelHalfHeight).clamp(
      0.0,
      height - labelHalfHeight * 2,
    );

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left:
                TaskTimeline.timeColWidth + TaskTimeline.markerColWidth / 2 - 1,
            top: 0,
            bottom: 0,
            child: _line(context, dashed: !solid, height: height),
          ),
          Positioned(
            left: TaskTimeline.timeColWidth + TaskTimeline.markerColWidth + 6,
            top: labelTop,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hourglass_empty,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.75,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _fmtDuration(gapMinutes),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (nowTop != null)
            Positioned(
              top: nowTop,
              left: 0,
              child: _NowMarker(minutes: nowMinutes),
            ),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context, {
    required bool dashed,
    required double height,
  }) {
    final color = TaskTimeline.lineColorOf(context);
    if (!dashed) {
      return Container(width: 2, color: color);
    }
    return _DashedLine(height: height, color: color);
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const dash = 4.0;
    const gap = 4.0;
    final count = (height / (dash + gap)).floor().clamp(1, 999);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: Container(width: 2, height: dash, color: color),
        ),
      ),
    );
  }
}

/// Where the clock stands right now: just the time in bold, in the same left
/// column and with the same alignment as a task's own start and end labels.
///
/// Positioned absolutely by its callers and centred on the current moment, so it
/// floats over whatever is underneath — including a task's own start or end label
/// when the clock happens to be near either end of the interval.
class _NowMarker extends StatelessWidget {
  const _NowMarker({required this.minutes});

  final int minutes;

  /// Fixed box height, so callers can centre it on a position rather than hang
  /// it below one.
  static const double height = 18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: TaskTimeline.timeColWidth,
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            _fmtTime(minutes),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
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
            Icons.schedule,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'На этот день нет задач со временем',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Нажмите + и укажите время задачи',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
