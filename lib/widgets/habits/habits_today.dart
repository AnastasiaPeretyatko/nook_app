import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/week.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/pages/habit_detail_page.dart';
import 'package:todo_app/widgets/habits/habit_actions_sheet.dart';
import 'package:todo_app/widgets/list_card.dart';
import 'package:todo_app/utils/habit_labels.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/task_icons.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/utils/tracking.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The habits tab's body in the "Иней" design (`Main.dc.html`): this week's
/// strip, then today's habits in one card, then the "Значение" tasks in the
/// same card, then the habits the rule leaves off today in a card of their own.
///
/// The off-today card is not in the mock-up, which only draws a day's list. It
/// is here so that a habit stays reachable on the days it is not due — its
/// sheet, its history, a day marked by hand — rather than vanishing until then.
class HabitsToday extends ConsumerWidget {
  const HabitsToday({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(rootTasksProvider);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = startOfWeek(today, ref.watch(weekStartProvider));
    final week = List.generate(7, (i) => monday.add(Duration(days: i)));
    final logsAsync = ref.watch(
      logsBetweenProvider(
        DateRange(monday, monday.add(const Duration(days: 7))),
      ),
    );
    final sessions =
        ref.watch(openSessionsProvider).valueOrNull ?? const <TaskSession>[];
    // The last mark of a "Значение" task can be months back, far outside this
    // week, so these read the whole table. It is already open for the nav bar's
    // badge, so this costs no query of its own.
    final lastDone = lastDoneByTask(
      ref.watch(allLogsProvider).valueOrNull ?? const <TaskLog>[],
    );

    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
      data: (tasks) {
        final active = tasks.where((t) => t.status == TaskStatus.active);
        final habits = active.where((t) => t.repeatType != null).toList();
        final values = active.where(isValueTask).toList();
        if (habits.isEmpty && values.isEmpty) return const _EmptyState();

        final logs = logsAsync.valueOrNull ?? const <TaskLog>[];
        final runningSince = <int, DateTime>{
          for (final session in sessions) session.taskId: session.startedAt,
        };
        final completedByTask = <int, Set<DateTime>>{};
        final todayLogByTask = <int, TaskLog>{};
        for (final log in logs) {
          final d = DateTime(log.date.year, log.date.month, log.date.day);
          if (log.completed) {
            completedByTask.putIfAbsent(log.taskId, () => {}).add(d);
          }
          if (d == today) todayLogByTask[log.taskId] = log;
        }
        bool doneOn(Task t, DateTime day) =>
            completedByTask[t.id]?.contains(day) ?? false;

        final dueToday = [
          for (final t in habits)
            if (isTaskScheduledOn(t, today)) t,
        ];
        final notToday = [
          for (final t in habits)
            if (!isTaskScheduledOn(t, today)) t,
        ];

        _WeekDayMark markOf(DateTime day) {
          if (day.isAfter(today)) return _WeekDayMark.none;
          final due = [
            for (final t in habits)
              if (isTaskScheduledOn(t, day)) t,
          ];
          if (due.isEmpty) return _WeekDayMark.none;
          return due.every((t) => doneOn(t, day))
              ? _WeekDayMark.allDone
              : _WeekDayMark.open;
        }

        HabitRow row(Task task) => HabitRow(
          task: task,
          today: today,
          completedDays: completedByTask[task.id] ?? const {},
          todayLog: todayLogByTask[task.id],
          lastDone: lastDone[task.id],
          timerRunningSince: runningSince[task.id],
          // A habit opens its page; a "Значение" task has no history to chart
          // and keeps the sheet. Holding the row opens the sheet either way —
          // marking an earlier day, copying, deleting.
          onTap: () => isValueTask(task)
              ? showHabitActionsSheet(context, task: task)
              : Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HabitDetailPage(taskId: task.id),
                  ),
                ),
          onLongPress: () => showHabitActionsSheet(context, task: task),
          onMark: () =>
              ref.read(tasksDaoProvider).toggleCompletion(task.id, today),
          onTimerStart: () => ref
              .read(tasksDaoProvider)
              .startTimer(
                task.id,
                DateTime.now(),
                targetSeconds: (task.targetDurationMinutes ?? 0) * 60,
              ),
          onTimerStop: () => ref
              .read(tasksDaoProvider)
              .stopTimer(
                task.id,
                DateTime.now(),
                targetSeconds: (task.targetDurationMinutes ?? 0) * 60,
              ),
          onCounterInc: () => ref
              .read(tasksDaoProvider)
              .incrementCounter(task.id, today, counterTarget(task).toDouble()),
        );

        final todayRows = [...dueToday, ...values];
        final doneCount = dueToday.where((t) => doneOn(t, today)).length;
        // Clear of the floating "+" too, which the scaffold's inset does not
        // count: 56 for the button, 20 above the bar, and a little air.
        final bottomInset = MediaQuery.paddingOf(context).bottom + 88;

        return ListView(
          padding: EdgeInsets.only(top: 4, bottom: bottomInset),
          children: [
            _WeekStrip(days: week, today: today, markOf: markOf),
            if (todayRows.isNotEmpty) ...[
              SectionCaption(
                title: 'Сегодня',
                trailing: dueToday.isEmpty
                    ? null
                    : '$doneCount из ${dueToday.length}',
              ),
              RowsCard(children: [for (final t in todayRows) row(t)]),
            ],
            if (notToday.isNotEmpty) ...[
              const SectionCaption(title: 'Не сегодня'),
              RowsCard(children: [for (final t in notToday) row(t)]),
            ],
          ],
        );
      },
    );
  }
}

