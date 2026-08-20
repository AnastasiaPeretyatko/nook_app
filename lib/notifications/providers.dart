import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/notifications/app_notifications.dart';
import 'package:todo_app/notifications/task_reminder.dart';
import 'package:todo_app/notifications/timer_notification.dart';
import 'package:todo_app/settings/notification_settings.dart';

final appNotificationsProvider = Provider<AppNotifications>((ref) {
  // Not cleared on dispose: the app going away does not stop a run or cancel a
  // reminder, and what the shade holds is exactly what should outlive it.
  return AppNotifications();
});

/// The shade entries the running timers currently call for.
///
/// Pure derivation — watching it costs nothing until something actually runs,
/// and the side effect of posting lives in [appNotificationsProvider].
final runningTimerNotificationsProvider = Provider<List<TimerNotification>>((
  ref,
) {
  final sessions =
      ref.watch(openSessionsProvider).valueOrNull ?? const <TaskSession>[];
  if (sessions.isEmpty) return const [];

  final tasks = ref.watch(allTasksProvider).valueOrNull ?? const <Task>[];

  // Two days wide: a run that began before midnight is still banked against the
  // day it started on, so yesterday's log is what shortens its countdown.
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final range = DateRange(
    today.subtract(const Duration(days: 1)),
    today.add(const Duration(days: 1)),
  );
  final logs =
      ref.watch(logsBetweenProvider(range)).valueOrNull ?? const <TaskLog>[];

  return timerNotificationsFor(
    tasks: tasks,
    openSessions: sessions,
    logs: logs,
  );
});

/// The reminders the timed tasks call for over the coming week.
final taskRemindersProvider = Provider<List<TaskReminder>>((ref) {
  // Watched even when reminders are off, so switching the setting back on
  // recomputes and reschedules without waiting for the next task edit.
  if (!ref.watch(taskRemindersEnabledProvider)) return const [];

  final tasks = ref.watch(rootTasksProvider).valueOrNull ?? const <Task>[];
  if (tasks.isEmpty) return const [];

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final range = DateRange(
    today,
    today.add(const Duration(days: defaultReminderHorizonDays)),
  );
  final logs =
      ref.watch(logsBetweenProvider(range)).valueOrNull ?? const <TaskLog>[];

  return taskRemindersFor(tasks: tasks, logs: logs, now: now);
});

/// Whether the platform will actually let the app post a notification.
///
/// Separate from [taskRemindersEnabledProvider]: that one is the user's wish,
/// this one is the system's answer, and they disagree exactly when reminders
/// are on and silently going nowhere. `null` where there is nothing to ask —
/// desktop, web, tests.
final notificationPermissionProvider =
    AsyncNotifierProvider<NotificationPermissionNotifier, bool?>(
      NotificationPermissionNotifier.new,
    );

class NotificationPermissionNotifier extends AsyncNotifier<bool?> {
  @override
  Future<bool?> build() =>
      ref.read(appNotificationsProvider).notificationsEnabled();

  /// Re-reads the system's answer. Called when the app comes back to the
  /// foreground, because the trip to system settings is how a denial is undone
  /// and nothing tells the app it happened.
  Future<void> refresh() =>
      _apply(ref.read(appNotificationsProvider).notificationsEnabled());

  /// Asks the user for the permission, then reports what the system says.
  Future<void> request() =>
      _apply(ref.read(appNotificationsProvider).requestPermission());

  Future<void> openSystemSettings() =>
      ref.read(appNotificationsProvider).openSystemSettings();

  Future<void> _apply(Future<bool?> answer) async {
    final granted = await answer;
    final changed = granted != state.valueOrNull;
    state = AsyncData(granted);
    // Reminders that could not be scheduled while the permission was missing
    // are not retried by anything else — no task changed — so the moment it is
    // granted has to push them out itself.
    if (changed && granted == true) {
      await ref
          .read(appNotificationsProvider)
          .syncReminders(
            ref.read(taskRemindersProvider),
            enabled: ref.read(taskRemindersEnabledProvider),
          );
    }
  }
}
