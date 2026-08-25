import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);
    final appColor = ref.watch(appColorProvider);
    final colorNotifier = ref.read(appColorProvider.notifier);

    final isDark = switch (themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Внешний вид')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            _SectionTitle(title: 'Тема'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ThemeOption(
                    icon: LucideIcons.sun,
                    label: 'Светлая',
                    selected: themeMode == ThemeMode.light,
                    onTap: () => notifier.setThemeMode(ThemeMode.light),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ThemeOption(
                    icon: LucideIcons.moon,
                    label: 'Тёмная',
                    selected: themeMode == ThemeMode.dark,
                    onTap: () => notifier.setThemeMode(ThemeMode.dark),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ThemeOption(
                    icon: LucideIcons.sun_moon,
                    label: 'Системная',
                    selected: themeMode == ThemeMode.system,
                    onTap: () => notifier.setThemeMode(ThemeMode.system),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _SectionTitle(title: 'Цвет приложения'),
            const SizedBox(height: 12),
            SizedBox(
              height: 18,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: appColorPalette.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final color = appColorPalette[index];
                  final selected = color.toARGB32() == appColor.toARGB32();
                  final displayColor =
                      (isDark && color.computeLuminance() < 0.1)
                      ? Colors.white
                      : color;
                  return _ColorBar(
                    color: displayColor,
                    selected: selected,
                    onTap: () => colorNotifier.setColor(color),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ColorBar extends StatelessWidget {
  const _ColorBar({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 56,
        padding: EdgeInsets.all(selected ? 3 : 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(selected ? 12 : 18),
          ),
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: selected ? 2 : 1),
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? theme.colorScheme.primary : null),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected ? theme.colorScheme.primary : null,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
