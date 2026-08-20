import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/habit_actions_sheet.dart';
import 'package:todo_app/widgets/habits/habit_day_state.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/tracking.dart';

/// Grid of habit cards — every active task that has a repeat rule, shown in two
/// columns regardless of whether it is scheduled for the current day.
class HabitsGrid extends ConsumerWidget {
  const HabitsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(rootTasksProvider);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentMonday = today.subtract(Duration(days: today.weekday - 1));
    final prevMonday = currentMonday.subtract(const Duration(days: 7));
    final days = List.generate(14, (i) => prevMonday.add(Duration(days: i)));
    final range = DateRange(
      prevMonday,
      prevMonday.add(const Duration(days: 14)),
    );
    final logsAsync = ref.watch(logsBetweenProvider(range));
    final sessions =
        ref.watch(openSessionsProvider).valueOrNull ?? const <TaskSession>[];

    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
      data: (tasks) {
        final habits = tasks
            .where((t) => t.status == TaskStatus.active)
            .where((t) => t.repeatType != null)
            .toList();

        if (habits.isEmpty) return const _EmptyState();

        final logs = logsAsync.valueOrNull ?? const <TaskLog>[];
        // A run going right now; its start instant is what the timer buttons
        // measure the elapsed time against.
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

        // Distribute cards across two balanced masonry-style columns.
        final left = <Widget>[];
        final right = <Widget>[];
        for (var i = 0; i < habits.length; i++) {
          final task = habits[i];
          final card = Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HabitCard(
              task: task,
              days: days,
              today: today,
              completedDays: completedByTask[task.id] ?? const {},
              todayLog: todayLogByTask[task.id],
              onTap: () => showHabitActionsSheet(context, task: task),
              onMark: () =>
                  ref.read(tasksDaoProvider).toggleCompletion(task.id, today),
              timerRunningSince: runningSince[task.id],
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
                  .incrementCounter(
                    task.id,
                    today,
                    counterTarget(task).toDouble(),
                  ),
            ),
          );
          (i.isEven ? left : right).add(card);
        }

        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: left)),
              const SizedBox(width: 12),
              Expanded(child: Column(children: right)),
            ],
          ),
        );
      },
    );
  }
}

class HabitCard extends StatelessWidget {
  const HabitCard({
    super.key,
    required this.task,
    required this.days,
    required this.today,
    required this.completedDays,
    required this.todayLog,
    required this.timerRunningSince,
    required this.onTap,
    required this.onMark,
    required this.onTimerStart,
    required this.onTimerStop,
    required this.onCounterInc,
  });

  final Task task;
  final List<DateTime> days;
  final DateTime today;
  final Set<DateTime> completedDays;
  final TaskLog? todayLog;

  /// When this habit's timer was started, or null when it is not running.
  final DateTime? timerRunningSince;
  final VoidCallback onTap;
  final VoidCallback onMark;
  final VoidCallback onTimerStart;
  final VoidCallback onTimerStop;
  final VoidCallback onCounterInc;

  Color get _color => task.colorValue != null
      ? Color(task.colorValue!)
      : ColorPickerRow.colors.first;

  /// Neutral chip for a habit already done today, the same tone as the tab bar
  /// on this screen. A finished habit recedes so the ones still open stand out.
  Color _cardColorOf(ThemeData theme) =>
      _doneToday ? neutralChip(theme) : _color;

  IconData get _icon => task.iconCodePoint != null
      // ignore: non_const_argument_for_const_parameter
      ? IconData(task.iconCodePoint!, fontFamily: 'MaterialIcons')
      : Icons.repeat;

  bool get _doneToday => completedDays.contains(today);

  /// Line height of the title, kept explicit so [_titleBlockHeight] can reserve
  /// exactly two lines for it.
  static const _titleLineHeight = 1.25;
  static const _titleMaxLines = 2;

  /// Height of the title block. It is fixed so that a one-line and a two-line
  /// title produce cards of the same height instead of pushing the layout down.
  double _titleBlockHeight(BuildContext context, TextStyle? style) {
    final fontSize = style?.fontSize ?? 14;
    final scaled = MediaQuery.textScalerOf(context).scale(fontSize);
    return scaled * _titleLineHeight * _titleMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = _cardColorOf(theme);
    final muted = onTaskColorFaint(cardColor);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      height: _titleLineHeight,
      color: onTaskColor(cardColor),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _titleBlockHeight(context, titleStyle),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: _titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(_icon, size: 18, color: muted),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _DaysGrid(
              task: task,
              days: days,
              today: today,
              completedDays: completedDays,
            ),
            const SizedBox(height: 12),
            if (task.trackingMode == TrackingMode.timer &&
                task.targetDurationMinutes != null &&
                task.targetDurationMinutes! > 0)
              _TimerButton(
                key: ValueKey('timer-${task.id}-$today'),
                targetSeconds: task.targetDurationMinutes! * 60,
                loggedSeconds: (todayLog?.value ?? 0).round(),
                runningSince: timerRunningSince,
                completed: _doneToday,
                onStart: onTimerStart,
                onStop: onTimerStop,
              )
            // Any counter counts, target set or not: [counterTarget] floors it
            // at one, so the button can never open on "Выполнено".
            else if (task.trackingMode == TrackingMode.counter)
              _CounterButton(
                count: (todayLog?.value ?? 0).round(),
                target: counterTarget(task),
                done: _doneToday,
                onTap: onCounterInc,
              )
            else
              _MarkButton(done: _doneToday, onTap: onMark),
          ],
        ),
      ),
    );
  }
}

