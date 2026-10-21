import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/habit_labels.dart';
import 'package:todo_app/utils/last_done.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_icons.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/habit_actions_sheet.dart';
import 'package:todo_app/widgets/habits/habit_history_stats.dart';
import 'package:todo_app/widgets/habits/habit_week_stats.dart';
import 'package:todo_app/widgets/habits/habits_week.dart' show DashedBox;
import 'package:todo_app/widgets/page_header.dart';
import 'package:todo_app/widgets/segmented_switch.dart';
import 'package:todo_app/widgets/swipe_to_switch.dart';

/// A habit's page (`HabitDetail.dc.html`): its streaks, how often it is done, a
/// calendar of the days, and at what time of day it really gets done.
///
/// Pushed from a tap on a habit's row; the old bottom sheet — marking days,
/// copying, deleting — is one row down, "Другие действия". Everything is derived
/// from the habit's logs by [HabitHistory], the same day rules as the week view.
class HabitDetailPage extends ConsumerStatefulWidget {
  const HabitDetailPage({super.key, required this.taskId});

  final int taskId;

  @override
  ConsumerState<HabitDetailPage> createState() => _HabitDetailPageState();
}

class _HabitDetailPageState extends ConsumerState<HabitDetailPage> {
  /// 0 month, 1 year, 2 all time. Null until the user picks: all time is what
  /// the mock-up opens on, but a young habit has none and opens on the month.
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final task = ref
        .watch(rootTasksProvider)
        .valueOrNull
        ?.where((t) => t.id == widget.taskId)
        .firstOrNull;
    final logs =
        ref.watch(logsForTaskProvider(widget.taskId)).valueOrNull ??
        const <TaskLog>[];

    // Gone — deleted from the sheet below, say — or not loaded yet.
    if (task == null) {
      return Scaffold(
        backgroundColor: p.background,
        body: const SafeArea(child: BackHeader(title: 'Привычка')),
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final history = HabitHistory.of(
      task: task,
      logs: logs,
      today: today,
      graceMinutes: ref.watch(lateGraceMinutesProvider),
      todayStaysOpen: ref.watch(todayStaysOpenProvider),
    );
    final color = task.colorValue != null
        ? Color(task.colorValue!)
        : ColorPickerRow.colors.first;
    final look = _Look.of(theme, color);
    final span = _spanOf(history.days.length);
    final young = span == _Span.young;
    final period = young ? math.min(_picked ?? 0, 1) : (_picked ?? 2);

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: SwipeToSwitch(
          onStep: (step) =>
              setState(() => _picked = (period + step).clamp(0, young ? 1 : 2)),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              BackHeader(
                title: 'Привычка',
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
              _Title(task: task, look: look),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedSwitch(
                  // A habit of less than four weeks has no "all time": it would be
                  // the month again.
                  labels: ['Месяц', 'Год', if (!young) 'Всё время'],
                  selected: period,
                  onChanged: (i) => setState(() => _picked = i),
                ),
              ),
              if (period == 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(
                    _sinceText(history),
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                ),
              const SizedBox(height: 12),
              _Headline(history: history, today: today, period: period),
              const SizedBox(height: 12),
              switch (period) {
                0 => _MonthCalendar(
                  history: history,
                  today: today,
                  look: look,
                  young: young,
                ),
                1 => _YearCalendars(history: history, today: today, look: look),
                _ => _AllTime(
                  history: history,
                  look: look,
                  byWeek: span == _Span.weeks,
                ),
              },
              if (task.scheduledTimeMinutes != null) ...[
                const SizedBox(height: 12),
                _TimeCard(
                  history: history,
                  today: today,
                  period: period,
                  byWeek: span == _Span.weeks,
                  look: look,
                ),
              ],
              const SizedBox(height: 12),
              _Actions(task: task),
            ],
          ),
        ),
      ),
    );
  }

  String _sinceText(HabitHistory h) {
    final first = h.days.first;
    final n = h.days.length;
    return 'С ${DateFormat('d MMMM y', 'ru_RU').format(first)} · '
        '$n ${pluralRu(n, 'день', 'дня', 'дней')}';
  }
}

/// How much history there is, which decides what "all time" can honestly show:
/// under four weeks it is no tab at all; up to about three months a bar per
/// week (four to a dozen of them, readable); beyond that a bar per month.
enum _Span { young, weeks, months }

_Span _spanOf(int ageDays) => ageDays < 28
    ? _Span.young
    : ageDays <= 92
    ? _Span.weeks
    : _Span.months;

