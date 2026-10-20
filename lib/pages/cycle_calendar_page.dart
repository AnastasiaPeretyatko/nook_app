import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/cycle.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/widgets/cycle/cycle_colors.dart';
import 'package:todo_app/widgets/cycle/cycle_day_info.dart';
import 'package:todo_app/widgets/cycle/cycle_heart.dart';
import 'package:todo_app/widgets/page_header.dart';

/// "Календарь" of the cycle (`CycleCalendar.dc.html`): months one under another,
/// every day in the colour of its phase, scrolling as far as anyone cares to go
/// in **both** directions. What the user entered is a solid fill; the cycles
/// that follow it are a forecast and drawn dashed. A tap on a day shows what was
/// marked on it.
///
/// ## Why not a calendar package
///
/// `table_calendar` is already in the project (the timeline's calendar), but it
/// shows **one month at a time** and pages sideways, and every cell here — the
/// dashed forecast, the hearts, the phase fills — would be a custom builder
/// anyway. A lazy list of months is the shorter road: only the months on screen
/// are ever built, so there is no range to choose and no cost to having none.
/// Two slivers meet at today's month — one grows upward, one downward.
class CycleCalendarPage extends ConsumerStatefulWidget {
  const CycleCalendarPage({super.key});

  @override
  ConsumerState<CycleCalendarPage> createState() => _CycleCalendarPageState();
}

class _CycleCalendarPageState extends ConsumerState<CycleCalendarPage> {
  final _scroll = ScrollController();

  /// The first of the downward sliver: this month is its first child, which is
  /// where the scroll offset 0 lies.
  final _center = UniqueKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final model = ref.watch(aboutSettingsProvider).model;
    final weekStart = ref.watch(weekStartProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sexByDay = <DateTime, int?>{
      for (final d in ref.watch(cycleDaysProvider).valueOrNull ?? const [])
        if (CycleHeart.shows(d.sex)) d.date: d.sex,
    };

    Widget month(int offset) {
      final first = DateTime(today.year, today.month + offset);
      return _Month(
        key: ValueKey('month-${first.year}-${first.month}'),
        first: first,
        today: today,
        model: model,
        sexByDay: sexByDay,
        weekStart: weekStart,
        onDayTap: (day) =>
            showCycleDayInfoSheet(context, day, model: model, today: today),
      );
    }

    return Scaffold(
      backgroundColor: pageSurface(Theme.of(context)),
      body: SafeArea(
        child: Column(
          children: [
            BackHeader(
              title: 'Календарь',
              trailing: RoundIconButton(
                icon: LucideIcons.calendar_check,
                tooltip: 'Сегодня',
                onPressed: () => _scroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _Legend(),
            _WeekdayRow(weekStart: weekStart),
            if (model == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Text(
                  'Укажите начало последних месячных в настройках — и здесь '
                  'появятся фазы цикла.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: p.textSecondary),
                ),
              ),
            Expanded(
              child: CustomScrollView(
                controller: _scroll,
                center: _center,
                slivers: [
                  // Before the centre a sliver is laid out backwards: its first
                  // child sits just above today's month, the next above that.
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => month(-1 - i),
                    ),
                  ),
                  SliverList(
                    key: _center,
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => month(i),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    Widget item(Widget mark, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: p.textSecondary)),
      ],
    );
    Widget dot(Color c) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          item(dot(periodColor), 'Месячные'),
          item(dot(fertileColor), 'Фертильные'),
          item(dot(ovulationColor), 'Овуляция'),
          item(
            CustomPaint(
              size: const Size(8, 8),
              painter: _DashedCirclePainter(color: p.textSecondary, width: 1),
            ),
            'Прогноз',
          ),
          item(const CycleHeart(sex: 1, size: 11), 'Секс с защитой'),
          item(const CycleHeart(sex: 2, size: 11), 'без защиты'),
        ],
      ),
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow({required this.weekStart});

  final int weekStart;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    // 2026-10-19 is a Monday; the names are the locale's own.
    final monday = DateTime(2026, 10, 19);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Text(
                DateFormat.E('ru_RU').format(
                  DateTime(
                    monday.year,
                    monday.month,
                    monday.day + (weekStart - DateTime.monday + i) % 7,
                  ),
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({
    super.key,
    required this.first,
    required this.today,
    required this.model,
    required this.sexByDay,
    required this.weekStart,
    required this.onDayTap,
  });

  final DateTime first;
  final DateTime today;
  final CycleModel? model;
  final Map<DateTime, int?> sexByDay;
  final int weekStart;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    // The year only once it is not this one — with no end to the list, "Март"
    // alone could be any of them.
    final name = DateFormat.LLLL('ru_RU').format(first);
    final title = first.year == today.year ? name : '$name ${first.year}';
    final days = DateTime(first.year, first.month + 1, 0).day;
    final pad = (first.weekday - weekStart + 7) % 7;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              title[0].toUpperCase() + title.substring(1),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (var i = 0; i < pad; i++) const SizedBox.shrink(),
              for (var d = 1; d <= days; d++)
                _DayCell(
                  day: DateTime(first.year, first.month, d),
                  today: today,
                  model: model,
                  sex: sexByDay[DateTime(first.year, first.month, d)],
                  onTap: onDayTap,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A day: a filled circle for what was entered, a dashed one for the forecast.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.model,
    required this.sex,
    required this.onTap,
  });

  final DateTime day;
  final DateTime today;
  final CycleModel? model;
  final int? sex;
  final ValueChanged<DateTime> onTap;

  // Light fills with their own dark ink, the same on both themes.
  static const _periodFill = Color(0xFFF3DDE6);
  static const _fertileFill = Color(0xFFDCE7FB);
  static const _ink = Color(0xFF1B2230);

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final phase = model?.phaseOn(day) ?? CyclePhase.other;
    final forecast = model?.isForecast(day) ?? false;
    final isToday = day == today;
    final color = cyclePhaseColor(phase, p);

    final (Color? fill, Color ink) = phase == CyclePhase.other || forecast
        ? (null, p.textPrimary)
        : switch (phase) {
            CyclePhase.period => (_periodFill, const Color(0xFF6E3550)),
            CyclePhase.fertile => (_fertileFill, _ink),
            _ => (ovulationColor, Colors.white),
          };

    return Semantics(
      button: true,
      label: '${day.day}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(day),
        child: CustomPaint(
          painter: forecast && phase != CyclePhase.other
              ? _DashedCirclePainter(color: color, width: 1.5)
              : null,
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
            foregroundDecoration: isToday
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: p.textPrimary, width: 2),
                  )
                : null,
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isToday || phase != CyclePhase.other
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: ink,
                  ),
                ),
                if (CycleHeart.shows(sex))
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: CycleHeart(sex: sex, size: 10),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A circle drawn as dashes — the forecast's outline.
class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final r = (size.shortestSide - width) / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    // 16 dashes, each half of its slot.
    const count = 16;
    const slot = 2 * math.pi / count;
    for (var i = 0; i < count; i++) {
      canvas.drawArc(rect, i * slot, slot / 2, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) =>
      old.color != color || old.width != width;
}
