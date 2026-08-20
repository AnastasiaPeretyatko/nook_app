import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/settings/app_version.dart';

void main() {
  test('the version in settings is the version in pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));

    expect(appVersion, line.substring('version:'.length).trim());
  });

  test('the label spells the build number out', () {
    expect(appVersionLabel, matches(RegExp(r'^\d+\.\d+\.\d+( \(\d+\))?$')));
  });
}