enum _WeekDayMark { none, open, allDone }

/// This week, from the day the settings start it on, today drawn as a dark pill. The dot under a day
/// says how that day went: accent when every habit due on it was done, an
/// outline when some were not, nothing for a day still ahead or with nothing
/// due.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.days,
    required this.today,
    required this.markOf,
  });

  final List<DateTime> days;
  final DateTime today;
  final _WeekDayMark Function(DateTime day) markOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(21, 14, 21, 4),
      child: Row(
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _dayCell(theme, p, day, markOf(day)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(
    ThemeData theme,
    AppPalette p,
    DateTime day,
    _WeekDayMark mark,
  ) {
    final isToday = day == today;
    final onPill = p.background;
    final dot = switch (mark) {
      _WeekDayMark.none => Colors.transparent,
      _WeekDayMark.allDone => isToday ? onPill : theme.colorScheme.primary,
      _WeekDayMark.open => isToday ? onPill.withValues(alpha: 0.4) : p.outline,
    };
    final name = weekdayShort[day.weekday - 1];
    return Semantics(
      label:
          '$name, ${day.day}${switch (mark) {
            _WeekDayMark.allDone => ', всё выполнено',
            _WeekDayMark.open => ', не всё выполнено',
            _WeekDayMark.none => '',
          }}',
      selected: isToday,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: isToday
            ? BoxDecoration(
                color: p.textPrimary,
                borderRadius: BorderRadius.circular(14),
              )
            : null,
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                color: isToday
                    ? onPill.withValues(alpha: 0.75)
                    : p.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
                color: isToday
                    ? onPill
                    : day.isAfter(today)
                    ? p.textTertiary
                    : p.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}

/// One habit or "Значение" task: icon tile, title over its rule, and on the
/// right the control its tracking mode asks for — a tick, a counter, a timer,
/// or how long ago it was last done.
class HabitRow extends StatelessWidget {
  const HabitRow({
    super.key,
    required this.task,
    required this.today,
    required this.completedDays,
    required this.todayLog,
    this.lastDone,
    required this.timerRunningSince,
    required this.onTap,
    this.onLongPress,
    required this.onMark,
    required this.onTimerStart,
    required this.onTimerStop,
    required this.onCounterInc,
  });

  final Task task;
  final DateTime today;
  final Set<DateTime> completedDays;
  final TaskLog? todayLog;

  /// The latest day a "Значение" task was marked on, or null when it never was.
  /// Ignored by every other kind of row.
  final DateTime? lastDone;

  /// When this habit's timer was started, or null when it is not running.
  final DateTime? timerRunningSince;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onMark;
  final VoidCallback onTimerStart;
  final VoidCallback onTimerStop;
  final VoidCallback onCounterInc;

  Color get _color => task.colorValue != null
      ? Color(task.colorValue!)
      : ColorPickerRow.colors.first;

  IconData get _icon => taskIconFor(task.iconKey) ?? LucideIcons.repeat;

  /// A "Значение" row reads the day from its own latest mark: this week's logs
  /// are no use to a task nobody lays out by day.
  bool get _doneToday =>
      isValueTask(task) ? lastDone == today : completedDays.contains(today);

  int? get _timerTargetSeconds {
    final minutes = task.targetDurationMinutes;
    return task.trackingMode == TrackingMode.timer &&
            minutes != null &&
            minutes > 0
        ? minutes * 60
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final fill = taskBadgeSurface(theme, _color, p.surface);
    // The "done" mark is the task's own colour, the tone its icon is drawn in —
    // not the app accent the mock-up uses — so a ticked row reads as that task.
    final doneColor = taskBadgeInk(theme, _color, p.surface);
    final done = _doneToday;
    final isCounter = task.trackingMode == TrackingMode.counter;
    final count = (todayLog?.value ?? 0).round();
    final target = counterTarget(task);

    final Widget trailing;
    final timerTarget = _timerTargetSeconds;
    if (isValueTask(task)) {
      trailing = _ValueChip(
        label: lastDoneLabel(lastDone, today: today),
        doneToday: done,
        onTap: onMark,
      );
    } else if (timerTarget != null) {
      trailing = HabitTimerControl(
        key: ValueKey('timer-${task.id}-$today'),
        targetSeconds: timerTarget,
        loggedSeconds: count,
        runningSince: timerRunningSince,
        completed: done,
        doneColor: doneColor,
        onStart: onTimerStart,
        onStop: onTimerStop,
      );
    } else if (isCounter) {
      // Any counter counts, target set or not: [counterTarget] floors it at
      // one, so the control can never open on "done".
      trailing = _CounterControl(
        count: count,
        target: target,
        done: done,
        doneColor: doneColor,
        onTap: onCounterInc,
      );
    } else {
      trailing = _CheckCircle(done: done, color: doneColor, onTap: onMark);
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _icon,
                size: 18,
                color: taskBadgeInk(theme, _color, fill),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: done ? p.textTertiary : p.textPrimary,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: p.textTertiary,
                    ),
                  ),
                  if (isCounter) ...[
                    const SizedBox(height: 6),
                    _ProgressBar(
                      fraction: target <= 0
                          ? 0
                          : (count / target).clamp(0.0, 1.0),
                      color: _color,
                      track: p.divider,
                    ),
                  ] else ...[
                    const SizedBox(height: 2),
                    Text(
                      habitSubtitle(task, lastDone: lastDone),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      // The full width of the column, not the fill's: the track is what shows
      // how much is left.
      child: SizedBox(
        height: 4,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              widthFactor: fraction,
              heightFactor: 1,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 26px circle in a 44px touch area — the tick of a checkbox habit, and the
/// "done" mark the counter and the timer turn into. Empty: an outline. Done:
/// filled with [color] — the task's — and a tick in whichever of black and
/// white reads on it. [onTap] null makes it a read-out.
class _CheckCircle extends StatelessWidget {
  const _CheckCircle({
    required this.done,
    required this.color,
    required this.onTap,
  });

  final bool done;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    return _TouchTarget(
      tooltip: onTap == null
          ? 'Выполнено'
          : done
          ? 'Отметить как невыполненное'
          : 'Отметить как выполненное',
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: done ? color : Colors.transparent,
          shape: BoxShape.circle,
          border: done ? null : Border.all(color: p.outline, width: 1.5),
        ),
        child: done
            ? Icon(LucideIcons.check, size: 14, color: onTaskColor(color))
            : null,
      ),
    );
  }
}

/// A 44×44 tap area around a smaller glyph (DESIGN.md §1), named for a screen
/// reader by its [tooltip].
class _TouchTarget extends StatelessWidget {
  const _TouchTarget({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox.square(dimension: 44, child: Center(child: child)),
      ),
    );
  }
}

/// "5/8" and a "+" — or the done mark once the target is reached.
class _CounterControl extends StatelessWidget {
  const _CounterControl({
    required this.count,
    required this.target,
    required this.done,
    required this.doneColor,
    required this.onTap,
  });

  final int count;
  final int target;
  final bool done;
  final Color doneColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final complete = done || count >= target;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$count'),
              TextSpan(
                text: '/$target',
                style: TextStyle(color: p.textTertiary),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: p.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (complete)
          _CheckCircle(done: true, color: doneColor, onTap: null)
        else
          _TouchTarget(
            tooltip: 'Добавить',
            onTap: onTap,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.outline, width: 1.5),
              ),
              child: Icon(LucideIcons.plus, size: 12, color: p.textPrimary),
            ),
          ),
      ],
    );
  }
}

