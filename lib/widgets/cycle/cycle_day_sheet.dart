import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/cycle_marks.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/cycle/cycle_colors.dart';
import 'package:todo_app/widgets/cycle/cycle_heart.dart';
import 'package:todo_app/widgets/page_header.dart' show RoundIconButton;

/// "Отметить день" (`CycleDay.dc.html`): everything a woman can note about one
/// day of her cycle, saved together with the check in the header.
///
/// [cycleDay] is only for the subtitle — the day's number in the running cycle,
/// or null when the forecast does not reach it.
///
/// [only] shows one group of choices instead of all of them — the "Быстро
/// отметить" buttons. It is the same sheet and the same controls; what is not
/// shown is saved as it was.
Future<void> showCycleDaySheet(
  BuildContext context,
  WidgetRef ref,
  DateTime day, {
  int? cycleDay,
  CycleSection? only,
}) async {
  final dao = ref.read(cycleDaoProvider);
  final existing = await dao.getDay(day);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _CycleDaySheet(
      day: day,
      cycleDay: cycleDay,
      existing: existing,
      only: only,
      onSave: (draft) async {
        await dao.saveDay(
          day,
          flow: draft.flow,
          mood: draft.mood,
          symptoms: draft.symptoms,
          discharge: draft.discharge,
          sex: draft.sex,
          pill: draft.pill,
          note: draft.note,
        );
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      },
    ),
  );
}

/// A group of choices in the sheet.
enum CycleSection { flow, sex, mood, symptoms, discharge, note }

/// What the sheet edits, before it is saved.
class _Draft {
  _Draft(CycleDay? day)
    : flow = day?.flow ?? 0,
      mood = day?.mood,
      symptoms = parseSymptoms(day?.symptoms ?? ''),
      discharge = day?.discharge,
      sex = day?.sex,
      pill = day?.pill ?? false,
      note = day?.note ?? '';

  int flow;
  int? mood;
  Set<int> symptoms;
  int? discharge;
  int? sex;
  bool pill;
  String note;
}

class _CycleDaySheet extends StatefulWidget {
  const _CycleDaySheet({
    required this.day,
    required this.cycleDay,
    required this.existing,
    required this.only,
    required this.onSave,
  });

  final DateTime day;
  final int? cycleDay;
  final CycleDay? existing;
  final CycleSection? only;
  final Future<void> Function(_Draft draft) onSave;

  @override
  State<_CycleDaySheet> createState() => _CycleDaySheetState();
}

// Selected tones of the design that are not phase colours: the flow's deep rose
// and the sex tile's deep heart. White on either clears 4.5:1.
const _flowOn = Color(0xFF924C68);
const _sexOn = Color(0xFFA8405F);
const _saveFill = Color(0xFFF3DDE6);
const _saveRing = Color(0xFFCF93AB);

