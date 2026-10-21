import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/cycle_calendar_page.dart';
import 'package:todo_app/widgets/cycle/cycle_setup.dart';
import 'package:todo_app/pages/habits_page.dart' show todayCaption;
import 'package:todo_app/pages/settings_page.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/cycle.dart';
import 'package:todo_app/utils/cycle_marks.dart';
import 'package:todo_app/utils/cycle_stats.dart';
import 'package:todo_app/utils/last_done.dart' show pluralRu;
import 'package:todo_app/utils/week.dart';
import 'package:todo_app/widgets/app_bottom_nav_bar.dart';
import 'package:todo_app/widgets/cycle/cycle_colors.dart';
import 'package:todo_app/widgets/cycle/cycle_day_info.dart';
import 'package:todo_app/widgets/cycle/cycle_day_sheet.dart';
import 'package:todo_app/widgets/cycle/cycle_heart.dart';
import 'package:todo_app/widgets/habits/habits_week.dart' show DashedBox;
import 'package:todo_app/widgets/page_header.dart';
import 'package:todo_app/widgets/settings/about_section.dart'
    show pickCycleStart;

// Tones of the mock-up that are not phase colours: each pale fill with its own
// dark ink, the same on both themes.
const _ovulationFill = Color(0xFFE3DEF8);
const _ovulationInk = Color(0xFF463A8C);
const _periodFill = Color(0xFFF3DDE6);
const _periodInk = Color(0xFF6E3550);
const _fertileFill = Color(0xFFDCE7FB);
const _fertileInk = Color(0xFF2C4F8F);

/// The "Цикл" tab (`Cycle.dc.html`): this week, the ring of the cycle with the
/// button that marks today, when the next ovulation and period are due, the
/// fertile window, quick marks and the lengths in use.
///
/// The forecast is built from the settings — the start of the last period and
/// the two lengths. The week strip swipes to earlier and later weeks, and a tap
/// on a day picks it; the ring, the "Отметить" button, the quick marks and the
/// block of what was marked all follow the picked day. The marks are stored in
/// `cycle_days` and do **not** yet feed the forecast. The calendar is behind the
/// header's button ([CycleCalendarPage]).
class CyclePage extends ConsumerStatefulWidget {
  const CyclePage({super.key});

  @override
  ConsumerState<CyclePage> createState() => _CyclePageState();
}

class _CyclePageState extends ConsumerState<CyclePage> {
  /// The day the ring, the button and the quick marks are about. Null is "today"
  /// — kept as null rather than as a date so the page still follows the clock
  /// past midnight when nothing was chosen.
  DateTime? _selected;

  /// "Пропустить, заполню позже" on the setup screen. Per launch, on purpose:
  /// without a start date there is no forecast, so it asks again next time.
  bool _skippedSetup = false;

  /// The strip's page 0 is the week of today, so any other week is a plain
  /// offset from it, in either direction, with no limit that has to be chosen.
  static const _origin = 5000;
  final _weeks = PageController(initialPage: _origin);

  @override
  void dispose() {
    _weeks.dispose();
    super.dispose();
  }

  /// A swipe to another week moves the pick along with it, to the same weekday —
  /// so the ring and the block below follow what the strip shows.
  void _onWeekChanged(int page, DateTime today, int weekStart) {
    final current = _selected ?? today;
    final shown = startOfWeek(today, weekStart);
    final first = DateTime(
      shown.year,
      shown.month,
      shown.day + (page - _origin) * 7,
    );
    final offset = CycleModel.daysBetween(
      startOfWeek(current, weekStart),
      current,
    );
    setState(
      () => _selected = DateTime(first.year, first.month, first.day + offset),
    );
  }

