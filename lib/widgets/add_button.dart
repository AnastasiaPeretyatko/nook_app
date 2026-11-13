import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/theme/app_palette.dart';

/// The floating "+" of every tab: a dark rounded square, light in the dark
/// theme — the main action is drawn in the text colour, not the accent
/// (DESIGN.md §1, §4: 56px, radius 20, 24 from the edge, 20 above the bar).
class AddButton extends StatelessWidget {
  const AddButton({super.key, required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final shape = BorderRadius.circular(20);
    return Padding(
      // On top of the 16 the scaffold's endFloat already leaves.
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E1B2230),
              offset: Offset(0, 8),
              blurRadius: 24,
            ),
          ],
        ),
        child: Material(
          color: p.textPrimary,
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Tooltip(
              message: tooltip,
              child: SizedBox.square(
                dimension: 56,
                child: Icon(LucideIcons.plus, size: 24, color: p.background),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
