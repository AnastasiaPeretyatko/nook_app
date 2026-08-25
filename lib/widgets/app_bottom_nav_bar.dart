import 'package:flutter/material.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class AppNavItem {
  const AppNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.onCenterTap,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onCenterTap;

  static const Color _inactiveColor = Color(0xFF9AA0A6);
  static const double _indicatorWidth = 26;
  static const double _indicatorHeight = 3;
  static const double _barHeight = 64;
  static const double _fabSize = 58;
  static const double _protrusion = 24;
  static const double _centerGap = 72;

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: SizedBox(
          height: _barHeight + _protrusion,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _bar(context, activeColor),
              ),
              Positioned(
                top: 0,
                child: _CenterButton(
                  size: _fabSize,
                  color: activeColor,
                  onTap: onCenterTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, Color activeColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: _barHeight,
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final splitIndex = items.length ~/ 2;
          final itemWidth = (constraints.maxWidth - _centerGap) / items.length;

          double indicatorLeft(int index) {
            final gapOffset = index >= splitIndex ? _centerGap : 0;
            return itemWidth * index +
                gapOffset +
                (itemWidth - _indicatorWidth) / 2;
          }

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                left: indicatorLeft(currentIndex),
                bottom: 10,
                child: Container(
                  width: _indicatorWidth,
                  height: _indicatorHeight,
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i == splitIndex) const SizedBox(width: _centerGap),
                    SizedBox(
                      width: itemWidth,
                      child: _NavBarButton(
                        item: items[i],
                        active: i == currentIndex,
                        onTap: () => onTap(i),
                        activeColor: activeColor,
                        inactiveColor: _inactiveColor,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({
    required this.size,
    required this.color,
    required this.onTap,
  });

  final double size;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // The button is a solid accent disc — a brand fill, so its glyph is
          // the brand ink rather than the scheme's luminance-flipped onPrimary.
          child: Icon(LucideIcons.plus, color: onBrandFill(color), size: 30),
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
  });

  final AppNavItem item;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: Center(
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          tween: Tween(end: active ? 1 : 0),
          builder: (context, t, child) {
            return Icon(
              item.icon,
              size: 29,
              weight: 300,
              color: Color.lerp(inactiveColor, activeColor, t),
            );
          },
        ),
      ),
    );
  }
}
