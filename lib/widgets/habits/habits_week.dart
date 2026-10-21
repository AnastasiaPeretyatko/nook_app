import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/habit_labels.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/task_icons.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/utils/week.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/habit_week_stats.dart';
import 'package:todo_app/widgets/list_card.dart';

/// The "Неделя" tab of the habits screen (`Week.dc.html`): how the week went —
/// a summary with a bar per day, then every habit as a row of seven squares.
///
/// The arrows page through earlier weeks; the one ahead is not offered.
class HabitsWeek extends ConsumerStatefulWidget {
  const HabitsWeek({super.key});

  @override
  ConsumerState<HabitsWeek> createState() => _HabitsWeekState();
}

class _HabitsWeekState extends ConsumerState<HabitsWeek> {
  /// Weeks back from the current one; never positive.
  int _back = 0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = startOfWeek(today, ref.watch(weekStartProvider));
    final start = DateTime(first.year, first.month, first.day - 7 * _back);
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
    final grace = ref.watch(lateGraceMinutesProvider);
    final todayStaysOpen = ref.watch(todayStaysOpenProvider);

    final tasks = ref.watch(rootTasksProvider).valueOrNull ?? const <Task>[];
    final logs =
        ref
            .watch(
              logsBetweenProvider(
                DateRange(
                  start,
                  DateTime(start.year, start.month, start.day + 7),
                ),
              ),
            )
            .valueOrNull ??
        const <TaskLog>[];

    final habits = [
      for (final t in tasks)
        if (t.status == TaskStatus.active &&
            t.repeatType != null &&
            !isValueTask(t))
          habitWeek(
            task: t,
            days: days,
            logs: logs,
            today: today,
            graceMinutes: grace,
            todayStaysOpen: todayStaysOpen,
          ),
    ].where((h) => h.cells.any((c) => c != WeekCell.off)).toList();
    final summary = weekSummary(habits, days, today: today);

    return ListView(
      padding: EdgeInsets.only(
        top: 4,
        bottom: MediaQuery.paddingOf(context).bottom + 88,
      ),
      children: [
        _WeekNav(
          days: days,
          canGoForward: _back > 0,
          onBack: () => setState(() => _back++),
          onForward: () => setState(() => _back--),
        ),
        _SummaryCard(summary: summary, days: days, today: today),
        const SectionCaption(
          title: 'По привычкам',
          trailing: 'выполнено / по плану',
        ),
        if (habits.isEmpty)
          const _NoHabits()
        else
          RowsCard(
            dividerIndent: 68,
            children: [
              _DaysHeader(days: days, today: today),
              for (final h in habits) _HabitWeekRow(habit: h),
            ],
          ),
      ],
    );
  }
}

class _WeekNav extends StatelessWidget {
  const _WeekNav({
    required this.days,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  final List<DateTime> days;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  /// "12 — 18 октября", or "28 сентября — 4 октября" across a month.
  String get _label {
    final a = days.first, b = days.last;
    final month = DateFormat('MMMM', 'ru_RU');
    return a.month == b.month
        ? '${a.day} — ${b.day} ${month.format(b)}'
        : '${a.day} ${month.format(a)} — ${b.day} ${month.format(b)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    Widget arrow(IconData icon, String tooltip, VoidCallback? onTap) => Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox.square(
          dimension: 44,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? p.iconMuted : p.textPrimary,
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          arrow(LucideIcons.chevron_left, 'Прошлая неделя', onBack),
          Text(
            _label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          arrow(
            LucideIcons.chevron_right,
            'Следующая неделя',
            canGoForward ? onForward : null,
          ),
        ],
      ),
    );
  }
}

