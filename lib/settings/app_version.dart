/// The name the app goes by everywhere it introduces itself: the launcher and
/// window titles of every platform, and the Настройки footer.
///
/// The Dart package is still `todo_app` — that is an identifier, not a name.
/// `test/app_name_test.dart` reads the platform manifests and fails if one of
/// them drifts away from this constant.
const appName = 'Nook';

/// The build shown at the bottom of Настройки, as `version+build`.
///
/// There is no way to read `pubspec.yaml` at runtime without pulling in a
/// plugin, so this is a plain constant — and `test/app_version_test.dart` reads
/// the pubspec and fails if the two ever drift apart. Bump both together.
const appVersion = '1.0.0+1';

/// `1.0.0+1` as "1.0.0 (1)"; the bare version when there is no build number.
String get appVersionLabel {
  final parts = appVersion.split('+');
  return parts.length == 2 ? '${parts.first} (${parts.last})' : appVersion;
}