  void _backToToday() {
    setState(() => _selected = null);
    _weeks.animateToPage(
      _origin,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final about = ref.watch(aboutSettingsProvider);
    if (about.lastStart == null && !_skippedSetup) {
      return CycleSetup(onSkip: () => setState(() => _skippedSetup = true));
    }
    final model = about.model;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = _selected ?? today;
    // A day that has not come cannot have happened yet: it can be looked at on
    // the ring, not marked.
    final canMark = !day.isAfter(today);
    final days = ref.watch(cycleDaysProvider).valueOrNull ?? const <CycleDay>[];
    final stats = cycleStats(days, lastStart: about.lastStart);
    final weekStart = ref.watch(weekStartProvider);

    void mark([CycleSection? only]) {
      if (!canMark) return;
      showCycleDaySheet(
        context,
        ref,
        day,
        cycleDay: model?.cycleDay(day),
        only: only,
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          // Room for the bar the body extends under — its own height and the
          // system inset below it — and a little air above it.
          padding: EdgeInsets.only(
            bottom:
                AppBottomNavBar.barHeight +
                MediaQuery.paddingOf(context).bottom +
                24,
          ),
          children: [
            PageHeader(
              caption: todayCaption(now),
              title: 'Цикл',
              actions: [
                RoundIconButton(
                  icon: LucideIcons.calendar,
                  tooltip: 'Календарь цикла',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CycleCalendarPage(),
                    ),
                  ),
                ),
                RoundIconButton(
                  icon: LucideIcons.user_round,
                  tooltip: 'Профиль и настройки',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
            if (model != null)
              _WeekStrip(
                controller: _weeks,
                origin: _origin,
                today: today,
                selected: day,
                onSelect: (d) => setState(() => _selected = d),
                onWeekChanged: (page) => _onWeekChanged(page, today, weekStart),
              ),
            _RingCard(
              model: model,
              day: day,
              today: today,
              row: cycleDayRow(days, day),
              enabled: canMark,
              onQuick: mark,
              onToday: _backToToday,
            ),
            if (model != null) _Stats(about: about, stats: stats),
            if (model != null) ...[
              const SizedBox(height: 12),
              _FertileWindow(model: model, today: today),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: TextButton.icon(
                onPressed: () => pickCycleStart(
                  context,
                  ref.read(aboutSettingsProvider.notifier),
                  about.lastStart,
                ),
                icon: const Icon(LucideIcons.droplet, size: 18),
                label: const Text('Месячные начались'),
              ),
            ),
            const _Disclaimer(),
          ],
        ),
      ),
    );
  }
}

/// The one white card under the week: the ring and its legend, when the next
/// ovulation and period are due, and below a divider the quick marks of the
/// picked day with what was marked on it as chips. The full sheet (with the
/// discharge and the note) is not on this tab — it is "Отметить день" in the
/// calendar.
class _RingCard extends StatelessWidget {
  const _RingCard({
    required this.model,
    required this.day,
    required this.today,
    required this.row,
    required this.enabled,
    required this.onQuick,
    required this.onToday,
  });

  final CycleModel? model;

  /// The day the ring shows — the one chosen in the week, today by default.
  final DateTime day;
  final DateTime today;

  /// What was marked on [day], if anything.
  final CycleDay? row;
  final bool enabled;
  final ValueChanged<CycleSection> onQuick;

  /// Back to today, offered while another day is picked.
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final model = this.model;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (model == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Укажите, когда начались последние месячные, — и здесь '
                'появится кольцо цикла и прогноз.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: p.textSecondary,
                ),
              ),
            )
          else ...[
            Center(
              child: _Ring(model: model, day: day),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final (color, label) in [
                  (periodColor, 'Месячные'),
                  (fertileColor, 'Фертильные'),
                  (ovulationColor, 'Овуляция'),
                  (otherDayColor(p), 'Другие дни'),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _Forecast(model: model, today: today),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, thickness: 1, color: p.divider),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'БЫСТРО ОТМЕТИТЬ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.04,
                    color: p.textSecondary,
                  ),
                ),
              ),
              if (day != today)
                TextButton(onPressed: onToday, child: const Text('Сегодня')),
            ],
          ),
          const SizedBox(height: 12),
          _QuickMarks(row: row, enabled: enabled, onTap: onQuick),
          _MarkChips(row: row),
        ],
      ),
    );
  }
}

