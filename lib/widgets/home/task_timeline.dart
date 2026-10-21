import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/day_plan.dart';
import 'package:todo_app/utils/habit_labels.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/settings/group_settings.dart';
import 'package:todo_app/utils/task_audience.dart';
import 'package:todo_app/widgets/member_avatar.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_icons.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/utils/tracking.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/task_actions_sheet.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The day under the calendar, in the "Иней" layout (`Timeline.dc.html`): an
/// overview card with the day's ribbon, "В течение дня" for the tasks with no
/// time, then the timed ones as rows on a line.
///
/// A row's capsule is as tall as the task is long — [pxPerMinute], never less
/// than [minCapsule] — but the rows themselves are not on a time scale: a free
/// stretch is one "Свободно 2 ч" row, not two hours of empty line.
///
/// Tasks whose times run into each other are one row (see [clusterByOverlap]):
/// their capsules side by side on the line, their texts one under another, and
/// under each later one, in red, what it collides with and for how long.
class TaskTimeline extends ConsumerStatefulWidget {
  const TaskTimeline({
    super.key,
    required this.selectedDay,
    this.scrollController,
  });

  final DateTime selectedDay;
  final ScrollController? scrollController;

  /// 72px an hour (DESIGN.md §6, "Таймлайн").
  static const double pxPerMinute = 72 / 60;
  static const double minCapsule = 26;

  /// A point task — a start and no end — is a dot this wide.
  static const double pointSize = 12;

  /// A free stretch at least this long gets a "Свободно" row of its own.
  static const int freeRowMinutes = 120;

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

