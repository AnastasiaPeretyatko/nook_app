import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/cycle.dart';
import 'package:todo_app/utils/cycle_marks.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/cycle/cycle_colors.dart';
import 'package:todo_app/widgets/cycle/cycle_day_sheet.dart';
import 'package:todo_app/widgets/cycle/cycle_heart.dart';

/// What a day of the cycle is, in words: the phase it falls in, or null for an
/// ordinary day.
String? cyclePhaseName(CyclePhase phase) => switch (phase) {
  CyclePhase.period => 'месячные',
  CyclePhase.fertile => 'фертильный день',
  CyclePhase.ovulation => 'овуляция',
  CyclePhase.other => null,
};

/// The row of [day] in [days], or null when nothing was ever saved for it.
CycleDay? cycleDayRow(Iterable<CycleDay> days, DateTime day) {
  for (final d in days) {
    if (d.date == day) return d;
  }
  return null;
}

/// One day as a card's contents: its date, its place in the cycle, and **what
/// was marked on it** — flow, sex, mood, symptoms, discharge, the note. The
/// Cycle tab shows it for the picked day and the calendar for the tapped one.
class CycleDayInfo extends StatelessWidget {
  const CycleDayInfo({
    super.key,
    required this.day,
    required this.model,
    required this.row,
    this.trailing,
  });

  final DateTime day;
  final CycleModel? model;
  final CycleDay? row;

  /// At the end of the title row — the tab's "Сегодня" back to today.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final cycleDay = model?.cycleDay(day);
    final phase = model == null ? null : cyclePhaseName(model!.phaseOn(day));
    final place = [
      if (cycleDay != null) 'день цикла $cycleDay',
      ?phase,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat.MMMMd('ru_RU').format(day),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                    ),
                  ),
                  if (place.isNotEmpty)
                    Text(
                      place,
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 12),
        CycleDayMarks(row: row),
      ],
    );
  }
}

/// The marks of one day as labelled rows; a line of grey text when there are
/// none. The `pill` column is not shown — nothing in the app marks it any more.
class CycleDayMarks extends StatelessWidget {
  const CycleDayMarks({super.key, required this.row});

  final CycleDay? row;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final r = row;
    // Sorted so the same marks always read the same way round.
    final symptoms = [
      if (r != null)
        for (final s in parseSymptoms(r.symptoms))
          if (s < cycleSymptoms.length) s,
    ]..sort();
    final note = r?.note;

    final rows = <(String, Widget)>[
      if (r != null && r.flow > 0) ('Месячные', _text(cycleFlows[r.flow], p)),
      if (r?.sex case final sex? when sex < cycleSex.length)
        (
          'Секс',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (CycleHeart.shows(sex)) ...[
                CycleHeart(sex: sex, size: 14),
                const SizedBox(width: 6),
              ],
              _text(cycleSex[sex], p),
            ],
          ),
        ),
      if (r?.mood case final m? when m < cycleMoods.length)
        (
          'Настроение',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: cycleMoodColors[m],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              _text(cycleMoods[m], p),
            ],
          ),
        ),
      if (symptoms.isNotEmpty)
        (
          'Симптомы',
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in symptoms)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: p.chip,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    cycleSymptoms[s],
                    style: TextStyle(fontSize: 12, color: p.textPrimary),
                  ),
                ),
            ],
          ),
        ),
      if (r?.discharge case final d? when d < cycleDischarges.length)
        ('Выделения', _text(cycleDischarges[d], p)),
      if (note != null && note.isNotEmpty) ('Заметка', _text(note, p)),
    ];

    if (rows.isEmpty) {
      return Text(
        'Пока ничего не отмечено',
        style: TextStyle(fontSize: 14, color: p.textSecondary),
      );
    }
    return Column(
      children: [
        for (final (i, (label, value)) in rows.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 13, color: p.textSecondary),
                  ),
                ),
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: value),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Widget _text(String text, AppPalette p) =>
      Text(text, style: TextStyle(fontSize: 14, color: p.textPrimary));
}

/// The calendar's tap on a day: what was marked on it, and the way to change
/// it. A day that has not come shows only where it falls in the cycle.
Future<void> showCycleDayInfoSheet(
  BuildContext context,
  DateTime day, {
  required CycleModel? model,
  required DateTime today,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => Consumer(
    builder: (context, ref, _) {
      final row = cycleDayRow(
        ref.watch(cycleDaysProvider).valueOrNull ?? const [],
        day,
      );
      final canMark = !day.isAfter(today);
      return AppSheet(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CycleDayInfo(day: day, model: model, row: row),
          ),
          if (canMark) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                showCycleDaySheet(
                  context,
                  ref,
                  day,
                  cycleDay: model?.cycleDay(day),
                );
              },
              child: Text(row == null ? 'Отметить' : 'Изменить'),
            ),
          ],
        ],
      );
    },
  ),
);
