import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/list_card.dart';

/// "Привычки и аналитика" of the settings list (`Settings.dc.html`): which day
/// the week starts on, how late a tick may be before it counts as late, and
/// whether today's open habits are spared until the day is over.
class AnalyticsSection extends ConsumerWidget {
  const AnalyticsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(Theme.of(context));
    final weekStart = ref.watch(weekStartProvider);
    final grace = ref.watch(lateGraceMinutesProvider);
    final todayOpen = ref.watch(todayStaysOpenProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(title: 'Привычки и аналитика'),
        RowsCard(
          dividerIndent: 16,
          children: [
            InkWell(
              onTap: () async {
                final chosen = await showOptionsSheet<int>(
                  context,
                  title: 'Начало недели',
                  options: [
                    for (final d in [DateTime.monday, DateTime.sunday])
                      (d, weekStartLabel(d)),
                  ],
                  selected: weekStart,
                );
                if (chosen != null) {
                  await ref.read(weekStartProvider.notifier).setDay(chosen.$1);
                }
              },
              child: SizedBox(
                height: 54,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Начало недели',
                          style: TextStyle(
                            fontSize: 15,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        weekStartLabel(weekStart),
                        style: TextStyle(
                          fontSize: 15,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        LucideIcons.chevron_right,
                        size: 16,
                        color: palette.iconMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Считать опозданием',
                    style: TextStyle(fontSize: 15, color: palette.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Если отметка позже запланированного времени',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // One row, the chips sharing its width: a Wrap broke the last
                  // one onto a second line on a narrow phone.
                  Row(
                    children: [
                      for (final (i, m) in lateGraceOptions.indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: _Chip(
                            label: lateGraceLabel(m),
                            selected: m == grace,
                            onTap: () => ref
                                .read(lateGraceMinutesProvider.notifier)
                                .setMinutes(m),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            ToggleRow(
              label: 'Учитывать сегодняшний день',
              sub: todayStaysOpenLabel(todayOpen),
              value: todayOpen,
              onChanged: (v) =>
                  ref.read(todayStaysOpenProvider.notifier).setEnabled(v),
            ),
          ],
        ),
      ],
    );
  }
}

/// A 36px pill: dark when chosen, outlined when not (DESIGN.md §5, "Чип").
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.textPrimary : p.surface,
            borderRadius: BorderRadius.circular(18),
            border: selected ? null : Border.all(color: p.borderStrong),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? p.background : p.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