  /// Rebuilds once per minute, aligned to the minute boundary, so "Сейчас" and
  /// the ribbon's mark keep up with the clock. A minute is the timeline's own
  /// resolution, so anything finer buys nothing.
  void _scheduleTick() {
    final now = DateTime.now();
    final toNextMinute = Duration(
      milliseconds: 60000 - (now.second * 1000 + now.millisecond),
    );
    _tick = Timer(toNextMinute, () {
      if (!mounted) return;
      // Only today's timeline moves; other days are static.
      if (DateUtils.isSameDay(DateTime.now(), widget.selectedDay)) {
        setState(() {});
      }
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
        // Mine, plus every task of a group switched to "show all"; the rest of a
        // group is listed by its own screen.
        final me = ref.watch(myUidProvider);
        // Read only when another member's task exists at all, like the group
        // providers below: a phone with no groups costs no lookup.
        final showAll = allTasks.any((t) => !isMyTask(t, me))
            ? ref.watch(groupsShowAllProvider)
            : const <String>{};
        final dayTasks = allTasks
            .where(
              (t) =>
                  t.parentId == null &&
                  (isMyTask(t, me) || showAll.contains(t.groupUid)) &&
                  t.status == TaskStatus.active &&
                  isTaskScheduledOn(t, selectedDay),
            )
            .toList();
        final timed = dayTasks
            .where((t) => t.scheduledTimeMinutes != null)
            .toList();
        // Tasks that belong to this day but carry no time of their own: one-off
        // tasks first, then habits, alphabetical within each.
        final untimed =
            dayTasks.where((t) => t.scheduledTimeMinutes == null).toList()
              ..sort((a, b) {
                final kind = (a.repeatType != null ? 1 : 0).compareTo(
                  b.repeatType != null ? 1 : 0,
                );
                return kind != 0 ? kind : a.title.compareTo(b.title);
              });

        final logs = logsAsync.valueOrNull ?? const <TaskLog>[];
        final logsByTaskId = {for (final l in logs) l.taskId: l};

        // Only read when a group task is on screen: a day of personal tasks —
        // which is every day for someone with no groups — costs no query.
        final hasGroupTasks = dayTasks.any((t) => t.groupUid != null);
        final marks = hasGroupTasks
            ? ref.watch(groupMarksProvider).valueOrNull ?? const <GroupMark>[]
            : const <GroupMark>[];
        final members = hasGroupTasks
            ? ref.watch(groupMembersProvider).valueOrNull ??
                  const <GroupMember>[]
            : const <GroupMember>[];
        // Only read when a timer habit is among the circles, for the same reason
        // as the groups: a day without one costs no query.
        final runningTimers =
            untimed.any((t) => t.trackingMode == TrackingMode.timer)
            ? {
                for (final s
                    in ref.watch(openSessionsProvider).valueOrNull ??
                        const <TaskSession>[])
                  s.taskId,
              }
            : const <int>{};
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dayIsPast = selectedDay.isBefore(today);
        _GroupNote? noteFor(Task task) {
          final groupUid = task.groupUid;
          if (groupUid == null) return null;
          GroupMember? member(String? uid) => members
              .where((m) => m.groupUid == groupUid && m.userUid == uid)
              .firstOrNull;
          final assignee = task.assigneeUid;
          if (assignee == null) {
            final status = sharedTaskStatus(
              task,
              selectedDay,
              me: me,
              done: logsByTaskId[task.id]?.completed ?? false,
              marks: marks,
              members: members,
            );
            return _GroupNote('Для всех · $status');
          }
          if (assignee != me) {
            final done = groupTaskDoneBy(
              task,
              selectedDay,
              me: me,
              doneByMe: false,
              marks: marks,
            ).contains(assignee);
            final name = memberName(member(assignee));
            return _GroupNote(
              'Для: $name · ${done
                  ? 'выполнено'
                  : dayIsPast
                  ? 'не выполнено'
                  : 'ждёт'}',
              delegatedTo: name,
              done: done,
            );
          }
          if (task.authorUid != me) {
            return _GroupNote('От: ${memberName(member(task.authorUid))}');
          }
          return null;
        }

        _EntryState stateOf(Task task) {
          final note = noteFor(task);
          final subtasks = subtasksByParent[task.id] ?? const <Task>[];
          // Looked up on the tap, not here: building a row must not open the
          // database for a day that nobody touches.
          TasksDao dao() => ref.read(tasksDaoProvider);
          void openSheet() => showTaskActionsSheet(
            context,
            task: task,
            completed: logsByTaskId[task.id]?.completed ?? false,
            completionDate: selectedDay,
          );
          final running = runningTimers.contains(task.id);
          final targetSeconds = (task.targetDurationMinutes ?? 0) * 60;
          // A circle acts on the habit's own terms; a task of someone else's is
          // not mine to tick, and a timer runs against the clock, so only today's.
          final VoidCallback quick = note?.delegatedTo != null
              ? openSheet
              : switch (task.trackingMode) {
                  TrackingMode.checkbox => () => dao().toggleCompletion(
                    task.id,
                    selectedDay,
                  ),
                  TrackingMode.counter => () => dao().incrementCounter(
                    task.id,
                    selectedDay,
                    counterTarget(task).toDouble(),
                  ),
                  TrackingMode.timer when selectedDay == today =>
                    () => running
                        ? dao().stopTimer(
                            task.id,
                            DateTime.now(),
                            targetSeconds: targetSeconds,
                          )
                        : dao().startTimer(
                            task.id,
                            DateTime.now(),
                            targetSeconds: targetSeconds,
                          ),
                  _ => openSheet,
                };
          return _EntryState(
            task: task,
            note: note,
            completed: note?.delegatedTo != null
                ? note!.done
                : logsByTaskId[task.id]?.completed ?? false,
            subtaskTotal: subtasks.length,
            subtaskDone: subtasks
                .where((s) => logsByTaskId[s.id]?.completed ?? false)
                .length,
            onToggle: () => dao().toggleCompletion(task.id, selectedDay),
            onTap: openSheet,
            onQuick: quick,
            progress: task.trackingMode == TrackingMode.counter
                ? '${(logsByTaskId[task.id]?.value ?? 0).floor()}/${counterTarget(task)}'
                : null,
            fraction: task.trackingMode == TrackingMode.counter
                ? ((logsByTaskId[task.id]?.value ?? 0) / counterTarget(task))
                      .clamp(0.0, 1.0)
                : null,
            timerRunning: running,
          );
        }

        final isToday = selectedDay == today;
        final nowMin = now.hour * 60 + now.minute;
        final bottomInset = MediaQuery.paddingOf(context).bottom + 88;

        return ListView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(16, 14, 16, bottomInset),
          children: [
            _DayOverview(
              day: selectedDay,
              taskCount: dayTasks.length,
              timed: [for (final t in timed) stateOf(t)],
              nowMinutes: isToday ? nowMin : null,
            ),
            if (untimed.isNotEmpty) ...[
              const SizedBox(height: 14),
              _UntimedCard(entries: [for (final t in untimed) stateOf(t)]),
            ],
            const SizedBox(height: 14),
            if (timed.isEmpty)
              _EmptyState(
                free: dayTasks.isEmpty,
                day: selectedDay,
                nowMinutes: isToday ? nowMin : null,
              )
            else
              _TimelineCard(
                clusters: clusterByOverlap(timed),
                stateOf: stateOf,
                nowMinutes: isToday ? nowMin : null,
              ),
          ],
        );
      },
    );
  }
}

