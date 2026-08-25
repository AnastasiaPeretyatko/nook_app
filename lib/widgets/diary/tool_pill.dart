import 'package:flutter/material.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';

/// The strip the diary's tools sit in: a rounded rectangle washed with the app
/// accent.
///
/// One widget for both screens on purpose — the bar under a note being read has
/// to look like the bar under a note being written, and the surest way to keep
/// two things identical is for them to be the same thing.
class ToolPill extends StatelessWidget {
  const ToolPill({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: accentWash(Theme.of(context)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: children,
      ),
    );
  }
}

/// One tool inside a [ToolPill].
///
/// Colour carries the whole state — the accent when the tool is on, the
/// placeholder tone when it is off — and nothing is drawn behind the glyph: a
/// chip under an active button would fight the strip it sits in.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.onTap,
    this.icon,
    this.label,
    this.tooltip,
    this.active = false,
  }) : assert(icon != null || label != null);

  /// Null disables the tool: dimmed, and nothing happens on a tap.
  final VoidCallback? onTap;

  final IconData? icon;
  final String? label;
  final String? tooltip;
  final bool active;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Asked against the strip's own tone: the pale families of the palette are
    // not readable as their own accent.
    final accent = inkOn(accentWash(theme), theme.colorScheme.primary);
    final color = onTap == null
        ? labelInk.withValues(alpha: 0.4)
        : active
        ? accent
        : labelInk;

    final button = InkWell(
      onTap: onTap,
      // The editor keeps the focus: a focusable button would close the keyboard
      // and drop the selection it is about to format.
      canRequestFocus: false,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: _size,
        height: _size,
        child: Center(
          child: icon != null
              ? Icon(icon, size: 22, color: color)
              : Text(
                  label!,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
        ),
      ),
    );

    final message = tooltip;
    return message == null ? button : Tooltip(message: message, child: button);
  }
}
