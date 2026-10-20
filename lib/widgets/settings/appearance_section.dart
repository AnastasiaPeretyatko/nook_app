import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/settings/calendar_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/widgets/list_card.dart';
import 'package:todo_app/widgets/segmented_switch.dart';

/// "Внешний вид" of the settings list (`Settings.dc.html`): the theme as a
/// switch, the accent as six dots, and what the calendar's dots cover.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  // The order the segments are drawn in; the index is the position here.
  static const _modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(Theme.of(context));
    final themeMode = ref.watch(themeModeProvider);
    final accent = accentFor(ref.watch(appColorProvider));
    final showHabits = ref.watch(showHabitsInCalendarProvider);
    final isDark = switch (themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(title: 'Внешний вид'),
        RowsCard(
          dividerIndent: 16,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Тема',
                    style: TextStyle(fontSize: 15, color: palette.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  SegmentedSwitch(
                    labels: const ['Как в системе', 'Светлая', 'Тёмная'],
                    selected: _modes.indexOf(themeMode),
                    onChanged: (i) => ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(_modes[i]),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Акцентный цвет',
                    style: TextStyle(fontSize: 15, color: palette.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final a in appAccents)
                        _AccentDot(
                          accent: a,
                          selected: a == accent,
                          dark: isDark,
                          onTap: () => ref
                              .read(appColorProvider.notifier)
                              .setColor(a.light),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // A daily habit puts a dot on every cell of the month, after which
            // no day looks any busier than another. Off, the dots are one-off
            // tasks only — the day screen still shows every habit.
            ToggleRow(
              label: 'Привычки в календаре',
              sub: calendarMarkersLabel(showHabits: showHabits),
              value: showHabits,
              onChanged: (v) =>
                  ref.read(showHabitsInCalendarProvider.notifier).setEnabled(v),
            ),
          ],
        ),
      ],
    );
  }
}

/// One accent: a 28px dot in a 44px touch target, ringed when chosen.
class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.accent,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final AppAccent accent;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = dark ? accent.dark : accent.light;
    final card = AppPalette.of(Theme.of(context)).surface;
    return Semantics(
      button: true,
      selected: selected,
      label: accent.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                // The ring first, the gap in the card's own colour over it.
                boxShadow: selected
                    ? [
                        BoxShadow(color: color, spreadRadius: 4),
                        BoxShadow(color: card, spreadRadius: 2),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