/// The habit's colours as this screen reads them.
class _Look {
  const _Look({
    required this.strong,
    required this.soft,
    required this.fill,
    required this.onStrong,
  });

  /// On time: the family's strong tone.
  final Color strong;

  /// Late: the same, paled.
  final Color soft;

  /// The pale tile behind the icon.
  final Color fill;
  final Color onStrong;

  factory _Look.of(ThemeData theme, Color color) {
    final p = AppPalette.of(theme);
    final fill = taskBadgeSurface(theme, color, p.surface);
    final strong = taskBadgeInk(theme, color, fill);
    return _Look(
      strong: strong,
      soft: Color.lerp(strong, p.surface, 0.62)!,
      fill: fill,
      onStrong: onTaskColor(strong),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.border),
        ),
        child: child,
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.task, required this.look});

  final Task task;
  final _Look look;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final mode = switch (task.trackingMode) {
      TrackingMode.counter => 'Счётчик',
      TrackingMode.timer => 'Таймер',
      _ => 'Чекбокс',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: look.fill,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              taskIconFor(task.iconKey) ?? LucideIcons.repeat,
              size: 24,
              color: look.strong,
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
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${habitSubtitle(task)} · $mode',
                  style: TextStyle(fontSize: 13, color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

DateTime _firstOfPeriod(DateTime today, int period) => switch (period) {
  0 => DateTime(today.year, today.month),
  1 => DateTime(today.year, today.month - 11),
  _ => DateTime(1900),
};

/// "Текущая серия" and "Выполнено N из M" (`Main figures`).
class _Headline extends StatelessWidget {
  const _Headline({
    required this.history,
    required this.today,
    required this.period,
  });

  final HabitHistory history;
  final DateTime today;
  final int period;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final streaks = history.streaks;
    final from = _firstOfPeriod(today, period);
    final c = history.counts((d) => !d.isBefore(from));
    final word = [
      'за ${_monthNominative(today)}',
      'за 12 месяцев',
      'за всё время',
    ];

    Widget card(String label, String big, String unit, String foot) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: p.textSecondary)),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                text: big,
                children: [
                  TextSpan(
                    text: unit,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: p.textSecondary,
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                color: p.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(foot, style: TextStyle(fontSize: 12, color: p.textSecondary)),
          ],
        ),
      ),
    );

    String days(int n) => pluralRu(n, 'день', 'дня', 'дней');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          card(
            'Текущая серия',
            '${streaks.current}',
            ' ${days(streaks.current)}',
            'Лучшая — ${streaks.best} ${days(streaks.best)}',
          ),
          const SizedBox(width: 10),
          card(
            'Выполнено',
            '${c.done}',
            ' из ${c.planned}',
            '${c.donePercent ?? 0}% ${word[period]}',
          ),
        ],
      ),
    );
  }
}

String _monthNominative(DateTime d) => DateFormat('LLLL', 'ru_RU').format(d);

String _capital(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "5 вовремя · 2 поздно · 1 пропуск".
String _countsLine(DayCounts c) =>
    '${c.onTime} вовремя · ${c.late} поздно'
    '${c.partial > 0 ? ' · ${c.partial} частично' : ''} · ${c.missed} пропуск';

/// The title of a period's card with its tally under it. Under, not beside: on
/// a long title ("Последние 12 месяцев") the tally had no room and wrapped. It
/// is one line however many digits the counts have — it scales down if it must.
class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.title, required this.counts});

  final String title;
  final DayCounts counts;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _countsLine(counts),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(fontSize: 12, color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.look, this.withMiss = true});

  final _Look look;
  final bool withMiss;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    Widget item(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: p.textSecondary)),
      ],
    );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(look.strong, 'Вовремя'),
        item(look.soft, 'С опозданием'),
        if (withMiss) item(p.dangerSoft, 'Пропуск'),
      ],
    );
  }
}

Map<DateTime, WeekCell> _cellsByDay(HabitHistory h) => {
  for (var i = 0; i < h.days.length; i++) h.days[i]: h.cellOf(i),
};

// ---------------------------------------------------------------------------
// Месяц
// ---------------------------------------------------------------------------

class _MonthCalendar extends ConsumerWidget {
  const _MonthCalendar({
    required this.history,
    required this.today,
    required this.look,
    required this.young,
  });

  final HabitHistory history;
  final DateTime today;
  final _Look look;

