import 'package:flutter/material.dart';
import 'package:todo_app/theme/app_palette.dart';

/// "СЕГОДНЯ ··· 3 из 6" over a card (DESIGN.md §3, "Подпись раздела").
/// [color] overrides the title's tone — "ПРОСРОЧЕНО" is drawn in `danger`.
class SectionCaption extends StatelessWidget {
  const SectionCaption({
    super.key,
    required this.title,
    this.trailing,
    this.color,
    this.horizontalInset = 24,
  });

  final String title;

  /// Left and right padding. 24 on a page of its own; less inside a list that
  /// already has a margin.
  final double horizontalInset;
  final String? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalInset, 20, horizontalInset, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.04,
                color: color ?? p.textSecondary,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontSize: 13,
                color: p.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

/// One white card holding rows, a hairline between them that starts where the
/// text does (DESIGN.md §5, "Карточка-список"): [dividerIndent] from the left.
class RowsCard extends StatelessWidget {
  const RowsCard({
    super.key,
    required this.children,
    this.dividerIndent = 68,
    this.horizontalMargin = 16,
  });

  final List<Widget> children;
  final double dividerIndent;

  /// Space left and right of the card; 0 inside a list that has its own margin.
  final double horizontalMargin;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: Material(
        color: p.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0)
                  Container(
                    height: 1,
                    margin: EdgeInsets.only(left: dividerIndent, right: 16),
                    color: p.divider,
                  ),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of a [RowsCard] with a switch at its end: the name, a line under it,
/// the switch. A null [onChanged] greys the switch out.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    final off = onChanged == null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: off ? palette.textTertiary : palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
