import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:todo_app/notifications/task_reminder.dart';
import 'package:todo_app/notifications/timer_notification.dart';

/// Everything this app puts in the notification shade: the ongoing entry for a
/// running habit timer, and the reminders for tasks that carry a time.
///
/// One class because they share a plugin, an initialisation and a permission —
/// two services would each ask the user for the same thing.
///
/// Nothing here counts time or waits for a clock. The platform is handed the
/// instant something is due and takes it from there, so what the shade shows
/// stays right without the app being alive to update it.
///
/// Every platform call is wrapped: a device that refuses notifications must not
/// take the timers or the tasks down with it.
class AppNotifications {
  AppNotifications({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The ongoing entries currently posted, by task. Compared against what is
  /// wanted so an unchanged run is left alone rather than re-posted.
  final Map<int, TimerNotification> _posted = {};

  bool _ready = false;
  bool _timezoneReady = false;

  static const _runningChannelId = 'habit_timer_running';
  static const _doneChannelId = 'habit_timer_done';
  static const _reminderChannelId = 'task_reminders';

  /// Two ids per task out of one counter, so the ongoing entry and the alert
  /// that replaces it can be cancelled independently.
  static int runningIdFor(int taskId) => taskId * 2;
  static int doneIdFor(int taskId) => taskId * 2 + 1;

  /// Reminders live above every timer id, so the two can never be mistaken for
  /// one another — which also makes "cancel the reminders" a range, not a list
  /// the app has to remember across restarts.
  static const reminderIdBase = 1000000;

  /// Slots a reminder id cycles through. One more than the horizon, so that no
  /// two days inside the window ever land on the same id.
  static const _reminderDaySlots = defaultReminderHorizonDays + 1;

  /// Stable for a given task and day, so a reschedule replaces the reminder it
  /// is meant to rather than piling a second one on top.
  static int reminderIdFor(int taskId, DateTime day) =>
      reminderIdBase +
      taskId * _reminderDaySlots +
      _daysSinceEpoch(day) % _reminderDaySlots;

  static int _daysSinceEpoch(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Brings the shade to [running]: posts what is new or changed, clears what
  /// stopped. Safe to call on every rebuild — an unchanged list does nothing.
  Future<void> sync(List<TimerNotification> running) async {
    if (!_supported) return;
    // Nothing running and nothing posted: do not even wake the plugin, so an
    // app whose timers are never used never asks for the permission.
    if (running.isEmpty && _posted.isEmpty) return;
    if (!await _ensureReady()) return;

    final wanted = {for (final entry in running) entry.taskId: entry};

    for (final taskId in _posted.keys.toList()) {
      if (wanted[taskId] != _posted[taskId]) await _clear(taskId);
    }
    for (final entry in wanted.values) {
      if (_posted[entry.taskId] == entry) continue;
      await _post(entry);
    }
  }

  /// Brings the scheduled task reminders to [wanted].
  ///
  /// [enabled] is the user's setting: when it is off every reminder is taken
  /// down and none are scheduled, whatever [wanted] holds.
  ///
  /// What is already scheduled is read back from the platform rather than
  /// remembered in memory, so reminders queued by a previous launch are still
  /// recognised — and reminders whose text or time changed are replaced instead
  /// of firing with what they used to say.
  Future<void> syncReminders(
    List<TaskReminder> wanted, {
    required bool enabled,
  }) async {
    if (!_supported) return;
    final target = enabled ? wanted : const <TaskReminder>[];

    // Scheduling needs the permission, clearing does not. Asking only when
    // there is something to schedule keeps a fresh install with no timed tasks
    // from being prompted for reminders it has none of.
    if (!await _ensureReady(requestPermission: target.isNotEmpty)) return;
    if (!await _ensureTimezone()) return;

    final byId = {
      for (final reminder in target)
        reminderIdFor(reminder.taskId, reminder.day): reminder,
    };

    final pending = await _pendingReminders();
    for (final entry in pending.entries) {
      final keep = byId[entry.key]?.fingerprint == entry.value;
      if (!keep) await _guard(() => _plugin.cancel(id: entry.key));
    }
    for (final entry in byId.entries) {
      if (pending[entry.key] == entry.value.fingerprint) continue;
      await _scheduleReminder(entry.key, entry.value);
    }
  }

  /// The reminders the platform currently holds, as id → fingerprint. Ids
  /// outside the reminder range belong to the timers and are left alone.
  Future<Map<int, String>> _pendingReminders() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return {
        for (final request in pending)
          if (request.id >= reminderIdBase) request.id: request.payload ?? '',
      };
    } catch (error) {
      debugPrint('Could not read pending reminders: $error');
      return const {};
    }
  }

  Future<void> _scheduleReminder(int id, TaskReminder reminder) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _reminderChannelId,
        'Напоминания о задачах',
        channelDescription: 'Сообщение в момент, на который назначена задача',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final at = tz.TZDateTime.from(reminder.at, tz.local);
    // The fingerprint rides along as the payload: it is the only thing that
    // comes back from [pendingNotificationRequests], so it is what tells a
    // still-correct reminder from one that has to be replaced.
    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: id,
      title: reminder.title,
      body: reminder.body,
      scheduledDate: at,
      notificationDetails: details,
      androidScheduleMode: mode,
      payload: reminder.fingerprint,
    );

