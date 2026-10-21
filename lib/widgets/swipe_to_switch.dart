import 'package:flutter/material.dart';

/// Turns a sideways swipe over [child] into a step between tabs: a swipe to the
/// left asks for the next one (+1), to the right for the previous (-1). The
/// caller clamps — it knows how many tabs there are.
class SwipeToSwitch extends StatelessWidget {
  const SwipeToSwitch({super.key, required this.onStep, required this.child});

  final ValueChanged<int> onStep;
  final Widget child;

  /// Slower than this (logical px/s) is a drag that merely wandered sideways.
  static const _minVelocity = 300.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() >= _minVelocity) onStep(v < 0 ? 1 : -1);
      },
      child: child,
    );
  }
}
