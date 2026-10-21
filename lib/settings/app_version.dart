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
///
/// **2.0.0**, and the major number is doing real work: this build is the first
/// that keeps an account's data to itself. It needs
/// `supabase/004_shared_moods.sql` to have been run, it takes the database to
/// schema 15, and it changes what signing in on a phone that already holds
/// somebody else's tasks does. A device running 1.0.0 against the migrated
/// server is not quite the same app.
const appVersion = '2.0.0+2';

/// `2.0.0+2` as "2.0.0 (2)"; the bare version when there is no build number.
String get appVersionLabel {
  final parts = appVersion.split('+');
  return parts.length == 2 ? '${parts.first} (${parts.last})' : appVersion;
}
