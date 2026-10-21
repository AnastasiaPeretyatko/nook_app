import 'package:flutter/material.dart';
import 'package:todo_app/theme/app_palette.dart';

/// Two or more equal segments on a grey track, the chosen one raised in white
/// (DESIGN.md §5, "Переключатель-сегмент"): "Активные / Выполненные",
/// "Сегодня / Неделя".
class SegmentedSwitch extends StatelessWidget {
  const SegmentedSwitch({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final n = labels.length;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.segmentTrack,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        height: 36,
        child: Stack(
          children: [
            // One raised thumb that slides under the chosen label. Fading one
            // segment out while the other faded in left both half-drawn
            // mid-way, which read as a blink.
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              alignment: Alignment(n == 1 ? 0 : -1 + 2 * selected / (n - 1), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: p.segmentSelected,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x141B2230),
                        offset: Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final (i, label) in labels.indexed)
                  Expanded(
                    child: Semantics(
                      selected: i == selected,
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: i == selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: i == selected
                                  ? p.textPrimary
                                  : p.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
