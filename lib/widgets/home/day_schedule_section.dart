import 'package:flutter/material.dart';
import 'package:todo_app/widgets/home/schedule_drag_handle.dart';
import 'package:todo_app/widgets/home/task_timeline.dart';

class DayScheduleSection extends StatefulWidget {
  const DayScheduleSection({
    super.key,
    required this.onHandleDragUpdate,
    required this.onHandleDragEnd,
    required this.onDayChange,
    required this.selectedDay,
  });

  final GestureDragUpdateCallback onHandleDragUpdate;
  final GestureDragEndCallback onHandleDragEnd;

  /// Called with +1 (swipe left → next day) or -1 (swipe right → previous day).
  final ValueChanged<int> onDayChange;
  final DateTime selectedDay;

  static const double _swipeVelocityThreshold = 250;

  @override
  State<DayScheduleSection> createState() => _DayScheduleSectionState();
}

class _DayScheduleSectionState extends State<DayScheduleSection> {
  /// Direction of the last day change: +1 forward (next), -1 backward (prev).
  /// Drives which side the incoming timeline slides in from.
  int _direction = 1;

  @override
  void didUpdateWidget(covariant DayScheduleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDay != oldWidget.selectedDay) {
      _direction = widget.selectedDay.isAfter(oldWidget.selectedDay) ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    // The sheet has to read as lifted above the calendar behind it. On white
    // that is the shadow's job; in the dark theme a shadow on near-black is
    // invisible, so the sheet takes the next surface up instead.
    final sheetColor = isLight
        ? theme.colorScheme.surface
        : theme.colorScheme.surfaceContainerLow;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.5),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScheduleDragHandle(
            onDragUpdate: widget.onHandleDragUpdate,
            onDragEnd: widget.onHandleDragEnd,
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity <= -DayScheduleSection._swipeVelocityThreshold) {
                  widget.onDayChange(1);
                } else if (velocity >=
                    DayScheduleSection._swipeVelocityThreshold) {
                  widget.onDayChange(-1);
                }
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final key = (child.key as ValueKey<DateTime>).value;
                  final isIncoming = key == widget.selectedDay;
                  // Incoming enters from the swipe direction; outgoing leaves
                  // toward the opposite side.
                  final begin = isIncoming
                      ? Offset(_direction.toDouble(), 0)
                      : Offset(-_direction.toDouble(), 0);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: begin,
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, ?currentChild],
                ),
                child: KeyedSubtree(
                  key: ValueKey<DateTime>(widget.selectedDay),
                  child: TaskTimeline(selectedDay: widget.selectedDay),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
