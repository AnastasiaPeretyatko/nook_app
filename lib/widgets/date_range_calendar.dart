import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/widgets/cycle/cycle_colors.dart';

enum DateSelectionMode { range, single }

/// A reusable, controlled single-month calendar for selecting either one date
/// or a range with optional holes. The parent owns [selectedDates], so it can
/// reset or confirm the selection without page-specific behavior leaking into
/// this widget.
class DateRangeCalendar extends StatefulWidget {
  const DateRangeCalendar({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.initialMonth,
    required this.selectedDates,
    required this.onSelectionChanged,
    this.weekStart = DateTime.monday,
    this.selectionMode = DateSelectionMode.range,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime initialMonth;
  final Set<DateTime> selectedDates;
  final ValueChanged<Set<DateTime>> onSelectionChanged;
  final int weekStart;
  final DateSelectionMode selectionMode;

  @override
  State<DateRangeCalendar> createState() => _DateRangeCalendarState();
}

class _DateRangeCalendarState extends State<DateRangeCalendar> {
  late final DateTime _firstMonth;
  late final DateTime _lastMonth;
  late final PageController _months;
  late int _page;
  DateTime? _anchor;

  @override
  void initState() {
    super.initState();
    _firstMonth = _month(widget.firstDate);
    _lastMonth = _month(widget.lastDate);
    final initial = _month(widget.initialMonth).isBefore(_firstMonth)
        ? _firstMonth
        : _month(widget.initialMonth).isAfter(_lastMonth)
        ? _lastMonth
        : _month(widget.initialMonth);
    _page = _monthDistance(_firstMonth, initial);
    _months = PageController(initialPage: _page);
    _syncAnchor();
  }

  @override
  void didUpdateWidget(DateRangeCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionMode != widget.selectionMode ||
        !_sameDays(oldWidget.selectedDates, widget.selectedDates)) {
      _syncAnchor();
    }
  }

  @override
  void dispose() {
    _months.dispose();
    super.dispose();
  }

  void _syncAnchor() {
    if (widget.selectionMode == DateSelectionMode.single) {
      _anchor = null;
      return;
    }
    final selected = _normalized(widget.selectedDates);
    _anchor = selected.length == 1 ? selected.single : null;
  }

  void _select(DateTime raw) {
    final day = _day(raw);
    if (widget.selectionMode == DateSelectionMode.single) {
      widget.onSelectionChanged(Set.unmodifiable({day}));
      return;
    }

    final next = _normalized(widget.selectedDates);
    if (next.remove(day)) {
      if (_anchor == day) _anchor = null;
      widget.onSelectionChanged(Set.unmodifiable(next));
      return;
    }

    final anchor = _anchor;
    if (anchor == null) {
      next.add(day);
      if (next.length == 1) _anchor = day;
    } else {
      final start = anchor.isBefore(day) ? anchor : day;
      final end = anchor.isAfter(day) ? anchor : day;
      for (
        var current = start;
        !current.isAfter(end);
        current = DateTime(current.year, current.month, current.day + 1)
      ) {
        if (!current.isBefore(_day(widget.firstDate)) &&
            !current.isAfter(_day(widget.lastDate))) {
          next.add(current);
        }
      }
      _anchor = null;
    }
    widget.onSelectionChanged(Set.unmodifiable(next));
  }

  void _move(int delta) {
    final target = _page + delta;
    if (target < 0 || target >= _monthCount) return;
    _months.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  int get _monthCount => _monthDistance(_firstMonth, _lastMonth) + 1;

  DateTime _monthAt(int page) =>
      DateTime(_firstMonth.year, _firstMonth.month + page);

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final shown = _monthAt(_page);
    final monthName = DateFormat('LLLL y', 'ru_RU').format(shown);
    final title = monthName[0].toUpperCase() + monthName.substring(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('calendar-previous-month'),
              tooltip: 'Предыдущий месяц',
              onPressed: _page == 0 ? null : () => _move(-1),
              icon: const Icon(LucideIcons.chevron_left),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  title,
                  key: ValueKey(shown),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('calendar-next-month'),
              tooltip: 'Следующий месяц',
              onPressed: _page == _monthCount - 1 ? null : () => _move(1),
              icon: const Icon(LucideIcons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            children: [
              _Weekdays(weekStart: widget.weekStart),
              const SizedBox(height: 6),
              SizedBox(
                height: 276,
                child: PageView.builder(
                  key: const ValueKey('date-range-month-pages'),
                  controller: _months,
                  itemCount: _monthCount,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (_, page) => _MonthGrid(
                    month: _monthAt(page),
                    firstDate: _day(widget.firstDate),
                    lastDate: _day(widget.lastDate),
                    selectedDates: _normalized(widget.selectedDates),
                    selectionMode: widget.selectionMode,
                    weekStart: widget.weekStart,
                    onSelect: _select,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Weekdays extends StatelessWidget {
  const _Weekdays({required this.weekStart});

  final int weekStart;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final monday = DateTime(2026, 10, 19);
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Text(
              DateFormat.E(
                'ru_RU',
              ).format(monday.add(Duration(days: (weekStart - 1 + i) % 7))),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: p.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.selectedDates,
    required this.selectionMode,
    required this.weekStart,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime firstDate;
  final DateTime lastDate;
  final Set<DateTime> selectedDates;
  final DateSelectionMode selectionMode;
  final int weekStart;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final leading = (month.weekday - weekStart + 7) % 7;
    final selected = selectedDates.toList()..sort();
    final rangeStart = selected.isEmpty ? null : selected.first;
    final rangeEnd = selected.isEmpty ? null : selected.last;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        mainAxisExtent: 42,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        final number = index - leading + 1;
        if (number < 1 || number > days) return const SizedBox.shrink();
        final day = DateTime(month.year, month.month, number);
        final enabled = !day.isBefore(firstDate) && !day.isAfter(lastDate);
        final isSelected = selectedDates.contains(day);
        final emphasized =
            isSelected &&
            (selectionMode == DateSelectionMode.single ||
                day == rangeStart ||
                day == rangeEnd);
        return _SelectableDay(
          day: day,
          enabled: enabled,
          selected: isSelected,
          emphasized: emphasized,
          singleSelection: selectionMode == DateSelectionMode.single,
          onTap: () => onSelect(day),
        );
      },
    );
  }
}

class _SelectableDay extends StatelessWidget {
  const _SelectableDay({
    required this.day,
    required this.enabled,
    required this.selected,
    required this.emphasized,
    required this.singleSelection,
    required this.onTap,
  });

  final DateTime day;
  final bool enabled;
  final bool selected;
  final bool emphasized;
  final bool singleSelection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final fill = emphasized
        ? singleSelection
              ? theme.colorScheme.primary
              : periodColor
        : selected
        ? const Color(0xFFF3DDE6)
        : null;
    final ink = emphasized
        ? singleSelection
              ? theme.colorScheme.onPrimary
              : Colors.white
        : selected
        ? const Color(0xFF6E3550)
        : enabled
        ? p.textPrimary
        : p.textTertiary;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: DateFormat('d MMMM y', 'ru_RU').format(day),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            key: ValueKey('date-${DateFormat('yyyy-MM-dd').format(day)}'),
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

DateTime _month(DateTime value) => DateTime(value.year, value.month);

int _monthDistance(DateTime from, DateTime to) =>
    (to.year - from.year) * 12 + to.month - from.month;

Set<DateTime> _normalized(Iterable<DateTime> values) => {
  for (final value in values) _day(value),
};

bool _sameDays(Set<DateTime> a, Set<DateTime> b) {
  final left = _normalized(a);
  final right = _normalized(b);
  return left.length == right.length && left.containsAll(right);
}
