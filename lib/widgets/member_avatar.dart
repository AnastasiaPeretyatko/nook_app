import 'package:flutter/material.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_palette.dart';

/// A group member as a circle with their first letter — for an assignee on the
/// timeline and in the member list. No picture: another member's avatar is a
/// network fetch per row, and a letter tells two people in a family apart.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    this.size = 28,
    this.accent,
  });

  final String name;
  final double size;

  /// A task-palette colour to paint the avatar in (see [memberAccent]). Null is
  /// the neutral grey.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = accent == null
        ? neutralChip(theme)
        : taskBadgeSurface(theme, accent!, raisedSurface(theme));
    final ink = accent == null
        ? theme.colorScheme.onSurface
        : taskBadgeInk(theme, accent!, fill);
    final trimmed = name.trim();
    final letter = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Text(
        letter,
        style: theme.textTheme.labelMedium?.copyWith(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    );
  }
}

/// A member's colour: one of the task palette's, fixed by the account id so the
/// same person is the same colour on every screen and every device.
Color memberAccent(String uid) {
  final sum = uid.codeUnits.fold<int>(0, (a, b) => a + b);
  return pickableTaskPalette[sum % pickableTaskPalette.length].accent;
}