/// Seven days at a time, swiped to earlier and later weeks; a tap picks the day
/// the ring and the buttons are about. The picked one is a dark pill. Under each
/// number is the day's heart if sex was marked — solid with protection, an
/// outline without — and nothing otherwise: the phase is the ring's and the
/// calendar's job.
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({
    required this.controller,
    required this.origin,
    required this.today,
    required this.selected,
    required this.onSelect,
    required this.onWeekChanged,
  });

  final PageController controller;

  /// The page of the week that holds today.
  final int origin;
  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onWeekChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thisWeek = startOfWeek(today, ref.watch(weekStartProvider));
    final sexByDay = <DateTime, int?>{
      for (final d in ref.watch(cycleDaysProvider).valueOrNull ?? const [])
        d.date: d.sex,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        height: 68,
        child: PageView.builder(
          controller: controller,
          onPageChanged: onWeekChanged,
          itemBuilder: (context, page) {
            final first = DateTime(
              thisWeek.year,
              thisWeek.month,
              thisWeek.day + (page - origin) * 7,
            );
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final day = DateTime(
                            first.year,
                            first.month,
                            first.day + i,
                          );
                          return _WeekDay(
                            day: day,
                            isToday: day == today,
                            isSelected: day == selected,
                            isFuture: day.isAfter(today),
                            sex: sexByDay[day],
                            onTap: () => onSelect(day),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isFuture,
    required this.sex,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool isFuture;
  final int? sex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final fg = isSelected ? p.background : p.textPrimary;
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CustomPaint(
          // Today, when it is not the picked day, keeps a dashed outline so it
          // can still be found.
          foregroundPainter: isToday && !isSelected
              ? DashedBox(color: p.outline, radius: 14)
              : null,
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: isSelected ? p.textPrimary : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat.E('ru_RU').format(day),
                  style: TextStyle(
                    fontSize: 11,
                    color: fg.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected || isToday
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: isFuture && !isSelected ? p.textTertiary : fg,
                  ),
                ),
                const SizedBox(height: 6),
                // The slot is kept when empty, so a heart does not move the number.
                CycleHeart(sex: sex),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The ring of the cycle (`Cycle.dc.html`): one dot per day on a circle, day 1
/// at the top and clockwise. Phase days are bigger, ovulation biggest; the days
/// already lived are paler. Today is a white dot with a blue rim and its number
/// in a blue badge outside the ring, in line with the dot; 1, 7, 14 and 21 are
/// numbered on the inside.
class _Ring extends StatelessWidget {
  const _Ring({required this.model, required this.day});

  final CycleModel model;
  final DateTime day;

  static const _size = 272.0;
  static const _radius = 118.0;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final length = model.length;
    final todayDay = model.cycleDay(day);

    Offset at(int day, double r) {
      final a = (day - 1) / length * 2 * math.pi;
      return Offset(_size / 2 + math.sin(a) * r, _size / 2 - math.cos(a) * r);
    }

    Widget dot(int day) {
      final phase = model.phaseOfCycleDay(day);
      final d = switch (phase) {
        CyclePhase.ovulation => 14.0,
        CyclePhase.other => 8.0,
        _ => 11.0,
      };
      final c = at(day, _radius);
      final past = todayDay != null && day < todayDay;
      final color = phase == CyclePhase.other
          ? otherDayColor(p)
          : cyclePhaseColor(phase, p);
      return Positioned(
        left: c.dx - d / 2,
        top: c.dy - d / 2,
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: past && phase != CyclePhase.other
                ? color.withValues(alpha: 0.55)
                : color,
          ),
        ),
      );
    }

    final phase = todayDay == null ? null : model.phaseOfCycleDay(todayDay);
    final (phaseLabel, chipFill, chipInk) = switch (phase) {
      CyclePhase.period => ('Месячные', _periodFill, _periodInk),
      CyclePhase.fertile => ('Фертильные дни', _fertileFill, _fertileInk),
      CyclePhase.ovulation => ('Овуляция', _ovulationFill, _ovulationInk),
      _ => ('', Colors.transparent, Colors.transparent),
    };

    final ring = todayDay == null ? null : at(todayDay, _radius);
    final outward = todayDay == null
        ? null
        : (at(todayDay, 1) - const Offset(_size / 2, _size / 2));
    return Semantics(
      label: todayDay == null
          ? 'Кольцо цикла'
          : 'День $todayDay из $length. $phaseLabel',
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          // Today's number sits beside its dot, which on the right and the lower
          // edge is outside the 272px square; the default would cut it off.
          clipBehavior: Clip.none,
          children: [
            for (var d = 1; d <= length; d++) dot(d),
            for (final n in const [1, 7, 14, 21])
              if (n <= length)
                Positioned(
                  left: at(n, _radius - 22).dx - 12,
                  top: at(n, _radius - 22).dy - 8,
                  width: 24,
                  child: Text(
                    '$n',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: p.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            if (ring != null && outward != null) ...[
              Positioned(
                left: ring.dx - 12,
                top: ring.dy - 12,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.surface,
                    border: Border.all(color: todayBlue, width: 3),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomSingleChildLayout(
                  delegate: _OutwardBadge(dot: ring, outward: outward),
                  child: Container(
                    height: 22,
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: todayBlue,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    // Not `alignment:` — that makes a Container take all the room
                    // it is offered, and here that is the whole ring.
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$todayDay',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'День цикла',
                    style: TextStyle(fontSize: 13, color: p.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${todayDay ?? '—'}',
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -2.5,
                          height: 1,
                          color: p.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/ $length',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  if (phaseLabel.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: chipFill,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      // A Row and not `alignment:`, which would stretch the pill
                      // across the whole ring.
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            phaseLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: chipInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Puts today's number outside the ring, on the line from the centre through
/// today's [dot], clear of the dot's rim. How far out depends on the pill's own
/// size and on the direction: a wide pill has to stand further off at three
/// o'clock, a short one only its height away at twelve — so the number never
/// lies over the neighbouring dots.
class _OutwardBadge extends SingleChildLayoutDelegate {
  const _OutwardBadge({required this.dot, required this.outward});

  /// The centre of today's dot, and the unit-ish direction away from the ring's
  /// centre through it.
  final Offset dot;
  final Offset outward;

  /// The dot's marker (12 radius, with its rim) and a little air.
  static const _clear = 14.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final direction = outward / outward.distance;
    final reach =
        direction.dx.abs() * childSize.width / 2 +
        direction.dy.abs() * childSize.height / 2;
    final centre = dot + direction * (_clear + reach);
    return centre - Offset(childSize.width / 2, childSize.height / 2);
  }

  @override
  bool shouldRelayout(_OutwardBadge old) =>
      old.dot != dot || old.outward != outward;
}

/// The next ovulation and the next period side by side, on the card itself — no
/// plate of their own, a hairline between them. Each is a coloured dot and its
/// date, the days to it in large type, and a line of detail.
class _Forecast extends StatelessWidget {
  const _Forecast({required this.model, required this.today});

  final CycleModel model;
  final DateTime today;

  /// "18 окт": the short month, without the full stop the locale puts after it.
  static String _short(DateTime d) =>
      '${d.day} ${DateFormat.MMM('ru_RU').format(d).replaceAll('.', '')}';

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final ovulation = model.nextOvulation(today);
    final period = model.nextPeriodStart(today);
    final window = model.fertileWindow(today);
    // "13–19 окт", or both months when the window straddles two.
    final range = window.start.month == window.end.month
        ? '${window.start.day}–${_short(window.end)}'
        : '${_short(window.start)} – ${_short(window.end)}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ForecastCard(
              dot: ovulationColor,
              title: 'Овуляция · ${_short(ovulation)}',
              when: _inDays(today, ovulation),
              detail: 'Фертильное окно $range',
            ),
          ),
          VerticalDivider(width: 21, thickness: 1, color: p.divider),
          Expanded(
            child: _ForecastCard(
              dot: periodColor,
              title: 'Месячные · ≈ ${_short(period)}',
              when: _inDays(today, period),
              detail:
                  'Ожидается ${model.periodLength} '
                  '${pluralRu(model.periodLength, 'день', 'дня', 'дней')}',
            ),
          ),
        ],
      ),
    );
  }

  static String _inDays(DateTime today, DateTime day) {
    final n = CycleModel.daysBetween(today, day);
    if (n == 0) return 'сегодня';
    return 'через $n ${pluralRu(n, 'день', 'дня', 'дней')}';
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({
    required this.dot,
    required this.title,
    required this.when,
    required this.detail,
  });

  final Color dot;
  final String title;
  final String when;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: p.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          when,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: p.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          style: TextStyle(fontSize: 12, height: 1.3, color: p.textSecondary),
        ),
      ],
    );
  }
}

class _IconDisc extends StatelessWidget {
  const _IconDisc({required this.icon, required this.fill, required this.ink});

  final IconData icon;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
    child: Icon(icon, size: 18, color: ink),
  );
}

/// A 30px pill: "через 2 дня", "Высокая".
class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.fill,
    required this.ink,
    required this.fontSize,
  });

  final String text;
  final Color fill;
  final Color ink;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(15),
    ),
    // A Row and not `alignment:`, which would stretch the pill to the card.
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ],
    ),
  );
}

