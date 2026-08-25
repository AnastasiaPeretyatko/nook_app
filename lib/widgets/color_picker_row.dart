import 'package:flutter/material.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Color? selected;
  final ValueChanged<Color> onChanged;

  /// The task colours: one swatch per family of [taskPalette], showing the
  /// accent — that is what a task stores. The light tone of the same family is
  /// what the timeline paints its pills with, see `taskLightTone`.
  static const colors = [
    Color(0xFF8B7CF6), // violet
    Color(0xFF76B894), // green
    Color(0xFFF5A76F), // orange
    Color(0xFF72B7D8), // blue
    Color(0xFFD98BA8), // pink
    Color(0xFFF4C95D), // yellow
    Color(0xFFE97B70), // red
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: colors.map((color) {
          final isSelected = selected?.toARGB32() == color.toARGB32();
          // A swatch is a fill of the colour itself, so what is drawn on it is
          // the brand ink — one white on every family — and not the
          // luminance-flipped [onTaskColor], which turns black on all seven of
          // these and made the ring and the tick read as dirt on the colour.
          // The tick is a glyph recognised by its shape rather than read, which
          // is the case white is for.
          final ink = onBrandFill(color);
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(color),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? ink : Colors.transparent,
                    width: 2.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? Icon(LucideIcons.check, size: 16, color: ink)
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
