import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/habit_labels.dart';

typedef MonthCalendarDayBuilder =
    Widget Function(BuildContext context, DateTime day);

/// The shared visual grid used by the monthly habit and value calendars.
///
/// It owns only calendar presentation: weekday labels, leading empty cells,
/// seven equal columns and spacing. The caller supplies all day-state logic.
class HabitMonthCalendarGrid extends ConsumerWidget {
  const HabitMonthCalendarGrid({
    super.key,
    required this.month,
    required this.dayBuilder,
  });

  final DateTime month;
  final MonthCalendarDayBuilder dayBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(Theme.of(context));
    final weekStart = ref.watch(weekStartProvider);
    final first = DateTime(month.year, month.month);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final pad = (first.weekday - weekStart + 7) % 7;
    final names = [
      for (var index = 0; index < 7; index++)
        weekdayShort[(weekStart - 1 + index) % 7],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final name in names)
              Expanded(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: palette.textSecondary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var index = 0; index < pad; index++) const SizedBox.shrink(),
            for (var day = 1; day <= count; day++)
              dayBuilder(context, DateTime(month.year, month.month, day)),
          ],
        ),
      ],
    );
  }
}