/// "Фертильное окно · 13–19 октября" and, while it is on, "Высокая".
class _FertileWindow extends StatelessWidget {
  const _FertileWindow({required this.model, required this.today});

  final CycleModel model;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final w = model.fertileWindow(today);
    final inside =
        CycleModel.daysBetween(w.start, today) >= 0 &&
        CycleModel.daysBetween(today, w.end) >= 0;
    // "октября", not "октябрь": the month as it reads after a day number.
    String month(DateTime d) =>
        DateFormat.MMMMd('ru_RU').format(d).split(' ').last;
    final range = w.start.month == w.end.month
        ? '${w.start.day}–${w.end.day} ${month(w.end)}'
        : '${w.start.day} ${month(w.start)} – ${w.end.day} ${month(w.end)}';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          const _IconDisc(
            icon: LucideIcons.sprout,
            fill: _fertileFill,
            ink: _fertileInk,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Фертильное окно',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  inside ? '$range · вероятность высокая' : range,
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
              ],
            ),
          ),
          if (inside)
            const _Badge(
              text: 'Высокая',
              fill: todayBlue,
              ink: Colors.white,
              fontSize: 13,
            ),
        ],
      ),
    );
  }
}

/// Four round buttons, each opening the sheet with just that group of choices —
/// the same ones as in "Отметить". A button whose group is already marked on the
/// day wears a small black disc with a white tick in its top right corner. (The
/// note and the discharge are in the full sheet only; "Лекарства" of the mock-up
/// is not kept at all.)
class _QuickMarks extends StatelessWidget {
  const _QuickMarks({
    required this.row,
    required this.enabled,
    required this.onTap,
  });