    try {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (error) {
      debugPrint('Reminder falling back to inexact: $error');
      await _guard(() => schedule(AndroidScheduleMode.inexactAllowWhileIdle));
    }
  }

  /// Takes every entry down. For signing out, wiping data, or tests.
  Future<void> clearAll() async {
    for (final taskId in _posted.keys.toList()) {
      await _clear(taskId);
    }
  }

  Future<void> _post(TimerNotification entry) async {
    final running = AndroidNotificationDetails(
      _runningChannelId,
      'Идущие таймеры',
      channelDescription: 'Таймер привычки, пока он идёт',
      importance: Importance.low,
      priority: Priority.low,
      // Not swipeable and not self-dismissing: it mirrors a run that is still
      // going, so only stopping the run may take it away.
      ongoing: true,
      autoCancel: false,
      // It is re-posted whenever the run changes; alerting each time would buzz
      // the phone for nothing.
      onlyAlertOnce: true,
      silent: true,
      playSound: false,
      enableVibration: false,
      showWhen: true,
      when: entry.finishesAt.millisecondsSinceEpoch,
      usesChronometer: true,
      chronometerCountDown: true,
      category: AndroidNotificationCategory.stopwatch,
    );

    await _guard(
      () => _plugin.show(
        id: runningIdFor(entry.taskId),
        title: entry.title,
        body: 'Таймер идёт',
        notificationDetails: NotificationDetails(
          android: running,
          iOS: const DarwinNotificationDetails(presentSound: false),
        ),
      ),
    );
    await _scheduleDone(entry);
    _posted[entry.taskId] = entry;
  }

