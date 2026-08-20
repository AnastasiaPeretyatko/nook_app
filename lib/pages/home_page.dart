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
  static const _dragThreshold = 36.0;

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

    if (_handleDragDelta > _dragThreshold) {
      _handleDragDelta = 0;
      _setCalendarFormat(CalendarFormat.month);
    } else if (_handleDragDelta < -_dragThreshold) {
      _handleDragDelta = 0;
      _setCalendarFormat(CalendarFormat.week);
    }
  }

  void _onHandleDragEnd(DragEndDetails details) {
    _handleDragDelta = 0;

    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 400) {
      _setCalendarFormat(CalendarFormat.month);
    } else if (velocity < -400) {
      _setCalendarFormat(CalendarFormat.week);
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
