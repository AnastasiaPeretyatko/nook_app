import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:todo_app/update/app_update.dart';

/// What the update banner shows. [info] null → no banner at all.
class UpdateState {
  const UpdateState({this.info, this.percent, this.error});

  final UpdateInfo? info;

  /// 0–100 while the APK is coming down, null otherwise.
  final int? percent;

  /// Set when the last attempt failed; the banner offers "Повторить".
  final String? error;

  bool get downloading => percent != null;
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);

class UpdateNotifier extends Notifier<UpdateState> {
  StreamSubscription<OtaEvent>? _sub;

  @override
  UpdateState build() {
    ref.onDispose(() => _sub?.cancel());
    return const UpdateState();
  }

  /// Asks GitHub once; called by `MainScreen` at launch. Android only — the
  /// APK route means nothing elsewhere, and tests (Linux) never hit the net.
  Future<void> check() async {
    if (!Platform.isAndroid) return;
    try {
      final installed = int.parse(
        (await PackageInfo.fromPlatform()).buildNumber,
      );
      final latest = await fetchLatestRelease();
      if (latest != null && latest.versionCode > installed) {
        state = UpdateState(info: latest);
      }
    } on Object {
      // A failed check is silent by design: the app simply works as before.
    }
  }

  void dismiss() {
    if (!state.downloading) state = const UpdateState();
  }

  void install() {
    final info = state.info;
    if (info == null || state.downloading) return;
    state = UpdateState(info: info, percent: 0);
    // A fresh OtaUpdate each time: one instance keeps its first (closed) stream
    // and would hand it back on a retry.
    _sub?.cancel();
    _sub = OtaUpdate()
        .execute(
          info.url,
          destinationFilename: 'nook-update.apk',
          sha256checksum: info.sha256,
        )
        .listen(
          (event) => _onEvent(info, event),
          onError: (Object _) => _fail(info, 'Не удалось обновить'),
        );
  }

  void _onEvent(UpdateInfo info, OtaEvent event) {
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        state = UpdateState(
          info: info,
          percent: int.tryParse(event.value ?? '') ?? state.percent ?? 0,
        );
      case OtaStatus.INSTALLING:
        // The system installer is up. If the user backs out of it the banner
        // is simply there again, ready for another try.
        state = UpdateState(info: info);
      case OtaStatus.CHECKSUM_ERROR:
        _fail(info, 'Файл повреждён. Попробуйте ещё раз');
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail(info, 'Нет разрешения на установку');
      case OtaStatus.DOWNLOAD_ERROR:
        _fail(info, 'Не удалось скачать. Проверьте интернет');
      case _:
        _fail(info, 'Не удалось обновить');
    }
  }

  void _fail(UpdateInfo info, String message) {
    // The plugin can send a second error after the first (a bad HTTP status
    // is followed by a failed checksum of the error page); keep the first.
    if (state.error != null) return;
    state = UpdateState(info: info, error: message);
  }
}