class _DaysGrid extends StatelessWidget {
  const _DaysGrid({
    required this.task,
    required this.days,
    required this.today,
    required this.completedDays,
  });

  final Task task;
  final List<DateTime> days;
  final DateTime today;
  final Set<DateTime> completedDays;

  @override
  Widget build(BuildContext context) {
    List<Widget> row(int offset) => [
      for (var i = 0; i < 7; i++) ...[
        if (i > 0) const SizedBox(width: 5),
        Expanded(
          child: _DaySquare(
            state: habitDayState(
              task,
              days[offset + i],
              today: today,
              completedDays: completedDays,
            ),
          ),
        ),
      ],
    ];

    return Column(
      children: [
        Row(children: row(0)),
        const SizedBox(height: 5),
        Row(children: row(7)),
      ],
    );
  }
}

/// One day of the strip, drawn in white over the habit's colour. A missed day is
/// hollow, a day the habit does not fall on is only a faint dot.
class _DaySquare extends StatelessWidget {
  const _DaySquare({required this.state});

  final HabitDayState state;

  @override
  Widget build(BuildContext context) {
    if (state == HabitDayState.off) {
      return AspectRatio(
        aspectRatio: 1,
        child: Center(
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    final (Color fill, Color? border) = switch (state) {
      HabitDayState.done => (Colors.white, null),
      HabitDayState.today => (
        Colors.white.withValues(alpha: 0.40),
        Colors.white.withValues(alpha: 0.95),
      ),
      // Pre-history looks the same as a miss: an empty slot to fill in.
      HabitDayState.missed || HabitDayState.beforeStart => (
        Colors.transparent,
        Colors.white.withValues(alpha: 0.55),
      ),
      HabitDayState.upcoming => (Colors.white.withValues(alpha: 0.28), null),
      HabitDayState.off => (Colors.transparent, null),
    };

    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(5),
          border: border == null ? null : Border.all(color: border, width: 1.4),
        ),
      ),
    );
  }
}

class _MarkButton extends StatelessWidget {
  const _MarkButton({required this.done, required this.onTap});

  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done ? Colors.white : Colors.white.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              done ? Icons.check_rounded : Icons.add_rounded,
              size: 16,
              color: Colors.black.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            // Shrinks instead of overflowing: "Выполнено" is wider than
            // "Отметить" and a narrow card leaves it no room.
            Flexible(
              child: Text(
                done ? 'Выполнено' : 'Отметить',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({
    required this.count,
    required this.target,
    required this.done,
    required this.onTap,
  });

  final int count;
  final int target;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = done || count >= target;
    final labelColor = Colors.black.withValues(alpha: 0.7);

    final IconData? icon;
    final String label;
    if (complete) {
      icon = Icons.check_rounded;
      label = 'Выполнено';
    } else if (count > 0) {
      icon = null;
      label = '$count/$target';
    } else {
      icon = Icons.add_rounded;
      label = 'Отметить';
    }

    return GestureDetector(
      onTap: complete ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: complete ? Colors.white : Colors.white.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: labelColor),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Start/pause plate for a habit tracked by a timer.
///
/// The elapsed time is never accumulated here: [loggedSeconds] is what previous
/// runs already banked for the day, and [runningSince] is when the current run
/// began. Everything on screen is derived from those two against the wall clock,
/// so a run keeps counting while the app is in the background and picks itself
/// back up after a restart. The ticker below only asks for a repaint.
class _TimerButton extends StatefulWidget {
  const _TimerButton({
    super.key,
    required this.targetSeconds,
    required this.loggedSeconds,
    required this.runningSince,
    required this.completed,
    required this.onStart,
    required this.onStop,
  });

  final int targetSeconds;

  /// Seconds already banked for today by runs that have finished.
  final int loggedSeconds;

  /// When the current run started, or null when the timer is not running.
  final DateTime? runningSince;
  final bool completed;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  State<_TimerButton> createState() => _TimerButtonState();
}

class _TimerButtonState extends State<_TimerButton> {
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
  void didUpdateWidget(_TimerButton oldWidget) {
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

  int get _shownSeconds => _elapsed.clamp(0, widget.targetSeconds);

  double get _fraction => widget.targetSeconds <= 0
      ? 0
      : (_elapsed / widget.targetSeconds).clamp(0.0, 1.0);

  void _toggle() {
    if (widget.completed) return;
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

  String _fmt(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = Colors.black.withValues(alpha: 0.75);

    final elapsed = _shownSeconds;

    final IconData? icon;
    final String label;
    if (widget.completed) {
      icon = Icons.check_rounded;
      label = 'Выполнено';
    } else if (_running) {
      icon = null;
      label = _fmt(elapsed);
    } else if (elapsed > 0) {
      icon = Icons.pause_rounded;
      label = _fmt(elapsed);
    } else {
      icon = Icons.play_arrow_rounded;
      label = 'Начать';
    }

    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 34,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Colors.white.withValues(alpha: 0.25)),
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _fraction,
                    heightFactor: 1,
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: labelColor),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
            Icons.repeat,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'Нет повторяющихся задач',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