/// What a row needs to know about one task besides the task itself.
class _EntryState {
  const _EntryState({
    required this.task,
    required this.note,
    required this.completed,
    required this.subtaskTotal,
    required this.subtaskDone,
    required this.onToggle,
    required this.onTap,
    required this.onQuick,
    this.progress,
    this.fraction,
    this.timerRunning = false,
  });

  final Task task;
  final _GroupNote? note;

  /// Mine ticked — or, for a task I handed over, theirs.
  final bool completed;
  final int subtaskTotal;
  final int subtaskDone;
  final VoidCallback onToggle;

  /// Opens the task's sheet.
  final VoidCallback onTap;

  /// What a tap on the circle of "В течение дня" does, by tracking mode: ticks,
  /// adds one, starts or stops the timer — or opens the sheet where the circle
  /// cannot act (a task handed to someone else, a timer on another day).
  final VoidCallback onQuick;

  /// A counter's "3/8", the feedback a +1 would otherwise not give.
  final String? progress;

  /// How far a counter has come, 0 to 1 — what its ring is filled to. Null for
  /// every other mode, which has no ring.
  final double? fraction;
  final bool timerRunning;

  Color get color => task.colorValue != null
      ? Color(task.colorValue!)
      : ColorPickerRow.colors.first;
}

/// The task colour as a line or a dot reads it: the family's own tone on a light
/// screen, its dark-theme ink on a dark one.
Color _inkOf(ThemeData theme, Color color, Color surface) =>
    theme.brightness == Brightness.light
    ? inkOn(surface, color, minContrast: 2)
    : taskBadgeInk(theme, color, surface);

