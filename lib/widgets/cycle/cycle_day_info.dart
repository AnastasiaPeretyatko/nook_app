import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/cycle.dart';
import 'package:todo_app/utils/cycle_marks.dart';
import 'package:todo_app/utils/surfaces.dart' show pageSurface;
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/cycle/cycle_colors.dart';
import 'package:todo_app/widgets/cycle/cycle_day_sheet.dart';
import 'package:todo_app/widgets/cycle/cycle_heart.dart';

/// The row of [day] in [days], or null when nothing was ever saved for it.
CycleDay? cycleDayRow(Iterable<CycleDay> days, DateTime day) {
  for (final d in days) {
    if (d.date == day) return d;
  }
  return null;
}

/// Whether anything was marked on [row] that [CycleDayMarks] would show: a flow,
/// sex (also "не было"), a mood, a symptom, the discharge or a note. The calendar
/// dots such a day, so the user can see where there is something to read.
bool cycleDayHasMarks(CycleDay row) =>
    row.flow > 0 ||
    row.sex != null ||
    row.mood != null ||
    parseSymptoms(row.symptoms).isNotEmpty ||
    row.discharge != null ||
    (row.note?.trim().isNotEmpty ?? false);

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

    Widget chips(List<Widget> items) =>
        Wrap(spacing: 6, runSpacing: 6, children: items);

    // Each row has its own tile — an icon on a pale fill with its own dark ink,
    // the same on both themes — and, for the flow, how strong it was.
    final rows = <_MarkRow>[
      if (r != null && r.flow > 0 && r.flow < cycleFlows.length)
        _MarkRow(
          'Месячные',
          LucideIcons.droplet,
          const Color(0xFFF3DDE6),
          const Color(0xFF924C68),
          chips([CycleChip(label: cycleFlows[r.flow], dot: cycleFlowDot)]),
          meter: r.flow,
        ),
      if (r?.sex case final sex? when sex < cycleSex.length)
        _MarkRow(
          'Секс',
          LucideIcons.heart,
          const Color(0xFFF6DCE4),
          heartColor,
          chips([
            CycleChip(
              label: cycleSex[sex],
              leading: CycleHeart.shows(sex)
                  ? CycleHeart(sex: sex, size: 12)
                  : null,
            ),
          ]),
        ),
      if (r?.mood case final m? when m < cycleMoods.length)
        _MarkRow(
          'Настроение',
          LucideIcons.face_slightly_smiling,
          const Color(0xFFD9F0E6),
          const Color(0xFF2B6E53),
          chips([CycleChip(label: cycleMoods[m], dot: cycleMoodColors[m])]),
        ),
      if (symptoms.isNotEmpty)
        _MarkRow(
          'Симптомы',
          LucideIcons.activity,
          const Color(0xFFE3DEF8),
          const Color(0xFF5D4DB0),
          chips([
            for (final s in symptoms)
              CycleChip(
                label: cycleSymptoms[s],
                dot: cycleSymptomColors[s % cycleSymptomColors.length],
              ),
          ]),
        ),
      if (r?.discharge case final d? when d < cycleDischarges.length)
        _MarkRow(
          'Выделения',
          LucideIcons.droplets,
          const Color(0xFFDCE7FB),
          const Color(0xFF3B66B5),
          chips([CycleChip(label: cycleDischarges[d], dot: cycleDischargeDot)]),
        ),
      if (note != null && note.isNotEmpty)
        _MarkRow(
          'Заметка',
          LucideIcons.notebook_pen,
          const Color(0xFFEEF1F5),
          const Color(0xFF4A5262),
          _text(note, p),
        ),
    ];

    if (rows.isEmpty) {
      return Text(
        'Пока ничего не отмечено',
        style: TextStyle(fontSize: 14, color: p.textSecondary),
      );
    }
    return Column(
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: p.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: row.fill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(row.icon, size: 17, color: row.ink),
                ),
                const SizedBox(width: 12),
                // The title above and the chips under it, across the whole
                // width: beside a fixed label column they would be squeezed into
                // a column of their own.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title,
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      row.value,
                      if (row.meter != null) ...[
                        const SizedBox(height: 8),
                        _FlowMeter(strength: row.meter!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static Widget _text(String text, AppPalette p) =>
      Text(text, style: TextStyle(fontSize: 14, color: p.textPrimary));
}

/// One labelled row of [CycleDayMarks].
class _MarkRow {
  const _MarkRow(
    this.title,
    this.icon,
    this.fill,
    this.ink,
    this.value, {
    this.meter,
  });

  final String title;
  final IconData icon;
  final Color fill;
  final Color ink;
  final Widget value;

  /// How strong the flow was, 1 to 4; null for every other row.
  final int? meter;
}

/// "Интенсивность 3 из 4": a dot for each step of the flow, filled up to this
/// one.
class _FlowMeter extends StatelessWidget {
  const _FlowMeter({required this.strength});

  final int strength;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final steps = cycleFlows.length - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < strength ? cycleFlowDot : const Color(0xFFEDD3DC),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Text(
          'Интенсивность $strength из $steps',
          style: TextStyle(fontSize: 12, color: p.textSecondary),
        ),
      ],
    );
  }
}