  /// A habit under four weeks old: a line under the calendar says since when
  /// it exists.
  final bool young;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(Theme.of(context));
    final weekStart = ref.watch(weekStartProvider);
    final cells = _cellsByDay(history);
    final first = DateTime(today.year, today.month);
    final count = DateTime(today.year, today.month + 1, 0).day;
    final pad = (first.weekday - weekStart + 7) % 7;
    final names = [
      for (var i = 0; i < 7; i++) weekdayShort[(weekStart - 1 + i) % 7],
    ];
    final counts = history.counts((d) => !d.isBefore(first));

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeriodHeader(
            title: _capital(_monthNominative(today)),
            counts: counts,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final n in names)
                Expanded(
                  child: Text(
                    n,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: p.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < pad; i++) const SizedBox.shrink(),
              // Days before the habit began are in no cell map: they read as
              // plain "off" numbers, so the whole month is drawn.
              for (var d = 1; d <= count; d++)
                _DayCell(
                  day: DateTime(today.year, today.month, d),
                  cell:
                      cells[DateTime(today.year, today.month, d)] ??
                      // Days ahead are in no cell map: only the ones the rule
                      // lands on get the dashed outline.
                      (isTaskScheduledOn(
                                history.task,
                                DateTime(today.year, today.month, d),
                              ) &&
                              DateTime(
                                today.year,
                                today.month,
                                d,
                              ).isAfter(today)
                          ? WeekCell.future
                          : WeekCell.off),
                  look: look,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _Legend(look: look),
          if (young) ...[
            const SizedBox(height: 12),
            Text(
              'Создана ${DateFormat('d MMMM', 'ru_RU').format(history.days.first)}'
              ' · ${history.days.length} '
              '${pluralRu(history.days.length, 'день', 'дня', 'дней')}',
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.cell, required this.look});

  final DateTime day;
  final WeekCell cell;
  final _Look look;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    var textColor = p.iconMuted;
    var weight = FontWeight.w400;
    Color? fill;
    Gradient? gradient;
    Border? border;
    switch (cell) {
      case WeekCell.onTime:
        fill = look.strong;
        textColor = look.onStrong;
        weight = FontWeight.w600;
      case WeekCell.late:
        fill = look.soft;
        textColor = p.textPrimary;
        weight = FontWeight.w500;
      case WeekCell.partial:
        gradient = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [look.strong, look.strong, p.chip, p.chip],
          stops: const [0, 0.5, 0.5, 1],
        );
        textColor = p.textPrimary;
      case WeekCell.missed:
        fill = p.dangerSoft;
        textColor = p.danger;
      case WeekCell.pending:
        border = Border.all(color: look.strong, width: 1.5);
        textColor = p.textPrimary;
        weight = FontWeight.w600;
      case WeekCell.off || WeekCell.future:
        break;
    }
    final box = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        gradient: gradient,
        border: border,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: weight,
          color: textColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    // A day ahead that the rule lands on: a pale dashed outline.
    return cell == WeekCell.future
        ? CustomPaint(
            foregroundPainter: DashedBox(color: p.outline, radius: 10),
            child: box,
          )
        : box;
  }
}

// ---------------------------------------------------------------------------
// Год
// ---------------------------------------------------------------------------

class _YearCalendars extends ConsumerWidget {
  const _YearCalendars({
    required this.history,
    required this.today,
    required this.look,
  });

  final HabitHistory history;
  final DateTime today;
  final _Look look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(weekStartProvider);
    final cells = _cellsByDay(history);
    final from = _firstOfPeriod(today, 1);
    final counts = history.counts((d) => !d.isBefore(from));
    final months = [
      for (var k = 0; k < 12; k++) DateTime(from.year, from.month + k),
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeriodHeader(title: 'Последние 12 месяцев', counts: counts),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, box) {
              const gap = 14.0;
              final w = (box.maxWidth - 2 * gap) / 3;
              return Wrap(
                spacing: gap,
                runSpacing: 16,
                children: [
                  for (final (k, m) in months.indexed)
                    SizedBox(
                      width: w,
                      child: _MiniMonth(
                        month: m,
                        showYear: k == 0 || m.month == 1,
                        weekStart: weekStart,
                        cells: cells,
                        today: today,
                        look: look,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _Legend(look: look),
        ],
      ),
    );
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.month,
    required this.showYear,
    required this.weekStart,
    required this.cells,
    required this.today,
    required this.look,
  });

