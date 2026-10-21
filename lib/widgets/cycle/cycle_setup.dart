import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/app_bottom_nav_bar.dart';
import 'package:todo_app/widgets/settings/about_section.dart';

/// "Настроим цикл" (`EmptyCycle.dc.html`): what the "Цикл" tab shows until the
/// start of the last period is known, because without it there is no forecast.
///
/// The two lengths have defaults and are written as they are stepped; the date
/// is held here until "Начать", which is what leaves the screen (the tab swaps
/// it for the page as soon as the date is saved). [onSkip] lets the tab carry on
/// without a date.
class CycleSetup extends ConsumerStatefulWidget {
  const CycleSetup({super.key, required this.onSkip});

  final VoidCallback onSkip;

  @override
  ConsumerState<CycleSetup> createState() => _CycleSetupState();
}

class _CycleSetupState extends ConsumerState<CycleSetup> {
  DateTime? _start;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final about = ref.watch(aboutSettingsProvider);
    final notifier = ref.read(aboutSettingsProvider.notifier);
    final bottom =
        AppBottomNavBar.barHeight + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottom + 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                      child: Text(
                        'Настроим цикл',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.6,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: Text(
                        'Три вопроса, чтобы прогнозы были точнее. Позже можно '
                        'поменять в настройках.',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: p.border),
                      ),
                      child: Column(
                        children: [
                          _Row(
                            label: 'Начало последних месячных',
                            child: _DateChip(
                              date: _start,
                              onTap: () async {
                                final picked = await pickCycleStartDate(
                                  context,
                                  _start,
                                );
                                if (picked != null) {
                                  setState(() => _start = picked);
                                }
                              },
                            ),
                          ),
                          Divider(height: 1, color: p.divider),
                          _Row(
                            label: 'Длина цикла',
                            child: _Count(
                              value: about.cycleLength,
                              range: cycleLengthRange,
                              onChanged: notifier.setCycleLength,
                            ),
                          ),
                          Divider(height: 1, color: p.divider),
                          _Row(
                            label: 'Длина месячных',
                            child: _Count(
                              value: about.periodLength,
                              range: periodLengthRange,
                              onChanged: notifier.setPeriodLength,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Text(
                        'Не помните точно — укажите примерно. Приложение '
                        'уточнит цикл по вашим отметкам.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Material(
                            color: _start == null ? p.chip : p.textPrimary,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _start == null
                                  ? null
                                  : () => notifier.setLastStart(_start!),
                              child: Container(
                                height: 52,
                                alignment: Alignment.center,
                                child: Text(
                                  'Начать',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: _start == null
                                        ? p.textTertiary
                                        : p.background,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: widget.onSkip,
                            style: TextButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              foregroundColor: p.textSecondary,
                            ),
                            child: const Text(
                              'Пропустить, заполню позже',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 15, color: p.textPrimary),
              ),
            ),
            const SizedBox(width: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// The rose chip: the picked day, or "Выбрать" before there is one.
class _DateChip extends StatelessWidget {
  const _DateChip({required this.date, required this.onTap});

  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rose = taskPalette.firstWhere((s) => s.key == 'pink');
    final fill = dark ? rose.darkFill : rose.light;
    final ink = dark ? rose.darkInk : rose.strong;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            date == null
                ? 'Выбрать'
                : DateFormat('d MMM', 'ru_RU').format(date!),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// "−  28 дн.  +"
class _Count extends StatelessWidget {
  const _Count({
    required this.value,
    required this.range,
    required this.onChanged,
  });

  final int value;
  final ({int min, int max}) range;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    Widget button(String sign, bool enabled, int step) => SizedBox.square(
      dimension: 36,
      child: OutlinedButton(
        onPressed: enabled ? () => onChanged(value + step) : null,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
          side: BorderSide(color: p.border),
          foregroundColor: p.textPrimary,
        ),
        child: Text(sign, style: const TextStyle(fontSize: 18)),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button('−', value > range.min, -1),
        SizedBox(
          width: 64,
          child: Text(
            '$value дн.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
        ),
        button('+', value < range.max, 1),
      ],
    );
  }
}
