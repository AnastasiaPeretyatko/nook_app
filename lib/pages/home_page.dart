import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:todo_app/home_widget/providers.dart';
import 'package:todo_app/home_widget/widget_actions.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/widgets/home/day_schedule_section.dart';
import 'package:todo_app/widgets/home/task_calendar.dart';

/// The day the home screen is showing: the one the calendar highlights, the one
/// the schedule below it draws, and the one a task created from the "+" button
/// starts on.
///
/// A provider rather than `_HomePageState` state, because that last reader sits
/// outside this screen. The "+" button belongs to `MainScreen`, which cannot
/// see into a page's state, so the form it pushed always opened on today — swipe
/// the schedule to the 1st of September, add a task, and the task was for
/// whatever day it happened to be.
final selectedDayProvider = NotifierProvider<SelectedDayNotifier, DateTime>(
  SelectedDayNotifier.new,
);

class SelectedDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => dayOnly(DateTime.now());

  /// The day [day] names, whatever spelling of a `DateTime` it arrives in — see
  /// [dayOnly].
  ///
  /// A day that is already the one on screen is dropped rather than written
  /// again, which is what the calendar needs: tapping today's own cell hands
  /// back the same date and must not read as a change.
  void select(DateTime day) {
    final next = dayOnly(day);
    if (next != state) state = next;
  }

  /// [deltaDays] days along from the day on screen: +1 the next one, -1 the
  /// previous.
  void shift(int deltaDays) {
    state = DateTime(state.year, state.month, state.day + deltaDays);
  }

  void goToToday() => select(DateTime.now());
}

/// The day of [day], as local midnight — the one spelling of "which day is
/// showing" this screen keeps.
///
/// Needed because the places the day is written do **not** agree on what a
/// `DateTime` is: it started life as `DateTime.now()`, `table_calendar` hands
/// `onDaySelected` a **UTC** midnight, and [SelectedDayNotifier.shift] builds a
/// local one. All three mean the same day and compare as three different values.
///
/// That matters in the one place the value is used *as a value* rather than as a
/// date: `DayScheduleSection` keys its `AnimatedSwitcher` on it and works out
/// which way to slide by comparing it against the previous one. So tapping
/// today's own date in the calendar read as a change and played a full backwards
/// day-change animation for a day that had not changed — and tapping versus
/// swiping onto the same day opened two `logsForDateProvider` streams for it, the
/// family being keyed by this too.
///
/// Reading `year`/`month`/`day` off a UTC value gives its UTC components, which
/// for a calendar cell are exactly the date printed in it.
///
/// Nothing downstream ever depended on the time: `recurrence.dart` strips it on
/// every comparison and `TasksDao.dayOf` folds a log onto its day on the way into
/// the database.
DateTime dayOnly(DateTime day) => DateTime(day.year, day.month, day.day);

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// The month the calendar has open. The screen's own affair — which day is
  /// selected is [selectedDayProvider]'s, and the two only move together because
  /// picking a day in another month scrolls the calendar to it.
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;

  @override
  void initState() {
    super.initState();
    // A tap on the home-screen widget means "show me what that widget was
    // showing", and the widget only ever shows today. Without this the app would
    // come back on whatever day was last swiped to, which for a screen opened
    // from a tick on today's list is the wrong one.
    ref.listenManual<WidgetTapRequest?>(widgetTapProvider, (_, request) {
      if (request?.action == WidgetTapAction.open) _goToToday();
    });
  }

  void _setCalendarFormat(CalendarFormat format) {
    if (_calendarFormat == format) return;
    setState(() => _calendarFormat = format);
  }

  void _changeSelectedDay(int deltaDays) {
    ref.read(selectedDayProvider.notifier).shift(deltaDays);
    setState(() => _focusedDay = ref.read(selectedDayProvider));
  }

  void _goToToday() {
    ref.read(selectedDayProvider.notifier).goToToday();
    setState(() => _focusedDay = ref.read(selectedDayProvider));
  }

  @override
  Widget build(BuildContext context) {
    final selectedDay = ref.watch(selectedDayProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MonthHeader(
              month: _focusedDay,
              expanded: _calendarFormat == CalendarFormat.month,
              onToggle: () => _setCalendarFormat(
                _calendarFormat == CalendarFormat.month
                    ? CalendarFormat.week
                    : CalendarFormat.month,
              ),
              onToday: _goToToday,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TaskCalendar(
                focusedDay: _focusedDay,
                selectedDay: selectedDay,
                calendarFormat: _calendarFormat,
                onDaySelected: (day, focusedDay) {
                  ref.read(selectedDayProvider.notifier).select(day);
                  setState(() => _focusedDay = focusedDay);
                },
                onPageChanged: (focusedDay) {
                  setState(() => _focusedDay = focusedDay);
                },
                onFormatChanged: _setCalendarFormat,
              ),
            ),
            Expanded(
              child: DayScheduleSection(
                onDayChange: _changeSelectedDay,
                selectedDay: selectedDay,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Октябрь ⌄" — a button that opens the month and closes it back to the week —
/// and "Сегодня" on the right (`Timeline.dc.html`, header). The year joins the
/// month only when it is not this one.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.expanded,
    required this.onToggle,
    required this.onToday,
  });

  final DateTime month;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final name = DateFormat.LLLL('ru_RU').format(month);
    final label =
        '${name[0].toUpperCase()}${name.substring(1)}'
        '${month.year == DateTime.now().year ? '' : ' ${month.year}'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: expanded
                    ? 'Свернуть календарь'
                    : 'Открыть календарь месяца',
                excludeSemantics: true,
                child: InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.6,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            LucideIcons.chevron_down,
                            size: 22,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: p.surface,
            shape: StadiumBorder(side: BorderSide(color: p.borderStrong)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToday,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(
                  height: 36,
                  child: Center(
                    child: Text(
                      'Сегодня',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: p.textPrimary,
                      ),
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
