import 'package:flutter/material.dart';

/// How many of a task's subtasks are done, as a plain read-out: a checkbox glyph
/// and "done/total". Deliberately not tappable — subtasks are ticked off in the
/// task's own sheet, not from the screen that reports the count.
///
/// Shared by the day timeline and the "Задачи" list so both read identically.
class SubtaskProgress extends StatelessWidget {
  const SubtaskProgress({super.key, required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDone = done == total;
    // Drawn on a surface (a timeline row, a list row), so it follows the theme
    // rather than assuming a light one.
    final muted = theme.colorScheme.onSurfaceVariant;
    final color = allDone ? muted : muted.withValues(alpha: 0.75);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: allDone ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color, width: 1.4),
          ),
          child: allDone
              // Punched out of the filled box: the surface showing through.
              ? Icon(
                  Icons.check,
                  size: 10,
                  color: theme.colorScheme.surface,
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(
          '$done/$total',
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
