import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/widgets/list_card.dart';
import 'package:todo_app/widgets/segmented_switch.dart';

/// "О себе" of the settings list (`Settings.dc.html`): the gender, and — only
/// for "Женский" — the cycle: the switch that puts the "Цикл" tab on the bar,
/// the start of the last period and the two lengths.
class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(Theme.of(context));
    final about = ref.watch(aboutSettingsProvider);
    final notifier = ref.read(aboutSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(title: 'О себе'),
        RowsCard(
          dividerIndent: 16,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Пол',
                    style: TextStyle(fontSize: 15, color: palette.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  SegmentedSwitch(
                    labels: [for (final g in Gender.values) g.label],
                    selected: about.gender.index,
                    onChanged: (i) => notifier.setGender(Gender.values[i]),
                  ),
                ],
              ),
            ),
            if (about.gender == Gender.female) ...[
              ToggleRow(
                label: 'Отслеживать цикл',
                sub: 'Вкладка «Цикл» в нижней панели',
                value: about.trackCycle,
                onChanged: notifier.setTrackCycle,
              ),
              if (about.trackCycle) ...[
                InkWell(
                  onTap: () =>
                      pickCycleStart(context, notifier, about.lastStart),
                  child: SizedBox(
                    height: 54,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Начало последних месячных',
                              style: TextStyle(
                                fontSize: 15,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            about.lastStart == null
                                ? 'Не указано'
                                : DateFormat.MMMMd(
                                    'ru_RU',
                                  ).format(about.lastStart!),
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
                _StepperRow(
                  label: 'Длина цикла',
                  sub: 'От первого дня месячных до следующих',
                  value: about.cycleLength,
                  range: cycleLengthRange,
                  onChanged: notifier.setCycleLength,
                ),
                _StepperRow(
                  label: 'Длина месячных',
                  sub: 'Сколько дней они обычно идут',
                  value: about.periodLength,
                  range: periodLengthRange,
                  onChanged: notifier.setPeriodLength,
                ),
              ],
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Text(
            'Пол нужен только для календаря цикла. Его не видят участники '
            'групп, а данные цикла хранятся только на этом телефоне.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens the date picker for the first day of the last period — never a day
/// that has not come yet.
Future<void> pickCycleStart(
  BuildContext context,
  AboutSettingsNotifier notifier,
  DateTime? current,
) async {
  final today = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: current ?? today,
    firstDate: DateTime(today.year - 1),
    lastDate: today,
    locale: const Locale('ru', 'RU'),
  );
  if (picked != null) await notifier.setLastStart(picked);
}

/// A name, a line under it and "− N дн. +" at the end.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.sub,
    required this.value,
    required this.range,
    required this.onChanged,
  });

  final String label;
  final String sub;
  final int value;
  final ({int min, int max}) range;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, color: palette.textPrimary),
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
            IconButton(
              tooltip: 'Меньше: $label',
              onPressed: value > range.min ? () => onChanged(value - 1) : null,
              icon: const Icon(LucideIcons.minus, size: 18),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '$value дн.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Больше: $label',
              onPressed: value < range.max ? () => onChanged(value + 1) : null,
              icon: const Icon(LucideIcons.plus, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
