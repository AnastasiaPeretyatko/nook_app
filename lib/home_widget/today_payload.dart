import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/color_picker_row.dart';

/// Everything the home-screen widget draws, as plain data.
///
/// The widget is not Flutter: it is inflated by the launcher out of Android
/// `RemoteViews`, in a process this app does not run in. So nothing about it can
/// be *asked* — the whole of what it shows has to be written down in advance,
/// where the launcher can reach it, and re-read from there whenever Android
/// decides to redraw. That store is `SharedPreferences`, one JSON string, and
/// this file is the shape of it.
///
/// ## Why several days and not just today
///
/// A widget is redrawn by the system on its own schedule — every half hour, at
/// midnight, after a reboot — and none of those moments start a Dart isolate.
/// A payload holding only "today" would therefore go quietly wrong the first
/// time the date changed with the app closed: the launcher would keep drawing
/// yesterday's tasks under a heading that says Сегодня, and nothing would fix it
/// until the app was opened.
///
/// So the payload carries a week, keyed by date, and the native side looks up
/// the day the clock is actually on. Midnight then costs nothing: the same
/// stored payload answers for tomorrow as well as for today.
///
/// ## Why both palettes
///
/// Same reason. The system theme can flip while the app is not running, so the
/// light and the dark colours both travel, and the launcher picks. When the user
/// has pinned the app to one theme rather than following the system, [mode] says
/// so and the choice is not the launcher's to make.
class TodayWidgetPayload {
  const TodayWidgetPayload({
    required this.days,
    required this.light,
    required this.dark,
    required this.mode,
  });

  /// The window the widget can draw without the app running, today first.
  final List<WidgetDay> days;

  final WidgetPalette light;
  final WidgetPalette dark;

  /// `system`, `light` or `dark` — the app's own theme setting, passed on so the
  /// widget follows the app rather than only the system.
  final String mode;

  /// The payload as the single string the widget store holds.
  ///
  /// Encoded here rather than by the caller because the encoded form is what
  /// change detection compares: two payloads are "the same" exactly when their
  /// JSON is, which is cheaper and more honest than teaching four classes an
  /// `operator ==` that has to stay in step with them.
  String encode() => jsonEncode({
    'version': payloadVersion,
    'mode': mode,
    'palettes': {'light': light.toJson(), 'dark': dark.toJson()},
    'days': [for (final day in days) day.toJson()],
  });

  /// Bumped when the shape below changes in a way the Kotlin side has to know
  /// about. It reads the number and ignores a payload it does not understand,
  /// so an app updated while a widget sits on the home screen shows the empty
  /// state for a moment instead of drawing nonsense.
  static const payloadVersion = 1;
}

/// One day of the window: what is scheduled for it, and how much of it is done.
class WidgetDay {
  const WidgetDay({
    required this.date,
    required this.label,
    required this.tasks,
    required this.total,
    required this.done,
  });

  /// Local midnight of the day. Its `yyyy-MM-dd` spelling is the key the native
  /// side looks the day up by, which is why the time is stripped: a day is a
  /// date here, never an instant.
  final DateTime date;

  /// The date as the header prints it — "27 авг.".
  ///
  /// Formatted here and not in Kotlin because the app is Russian and `intl`
  /// already knows how to abbreviate a Russian month; Android's own formatter
  /// would follow the *system* locale and print "Aug 27" on an English phone.
  final String label;

  /// The day's tasks in the order they are drawn, capped at
  /// [todayWidgetMaxTasks] — the widget can show a handful of rows at most, and
  /// a payload is a `SharedPreferences` string rather than a database.
  final List<WidgetTask> tasks;

  /// How many the day *has*, before the cap. What the "3 из 6" counter and the
  /// "ещё N" line are built from, so a widget too small to list everything still
  /// tells the truth about the day.
  final int total;
  final int done;

  Map<String, Object?> toJson() => {
    'date': DateFormat('yyyy-MM-dd').format(date),
    'label': label,
    'total': total,
    'done': done,
    'tasks': [for (final task in tasks) task.toJson()],
  };
}

/// One row of the widget.
class WidgetTask {
  const WidgetTask({
    required this.id,
    required this.title,
    required this.time,
    required this.done,
    required this.color,
    required this.checkInk,
  });

  /// The task's local id. It travels into the tap's URI and comes back to
  /// [TasksDao.toggleCompletion], so the row the user pressed is the row that
  /// gets ticked.
  final int id;

  final String title;

  /// "09:00", or null for a task that belongs to the day without sitting at a
  /// time on it — the timeline puts those in a strip of their own, and here the
  /// time column is simply left empty.
  final String? time;

  final bool done;

  /// The task's own colour, as ARGB. Painted on the left bar, the dot and the
  /// ticked circle — the three marks the design gives a row.
  final int color;

  /// The tick drawn *inside* [color] once the row is done. Worked out here with
  /// [onBrandFill], because that decision needs the palette's own crossover
  /// luminance and Kotlin has no business re-deriving it.
  final int checkInk;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (time != null) 'time': time,
    'done': done,
    'color': color,
    'checkInk': checkInk,
  };
}

/// The colours one theme of the widget is drawn in, all opaque.
///
/// Opaque on purpose: a `RemoteViews` colour is applied as a tint over a shape
/// drawable, and a translucent one would let the wallpaper through in places the
/// design means to be solid. Anything the app expresses as an overlay is
/// flattened against the card here, where [flattenOn] lives.
class WidgetPalette {
  const WidgetPalette({
    required this.card,
    required this.title,
    required this.muted,
    required this.outline,
    required this.accent,
    required this.ring,
  });

