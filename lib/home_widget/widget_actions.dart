import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/utils/task_audience.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/home_widget/home_widget_bridge.dart';
import 'package:todo_app/home_widget/today_payload.dart';
import 'package:todo_app/home_widget/widget_theme.dart';

/// The URIs the widget's taps carry, and the entry point Android calls with
/// them.
///
/// Both sides of the tap live here because they are one agreement: Kotlin builds
/// these URIs when it draws a row, and one of the two readers below takes them
/// apart. Nothing checks the spelling at build time, so it is written down once
/// and referred to from both languages.

/// Scheme of every URI the widget sends. The app's name, and deliberately not
/// the OAuth scheme in the manifest: these never leave the device and no
/// `intent-filter` matches on them — the intents they ride on are explicit.
const widgetUriScheme = 'nook';
const widgetUriHost = 'widget';

/// A row's checkbox: tick or untick that task for that day. Answered in the
/// background, without opening the app.
const widgetTogglePath = '/toggle';

/// A row's body, and the header: open the app on today's schedule.
const widgetOpenPath = '/open';

/// "Добавить задачу": open the app straight into the task form.
const widgetCreatePath = '/create';

/// Not a tap at all: the widget asking to be filled in.
///
/// Sent by `TodayWidgetProvider` when it is asked to draw and finds no payload
/// for today — a widget just dropped onto the home screen, or one whose stored
/// week has run out because the app has not been opened in a while. It wakes the
/// same background isolate a checkbox does, and that isolate can read the
/// database whether or not the app is running.
const widgetRefreshPath = '/refresh';

/// Query keys of [widgetTogglePath].
const widgetTaskParam = 'task';
const widgetDayParam = 'day';

/// What a tap on the widget means, once its URI has been read.
///
/// [WidgetTapAction.unknown] covers a URI from a widget drawn by an older or
/// newer build of the app — a home-screen widget outlives the version that put
/// it there, so an unrecognised tap has to be an ordinary answer.
enum WidgetTapAction { toggle, open, create, refresh, unknown }

/// The action [uri] asks for, or [WidgetTapAction.unknown] for anything else,
/// null included.
WidgetTapAction widgetTapActionOf(Uri? uri) {
  if (uri == null ||
      uri.scheme != widgetUriScheme ||
      uri.host != widgetUriHost) {
    return WidgetTapAction.unknown;
  }
  return switch (uri.path) {
    widgetTogglePath => WidgetTapAction.toggle,
    widgetOpenPath => WidgetTapAction.open,
    widgetCreatePath => WidgetTapAction.create,
    widgetRefreshPath => WidgetTapAction.refresh,
    _ => WidgetTapAction.unknown,
  };
}

/// Android's way in when a checkbox on the widget is pressed.
///
/// This runs in an isolate of its own, started by `WorkManager` in a Flutter
/// engine that never ran `main`. Three consequences shape everything below:
///
/// * **Nothing is initialised.** No binding, no plugins registered on the Dart
///   side, no date symbols — so the first thing it does is all three. Without
///   [DartPluginRegistrant.ensureInitialized] the database cannot even find out
///   where it lives, because `path_provider` would not be registered.
/// * **There are no providers.** The `ProviderScope` belongs to the app's
///   isolate, so the database and the settings are opened by hand here and
///   closed again before returning.
/// * **It is killed straight after.** Whatever the tap has to leave behind has
///   to be written before this future completes.
///
/// The write goes through [TasksDao.toggleCompletion] like every other tick in
/// the app, which is the whole reason a tap is answered in Dart rather than in
/// Kotlin: the mark has to be stamped and marked unsent exactly as the app
/// stamps it, or the day would be ticked on this phone and on no other.
@pragma('vm:entry-point')
Future<void> onHomeWidgetTap(Uri? uri) async {
  final action = widgetTapActionOf(uri);
  // The other two are answered by opening the app, which Android does without
  // asking Dart anything. Nothing else has any business waking an isolate.
  if (action != WidgetTapAction.toggle && action != WidgetTapAction.refresh) {
    return;
  }

  final taskId = int.tryParse(uri!.queryParameters[widgetTaskParam] ?? '');
  final day = DateTime.tryParse(uri.queryParameters[widgetDayParam] ?? '');
  if (action == WidgetTapAction.toggle && (taskId == null || day == null)) {
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  // The payload carries Russian month names, and this isolate has never heard
  // of a locale.
  await initializeDateFormatting('ru_RU', null);

  final database = AppDatabase();
  try {
    final now = DateTime.now();
    // The row was drawn against the day the widget believed it was showing. A
    // widget drawn before midnight and tapped after it would otherwise tick
    // yesterday — so a tap for any day but today is dropped, and the redraw
    // below replaces the stale rows with the ones that belong to the new day.
    if (action == WidgetTapAction.toggle && _isSameDay(day!, now)) {
      // Foreign keys are off in this database, so a log can be written against
      // a task that is no longer there. The widget can easily be a few minutes
      // behind a deletion.
      final task = await database.tasksDao.getTaskById(taskId!);
      if (task != null) {
        await database.tasksDao.toggleCompletion(taskId, day);
      }
    }
    await pushWidgetPayload(database);
  } catch (error, stack) {
    debugPrint('Home widget tap failed: $error\n$stack');
  } finally {
    await database.close();
  }
}

/// Rebuilds the payload straight from [database] and hands it to the widget.
///
/// For the background isolate, which has no providers to derive it from. The app
/// itself pushes from `HomeWidgetScope`, off the same streams every screen
/// watches.
Future<void> pushWidgetPayload(AppDatabase database) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final prefs = await SharedPreferences.getInstance();
  // No session in this isolate. The account that settled what is on the device
  // is the one its groups belong to, so it stands in for "me".
  final me = prefs.getString(SyncClaimNotifier.prefsKey);
  final tasks = [
    for (final task in await database.tasksDao.getRootTasks())
      if (isMyTask(task, me)) task,
  ];
  final logs = await database.tasksDao.getLogsBetween(
    today,
    today.add(const Duration(days: todayWidgetHorizonDays)),
  );
  final theme = widgetThemeFromPrefs(prefs);

  await HomeWidgetBridge().push(
    buildTodayWidgetPayload(
      tasks: tasks,
      logs: logs,
      now: now,
      light: theme.light,
      dark: theme.dark,
      mode: theme.mode,
    ).encode(),
  );
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
