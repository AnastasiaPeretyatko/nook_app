import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/home_widget/habits_payload.dart';
import 'package:todo_app/home_widget/home_widget_bridge.dart';
import 'package:todo_app/home_widget/today_payload.dart';
import 'package:todo_app/home_widget/widget_actions.dart';
import 'package:todo_app/home_widget/widget_theme.dart';
import 'package:todo_app/settings/analytics_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';

final homeWidgetBridgeProvider = Provider<HomeWidgetBridge>((ref) {
  return HomeWidgetBridge();
});

/// What the home-screen widget should be showing, already encoded — or an empty
/// string while the database has not answered yet, which nobody pushes.
///
/// Pure derivation, like [taskRemindersProvider]: watching it costs nothing and
/// the platform call lives behind [homeWidgetBridgeProvider]. Encoded here
/// rather than kept as an object so that "has it changed" is a string
/// comparison — the provider fires only when the widget would actually look
/// different, which is what stops a redraw broadcast per keystroke in the task
/// form.
final todayWidgetPayloadProvider = Provider<String>((ref) {
  final tasksState = ref.watch(rootTasksProvider);
  final tasks = tasksState.valueOrNull ?? const <Task>[];

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final logsState = ref.watch(
    logsBetweenProvider(
      DateRange(today, today.add(const Duration(days: todayWidgetHorizonDays))),
    ),
  );
  // Nothing until the database has answered: a payload built from the empty
  // first emission would be stored — and drawn — as "no tasks".
  if (!tasksState.hasValue || !logsState.hasValue) return '';
  final logs = logsState.value!;

  // The widget is repainted when the app's accent or theme changes, the same as
  // every screen — it is the app's surface, just one that happens to be drawn by
  // the launcher.
  final theme = widgetThemeFor(
    accent: ref.watch(appColorProvider),
    mode: ref.watch(themeModeProvider),
  );

  return buildTodayWidgetPayload(
    tasks: tasks,
    logs: logs,
    now: now,
    light: theme.light,
    dark: theme.dark,
    mode: theme.mode,
  ).encode();
});

/// The same for the two habit widgets. Needs every log, not a window of them:
/// a streak reaches back to the habit's first day.
final habitsWidgetPayloadProvider = Provider<String>((ref) {
  final tasks = ref.watch(rootTasksProvider);
  final logs = ref.watch(allLogsProvider);
  // As above: not before the database has answered.
  if (!tasks.hasValue || !logs.hasValue) return '';
  final theme = widgetThemeFor(
    accent: ref.watch(appColorProvider),
    mode: ref.watch(themeModeProvider),
  );
  return buildHabitsWidgetPayload(
    tasks: tasks.value!,
    logs: logs.value!,
    now: DateTime.now(),
    light: theme.light,
    dark: theme.dark,
    mode: theme.mode,
    weekStart: ref.watch(weekStartProvider),
    graceMinutes: ref.watch(lateGraceMinutesProvider),
    todayStaysOpen: ref.watch(todayStaysOpenProvider),
  ).encode();
});

/// A tap on the widget that the app still has to act on, and nothing else.
///
/// Only the two that open the app arrive here — [WidgetTapAction.open] and
/// [WidgetTapAction.create]. A checkbox never does: it is answered in a
/// background isolate and never reaches this one.
///
/// [WidgetTapRequest.serial] is what makes two identical taps two distinct
/// states, so pressing "Добавить задачу" twice opens the form twice. Nothing
/// clears the request once handled — with a serial there is nothing to clear,
/// and no listener can race another into clearing a tap the second one has not
/// seen yet.
final widgetTapProvider =
    NotifierProvider<WidgetTapNotifier, WidgetTapRequest?>(
      WidgetTapNotifier.new,
    );

class WidgetTapNotifier extends Notifier<WidgetTapRequest?> {
  int _serial = 0;

  @override
  WidgetTapRequest? build() => null;

  void report(WidgetTapAction action) {
    if (action != WidgetTapAction.open && action != WidgetTapAction.create) {
      return;
    }
    state = WidgetTapRequest(action: action, serial: ++_serial);
  }
}

class WidgetTapRequest {
  const WidgetTapRequest({required this.action, required this.serial});

  final WidgetTapAction action;

  /// Counts up with every tap, so a second identical tap is a new value.
  final int serial;

  @override
  bool operator ==(Object other) =>
      other is WidgetTapRequest &&
      other.action == action &&
      other.serial == serial;

  @override
  int get hashCode => Object.hash(action, serial);
}