/// How long ago a "Значение" task was last done, on a grey plate. Tapping it
/// marks today — or takes today's mark back — so the task can be marked from
/// the list as it could before the redesign.
class _ValueChip extends StatelessWidget {
  const _ValueChip({
    required this.label,
    required this.doneToday,
    required this.onTap,
  });

  final String label;
  final bool doneToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Tooltip(
      message: doneToday ? 'Снять отметку за сегодня' : 'Отметить сегодня',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: p.chip,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  // Shrunk rather than wrapped or cut: at a large system font
                  // "21 день назад" would push the title out of the row.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 128),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What is left of a timer habit's run, and a round play/pause button.
///
/// The elapsed time is never accumulated here: [loggedSeconds] is what previous
/// runs already banked for the day, and [runningSince] is when the current run
/// began. Everything on screen is derived from those two against the wall clock,
/// so a run keeps counting while the app is in the background and picks itself
/// back up after a restart. The ticker below only asks for a repaint.
class HabitTimerControl extends StatefulWidget {
  const HabitTimerControl({
    super.key,
    required this.targetSeconds,
    required this.loggedSeconds,
    required this.runningSince,
    required this.completed,
    required this.doneColor,
    required this.onStart,
    required this.onStop,
  });

  final int targetSeconds;

  /// Seconds already banked for today by runs that have finished.
  final int loggedSeconds;

  /// When the current run started, or null when the timer is not running.
  final DateTime? runningSince;
  final bool completed;

  /// The fill of the "done" mark the control turns into — the task's colour.
  final Color doneColor;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  State<HabitTimerControl> createState() => _HabitTimerControlState();
}

class _HabitTimerControlState extends State<HabitTimerControl> {
  Timer? _tick;

  /// Set between asking for the run to be closed and the database saying it is.
  /// Without it the ticker would fire the finish again on every second of that
  /// gap, replaying the sound and the haptic.
  bool _finishing = false;

  bool get _running => widget.runningSince != null;

  @override
  void initState() {
    super.initState();
    _syncTicker();
    // A run may already be over when this is built — the app was away while the
    // clock ran out. Settle that once the first frame is on screen rather than
    // writing to the database during build.
    if (_running) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishIfDue());
    }
  }