/// "82% выполнено · 53% вовремя · +40 мин", the bars, the legend.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.days,
    required this.today,
  });

  final WeekSummary summary;
  final List<DateTime> days;
  final DateTime today;

  static const double _barHeight = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final accent = theme.colorScheme.primary;

    Widget figure(String value, String label, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: color ?? p.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: p.textSecondary)),
        ],
      ),
    );
    String pct(int? v) => v == null ? '—' : '$v%';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                figure(pct(summary.donePercent), 'выполнено'),
                figure(pct(summary.onTimePercent), 'вовремя', color: accent),
                figure(
                  lateAverageLabel(summary.averageLateMinutes),
                  'среднее опоздание',
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: _barHeight + 24,
              child: Row(
                children: [
                  for (final (i, day) in days.indexed)
                    Expanded(
                      child: _Bar(
                        bar: summary.bars[i],
                        day: day,
                        isToday: day == today,
                        height: _barHeight,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _LegendItem(color: accent, label: 'Вовремя'),
                _LegendItem(color: p.lateSoft, label: 'С опозданием'),
                _LegendItem(
                  label: 'Частично',
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [accent, accent, p.chip, p.chip],
                    stops: const [0, 0.5, 0.5, 1],
                  ),
                ),
                _LegendItem(color: p.dangerSoft, label: 'Пропуск', mark: '×'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.bar,
    required this.day,
    required this.isToday,
    required this.height,
  });

  final DayBar bar;
  final DateTime day;
  final bool isToday;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final name = weekdayShort[day.weekday - 1];
    final percent = ((bar.onTime + bar.late) * 100).round();
    return Semantics(
      label:
          '$name: $percent%, вовремя ${(bar.onTime * 100).round()}%'
          '${bar.open ? ', день не закончился' : ''}',
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 24,
            height: height,
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.bottomCenter,
            decoration: BoxDecoration(
              color: p.chip,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(height: bar.late * height, color: p.lateSoft),
                Container(
                  height: bar.onTime * height,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              color: isToday ? p.textPrimary : p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    this.color,
    this.gradient,
    this.mark,
  });

  final String label;
  final Color? color;
  final Gradient? gradient;
  final String? mark;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            gradient: gradient,
            borderRadius: BorderRadius.circular(3),
          ),
          child: mark == null
              ? null
              : Text(
                  mark!,
                  style: TextStyle(fontSize: 9, height: 1, color: p.danger),
                ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: p.textSecondary)),
      ],
    );
  }
}

/// The weekday letters above the squares, lined up with them.
class _DaysHeader extends StatelessWidget {
  const _DaysHeader({required this.days, required this.today});

  final List<DateTime> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(68, 8, 16, 2),
      child: Row(
        children: [
          for (final (i, day) in days.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            SizedBox(
              width: _HabitWeekRow.cell,
              child: Text(
                weekdayShort[day.weekday - 1],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: day == today ? FontWeight.w700 : FontWeight.w400,
                  color: day == today ? p.textPrimary : p.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HabitWeekRow extends StatelessWidget {
  const _HabitWeekRow({required this.habit});

  final HabitWeek habit;

  static const double cell = 26;

  static const _words = {
    WeekCell.onTime: 'вовремя',
    WeekCell.late: 'с опозданием',
    WeekCell.partial: 'частично',
    WeekCell.missed: 'пропуск',
    WeekCell.off: 'не по плану',
    WeekCell.future: 'впереди',
    WeekCell.pending: 'сегодня, ещё не отмечено',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final task = habit.task;
    final color = task.colorValue != null
        ? Color(task.colorValue!)
        : ColorPickerRow.colors.first;
    final fill = taskBadgeSurface(theme, color, p.surface);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              taskIconFor(task.iconKey) ?? LucideIcons.repeat,
              size: 18,
              color: taskBadgeInk(theme, color, fill),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
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
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            habitSubtitle(task),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${habit.done}/${habit.planned}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Semantics(
                  label:
                      '${task.title}: ${[for (final (i, c) in habit.cells.indexed) '${i + 1} — ${_words[c]}'].join(', ')}',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      for (final (i, c) in habit.cells.indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        _Square(cell: c),
                      ],
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

/// One of the seven squares of a habit's week.
class _Square extends StatelessWidget {
  const _Square({required this.cell});

  final WeekCell cell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final accent = theme.colorScheme.primary;
    const size = _HabitWeekRow.cell;
    final radius = BorderRadius.circular(8);

    Widget box({
      Color? color,
      Gradient? gradient,
      Border? border,
      String? mark,
      Color? markColor,
    }) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        border: border,
        borderRadius: radius,
      ),
      child: mark == null
          ? null
          : Text(
              mark,
              style: TextStyle(fontSize: 13, height: 1, color: markColor),
            ),
    );

    return switch (cell) {
      WeekCell.onTime => box(color: accent),
      WeekCell.late => box(color: p.lateSoft),
      WeekCell.partial => box(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [accent, accent, p.chip, p.chip],
          stops: const [0, 0.5, 0.5, 1],
        ),
      ),
      WeekCell.missed => box(
        color: p.dangerSoft,
        mark: '×',
        markColor: p.danger,
      ),
      WeekCell.off => box(mark: '·', markColor: p.outline),
      WeekCell.future => CustomPaint(
        size: const Size.square(size),
        painter: DashedBox(color: p.outline, radius: 8),
      ),
      WeekCell.pending => box(border: Border.all(color: accent, width: 1.5)),
    };
  }
}

/// A dashed rounded outline — a day still ahead.
class DashedBox extends CustomPainter {
  const DashedBox({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final PathMetric m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, math.min(d + 3.5, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedBox old) =>
      old.color != color || old.radius != radius;
}

class _NoHabits extends StatelessWidget {
  const _NoHabits();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Text(
        'На этой неделе привычек нет',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: p.textSecondary),
      ),
    );
  }
}
