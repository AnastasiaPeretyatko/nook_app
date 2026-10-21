import 'dart:convert';
import 'dart:io';

/// The GitHub repository the releases live in. The one place it is written
/// down: `scripts/release.sh` reads it from here, so the two cannot disagree.
const updateRepo = 'AnastasiaPeretyatko/nook_app';

/// Always the newest release's `version.json`. GitHub answers with a redirect
/// to the file of that release (and the APK link redirects again to another
/// domain); `HttpClient` follows both on its own.
const updateManifestUrl =
    'https://github.com/$updateRepo/releases/latest/download/version.json';

/// What `version.json` says about the newest release.
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
    this.changelog = '',
    this.sha256,
  });

  /// The build number (`+N` in pubspec) — the only thing compared with the
  /// installed app; Android refuses to install anything that is not higher.
  final int versionCode;
  final String versionName;
  final String url;
  final String changelog;

  /// 64 hex characters, or null when the release did not carry one.
  final String? sha256;

  /// Null for anything that is not a usable manifest — the caller treats it as
  /// "no update", never as an error.
  static UpdateInfo? parse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      final code = json['versionCode'];
      final name = json['versionName'];
      final url = json['url'];
      final sum = json['sha256'];
      if (code is! int || name is! String || url is! String) return null;
      // The manifest decides what gets downloaded and offered for install.
      if (!url.startsWith('https://')) return null;
      // A malformed sum would silently turn the check off — refuse the lot.
      if (sum != null && !(sum is String && _hex64.hasMatch(sum))) return null;
      final log = json['changelog'];
      return UpdateInfo(
        versionCode: code,
        versionName: name,
        url: url,
        changelog: log is String ? log.trim() : '',
        sha256: sum as String?,
      );
    } on FormatException {
      return null;
    }
  }

  static final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');
}

/// Downloads and reads `version.json`; null when it cannot be had or read.
Future<UpdateInfo?> fetchLatestRelease({String url = updateManifestUrl}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 15));
    return UpdateInfo.parse(body);
  } on Exception {
    // Offline, DNS, timeout, TLS: none of them is the user's problem.
    return null;
  } finally {
    client.close(force: true);
  }
}