  final DateTime month;
  final bool showYear;
  final int weekStart;
  final Map<DateTime, WeekCell> cells;
  final DateTime today;
  final _Look look;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final count = DateTime(month.year, month.month + 1, 0).day;
    final pad = (month.weekday - weekStart + 7) % 7;
    Widget cell(DateTime day) {
      final c =
          cells[day] ?? (day.isAfter(today) ? WeekCell.future : WeekCell.off);
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3.5),
          color: switch (c) {
            WeekCell.onTime => look.strong,
            WeekCell.late => look.soft,
            WeekCell.partial => look.soft,
            WeekCell.missed => p.dangerSoft,
            WeekCell.pending => p.surface,
            _ => p.chip,
          },
          border: c == WeekCell.pending
              ? Border.all(color: look.strong, width: 1.5)
              : null,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _capital(_monthNominative(month)) +
              (showYear ? ' ${month.year}' : ''),
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: p.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < pad; i++) const SizedBox.shrink(),
            for (var d = 1; d <= count; d++)
              cell(DateTime(month.year, month.month, d)),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Всё время
// ---------------------------------------------------------------------------

const _monthShort = [
  'Янв',
  'Фев',
  'Мар',
  'Апр',
  'Май',
  'Июн',
  'Июл',
  'Авг',
  'Сен',
  'Окт',
  'Ноя',
  'Дек',
];

const _weekdayDative = [
  'понедельникам',
  'вторникам',
  'средам',
  'четвергам',
  'пятницам',
  'субботам',
  'воскресеньям',
];

class _AllTime extends ConsumerWidget {
  const _AllTime({
    required this.history,
    required this.look,
    required this.byWeek,
  });

  final HabitHistory history;
  final _Look look;

  /// A bar per week instead of per month: with a month or three of history,
  /// two or three bars say nothing.
  final bool byWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(Theme.of(context));
    final weekStart = ref.watch(weekStartProvider);
    final rates = history.weekdayRates;
    final bars = byWeek
        ? [
            for (final (i, w) in history.weeks(weekStart).indexed)
              (
                counts: w.counts,
                label: i % 2 == 0
                    ? '${w.start.day} ${_monthShort[w.start.month - 1].toLowerCase()}'
                    : null,
              ),
          ]
        : [
            for (final (i, m) in history.months.indexed)
              (
                counts: m.counts,
                label: i % 3 == 0
                    ? _monthShort[m.month - 1] +
                          (m.month == 1 || i == 0 ? ' ’${m.year % 100}' : '')
                    : null,
              ),
          ];
    final order = [for (var i = 0; i < 7; i++) (weekStart - 1 + i) % 7];

    // Best and worst weekday, for the line under the bars — only meaningful
    // when the rule lands on at least two of them.
    final known = [
      for (final w in order)
        if (rates[w] != null) w,
    ];
    int? best, worst;
    if (known.length >= 2) {
      best = known.reduce((a, b) => rates[a]! >= rates[b]! ? a : b);
      worst = known.reduce((a, b) => rates[a]! <= rates[b]! ? a : b);
    }
    String pct(int w) => '${(rates[w]! * 100).round()}%';

