import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The name the app goes by everywhere it introduces itself: the launcher and
/// window titles of every platform, and the Настройки footer.
///
/// The Dart package is still `todo_app` — that is an identifier, not a name.
/// `test/app_name_test.dart` reads the platform manifests and fails if one of
/// them drifts away from this constant.
const appName = 'Nook';

/// The installed build as "2.0.2 (5)", read from the app itself — the version
/// and build number of `pubspec.yaml` as they were when it was built, so there
/// is no second copy to forget. The bare version when there is no build number.
final appVersionLabelProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty
      ? info.version
      : '${info.version} (${info.buildNumber})';
});