  @override
  void didUpdateWidget(HabitTimerControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.runningSince != oldWidget.runningSince) {
      _finishing = false;
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// One repaint per second while a run is going, nothing at all when it is not.
  /// A second is the readout's own resolution, so anything finer buys nothing.
  void _syncTicker() {
    _tick?.cancel();
    if (!_running) {
      _tick = null;
      return;
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _finishIfDue();
    });
  }

  /// Seconds worked today: what is banked, plus the run in progress.
  int get _elapsed {
    final since = widget.runningSince;
    if (since == null) return widget.loggedSeconds;
    // A clock that moved backwards must not eat time already worked.
    final ran = DateTime.now().difference(since).inSeconds;
    return widget.loggedSeconds + (ran < 0 ? 0 : ran);
  }

  /// What is left of the target — the mock-up counts down, not up.
  int get _remaining =>
      widget.targetSeconds - _elapsed.clamp(0, widget.targetSeconds);

  void _toggle() {
    if (_running) {
      widget.onStop();
    } else {
      widget.onStart();
    }
  }

  void _finishIfDue() {
    if (!_running || _finishing || widget.completed) return;
    if (_elapsed < widget.targetSeconds) return;

    _finishing = true;
    // Closing the run is what marks the day done — the stop path already folds
    // the seconds in and ticks the log once the target is reached.
    widget.onStop();
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.mediumImpact();
  }

  static String _fmt(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.completed) {
      return _CheckCircle(done: true, color: widget.doneColor, onTap: null);
    }

    final p = AppPalette.of(Theme.of(context));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _fmt(_remaining),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: p.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        _TouchTarget(
          tooltip: _running ? 'Остановить таймер' : 'Запустить таймер',
          onTap: _toggle,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: p.textPrimary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _running ? LucideIcons.pause : LucideIcons.play,
              size: 12,
              color: p.background,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.repeat, size: 48, color: p.iconMuted),
          const SizedBox(height: 12),
          Text(
            'Нет повторяющихся задач',
            style: TextStyle(fontSize: 15, color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}