    Widget bar(({DayCounts counts, String? label}) m) {
      final planned = m.counts.planned;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Column(
            children: [
              Container(
                height: 84,
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.bottomCenter,
                decoration: BoxDecoration(
                  color: p.chip,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: planned == 0 ? 0 : m.counts.late / planned * 84,
                      color: look.soft,
                    ),
                    Container(
                      height: planned == 0 ? 0 : m.counts.onTime / planned * 84,
                      color: look.strong,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 12,
                child: m.label != null
                    ? OverflowBox(
                        maxWidth: 48,
                        child: Text(
                          m.label!,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 10,
                            color: p.textSecondary,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                byWeek ? 'Каждая неделя' : 'Каждый месяц',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Доля дней, когда привычка выполнена',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final b in bars) bar(b)],
              ),
              const SizedBox(height: 14),
              _Legend(look: look, withMiss: false),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'По дням недели',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'В какие дни получается чаще',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final w in order)
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            rates[w] == null ? '—' : pct(w),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: w == best
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: w == best
                                  ? p.textPrimary
                                  : p.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 28,
                            height: 72,
                            clipBehavior: Clip.antiAlias,
                            alignment: Alignment.bottomCenter,
                            decoration: BoxDecoration(
                              color: p.chip,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Container(
                              height: (rates[w] ?? 0) * 72,
                              color: w == best ? look.strong : look.soft,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            weekdayShort[w],
                            style: TextStyle(
                              fontSize: 11,
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (best != null && worst != null) ...[
                const SizedBox(height: 12),
                _Insight(
                  'Лучше всего получается по ${_weekdayDative[best]} '
                  '(${pct(best)}), хуже всего — по ${_weekdayDative[worst]} '
                  '(${pct(worst)}).',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The grey lightbulb note under a chart.
class _Insight extends StatelessWidget {
  const _Insight(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              LucideIcons.lightbulb,
              size: 18,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Во сколько выполняешь
// ---------------------------------------------------------------------------

/// One dot of the time chart: where along the width, how far from the plan.
class _Dot {
  const _Dot(this.x, this.offset, {this.missed = false});

  final double x;
  final double? offset;
  final bool missed;
}

class _TimeCard extends ConsumerWidget {
  const _TimeCard({
    required this.history,
    required this.today,
    required this.period,
    required this.byWeek,
    required this.look,
  });

  final HabitHistory history;
  final DateTime today;
  final int period;

  /// "All time" is weeks, not months: the line then runs through weekly
  /// averages.
  final bool byWeek;
  final _Look look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(Theme.of(context));
    // The same grace as everywhere else: past it a mark is late, and the chart
    // draws it hollow.
    final grace = ref.watch(lateGraceMinutesProvider);
    final plan = history.task.scheduledTimeMinutes!;
    final planLabel = clockLabel(plan);

    final dots = <_Dot>[];
    String sub;
    double? average;
    var line = false;
    if (period == 0) {
      final pts = history.recentPoints(today);
      for (final (i, pt) in pts.indexed) {
        final x = pts.length < 2 ? 0.5 : i / (pts.length - 1);
        dots.add(
          pt.offset == null
              ? _Dot(
                  x,
                  null,
                  missed:
                      pt.cell == WeekCell.missed || pt.cell == WeekCell.partial,
                )
              : _Dot(x, pt.offset!.toDouble()),
        );
      }
      sub = 'Последние ${pts.length} дней · план $planLabel';
      final real = [for (final pt in pts) ?pt.offset];
      average = real.isEmpty
          ? null
          : real.reduce((a, b) => a + b) / real.length;
    } else {
      line = true;
      final weekly = period == 2 && byWeek;
      var averages = weekly
          ? [
              for (final w in history.weeks(ref.watch(weekStartProvider)))
                w.averageOffset,
            ]
          : [for (final m in history.months) m.averageOffset];
      if (period == 1 && averages.length > 12) {
        averages = averages.sublist(averages.length - 12);
      }
      for (final (i, avg) in averages.indexed) {
        final x = averages.length < 2 ? 0.5 : i / (averages.length - 1);
        if (avg != null) dots.add(_Dot(x, avg));
      }
      final first = history.days.first;
      sub = period == 1
          ? 'Среднее по месяцам, 12 месяцев · план $planLabel'
          : 'Среднее по ${weekly ? 'неделям' : 'месяцам'}, '
                'с ${DateFormat(weekly ? 'd MMMM' : 'MMMM y', 'ru_RU').format(first)}'
                ' · план $planLabel';
      average = history.averageOffset(
        period == 1 ? (d) => !d.isBefore(_firstOfPeriod(today, 1)) : null,
      );
    }

    // Nothing with a moment on it yet: a chart of nothing says nothing.
    if (!dots.any((d) => d.offset != null)) return const SizedBox.shrink();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Во сколько выполняешь',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 12, color: p.textSecondary)),
          const SizedBox(height: 12),
          SizedBox(
            height: 132,
            child: CustomPaint(
              painter: _TimeChart(
                dots: dots,
                line: line,
                plan: plan,
                lateAfter: grace,
                look: look,
                grid: p.divider,
                label: p.textTertiary,
                missed: const Color(0xFFE6B9AE),
              ),
            ),
          ),
          if (average != null) ...[
            const SizedBox(height: 12),
            _Insight(_timeInsight(history.task, plan, average, grace)),
          ],
          const SizedBox(height: 10),
          // How to read it, since the picture alone does not say.
          Text(
            'Пунктир — время по плану. Чем выше точка, тем позже отмечено, '
            'чем ниже — тем раньше. Пустая точка — с опозданием, '
            'чёрточка внизу — пропуск.',
            style: TextStyle(fontSize: 12, height: 1.4, color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  /// "В среднем «Медитация» отмечается около 22:38, на 38 минут позже плана.
  /// Возможно, стоит перенести время на 22:30."
  String _timeInsight(Task task, int plan, double average, int grace) {
    final avg = average.round();
    final at = clockLabel(plan + avg);
    final head = 'В среднем «${task.title}» отмечается около $at';
    if (avg <= 0) return '$head, вовремя.';
    final text = '$head, на ${_howLate(avg)} позже плана.';
    if (avg <= grace) return text;
    // The half hour nearest to when it really happens.
    final suggested = ((plan + avg) / 30).round() * 30;
    return suggested == plan
        ? text
        : '$text Возможно, стоит перенести время на ${clockLabel(suggested)}.';
  }
}

/// "25 минут", but from an hour up whole hours: "1 час", "2 часа". Past 59
/// minutes the minutes are noise.
String _howLate(int minutes) {
  if (minutes < 60) {
    return '$minutes ${pluralRu(minutes, 'минуту', 'минуты', 'минут')}';
  }
  final hours = (minutes / 60).round();
  return '$hours ${pluralRu(hours, 'час', 'часа', 'часов')}';
}

class _TimeChart extends CustomPainter {
  const _TimeChart({
    required this.dots,
    required this.line,
    required this.plan,
    required this.lateAfter,
    required this.look,
    required this.grid,
    required this.label,
    required this.missed,
  });

  final List<_Dot> dots;
  final bool line;
  final int plan;

  /// Minutes past the plan after which a mark is drawn as late.
  final int lateAfter;
  final _Look look;
  final Color grid;
  final Color label;
  final Color missed;

  static const double _left = 40;
  static const double _min = -30, _max = 90;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - _left;
    final h = size.height;
    double y(double m) => h - (m.clamp(_min, _max) - _min) / (_max - _min) * h;
    double x(double f) => _left + f * w;

    // The three hours-and-a-half lines, with their clock labels.
    for (final m in const [-30.0, 30.0, 90.0]) {
      final yy = y(m);
      canvas.drawLine(
        Offset(_left, yy),
        Offset(size.width, yy),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: clockLabel(plan + m.round()),
          style: TextStyle(
            fontSize: 10,
            color: label,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_left - 6 - tp.width, yy - tp.height / 2));
    }

    // The plan: a dashed line at zero.
    final planPaint = Paint()
      ..color = look.strong.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(_left, y(0))
      ..lineTo(size.width, y(0));
    for (final PathMetric m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), planPaint);
      }
    }

    final real = [
      for (final d in dots)
        if (d.offset != null) d,
    ];
    if (line && real.length > 1) {
      final poly = Path()..moveTo(x(real.first.x), y(real.first.offset!));
      for (final d in real.skip(1)) {
        poly.lineTo(x(d.x), y(d.offset!));
      }
      canvas.drawPath(
        poly,
        Paint()
          ..color = look.soft
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    final r = line ? 4.0 : 5.0;
    for (final d in dots) {
      if (d.offset == null) {
        // A miss: a short dash on the floor.
        if (d.missed) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(x(d.x), h - 3),
                width: 8,
                height: 2,
              ),
              const Radius.circular(1),
            ),
            Paint()..color = missed,
          );
        }
        continue;
      }
      final c = Offset(x(d.x), y(d.offset!));
      if (d.offset! > lateAfter) {
        // Late: a hollow dot.
        canvas.drawCircle(
          c,
          r - 1,
          Paint()
            ..color = look.soft
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else {
        canvas.drawCircle(c, r, Paint()..color = look.strong);
      }
    }
  }

  @override
  bool shouldRepaint(_TimeChart old) =>
      old.dots != dots ||
      old.line != line ||
      old.plan != plan ||
      old.lateAfter != lateAfter ||
      old.look != look;
}

// ---------------------------------------------------------------------------
// Действия
// ---------------------------------------------------------------------------

class _Actions extends ConsumerWidget {
  const _Actions({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(Theme.of(context));
    Widget row(String label, VoidCallback onTap, {Color? color}) => InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15, color: color ?? p.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Widget divider() => Container(height: 1, color: p.divider);

    return _Card(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          // The day squares, copying and deleting live in the old sheet.
          row(
            'Другие действия',
            () => showHabitActionsSheet(context, task: task),
          ),
          divider(),
          row('Архивировать', () async {
            final navigator = Navigator.of(context);
            await ref
                .read(tasksDaoProvider)
                .setTaskStatus(task.id, TaskStatus.archived);
            navigator.pop();
          }, color: p.danger),
        ],
      ),
    );
  }
}