/// "Привычка · Пн, Ср, Пт", "Подзадачи 2/6", "Задача".
String _kindLabel(_EntryState e) {
  final task = e.task;
  if (task.repeatType != null) {
    final rule = habitRuleLabel(task);
    return rule == 'Каждый день' ? 'Привычка' : 'Привычка · $rule';
  }
  if (e.subtaskTotal > 0) return 'Подзадачи ${e.subtaskDone}/${e.subtaskTotal}';
  return 'Задача';
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Material(
      color: p.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.border),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// Обзор дня
// ---------------------------------------------------------------------------

/// "Пятница · 8 дел · занято 4 ч 25 мин" over a 7–22h ribbon of the day's busy
/// stretches and the current moment.
class _DayOverview extends StatelessWidget {
  const _DayOverview({
    required this.day,
    required this.taskCount,
    required this.timed,
    required this.nowMinutes,
  });

  final DateTime day;
  final int taskCount;
  final List<_EntryState> timed;
  final int? nowMinutes;

  static const _from = 7 * 60;
  static const _to = 22 * 60;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final weekday = DateFormat('EEEE', 'ru_RU').format(day);
    final busy = busyMinutes([for (final e in timed) e.task]);
    final summary = taskCount == 0
        ? 'дел нет · весь день свободен'
        : [
            '$taskCount ${pluralRu(taskCount, 'дело', 'дела', 'дел')}',
            if (busy > 0) 'занято ${durationLabel(busy)}',
          ].join(' · ');

    return _Card(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                weekday[0].toUpperCase() + weekday.substring(1),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              // The summary gives way, not the day's name: at a large system
              // font it is cut short rather than pushed off the card.
              Expanded(
                child: Text(
                  summary,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Semantics(
            label:
                'Лента дня с 7 до 22 часов'
                '${nowMinutes == null ? '' : ', сейчас ${clockLabel(nowMinutes!)}'}',
            excludeSemantics: true,
            child: SizedBox(
              height: 34,
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  double x(int minutes) =>
                      (minutes.clamp(_from, _to) - _from) / (_to - _from) * w;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 6,
                        height: 14,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: p.chip,
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      ),
                      for (final e in timed)
                        if (TimedSpan(e.task) case final span
                            when span.end >= _from && span.start <= _to)
                          Positioned(
                            left: x(span.start),
                            top: 6,
                            height: 14,
                            width: math.max(4, x(span.end) - x(span.start)),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _inkOf(
                                  theme,
                                  e.color,
                                  p.surface,
                                ).withValues(alpha: e.completed ? 0.45 : 1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                      if (nowMinutes case final m? when m >= _from && m <= _to)
                        Positioned(
                          left: x(m) - 1,
                          top: 1,
                          width: 2,
                          height: 24,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      for (final hour in const [8, 12, 16, 20])
                        Positioned(
                          left: x(hour * 60) - 20,
                          width: 40,
                          top: 22,
                          child: Text(
                            clockLabel(hour * 60),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: p.textTertiary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// В течение дня
// ---------------------------------------------------------------------------

/// Whether "В течение дня" is folded. A provider and not card state: the card is
/// rebuilt for every day the user swipes to, and a fold that came undone on each
/// swipe would be no fold at all. Kept for the session only.
final untimedFoldedProvider = StateProvider<bool>((ref) => false);

/// The day's tasks with no time of their own, as a horizontal strip: a circle in
/// the task's colour with its icon, the title underneath. It scrolls sideways
/// when the circles outgrow the card, and the arrow in the header folds the card
/// to its header. A tap opens the task's sheet, where it can be ticked.
class _UntimedCard extends ConsumerWidget {
  const _UntimedCard({required this.entries});

  final List<_EntryState> entries;

  static const double circleSize = 52;
  static const double slotWidth = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(Theme.of(context));
    final folded = ref.watch(untimedFoldedProvider);
    void toggle() => ref.read(untimedFoldedProvider.notifier).state = !folded;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: toggle,
            child: Semantics(
              button: true,
              expanded: !folded,
              label: folded
                  ? 'Развернуть «В течение дня»'
                  : 'Свернуть «В течение дня»',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'В ТЕЧЕНИЕ ДНЯ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.04,
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${entries.where((e) => e.completed).length} из ${entries.length}',
                      style: TextStyle(fontSize: 13, color: p.textSecondary),
                    ),
                    SizedBox.square(
                      dimension: 40,
                      child: AnimatedRotation(
                        turns: folded ? -0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          LucideIcons.chevron_down,
                          size: 20,
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: folded
                ? const SizedBox(width: double.infinity)
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in entries) _UntimedSlot(entry: e),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The round badge of a task in "В течение дня": the family's pale tone with its
/// glyph in the strong one, like the tile on the habits tab. A counter's fills a
/// ring along its inner rim as the count climbs. Done, it turns to the strong
/// tone itself with a white check — the darker circle says "finished".
///
/// Becoming done is a small event: the circle pops (swells and settles), the
/// colour fades to the strong tone and the check scales in over the old glyph.
/// Only the *change* plays — a day opened with the task already done, or one
/// swiped to, shows it settled.
class _Circle extends StatefulWidget {
  const _Circle({required this.entry});

  final _EntryState entry;

  @override
  State<_Circle> createState() => _CircleState();
}

class _CircleState extends State<_Circle> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.16,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.16,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 60,
    ),
  ]).animate(_pop);

  @override
  void didUpdateWidget(_Circle old) {
    super.didUpdateWidget(old);
    if (!old.entry.completed && widget.entry.completed) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final size = _UntimedCard.circleSize;
    final fill = taskBadgeSurface(theme, entry.color, p.surface);
    final strong = taskBadgeInk(theme, entry.color, fill);
    final done = entry.completed;
    final glyph = Icon(
      done
          ? LucideIcons.check
          : entry.timerRunning
          ? LucideIcons.pause
          : taskIconFor(entry.task.iconKey) ?? LucideIcons.circle_check,
      size: 24,
      color: done ? onTaskColor(strong) : strong,
    );
    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? strong : fill,
        shape: BoxShape.circle,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: KeyedSubtree(
          key: ValueKey(
            done
                ? 'done'
                : entry.timerRunning
                ? 'run'
                : 'idle',
          ),
          child: glyph,
        ),
      ),
    );

    // Always wrapped, ring or not: swapping the wrapper out when a counter
    // finishes would rebuild the circle and drop the colour fade. A finished
    // counter's arc runs on to the full turn as the circle fills in behind it.
    return ScaleTransition(
      scale: _scale,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: done ? 1.0 : entry.fraction ?? 0),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => CustomPaint(
          foregroundPainter: entry.fraction == null
              ? null
              : _RingPainter(fraction: value, arc: strong, stroke: 4),
          child: child,
        ),
        child: badge,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.arc,
    required this.stroke,
  });

  final double fraction;
  final Color arc;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // Flush with the circle: the stroke's outer edge is the circle's own, so no
    // strip of the pale fill shows outside the arc.
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (fraction > 0) {
      // From twelve o'clock, clockwise.
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        paint..color = arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.arc != arc || old.stroke != stroke;
}

class _UntimedSlot extends StatelessWidget {
  const _UntimedSlot({required this.entry});

  final _EntryState entry;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final done = entry.completed;
    final delegatedTo = entry.note?.delegatedTo;
    return GestureDetector(
      // The circle acts; holding it opens the sheet.
      onTap: entry.onQuick,
      onLongPress: entry.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        // A fixed slot keeps the circles evenly spaced whatever the titles say.
        width: _UntimedCard.slotWidth,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _Circle(entry: entry),
                // A task of another member carries their letter.
                if (delegatedTo != null)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: MemberAvatar(name: delegatedTo, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              entry.task.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                color: done ? p.textTertiary : p.textPrimary,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
            if (entry.progress != null)
              Text(
                entry.progress!,
                style: TextStyle(
                  fontSize: 12,
                  color: p.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The line
// ---------------------------------------------------------------------------

/// The geometry the rows share: [left] padding, then the time column, the node
/// column the line runs down, and the text.
abstract final class _Axis {
  static const double left = 14;
  static const double time = 56;
  static const double gap = 10;

  /// Room for three 6px lanes and their gaps.
  static const double node = 24;
  static const double top = 12;

  static double get nodeLeft => left + time + gap;
  static double get bodyLeft => nodeLeft + node + gap;
  static double get lineX => nodeLeft + node / 2;
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.clusters,
    required this.stateOf,
    required this.nowMinutes,
  });

  final List<TimedCluster> clusters;
  final _EntryState Function(Task) stateOf;

  /// Minutes past midnight on today's timeline; null on any other day.
  final int? nowMinutes;

  @override
  Widget build(BuildContext context) {
    // "Сейчас" stands before the first block that has not begun; after all of
    // them once the day's last one has.
    final now = nowMinutes;
    int? nowAt;
    if (now != null) {
      final i = clusters.indexWhere((c) => c.start > now);
      nowAt = i < 0 ? clusters.length : i;
    }

    final rows = <Widget>[];
    for (var i = 0; i <= clusters.length; i++) {
      final past = nowAt != null && i < nowAt;
      if (i == nowAt) {
        final next = i < clusters.length ? clusters[i] : null;
        rows.add(
          _NowRow(
            minutes: now!,
            next: next?.entries.first.span.task.title,
            minutesToNext: next == null ? null : next.start - now,
            first: rows.isEmpty,
            last: i == clusters.length,
          ),
        );
      } else if (i > 0 && i < clusters.length) {
        final free = clusters[i].start - clusters[i - 1].end;
        if (free >= TaskTimeline.freeRowMinutes) {
          rows.add(_FreeRow(minutes: free, past: past));
        }
      }
      if (i == clusters.length) break;
      rows.add(
        _ClusterRow(
          cluster: clusters[i],
          entries: [for (final e in clusters[i].entries) stateOf(e.span.task)],
          past: past,
          first: rows.isEmpty,
          last: i == clusters.length - 1 && nowAt != clusters.length,
        ),
      );
    }

    return _Card(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: rows),
    );
  }
}

/// The line through the node column: [top] to [bottom] of the row, darker above
/// "Сейчас" — the part of the day already behind.
Widget _lineSegment(
  AppPalette p, {
  required double top,
  double? height,
  double? bottom,
  required bool past,
}) => Positioned(
  left: _Axis.lineX - 0.75,
  top: top,
  height: height,
  bottom: height == null ? (bottom ?? 0) : null,
  width: 1.5,
  child: ColoredBox(color: past ? p.outline : p.borderStrong),
);

/// One block of the timeline: a task, or the tasks whose times run into each
/// other (decided 2026-10-19).
///
/// A block of several opens with a quiet "3 задачи пересекаются · 15:00–16:30".
/// On the axis each task runs in its lane ([ClusterEntry.lane]) — at most
/// [maxLanes] are drawn, 6px each, and "+N" under them counts the tasks of the
/// lanes beyond. Below, every task keeps its own text and its own ring — each
/// has to be tickable — but past [shownEntries] the rest fold behind "Ещё N
/// задачи".
class _ClusterRow extends StatefulWidget {
  const _ClusterRow({
    required this.cluster,
    required this.entries,
    required this.past,
    required this.first,
    required this.last,
  });

  final TimedCluster cluster;
  final List<_EntryState> entries;
  final bool past;
  final bool first;
  final bool last;

  static const int maxLanes = 3;
  static const int shownEntries = 3;
  static const double laneWidth = 6;
  static const double laneGap = 3;

  static double capsuleOf(TimedSpan span) => span.isPoint
      ? TaskTimeline.pointSize
      : math.max(
          span.minutes * TaskTimeline.pxPerMinute,
          TaskTimeline.minCapsule,
        );

  @override
  State<_ClusterRow> createState() => _ClusterRowState();
}

class _ClusterRowState extends State<_ClusterRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final cluster = widget.cluster;
    final n = cluster.entries.length;
    double topOf(TimedSpan s) =>
        _Axis.top + (s.start - cluster.start) * TaskTimeline.pxPerMinute;
    final drawn = [
      for (final (i, e) in cluster.entries.indexed)
        if (e.lane < _ClusterRow.maxLanes) i,
    ];
    final hidden = n - drawn.length;
    final pillsBottom = drawn
        .map((i) {
          final s = cluster.entries[i].span;
          return topOf(s) + _ClusterRow.capsuleOf(s);
        })
        .reduce(math.max);

    // A task alone is the full 12px; in a block every lane is 6px, the lanes
    // centred on the line.
    final lanes = math.min(cluster.laneCount, _ClusterRow.maxLanes);
    final width = n == 1 ? TaskTimeline.pointSize : _ClusterRow.laneWidth;
    final groupWidth = n == 1
        ? width
        : lanes * width + (lanes - 1) * _ClusterRow.laneGap;
    final groupLeft = _Axis.nodeLeft + (_Axis.node - groupWidth) / 2;

    final showEnd =
        cluster.end > cluster.start && pillsBottom - _Axis.top >= 50;
    final folds = n > _ClusterRow.shownEntries;
    final shown = folds && !_expanded ? _ClusterRow.shownEntries : n;
    // The day's first block starts its line at its first capsule.
    final lineTop = widget.first ? _Axis.top : 0.0;

    final block = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: pillsBottom + (hidden > 0 ? 28 : 18),
      ),
      child: Stack(
        children: [
          _lineSegment(
            p,
            top: lineTop,
            height: pillsBottom - lineTop,
            past: widget.past,
          ),
          if (!widget.last)
            _lineSegment(p, top: pillsBottom, past: widget.past),
          Positioned(
            left: _Axis.left,
            width: _Axis.time,
            top: _Axis.top - 3,
            child: Text(
              clockLabel(cluster.start),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: widget.entries.every((e) => e.completed)
                    ? p.textTertiary
                    : p.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (showEnd)
            Positioned(
              left: _Axis.left,
              width: _Axis.time,
              top: pillsBottom - 15,
              child: Text(
                clockLabel(cluster.end),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  color: p.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          for (final i in drawn)
            Positioned(
              left:
                  groupLeft +
                  cluster.entries[i].lane * (width + _ClusterRow.laneGap),
              top: topOf(cluster.entries[i].span),
              width: width,
              height: _ClusterRow.capsuleOf(cluster.entries[i].span),
              child: Semantics(
                container: true,
                label: _spanLabel(cluster.entries[i].span),
                child: _Capsule(entry: widget.entries[i]),
              ),
            ),
          if (hidden > 0)
            Positioned(
              left: _Axis.lineX - 14,
              width: 28,
              top: pillsBottom + 6,
              child: Center(
                child: Semantics(
                  container: true,
                  label: 'Ещё $hidden на оси',
                  excludeSemantics: true,
                  child: Container(
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.chip,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+$hidden',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: p.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(left: _Axis.bodyLeft, top: _Axis.top - 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, entry)
                    in cluster.entries.take(shown).indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _ClusterEntryBody(
                    entry: widget.entries[i],
                    span: entry.span,
                    conflicts: entry.conflicts,
                    showRange: cluster.overlaps,
                  ),
                ],
                if (folds)
                  _FoldToggle(
                    hiddenCount: n - _ClusterRow.shownEntries,
                    expanded: _expanded,
                    onTap: () => setState(() => _expanded = !_expanded),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );

    if (!cluster.overlaps) return block;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            if (!widget.first) _lineSegment(p, top: 0, past: widget.past),
            Padding(
              padding: EdgeInsets.only(left: _Axis.bodyLeft, top: 8, right: 16),
              child: Text(
                '$n ${pluralRu(n, 'задача пересекается', 'задачи пересекаются', 'задач пересекаются')}'
                ' · ${clockLabel(cluster.start)}–${clockLabel(cluster.end)}',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            ),
          ],
        ),
        block,
      ],
    );
  }
}

String _spanLabel(TimedSpan span) => span.isPoint
    ? clockLabel(span.start)
    : '${clockLabel(span.start)} – ${clockLabel(span.end)}, '
          '${durationLabel(span.minutes)}';

/// "Ещё 2 задачи ⌄" under a folded block, "Свернуть ⌃" once it is open.
class _FoldToggle extends StatelessWidget {
  const _FoldToggle({
    required this.hiddenCount,
    required this.expanded,
    required this.onTap,
  });

  final int hiddenCount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                expanded
                    ? 'Свернуть'
                    : 'Ещё $hiddenCount '
                          '${pluralRu(hiddenCount, 'задача', 'задачи', 'задач')}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: p.link,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                size: 16,
                color: p.link,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A task's capsule: its light tone ringed in its colour while open, the colour
/// itself, faded, once done.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.entry});

  final _EntryState entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final ink = _inkOf(theme, entry.color, p.surface);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: entry.completed
            ? ink.withValues(alpha: 0.55)
            : taskBadgeSurface(theme, entry.color, p.surface),
        border: entry.completed ? null : Border.all(color: ink, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

/// One task's text in a block: title, its line, and — when it collides with an
/// earlier one — a red line per collision. The tick on the right.
class _ClusterEntryBody extends StatelessWidget {
  const _ClusterEntryBody({
    required this.entry,
    required this.span,
    required this.conflicts,
    required this.showRange,
  });

  final _EntryState entry;
  final TimedSpan span;
  final List<Conflict> conflicts;

  /// In a block of several the time column names only the block's start and
  /// end, so each task spells out its own range.
  final bool showRange;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final meta = [
      if (showRange)
        span.isPoint
            ? clockLabel(span.start)
            : '${clockLabel(span.start)}–${clockLabel(span.end)}',
      if (!span.isPoint) durationLabel(span.minutes),
      _kindLabel(entry),
    ].join(' · ');

    return InkWell(
      onTap: entry.onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Title(entry: entry),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                  if (entry.note != null) ...[
                    const SizedBox(height: 6),
                    _GroupBadge(note: entry.note!),
                  ],
                  // One clash names the other task and the minutes; several only
                  // count, or the line would grow with every task in the block.
                  if (conflicts.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            LucideIcons.triangle_alert,
                            size: 12,
                            color: p.danger,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _conflictLabel(conflicts),
                            style: TextStyle(fontSize: 12, color: p.danger),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _Tick(entry: entry, compact: true),
          ],
        ),
      ),
    );
  }
}

/// "Пересекается с «Созвон» · 20 мин", or "Пересекается с 3 задачами".
String _conflictLabel(List<Conflict> conflicts) {
  if (conflicts.length > 1) {
    final n = conflicts.length;
    return 'Пересекается с $n ${pluralRu(n, 'задачей', 'задачами', 'задачами')}';
  }
  final c = conflicts.single;
  return 'Пересекается с «${c.other.title}»'
      '${c.minutes == null ? '' : ' · ${durationLabel(c.minutes!)}'}';
}

class _Title extends StatelessWidget {
  const _Title({required this.entry});

  final _EntryState entry;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Text(
      entry.task.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: entry.completed ? p.textTertiary : p.textPrimary,
        decoration: entry.completed ? TextDecoration.lineThrough : null,
        decorationColor: p.textTertiary,
      ),
    );
  }
}

/// The ring a task is ticked with, in its own colour; filled once done. A task
/// I handed to someone else is not mine to tick: their letter stands there
/// instead. A counter or a timer is ticked from its own sheet, so it gets none.
class _Tick extends StatelessWidget {
  const _Tick({required this.entry, this.compact = false});

  final _EntryState entry;

  /// On a timeline row, where it sits beside the title rather than centred on
  /// a 44px row: the touch area hangs below the ring instead of around it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final delegatedTo = entry.note?.delegatedTo;
    if (delegatedTo != null) {
      return SizedBox.square(
        dimension: 44,
        child: Center(child: MemberAvatar(name: delegatedTo, size: 24)),
      );
    }
    if (entry.task.trackingMode != TrackingMode.checkbox) {
      return const SizedBox(width: 44);
    }
    final ink = inkOn(p.surface, entry.color, minContrast: 3);
    final fill = taskBadgeInk(theme, entry.color, p.surface);
    final done = entry.completed;
    return Tooltip(
      message: done
          ? 'Отметить «${entry.task.title}» как невыполненную'
          : 'Отметить «${entry.task.title}» как выполненную',
      child: InkResponse(
        onTap: entry.onToggle,
        radius: 22,
        child: SizedBox.square(
          dimension: 44,
          child: Align(
            alignment: compact ? Alignment.topCenter : Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? fill : Colors.transparent,
                border: done ? null : Border.all(color: ink, width: 2),
              ),
              child: done
                  ? Icon(LucideIcons.check, size: 13, color: onTaskColor(fill))
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Семья · всем" on a grey plate — a group task's line (DESIGN.md §5).
class _GroupBadge extends StatelessWidget {
  const _GroupBadge({required this.note});

  final _GroupNote note;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Container(
      height: 24,
      padding: const EdgeInsets.fromLTRB(6, 0, 9, 0),
      decoration: BoxDecoration(
        color: p.chip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.users, size: 12, color: p.textSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              note.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: p.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Сейчас 14:06 · до «Созвон с командой» 54 мин" on an accent dot.
class _NowRow extends StatelessWidget {
  const _NowRow({
    required this.minutes,
    required this.next,
    required this.minutesToNext,
    required this.first,
    required this.last,
  });

  final int minutes;
  final String? next;
  final int? minutesToNext;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final accent = theme.colorScheme.primary;
    return SizedBox(
      height: 48,
      child: Stack(
        children: [
          if (!first) _lineSegment(p, top: 0, height: 24, past: true),
          if (!last) _lineSegment(p, top: 24, past: false),
          Positioned(
            left: _Axis.lineX - 6,
            top: 18,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.2),
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: _Axis.bodyLeft,
            right: 16,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                // Shrunk, not cut, on a narrow screen at a large font.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text(
                        'Сейчас ${clockLabel(minutes)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                if (next != null && minutesToNext != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'до «$next» · ${durationLabel(minutesToNext!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Свободно 2 ч" on a dashed stretch of the line.
class _FreeRow extends StatelessWidget {
  const _FreeRow({required this.minutes, required this.past});

  final int minutes;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return SizedBox(
      height: 34,
      child: Stack(
        children: [
          Positioned(
            left: _Axis.lineX - 0.75,
            top: 0,
            bottom: 0,
            width: 1.5,
            child: Column(
              children: [
                for (var i = 0; i < 5; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  Container(height: 3, color: p.outline),
                ],
              ],
            ),
          ),
          Positioned(
            left: _Axis.lineX - 2,
            top: 15,
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: p.outline,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: _Axis.bodyLeft,
            top: 0,
            bottom: 0,
            child: Center(
              child: Text(
                'Свободно ${durationLabel(minutes)}',
                style: TextStyle(fontSize: 12, color: p.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.free,
    required this.day,
    required this.nowMinutes,
  });

  /// Nothing at all on the day. False means there are tasks, just none with a
  /// time — they sit in "В течение дня" above.
  final bool free;
  final DateTime day;

  /// Minutes past midnight when the day is today: "Сейчас" opens the line.
  final int? nowMinutes;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    if (!free) {
      return _Card(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            Icon(LucideIcons.clock, size: 40, color: p.iconMuted),
            const SizedBox(height: 12),
            Text(
              'На этот день нет задач со временем',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: p.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Нажмите + и укажите время задачи',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.textTertiary),
            ),
          ],
        ),
      );
    }
    // The line of the day, empty: "Сейчас" on today, then a dashed stretch with
    // the invitation beside it (`EmptyTimeline.dc.html`).
    final now = nowMinutes;
    return _Card(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (now != null)
            _NowRow(
              minutes: now,
              next: null,
              minutesToNext: null,
              first: true,
              last: true,
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 150),
            child: Stack(
              children: [
                Positioned(
                  left: _Axis.lineX - 0.75,
                  top: 0,
                  bottom: 0,
                  width: 1.5,
                  child: CustomPaint(painter: _DashedLine(p.outline)),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(_Axis.bodyLeft, 16, 16, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'День пока свободен',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Добавьте задачу со временем — она появится на линии '
                        'дня.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: p.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Material(
                        color: p.textPrimary,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () =>
                              showCreateTaskSheet(context, initialDate: day),
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            alignment: Alignment.center,
                            child: Text(
                              'Добавить задачу',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: p.background,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertical line of 3px dashes 4px apart, as long as the room it is given.
class _DashedLine extends CustomPainter {
  const _DashedLine(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 0.0; y < size.height; y += 7) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 3), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}

/// The line a group task carries on the timeline.
class _GroupNote {
  const _GroupNote(this.text, {this.delegatedTo, this.done = false});

  final String text;

  /// Set when the task is another member's, handed to them or their own: their
  /// name, and [done] for whether they have ticked it.
  final String? delegatedTo;
  final bool done;
}