  /// The card the whole widget is drawn on.
  final int card;

  /// Titles — the header and the task names.
  final int title;

  /// The time column, the counter, the date.
  final int muted;

  /// The two hairlines and the progress track.
  final int outline;

  /// The app accent: "Добавить задачу" and the progress fill.
  final int accent;

  /// The empty circle of a row that is not done yet.
  final int ring;

  /// The palette of a theme the app actually ships.
  ///
  /// Derived from the real [ColorScheme] rather than from a second set of
  /// constants, so the widget cannot drift away from the app the way a copied
  /// hex value always eventually does.
  factory WidgetPalette.fromScheme(ColorScheme scheme) {
    // The card tone, not the page under it: a widget lies on the wallpaper,
    // and the near-black page against a dark photo is not a card, it is a
    // hole. `buildAppTheme` keeps the page out of `surface` in both themes.
    final card = scheme.surface;
    return WidgetPalette(
      card: card.toARGB32(),
      title: flattenOn(card, scheme.onSurface).toARGB32(),
      muted: flattenOn(card, scheme.onSurfaceVariant).toARGB32(),
      outline: flattenOn(card, scheme.outlineVariant).toARGB32(),
      accent: inkOn(card, scheme.primary, minContrast: 3).toARGB32(),
      // A shade stronger than the hairlines: an empty checkbox is the thing the
      // eye looks for on this widget, and outlineVariant alone disappears.
      ring: flattenOn(
        card,
        scheme.onSurfaceVariant.withValues(alpha: 0.45),
      ).toARGB32(),
    );
  }

  Map<String, Object?> toJson() => {
    'card': card,
    'title': title,
    'muted': muted,
    'outline': outline,
    'accent': accent,
    'ring': ring,
  };
}

/// How many days the payload carries. A week: long enough that a phone left
/// alone for a few days still has a correct widget, short enough that the whole
/// thing stays a small string.
const todayWidgetHorizonDays = 7;

/// Rows one day may contribute. The widget shows four or five of them depending
/// on how tall it was dragged, so this is headroom rather than a limit anyone
/// sees — what does not fit is reported as "ещё N".
const todayWidgetMaxTasks = 8;

/// Builds the payload for the coming [todayWidgetHorizonDays] days.
///
/// A day's tasks are exactly what the app's own timeline draws for it: root
/// tasks only (a subtask is reported through its parent), active ones only, and
/// only those whose repeat rule lands on the day. Timed tasks come first in
/// clock order, then the ones that belong to the day without a time — the same
/// two groups the timeline splits into, run together into one list because a
/// widget four rows tall has no room for a second section.
///
/// [logs] must cover the whole window; anything outside it simply reads as "not
/// done", which is what a missing log means anyway.
TodayWidgetPayload buildTodayWidgetPayload({
  required List<Task> tasks,
  required List<TaskLog> logs,
  required DateTime now,
  required WidgetPalette light,
  required WidgetPalette dark,
  required String mode,
  int horizonDays = todayWidgetHorizonDays,
  int maxTasks = todayWidgetMaxTasks,
}) {
  final completed = <(int, DateTime)>{
    for (final log in logs)
      if (log.completed) (log.taskId, _dateOnly(log.date)),
  };

  final candidates = [
    for (final task in tasks)
      if (task.parentId == null && task.status == TaskStatus.active) task,
  ];

  final today = _dateOnly(now);
  final days = <WidgetDay>[];

  for (var offset = 0; offset < horizonDays; offset++) {
    final day = DateTime(today.year, today.month, today.day + offset);
    final scheduled = [
      for (final task in candidates)
        if (isTaskScheduledOn(task, day)) task,
    ]..sort(byTimeThenTitle);

    days.add(
      WidgetDay(
        date: day,
        label: DateFormat('d MMM', 'ru').format(day),
        total: scheduled.length,
        done: scheduled
            .where((task) => completed.contains((task.id, day)))
            .length,
        tasks: [
          for (final task in scheduled.take(maxTasks))
            _rowFor(task, done: completed.contains((task.id, day))),
        ],
      ),
    );
  }

  return TodayWidgetPayload(days: days, light: light, dark: dark, mode: mode);
}

WidgetTask _rowFor(Task task, {required bool done}) {
  final color = task.colorValue != null
      ? Color(task.colorValue!)
      : ColorPickerRow.colors.first;
  final minutes = task.scheduledTimeMinutes;
  return WidgetTask(
    id: task.id,
    title: task.title,
    time: minutes == null ? null : _fmtTime(minutes),
    done: done,
    color: color.toARGB32(),
    checkInk: onBrandFill(color).toARGB32(),
  );
}

/// Clock order, and the timeless tasks after all of them, by title — the order
/// the timeline and its untimed strip read in, flattened into one column.
int byTimeThenTitle(Task a, Task b) {
  final ta = a.scheduledTimeMinutes;
  final tb = b.scheduledTimeMinutes;
  if (ta != null && tb != null) {
    final byStart = ta.compareTo(tb);
    if (byStart != 0) return byStart;
    final ea = a.endTimeMinutes ?? ta;
    final eb = b.endTimeMinutes ?? tb;
    final byEnd = ea.compareTo(eb);
    if (byEnd != 0) return byEnd;
    return a.title.compareTo(b.title);
  }
  if (ta == null && tb == null) return a.title.compareTo(b.title);
  return ta == null ? 1 : -1;
}

String _fmtTime(int minutes) {
  final normalized = minutes % (24 * 60);
  final h = (normalized ~/ 60).toString().padLeft(2, '0');
  final m = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
