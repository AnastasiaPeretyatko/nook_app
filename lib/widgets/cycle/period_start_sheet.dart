import 'package:flutter/material.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/date_range_calendar.dart';

/// Opens the cycle's period-date selector. Confirmation and reset live here;
/// [DateRangeCalendar] remains reusable and page-agnostic.
Future<Set<DateTime>?> showPeriodStartSheet(
  BuildContext context, {
  required DateTime firstDate,
  required DateTime lastDate,
  required DateTime initialMonth,
  Set<DateTime> initialSelectedDates = const {},
  int weekStart = DateTime.monday,
}) => showModalBottomSheet<Set<DateTime>>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => PeriodStartSheet(
    firstDate: firstDate,
    lastDate: lastDate,
    initialMonth: initialMonth,
    initialSelectedDates: initialSelectedDates,
    weekStart: weekStart,
  ),
);

class PeriodStartSheet extends StatefulWidget {
  const PeriodStartSheet({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.initialMonth,
    this.initialSelectedDates = const {},
    this.weekStart = DateTime.monday,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime initialMonth;
  final Set<DateTime> initialSelectedDates;
  final int weekStart;

  @override
  State<PeriodStartSheet> createState() => _PeriodStartSheetState();
}

class _PeriodStartSheetState extends State<PeriodStartSheet> {
  late Set<DateTime> _selected = {
    for (final day in widget.initialSelectedDates)
      DateTime(day.year, day.month, day.day),
  };

  void _closeWith(Set<DateTime> result) {
    setState(() => _selected = {});
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return AppSheet(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Месячные начались',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Выберите дни месячных',
                style: TextStyle(fontSize: 13, color: p.textSecondary),
              ),
            ],
          ),
        ),
        DateRangeCalendar(
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
          initialMonth: widget.initialMonth,
          selectedDates: _selected,
          weekStart: widget.weekStart,
          onSelectionChanged: (days) => setState(() => _selected = days),
        ),
        Row(
          children: [
            Expanded(
              child: _SheetButton(
                key: const ValueKey('period-start-reset'),
                label: 'Сбросить',
                fill: p.chip,
                ink: p.textPrimary,
                onTap: () => _closeWith(const <DateTime>{}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SheetButton(
                key: const ValueKey('period-start-apply'),
                label: 'Применить',
                fill: p.textPrimary,
                ink: p.background,
                onTap: () => _closeWith(Set<DateTime>.unmodifiable(_selected)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    super.key,
    required this.label,
    required this.fill,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final Color fill;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.45 : 1,
    child: Material(
      color: fill,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
