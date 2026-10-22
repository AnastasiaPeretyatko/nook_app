import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

// shortcut: getToken / onTokenRefresh / deleteToken are deprecated for
// register() / onRegistered (a Firebase Installation ID). Move once sending to
// an FID is confirmed on the server; every use of the old names is in this file.

/// Brings Firebase up for push, and never throws.
///
/// Same bargain as `initSupabase`: push is an extra, and a launch on a phone
/// without Google Play services, or with a broken config, has to end in a
/// running app. Android only — `google-services.json` is the one config there
/// is; other platforms have none.
///
/// Returns the device's FCM token, or null when Firebase did not come up.
Future<String?> initPush() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    // No options: on Android Firebase reads them from google-services.json.
    await Firebase.initializeApp().timeout(const Duration(seconds: 5));
    // ignore: deprecated_member_use
    return await FirebaseMessaging.instance.getToken();
  } catch (e) {
    debugPrint('Push init failed: $e');
    return null;
  }
}

/// A new token for this phone. Only after [initPush] has succeeded.
Stream<String> pushTokenRefreshes() =>
    // ignore: deprecated_member_use
    FirebaseMessaging.instance.onTokenRefresh;

/// The group a tapped push is about, while the app was in the background. A
/// push without one (the hand-made test) is skipped.
Stream<String> pushOpenedGroups() => FirebaseMessaging.onMessageOpenedApp
    .map((message) => message.data['group_id'])
    .where((group) => group is String)
    .cast<String>();

/// The same, for the push whose tap started the app. Null when it did not, and
/// once the answer has been given FCM does not give it twice.
Future<String?> pushLaunchedGroup() async {
  try {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    final group = message?.data['group_id'];
    return group is String ? group : null;
  } catch (e) {
    debugPrint('Push launch message failed: $e');
    return null;
  }
}

/// Throws this phone's token away and returns what it was, or null.
///
/// Deleting it makes the old one dead for FCM, so a push sent to a row the
/// server could not remove (signed out offline) goes nowhere; the next
/// [initPush] gets a fresh one.
Future<String?> releasePushToken() async {
  try {
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    // ignore: deprecated_member_use
    await FirebaseMessaging.instance.deleteToken();
    return token;
  } catch (e) {
    debugPrint('Push token release failed: $e');
    return null;
  }
}
