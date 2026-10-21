import 'package:flutter/material.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_palette.dart';

class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Color? selected;
  final ValueChanged<Color> onChanged;

  /// The task colours: one swatch per family of [pickableTaskPalette], showing
  /// the accent — that is what a task stores. The light tone of the same family
  /// is what the timeline paints its pills with, see `taskLightTone`.
  static final colors = [
    for (final swatch in pickableTaskPalette) swatch.accent,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheet = raisedSurface(theme);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: colors.map((color) {
          final isSelected = selected?.toARGB32() == color.toARGB32();
          // The selected pill is ringed three times — sheet, light tone, ink —
          // as nested boxes: stacked shadows paint in an order that is easy to
          // get backwards.
          final pill = Container(
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
          );
          return Expanded(
            // The tap area is the full 44px row, not the 16px pill.
            child: GestureDetector(
              onTap: () => onChanged(color),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 48),
                    child: isSelected
                        ? _ring(
                            color,
                            taskBadgeSurface(theme, color, sheet),
                            sheet,
                            pill,
                          )
                        : pill,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static Widget _ring(Color ink, Color fill, Color gap, Widget pill) => _Ring(
    color: ink,
    radius: 14,
    padding: 1,
    child: _Ring(
      color: fill,
      radius: 13,
      padding: 2,
      child: _Ring(color: gap, radius: 11, padding: 3, child: pill),
    ),
  );
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.color,
    required this.radius,
    required this.padding,
    required this.child,
  });

  final Color color;
  final double radius;
  final double padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}
