import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/settings/app_version.dart';

/// Every platform spells the app's name in its own manifest, so the name is
/// only "one" name as long as nobody edits a single file. These read the
/// manifests back and fail when one of them drifts away from [appName].
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Android labels the launcher entry with the app name', () {
    expect(
      read('android/app/src/main/AndroidManifest.xml'),
      contains('android:label="$appName"'),
    );
  });

  test('iOS carries the app name as display name and bundle name', () {
    final plist = read('ios/Runner/Info.plist');

    expect(
      plist,
      contains('<key>CFBundleDisplayName</key>\n\t<string>$appName</string>'),
    );
    expect(
      plist,
      contains('<key>CFBundleName</key>\n\t<string>$appName</string>'),
    );
  });

  test('the web page and its manifest carry the app name', () {
    expect(read('web/index.html'), contains('<title>$appName</title>'));

    final manifest = read('web/manifest.json');
    expect(manifest, contains('"name": "$appName"'));
    expect(manifest, contains('"short_name": "$appName"'));
  });

  test('the desktop window titles carry the app name', () {
    expect(
      read('macos/Runner/Configs/AppInfo.xcconfig'),
      contains('PRODUCT_NAME = $appName'),
    );
    expect(read('linux/runner/my_application.cc'), contains('"$appName"'));
    expect(read('windows/runner/main.cpp'), contains('L"$appName"'));
  });
}