  Future<void> _scheduleDone(TimerNotification entry) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _doneChannelId,
        'Таймер завершён',
        channelDescription: 'Сообщение о том, что время вышло',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
      ),
      iOS: DarwinNotificationDetails(),
    );

    // Only the scheduled alert needs a timezone. Loading it here, and letting a
    // failure stop just this call, keeps the ongoing entry — which needs no
    // timezone at all — out of reach of anything that can go wrong with it.
    if (!await _ensureTimezone()) return;

    // A run already past its target fires at once rather than being scheduled
    // into the past, which the platform would reject.
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime.from(entry.finishesAt, tz.local);
    if (!at.isAfter(now)) at = now.add(const Duration(seconds: 1));

    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: doneIdFor(entry.taskId),
      title: entry.title,
      body: 'Время вышло',
      scheduledDate: at,
      notificationDetails: details,
      androidScheduleMode: mode,
    );

    try {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (error) {
      // Exact alarms are denied by default on Android 12+ and the app does not
      // ask for them, so this is the ordinary path rather than a fault — logged
      // without a stack trace because it happens on every post.
      debugPrint('Timer alert falling back to inexact: $error');
      await _guard(() => schedule(AndroidScheduleMode.inexactAllowWhileIdle));
    }
  }

  Future<void> _clear(int taskId) async {
    await _guard(() => _plugin.cancel(id: runningIdFor(taskId)));
    await _guard(() => _plugin.cancel(id: doneIdFor(taskId)));
    _posted.remove(taskId);
  }

  /// Loads the device's timezone, once. Only [_scheduleDone] needs it.
  Future<bool> _ensureTimezone() async {
    if (_timezoneReady) return true;
    _timezoneReady = await _guard(() async {
      tz_data.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    });
    return _timezoneReady;
  }

  /// Initialises the plugin and asks for what it needs, once. Returns whether
  /// the shade can be written to at all.
  Future<bool> _ensureReady({bool requestPermission = true}) async {
    if (_ready) {
      if (requestPermission) await _requestPermission();
      return true;
    }

    final ok = await _guard(() async {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // Android draws a small icon from its alpha channel alone, so this
          // has to be the flat white silhouette in res/drawable-*, never the
          // full-colour launcher icon — that one comes out as a white blob.
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          // Every request* is off so that initialising does not prompt on iOS.
          // The ask belongs to the first thing that actually needs the shade,
          // which is what [_requestPermission] is called from.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
    });

    _ready = ok;
    if (ok && requestPermission) await _requestPermission();
    return ok;
  }

  bool _permissionAsked = false;

  /// Asks for the notification permission, once. Called from the first sync
  /// that has something to show, not at startup: an app whose timers and
  /// reminders are never used never prompts.
  Future<void> _requestPermission() async {
    if (_permissionAsked) return;
    _permissionAsked = true;
    await _askPlatform();
  }

  /// Asks because the *user* asked — the reminders switch in settings.
  ///
  /// The lazy ask above only fires once a timer runs or a timed task exists,
  /// which leaves a fresh install with nothing to grant and no way to grant it.
  /// Turning the switch on is that intent, so it does not wait for a task, and
  /// it is not spent by the once-per-launch gate. Returns what the system says
  /// afterwards, so a denial can be shown rather than guessed at.
  Future<bool?> requestPermission() async {
    if (!_supported) return null;
    if (!await _ensureReady(requestPermission: false)) return null;
    _permissionAsked = true;
    await _askPlatform();
    return notificationsEnabled();
  }

  /// Whether the platform will let the app post at all: the `POST_NOTIFICATIONS`
  /// permission from Android 13 on, the notification switch before that, the
  /// alert setting on iOS. `null` where there is nothing to ask.
  ///
  /// Read from the system every time, never cached — it can be revoked in
  /// system settings while the app is not even running.
  Future<bool?> notificationsEnabled() async {
    if (!_supported) return null;
    if (!await _ensureReady(requestPermission: false)) return null;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      bool? enabled;
      await _guard(() async {
        enabled = await android.areNotificationsEnabled();
      });
      return enabled;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      bool? enabled;
      await _guard(() async {
        enabled = (await ios.checkPermissions())?.isAlertEnabled;
      });
      return enabled;
    }
    return null;
  }

  /// Opens this app's page in the system notification settings.
  ///
  /// The only way back from a denial: Android answers a second
  /// [requestPermission] with a silent `false` once the user has refused, so
  /// the switch has to hand them over to the system instead of asking again.
  Future<void> openSystemSettings() async {
    if (!_supported) return;
    await _guard(() async {
      await _plugin.openAppNotificationSettings();
    });
  }

  Future<void> _askPlatform() async {
    await _guard(() async {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        // Asked for here rather than at startup: permission is requested the
        // first time a timer actually needs the shade, not on a cold launch
        // that may never run one.
        final granted = await android.requestNotificationsPermission();
        if (granted == false) {
          debugPrint(
            'Notifications denied — timers will run without a shade '
            'entry until the permission is granted in system settings.',
          );
        }
        // Exact alarms are deliberately *not* requested: asking throws the user
        // out into a system settings screen mid-task, which is far too rude for
        // a convenience. Alerts fall back to inexact ones, which fire a little
        // late rather than not at all.
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await ios?.requestPermissions(alert: true, sound: true);
    });
  }

  /// Runs a platform call, swallowing anything it throws. A shade that cannot
  /// be written to is a missing convenience, never a broken timer.
  Future<bool> _guard(Future<void> Function() call) async {
    try {
      await call();
      return true;
    } catch (error, stack) {
      debugPrint('Timer notification failed: $error\n$stack');
      return false;
    }
  }
}
