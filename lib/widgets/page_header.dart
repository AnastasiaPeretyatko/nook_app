import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/theme/app_palette.dart';

/// The top of a tab's page in the "Иней" design: a small caption over a large
/// title, round buttons on the right (`Main.dc.html`, `Tasks.dc.html`).
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.caption,
    required this.title,
    this.actions = const [],
  });

  final String caption;
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption,
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.26,
                    color: p.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.6,
                    height: 1.2,
                    color: p.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          for (final (i, action) in actions.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            action,
          ],
        ],
      ),
    );
  }
}

/// A 44px round button with a hairline ring — the header's buttons (profile,
/// back, search).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// The glyph's colour when it should say something (a pinned note); the
  /// ordinary ink otherwise.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.surface,
        shape: CircleBorder(side: BorderSide(color: p.borderStrong)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(icon, size: 20, color: iconColor ?? p.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// The top of a screen that is pushed rather than switched to: a round back
/// button, the title in the middle, and an optional round button at the end
/// (`Account.dc.html`, `Group.dc.html`).
class BackHeader extends StatelessWidget {
  const BackHeader({super.key, required this.title, this.trailing});

  final String title;

  /// A [RoundIconButton] for the right-hand side; without one the title stays
  /// centred all the same.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: RoundIconButton(
                icon: LucideIcons.chevron_left,
                tooltip: 'Назад',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: trailing ?? const SizedBox(width: 44, height: 44),
            ),
          ),
        ],
      ),
    );
  }
}
