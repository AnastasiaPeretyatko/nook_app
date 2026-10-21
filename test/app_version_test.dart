import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:todo_app/settings/app_version.dart';

Future<String> _label(String version, String build) {
  PackageInfo.setMockInitialValues(
    appName: 'Nook',
    packageName: 'com.yourname.todo_app',
    version: version,
    buildNumber: build,
    buildSignature: '',
  );
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container.read(appVersionLabelProvider.future);
}

void main() {
  test('the footer shows the installed version and build', () async {
    expect(await _label('2.0.2', '5'), '2.0.2 (5)');
  });

  test('without a build number it is the bare version', () async {
    expect(await _label('2.0.2', ''), '2.0.2');
  });
}
