import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A tap on a group push that the app still has to act on.
///
/// Same shape as `widgetTapProvider`: reported from outside the screens, acted
/// on by `MainScreen`, which has the navigator. [serial] makes two taps on the
/// same group two distinct states, so nothing has to clear the request.
final pushTapProvider = NotifierProvider<PushTapNotifier, PushTap?>(
  PushTapNotifier.new,
);

class PushTapNotifier extends Notifier<PushTap?> {
  int _serial = 0;

  @override
  PushTap? build() => null;

  void report(String? groupUid) {
    if (groupUid == null) return;
    state = PushTap(groupUid: groupUid, serial: ++_serial);
  }
}

class PushTap {
  const PushTap({required this.groupUid, required this.serial});

  final String groupUid;
  final int serial;

  @override
  bool operator ==(Object other) =>
      other is PushTap && other.groupUid == groupUid && other.serial == serial;

  @override
  int get hashCode => Object.hash(groupUid, serial);
}
