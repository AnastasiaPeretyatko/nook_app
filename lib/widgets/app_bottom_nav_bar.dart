import 'package:flutter/material.dart';
import 'package:todo_app/theme/app_palette.dart';

class AppNavItem {
  const AppNavItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;

  /// How many things are waiting behind this tab — drawn as a small count on the
  /// icon, and nothing at all at zero.
  ///
  /// The bar is handed a number and knows nothing about where it comes from:
  /// today the only one is the overdue tasks behind the tasks tab, counted by
  /// `overdueTasksProvider` and watched by `MainScreen`.
  final int badgeCount;

  /// This item carrying [count] as its badge — how `MainScreen` puts a live
  /// number onto its otherwise `const` list of buttons.
  AppNavItem withBadge(int count) =>
      AppNavItem(icon: icon, label: label, badgeCount: count);
}

/// The bottom bar of the "Иней" design: four labelled tabs on a flat bar with a
/// hairline on top (`Main.dc.html`, `<nav>`). The active tab is drawn in the
/// text colour, not the accent — the interface is near-monochrome and colour
/// belongs to the tasks (DESIGN.md §1). Creating things is the floating "+"
/// button above it, which `MainScreen` owns.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// The bar without the system inset: the mock-up's 84 is 64 plus a 20px
  /// home-indicator area, which here is whatever the device says it is.
  static const double barHeight = 64;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.navBar,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavBarButton(
                    item: items[i],
                    active: i == currentIndex,
                    onTap: () => onTap(i),
                    activeColor: p.textPrimary,
                    inactiveColor: p.navInactive,
                    barColor: p.navBar,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarButton extends StatelessWidget {
  const _NavBarButton({
    required this.item,
    required this.active,
    required this.onTap,
    required this.activeColor,
    required this.inactiveColor,
    required this.barColor,
  });

  final AppNavItem item;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;
  final Color inactiveColor;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : inactiveColor;
    return InkWell(
      onTap: onTap,
      child: Semantics(
        selected: active,
        button: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The badge hangs off the icon's top-right corner, so the stack is
            // the icon's own size and the bubble is allowed to spill outside it.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(item.icon, size: 22, color: color),
                if (item.badgeCount > 0)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: _NavBadge(
                      count: item.badgeCount,
                      barColor: barColor,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The count on a tab's icon.
///
/// A number and not a bare dot: what is behind it is a list to work through, and
/// one task late is a different afternoon from eleven. Above [_maxCount] it
/// reads "9+" — the bubble marks a 22px icon, and a three-digit count would be
/// wider than the thing it is attached to.
class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count, required this.barColor});

  final int count;

  /// The bar's own fill, painted as a ring around the bubble so it reads as a
  /// separate object where it overlaps the icon's strokes.
  final Color barColor;

  static const int _maxCount = 9;
  static const double _ringWidth = 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = count > _maxCount ? '$_maxCount+' : '$count';

    return Semantics(
      label: 'Просроченных задач: $count',
      // The bubble reads as one thing, not as a bare number floating on an icon.
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          // The scheme's own error red, and its paired ink on top: the one pair
          // in the theme that is guaranteed to read on each other, and it
          // follows the light and dark schemes without a second colour here.
          color: scheme.error,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: barColor, width: _ringWidth),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onError,
              fontSize: 10,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
