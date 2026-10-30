import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// The moments the app asks for the permission to show notifications.
///
/// Each asks at most once, and never at startup: an app that has not yet done
/// anything worth a notification stays quiet. From Android 13 on a push that
/// arrives without the permission is dropped silently, so the group's pushes
/// (and the reminders) need it asked for *somewhere*; these are the two places
/// where the user has just made something that may later notify them.
enum NotificationAsk {
  /// The first task the user creates.
  task('notification_asked_task'),

  /// The first group the user creates or joins.
  group('notification_asked_group');

  const NotificationAsk(this.prefsKey);
  final String prefsKey;
}

/// Asks for the permission for [NotificationAsk]'s reason, when the system does
/// not allow notifications right now and this reason has not asked before.
///
/// Spent only when the system dialog is really shown, so a user who already
/// allowed (or a platform with nothing to ask — desktop, tests) is never marked
/// and never bothered. Two reasons mean two tries for the system, which is as
/// many as Android lets an app make. Never throws: it runs after something the
/// user did, and must not make that fail.
final offerNotificationPermissionProvider =
    Provider<Future<void> Function(NotificationAsk)>((ref) {
      return (reason) async {
        try {
          final prefs = ref.read(sharedPreferencesProvider);
          if (prefs.getBool(reason.prefsKey) ?? false) return;
          final allowed = await ref
              .read(appNotificationsProvider)
              .notificationsEnabled();
          // `null` is "nothing to ask here", `true` is "already allowed".
          if (allowed != false) return;
          await prefs.setBool(reason.prefsKey, true);
          await ref.read(notificationPermissionProvider.notifier).request();
        } catch (e) {
          debugPrint('Notification permission not offered: $e');
        }
      };
    });
