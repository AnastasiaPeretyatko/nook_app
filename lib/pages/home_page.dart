import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:todo_app/widgets/home/day_schedule_section.dart';
import 'package:todo_app/widgets/home/task_calendar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;

  double _handleDragDelta = 0;

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
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
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