class _CycleDaySheetState extends State<_CycleDaySheet> {
  late final _draft = _Draft(widget.existing);
  late final _note = TextEditingController(text: _draft.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final d = _draft;
    bool show(CycleSection section) =>
        widget.only == null || widget.only == section;

    return AppSheet(
      children: [
        _Header(
          day: widget.day,
          cycleDay: widget.cycleDay,
          onSave: () {
            d.note = _note.text;
            widget.onSave(d);
          },
        ),
        if (show(CycleSection.flow))
          _Card(
            title: 'Месячные',
            child: _Grid(
              columns: 5,
              children: [
                for (final (i, label) in cycleFlows.indexed)
                  _Tile(
                    selected: d.flow == i,
                    selectedFill: i == 0 ? p.textPrimary : _flowOn,
                    selectedInk: i == 0 ? p.background : Colors.white,
                    height: 64,
                    onTap: () => setState(() => d.flow = i),
                    builder: (ink, selected) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 14,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // "Нет" is one empty drop; the rest are as many full
                              // ones as the flow is heavy.
                              for (var k = 0; k < (i == 0 ? 1 : i); k++)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 0.5,
                                  ),
                                  child: CustomPaint(
                                    size: const Size(9, 12),
                                    painter: _DropPainter(
                                      filled: i != 0,
                                      color: selected
                                          ? Colors.white
                                          : (i == 0
                                                ? p.iconMuted
                                                : const Color(0xFFCF93AB)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (show(CycleSection.sex))
          _Card(
            title: 'Секс',
            leading: const CustomPaint(
              size: Size(16, 16),
              painter: CycleHeartPainter(fill: heartColor),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.lock, size: 12, color: p.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'только ты',
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
              ],
            ),
            child: _Grid(
              columns: 3,
              children: [
                for (final (i, label) in cycleSex.indexed)
                  _Tile(
                    selected: d.sex == i,
                    selectedFill: i == 0 ? p.textPrimary : _sexOn,
                    selectedInk: i == 0 ? p.background : Colors.white,
                    height: 64,
                    onTap: () => setState(() => d.sex = d.sex == i ? null : i),
                    builder: (ink, selected) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(20, 20),
                          painter: CycleHeartPainter(
                            // "Не было" is an outline, the others solid.
                            fill: i == 0
                                ? null
                                : (selected ? Colors.white : heartColor),
                            stroke: i == 0
                                ? (selected ? p.background : p.textTertiary)
                                : (selected ? Colors.white : heartColor),
                            strokeWidth: 1.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (show(CycleSection.mood))
          _Card(
            title: 'Настроение',
            child: _Grid(
              columns: 3,
              children: [
                for (final (i, label) in cycleMoods.indexed)
                  _Tile(
                    selected: d.mood == i,
                    // The mood tile is not filled when chosen — it is ringed.
                    ringed: true,
                    height: 44,
                    onTap: () =>
                        setState(() => d.mood = d.mood == i ? null : i),
                    builder: (ink, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: cycleMoodColors[i],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (show(CycleSection.symptoms))
          _Card(
            title: 'Симптомы',
            hint: 'можно несколько',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, label) in cycleSymptoms.indexed)
                  _Chip(
                    label: label,
                    selected: d.symptoms.contains(i),
                    onTap: () => setState(
                      () => d.symptoms.contains(i)
                          ? d.symptoms.remove(i)
                          : d.symptoms.add(i),
                    ),
                  ),
              ],
            ),
          ),
        if (show(CycleSection.discharge))
          _Card(
            title: 'Выделения',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, label) in cycleDischarges.indexed)
                  _Chip(
                    label: label,
                    selected: d.discharge == i,
                    onTap: () => setState(
                      () => d.discharge = d.discharge == i ? null : i,
                    ),
                  ),
              ],
            ),
          ),
        if (show(CycleSection.note))
          _Card(
            title: 'Заметка',
            child: TextField(
              controller: _note,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: p.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Как ты себя чувствуешь?',
                hintStyle: TextStyle(color: p.textTertiary),
                filled: true,
                fillColor: p.surface,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// × · date and the day of the cycle · the rose check.
class _Header extends StatelessWidget {
  const _Header({
    required this.day,
    required this.cycleDay,
    required this.onSave,
  });

  final DateTime day;
  final int? cycleDay;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: RoundIconButton(
                icon: LucideIcons.x,
                tooltip: 'Закрыть',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Column(
            children: [
              Text(
                DateFormat.MMMMd('ru_RU').format(day),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              if (cycleDay != null)
                Text(
                  'День цикла $cycleDay',
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: 'Сохранить',
                child: Material(
                  color: _saveFill,
                  shape: const CircleBorder(
                    side: BorderSide(color: _saveRing, width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onSave,
                    child: const SizedBox.square(
                      dimension: 44,
                      child: Icon(LucideIcons.check, size: 18, color: _flowOn),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A grey card of the sheet: a small upper-case title, then its controls.
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.child,
    this.hint,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String? hint;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.04,
                      color: p.textSecondary,
                    ),
                  ),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// [columns] equal columns, 6px apart.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 6 * (columns - 1)) / columns;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in children) SizedBox(width: width, child: c),
          ],
        );
      },
    );
  }
}

/// A square-ish choice: white with a hairline when off. On, it is [selectedFill]
/// with [selectedInk] on it — or, when [ringed], keeps its look and gets a
/// 2px ring in the text colour (the moods, whose dot has to stay readable).
class _Tile extends StatelessWidget {
  const _Tile({
    required this.selected,
    required this.height,
    required this.onTap,
    required this.builder,
    this.selectedFill,
    this.selectedInk,
    this.ringed = false,
  });

  final bool selected;
  final bool ringed;
  final double height;
  final Color? selectedFill;
  final Color? selectedInk;
  final VoidCallback onTap;

  /// Draws the content in the ink it is given.
  final Widget Function(Color ink, bool selected) builder;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final filled = selected && !ringed;
    final ink = filled ? (selectedInk ?? p.background) : p.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: filled ? (selectedFill ?? p.textPrimary) : p.surface,
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(
                    color: selected ? p.textPrimary : p.borderStrong,
                    width: selected ? 2 : 1,
                  ),
          ),
          child: builder(ink, filled),
        ),
      ),
    );
  }
}

/// A mood tile's look — white, rounded 14, ringed when chosen — at the width of
/// its text, for the lists that wrap (the symptoms).
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
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? p.textPrimary : p.borderStrong,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: p.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A drop of the flow scale — the design's 10x13 path, outlined or filled.
class _DropPainter extends CustomPainter {
  const _DropPainter({required this.filled, required this.color});

  final bool filled;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 10, size.height / 13);
    final path = Path()
      ..moveTo(5, .8)
      ..cubicTo(7, 3.6, 9, 5.8, 9, 8.2)
      ..arcToPoint(const Offset(1, 8.2), radius: const Radius.circular(4))
      ..cubicTo(1, 5.8, 3, 3.6, 5, .8)
      ..close();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
    canvas.drawPath(path, paint);
    // The design strokes a filled drop too, so its edge matches the outline's.
    if (filled) {
      canvas.drawPath(path, paint..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(_DropPainter old) =>
      old.filled != filled || old.color != color;
}
