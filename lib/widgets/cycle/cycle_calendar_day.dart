import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/cycle.dart';
import 'package:todo_app/widgets/cycle/cycle_colors.dart';
import 'package:todo_app/widgets/cycle/cycle_heart.dart';

/// Cycle state shared by the full and weekly calendars. The calendars keep
/// their own layouts while agreeing on what is recorded, predicted or excluded.
@immutable
class CycleCalendarDayState {
  const CycleCalendarDayState({
    required this.phase,
    required this.predictedPeriod,
  });

  final CyclePhase phase;
  final bool predictedPeriod;

  Color? get dashColor => switch (phase) {
    CyclePhase.period when predictedPeriod => periodColor,
    CyclePhase.ovulation => todayBlue,
    _ => null,
  };
}

CycleCalendarDayState cycleCalendarDayState({
  required DateTime day,
  required DateTime today,
  required CycleModel? model,
  required bool marked,
  required bool excluded,
}) {
  final forecastPhase = model?.phaseOn(day) ?? CyclePhase.other;
  final phase = marked
      ? CyclePhase.period
      : excluded && forecastPhase == CyclePhase.period
      ? CyclePhase.other
      : forecastPhase;
  return CycleCalendarDayState(
    phase: phase,
    predictedPeriod:
        phase == CyclePhase.period &&
        !marked &&
        (day.isAfter(today) || (model?.isForecast(day) ?? false)),
  );
}

/// The visual day of the full cycle calendar.
class CycleCalendarDay extends StatelessWidget {
  const CycleCalendarDay({
    super.key,
    required this.day,
    required this.today,
    required this.model,
    required this.sex,
    required this.marked,
    required this.excluded,
    required this.hasInfo,
    required this.selected,
    required this.onTap,
    this.padding = 6,
    this.selectedPadding = 4,
    this.showTodayLabel = true,
  });

  final DateTime day;
  final DateTime today;
  final CycleModel? model;
  final int? sex;

  /// A recorded period day: solid period fill, forecast or not.
  final bool marked;

  /// A forecast period day the user explicitly removed.
  final bool excluded;

  /// A non-sex record exists and needs the information dot.
  final bool hasInfo;

  final bool selected;
  final ValueChanged<DateTime> onTap;

  /// Normal inset of the event disc from the available cell.
  final double padding;

  /// Inset of the larger selection layer. The difference from [padding] is
  /// the visible gray rim around a selected event.
  final double selectedPadding;

  final bool showTodayLabel;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final state = cycleCalendarDayState(
      day: day,
      today: today,
      model: model,
      marked: marked,
      excluded: excluded,
    );
    final phase = state.phase;
    final isToday = day == today;
    final (Color? fill, Color ink) = switch (phase) {
      CyclePhase.period when state.predictedPeriod => (null, periodColor),
      CyclePhase.period => (periodColor, Colors.white),
      CyclePhase.fertile || CyclePhase.ovulation => (null, todayBlue),
      CyclePhase.other => (null, p.textPrimary),
    };
    final hasCycleEvent = phase != CyclePhase.other;
    final layeredSelection = selected && hasCycleEvent;
    final innerFill = layeredSelection
        ? fill ?? p.surface
        : selected
        ? p.chip
        : fill;
    final outerInset = layeredSelection ? selectedPadding : padding;
    final layerGap = layeredSelection ? padding - selectedPadding : 0.0;

    return Semantics(
      button: true,
      selected: selected,
      label: '${day.day}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(day),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsets.all(outerInset),
              child: Container(
                key: layeredSelection
                    ? const ValueKey('selected-day-outer-layer')
                    : null,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: layeredSelection ? p.chip : null,
                ),
                child: Padding(
                  padding: EdgeInsets.all(layerGap),
                  child: CustomPaint(
                    painter: state.dashColor == null
                        ? null
                        : _DashedCirclePainter(
                            color: state.dashColor!,
                            width: 1.5,
                          ),
                    child: Container(
                      key: hasCycleEvent
                          ? const ValueKey('cycle-event-inner-layer')
                          : null,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: innerFill,
                      ),
                      alignment: Alignment.center,
                      child: Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: [
                          Center(
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isToday
                                    ? FontWeight.w700
                                    : phase != CyclePhase.other
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: ink,
                              ),
                            ),
                          ),
                          if (hasInfo)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 2,
                              child: Center(
                                child: Container(
                                  key: const ValueKey('info-dot'),
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: ink,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          if (CycleHeart.showsCalendar(sex))
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: CycleHeart(
                                sex: sex,
                                size: 11,
                                rim: p.surface,
                                showNoSex: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showTodayLabel && isToday)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Text(
                  'сегодня',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 7,
                    height: 0.8,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
    final radius = (size.shortestSide - width) / 2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
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
