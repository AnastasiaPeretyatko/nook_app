import 'package:todo_app/notifications/app_notifications.dart';
import 'package:todo_app/notifications/task_reminder.dart';

/// Stands in for the notification plugin, which a test does not have. Answers
/// the permission questions from [enabled] and counts the asks.
class FakeAppNotifications implements AppNotifications {
  FakeAppNotifications({this.enabled});

  /// What the system says about showing notifications; `null` = nothing to ask.
  bool? enabled;
  int asks = 0;
  bool grantWhenAsked = true;

  @override
  Future<bool?> notificationsEnabled() async => enabled;

  @override
  Future<bool?> requestPermission() async {
    asks++;
    if (grantWhenAsked) enabled = true;
    return enabled;
  }

  @override
  Future<void> ensureGroupChannel() async {}

  @override
  Future<void> syncReminders(
    List<TaskReminder> wanted, {
    required bool enabled,
    bool reschedule = false,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
