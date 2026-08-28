import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:todo_app/home_widget/providers.dart';
import 'package:todo_app/home_widget/widget_actions.dart';
import 'package:todo_app/widgets/home/day_schedule_section.dart';
import 'package:todo_app/widgets/home/task_calendar.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// Steps the handle walks through, shortest calendar first. The middle step is
  /// what keeps a drag from flipping the whole month open in one jump.
  static const _formatStages = [
    CalendarFormat.week,
    CalendarFormat.twoWeeks,
    CalendarFormat.month,
  ];

  /// Finger travel each step costs, roughly the height of the rows it adds (one
  /// more week, then the rest of the month), so the calendar grows at about the
  /// speed of the thumb instead of waiting for one fixed threshold.
  static const _stageDrag = <double>[52, 140];

  /// A flick opens or closes the calendar all the way, whatever the distance.
  static const _flingVelocity = 400.0;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = _dayOnly(DateTime.now());
  CalendarFormat _calendarFormat = CalendarFormat.week;

  /// The day of [day], as local midnight — the one spelling of "which day is
  /// showing" this screen keeps.
  ///
  /// Needed because the three places [_selectedDay] is written do **not** agree
  /// on what a `DateTime` is: the field started life as `DateTime.now()`,
  /// `table_calendar` hands `onDaySelected` a **UTC** midnight, and
  /// [_changeSelectedDay] builds a local one. All three mean the same day and
  /// compare as three different values.
  ///
  /// That matters in the one place the value is used *as a value* rather than as
  /// a date: `DayScheduleSection` keys its `AnimatedSwitcher` on it and works out
  /// which way to slide by comparing it against the previous one. So tapping
  /// today's own date in the calendar read as a change and played a full
  /// backwards day-change animation for a day that had not changed — and tapping
  /// versus swiping onto the same day opened two `logsForDateProvider` streams
  /// for it, the family being keyed by this too.
  ///
  /// Reading `year`/`month`/`day` off a UTC value gives its UTC components,
  /// which for a calendar cell are exactly the date printed in it.
  ///
  /// Nothing downstream ever depended on the time: `recurrence.dart` strips it on
  /// every comparison and `TasksDao.dayOf` folds a log onto its day on the way
  /// into the database.
  static DateTime _dayOnly(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  double _handleDragDelta = 0;

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
    setState(() {
      _selectedDay = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day + deltaDays,
      );
      _focusedDay = _selectedDay;
    });
  }

  void _goToToday() {
    final today = _dayOnly(DateTime.now());
    if (_selectedDay == today && _focusedDay == today) return;
    setState(() {
      _selectedDay = today;
      _focusedDay = today;
    });
  }

  void _onHandleDragUpdate(DragUpdateDetails details) {
    _handleDragDelta += details.delta.dy;

    // Walk as many steps as the finger has actually covered and keep the
    // remainder: a long drag opens the calendar within one gesture, and turning
    // back mid-drag closes it again without first re-paying the travel spent.
    var stage = _formatStages.indexOf(_calendarFormat);
    final startStage = stage;
    while (true) {
      if (stage < _stageDrag.length && _handleDragDelta >= _stageDrag[stage]) {
        _handleDragDelta -= _stageDrag[stage];
        stage++;
      } else if (stage > 0 && -_handleDragDelta >= _stageDrag[stage - 1]) {
        _handleDragDelta += _stageDrag[stage - 1];
        stage--;
      } else {
        break;
      }
    }

    // Nothing left to open (or to close) in that direction, so drop the travel
    // rather than banking it — otherwise the way back starts with dead pixels.
    if (stage == _formatStages.length - 1 && _handleDragDelta > 0) {
      _handleDragDelta = 0;
    } else if (stage == 0 && _handleDragDelta < 0) {
      _handleDragDelta = 0;
    }

    if (stage != startStage) _setCalendarFormat(_formatStages[stage]);
  }

  void _onHandleDragEnd(DragEndDetails details) {
    _handleDragDelta = 0;

    final velocity = details.primaryVelocity ?? 0;
    if (velocity > _flingVelocity) {
      _setCalendarFormat(_formatStages.last);
    } else if (velocity < -_flingVelocity) {
      _setCalendarFormat(_formatStages.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: TaskCalendar(
                focusedDay: _focusedDay,
                selectedDay: _selectedDay,
                calendarFormat: _calendarFormat,
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = _dayOnly(selectedDay);
                    _focusedDay = focusedDay;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                onTodayPressed: _goToToday,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DayScheduleSection(
                onHandleDragUpdate: _onHandleDragUpdate,
                onHandleDragEnd: _onHandleDragEnd,
                onDayChange: _changeSelectedDay,
                selectedDay: _selectedDay,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
