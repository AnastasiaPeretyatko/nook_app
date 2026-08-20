import 'package:flutter/material.dart';
import 'package:todo_app/utils/task_colors.dart';

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
                    color: isSelected
                        ? onTaskColorMuted(color)
                        : Colors.transparent,
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
                    ? Icon(Icons.check, size: 16, color: onTaskColor(color))
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
