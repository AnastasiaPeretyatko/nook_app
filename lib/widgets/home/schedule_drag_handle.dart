import 'package:flutter/material.dart';

/// The grip at the top of the day-schedule sheet. Dragging it opens and closes
/// the calendar above; the touch target is the whole strip, not the drawn bar.
class ScheduleDragHandle extends StatefulWidget {
  const ScheduleDragHandle({
    super.key,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  /// Height of the grab zone. Well past what the bar needs — the bar is only
  /// the hint, the strip is what the thumb actually lands on.
  static const double touchHeight = 44;

  @override
  State<ScheduleDragHandle> createState() => _ScheduleDragHandleState();
}

class _ScheduleDragHandleState extends State<ScheduleDragHandle> {
  bool _dragging = false;

  void _setDragging(bool value) {
    if (_dragging == value) return;
    setState(() => _dragging = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _setDragging(true),
      onVerticalDragUpdate: widget.onDragUpdate,
      onVerticalDragCancel: () => _setDragging(false),
      onVerticalDragEnd: (details) {
        _setDragging(false);
        widget.onDragEnd(details);
      },
      child: SizedBox(
        height: ScheduleDragHandle.touchHeight,
        width: double.infinity,
        child: Center(
          // The bar grows and darkens under the finger, so the gesture reads as
          // grabbed even before the calendar moves.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: _dragging ? 64 : 56,
            height: 6,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(
                alpha: _dragging ? 0.6 : 0.4,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}
