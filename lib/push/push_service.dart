import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/push/push_init.dart';

/// The phone's side of push — Firebase, as little of it as the app needs — behind
/// an interface so that a test can stand in for it. Registering the token with
/// our server is `push_registration.dart`; this is only getting the token and
/// hearing about taps.
abstract class PushService {
  /// Brings push up and returns this phone's token, or null when it did not
  /// come up (no Google Play services, a platform without push, a broken
  /// config). Never throws.
  Future<String?> init();

  /// A new token for this phone. Only after [init] returned one.
  Stream<String> tokenRefreshes();

  /// The group a tapped push is about, while the app was in the background.
  Stream<String> openedGroups();

  /// The group of the push whose tap started the app, if one did.
  Future<String?> launchedGroup();

  /// Throws this phone's token away and returns what it was, or null.
  Future<String?> releaseToken();
}

class FirebasePushService implements PushService {
  const FirebasePushService();

  @override
  Future<String?> init() => initPush();

  @override
  Stream<String> tokenRefreshes() => pushTokenRefreshes();

  @override
  Stream<String> openedGroups() => pushOpenedGroups();

  @override
  Future<String?> launchedGroup() => pushLaunchedGroup();

  @override
  Future<String?> releaseToken() => releasePushToken();
}

final pushServiceProvider = Provider<PushService>(
  (ref) => const FirebasePushService(),
);