  final CycleDay? row;
  final bool enabled;
  final ValueChanged<CycleSection> onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final r = row;
    final items = [
      (
        'Месячные',
        CycleSection.flow,
        LucideIcons.droplet,
        const Color(0xFFF3DDE6),
        const Color(0xFF924C68),
        r != null && r.flow > 0,
      ),
      (
        'Секс',
        CycleSection.sex,
        LucideIcons.heart,
        const Color(0xFFF9DDE6),
        heartColor,
        r?.sex != null,
      ),
      (
        'Настроение',
        CycleSection.mood,
        LucideIcons.face_slightly_smiling,
        const Color(0xFFD9F0E6),
        const Color(0xFF2B6E53),
        r?.mood != null,
      ),
      (
        'Симптомы',
        CycleSection.symptoms,
        LucideIcons.activity,
        const Color(0xFFE3DEF8),
        const Color(0xFF5D4DB0),
        r != null && parseSymptoms(r.symptoms).isNotEmpty,
      ),
    ];
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Row(
        children: [
          for (final (label, section, icon, fill, ink, marked) in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? () => onTap(section) : null,
                child: Column(
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: fill,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 22, color: ink),
                          ),
                          if (marked)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: p.textPrimary,
                                  shape: BoxShape.circle,
                                  // The card's own colour, so the disc reads as
                                  // its own object over the button's edge.
                                  border: Border.all(
                                    color: p.surface,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  LucideIcons.check,
                                  size: 11,
                                  color: p.background,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: p.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What was marked on the day, as chips under the buttons: the flow, sex, mood,
/// each symptom, the discharge and the note. Nothing at all while nothing is.
class _MarkChips extends StatelessWidget {
  const _MarkChips({required this.row});

  final CycleDay? row;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final r = row;
    if (r == null) return const SizedBox.shrink();

    Widget chip(String text, {Widget? leading}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: p.chip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 6)],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: p.textPrimary),
            ),
          ),
        ],
      ),
    );

    final symptoms = [
      for (final s in parseSymptoms(r.symptoms))
        if (s < cycleSymptoms.length) s,
    ]..sort();
    final note = r.note?.trim() ?? '';
    final chips = <Widget>[
      if (r.flow > 0 && r.flow < cycleFlows.length)
        chip('Месячные · ${cycleFlows[r.flow].toLowerCase()}'),
      if (r.sex case final sex? when sex < cycleSex.length)
        chip(
          sex == 0 ? 'Секса не было' : 'Секс · ${cycleSex[sex].toLowerCase()}',
          leading: CycleHeart.shows(sex)
              ? CycleHeart(sex: sex, size: 12)
              : null,
        ),
      if (r.mood case final m? when m < cycleMoods.length)
        chip(
          cycleMoods[m],
          leading: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: cycleMoodColors[m],
              shape: BoxShape.circle,
            ),
          ),
        ),
      for (final s in symptoms) chip(cycleSymptoms[s]),
      if (r.discharge case final d? when d < cycleDischarges.length)
        chip('Выделения · ${cycleDischarges[d].toLowerCase()}'),
      if (note.isNotEmpty) chip(note, leading: _noteIcon(p)),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  static Widget _noteIcon(AppPalette p) =>
      Icon(LucideIcons.notebook_pen, size: 12, color: p.textSecondary);
}

/// "27 Средний цикл", "5 Дней месячных", "±1 д. Разброс циклов" — worked out
/// from the marks (`cycleStats`). Until there are enough, the lengths are the
/// ones from the settings and the spread is a dash.
class _Stats extends StatelessWidget {
  const _Stats({required this.about, required this.stats});

  final AboutSettings about;
  final CycleStats stats;

  @override
  Widget build(BuildContext context) {
    final spread = stats.spread;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              value: '${stats.cycleLength ?? about.cycleLength}',
              label: 'Средний цикл',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Stat(
              value: '${stats.periodLength ?? about.periodLength}',
              label: 'Дней месячных',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Stat(
              value: spread == null ? '—' : '±$spread д.',
              label: 'Разброс циклов',
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: p.textSecondary)),
        ],
      ),
    );
  }
}

/// A grey box with a lock: the data is the user's alone, and a forecast is not
/// contraception.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.chip,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.lock, size: 16, color: p.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Данные цикла видны только тебе и никогда не попадают в группы. '
              'Прогнозы — это примерная оценка, а не способ предохранения.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: p.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