/// One thing marked on a day, as the design draws it (`CycleDayInfo.html`): a
/// 32px pill on the page's own tone with a dot of the item's colour — or a
/// [leading] widget, the heart of a day with sex — and its name.
class CycleChip extends StatelessWidget {
  const CycleChip({super.key, required this.label, this.dot, this.leading});

  final String label;
  final Color? dot;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.chip,
        borderRadius: BorderRadius.circular(16),
      ),
      // A Row and not `alignment:`, which would stretch the pill to the row.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 7)],
          if (leading == null && dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The calendar's second tap on a day (`CycleDayInfo.html`): its date and place
/// in the cycle between arrows to the day before and after, tags for the phase
/// and what was marked, the marks themselves, and the way to change or clear
/// them. A day that has not come shows only where it falls in the cycle.
///
/// [pageContext] is the screen under the sheet — the day sheet that "Изменить
/// день" opens must outlive this one. [onDayChanged] hears each day the arrows
/// move to, so the calendar behind the half-height sheet can follow.
Future<void> showCycleDayInfoSheet(
  BuildContext pageContext,
  DateTime day, {
  required CycleModel? model,
  required DateTime today,
  ValueChanged<DateTime>? onDayChanged,
}) => showModalBottomSheet<void>(
  context: pageContext,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _DayInfoSheet(
    pageContext: pageContext,
    day: day,
    model: model,
    today: today,
    onDayChanged: onDayChanged,
  ),
);

class _DayInfoSheet extends ConsumerStatefulWidget {
  const _DayInfoSheet({
    required this.pageContext,
    required this.day,
    required this.model,
    required this.today,
    required this.onDayChanged,
  });

  final BuildContext pageContext;
  final DateTime day;
  final CycleModel? model;
  final DateTime today;
  final ValueChanged<DateTime>? onDayChanged;

  @override
  ConsumerState<_DayInfoSheet> createState() => _DayInfoSheetState();
}

class _DayInfoSheetState extends ConsumerState<_DayInfoSheet> {
  late DateTime _day = widget.day;

  void _step(int by) {
    setState(() => _day = DateTime(_day.year, _day.month, _day.day + by));
    widget.onDayChanged?.call(_day);
  }

  /// "Среда, 7 октября".
  static String _title(DateTime d) {
    final text = DateFormat('EEEE, d MMMM', 'ru_RU').format(d);
    return text[0].toUpperCase() + text.substring(1);
  }

  Future<void> _clear() async {
    final confirmed = await showConfirmDialog(
      context,
      icon: DialogIcons.delete,
      title: 'Очистить отметки дня?',
      body:
          'Всё, что отмечено на ${DateFormat.MMMMd('ru_RU').format(_day)}, '
          'будет убрано.',
      action: 'Очистить',
    );
    if (confirmed) await ref.read(cycleDaoProvider).clearDay(_day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final model = widget.model;
    final row = cycleDayRow(
      ref.watch(cycleDaysProvider).valueOrNull ?? const [],
      _day,
    );
    final hasMarks = row != null && cycleDayHasMarks(row);
    final canMark = !_day.isAfter(widget.today);
    final cycleDay = model?.cycleDay(_day);
    final phase = model?.phaseOn(_day);

    // What the day is, in a few words: its phase and, if there was one, the sex.
    final tags = <(String, Color, Color)>[
      if (phase == CyclePhase.period)
        ('Месячные · день $cycleDay', _tagPeriodFill, _tagPeriodInk)
      else if (row != null && row.flow > 0)
        ('Месячные', _tagPeriodFill, _tagPeriodInk),
      if (phase == CyclePhase.fertile)
        ('Фертильный день', _tagFertileFill, _tagFertileInk),
      if (phase == CyclePhase.ovulation)
        ('Овуляция', _tagOvulationFill, _tagOvulationInk),
      if (CycleHeart.shows(row?.sex)) ('Близость', _tagSexFill, _tagSexInk),
    ];

    return Container(
      decoration: BoxDecoration(
        color: pageSurface(theme),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                child: Row(
                  children: [
                    _Step(
                      icon: LucideIcons.chevron_left,
                      tooltip: 'Предыдущий день',
                      onTap: () => _step(-1),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _title(_day),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: p.textPrimary,
                            ),
                          ),
                          if (cycleDay != null)
                            Text(
                              'День цикла $cycleDay из ${model!.length}',
                              style: TextStyle(
                                fontSize: 12,
                                color: p.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _Step(
                      icon: LucideIcons.chevron_right,
                      tooltip: 'Следующий день',
                      onTap: () => _step(1),
                    ),
                  ],
                ),
              ),
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (label, fill, ink) in tags)
                        Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          // A Row and not `alignment:`, which would stretch the
                          // pill across the whole line.
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: p.border),
                ),
                child: hasMarks
                    ? CycleDayMarks(row: row)
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Пока ничего не отмечено',
                          style: TextStyle(
                            fontSize: 14,
                            color: p.textSecondary,
                          ),
                        ),
                      ),
              ),
              if (canMark)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: p.textPrimary,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              showCycleDaySheet(
                                widget.pageContext,
                                ref,
                                _day,
                                cycleDay: cycleDay,
                              );
                            },
                            child: SizedBox(
                              height: 52,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.pencil,
                                    size: 17,
                                    color: p.background,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    hasMarks
                                        ? 'Изменить день'
                                        : 'Отметить день',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: p.background,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (hasMarks) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Очистить отметки этого дня',
                          child: Material(
                            color: p.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: p.borderStrong),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _clear,
                              child: SizedBox.square(
                                dimension: 52,
                                child: Icon(
                                  LucideIcons.trash_2,
                                  size: 19,
                                  color: p.danger,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 44px arrow to the day before or after.
class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 18, color: p.textPrimary),
    );
  }
}

// The tags' tones: a pale fill with its own dark ink, the same on both themes.
const _tagPeriodFill = Color(0xFFF3DDE6);
const _tagPeriodInk = Color(0xFF6E3550);
const _tagFertileFill = Color(0xFFDCE7FB);
const _tagFertileInk = Color(0xFF2C4F8F);
const _tagOvulationFill = Color(0xFFE3DEF8);
const _tagOvulationInk = Color(0xFF463A8C);
const _tagSexFill = Color(0xFFF6DCE4);
const _tagSexInk = Color(0xFF9A3A5C);
