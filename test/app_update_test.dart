import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/update/app_update.dart';

String _manifest([Map<String, Object?> patch = const {}]) => jsonEncode({
  'versionCode': 5,
  'versionName': '1.0.4',
  'url': 'https://github.com/o/r/releases/download/v1.0.4/app-release.apk',
  'changelog': ' Что нового ',
  'sha256': 'a' * 64,
  ...patch,
});

void main() {
  group('UpdateInfo.parse', () {
    test('reads a full manifest', () {
      final info = UpdateInfo.parse(_manifest())!;
      expect(info.versionCode, 5);
      expect(info.versionName, '1.0.4');
      expect(info.changelog, 'Что нового');
      expect(info.sha256, 'a' * 64);
    });

    test('changelog and sha256 are optional', () {
      final info = UpdateInfo.parse(
        _manifest({'changelog': null, 'sha256': null}),
      )!;
      expect(info.changelog, '');
      expect(info.sha256, isNull);
    });

    test('refuses what it cannot trust', () {
      expect(UpdateInfo.parse('not json'), isNull);
      expect(UpdateInfo.parse('[1]'), isNull);
      expect(UpdateInfo.parse(_manifest({'versionCode': '5'})), isNull);
      expect(UpdateInfo.parse(_manifest({'versionName': null})), isNull);
      expect(UpdateInfo.parse(_manifest({'url': 'http://x/app.apk'})), isNull);
      expect(UpdateInfo.parse(_manifest({'sha256': 'abc'})), isNull);
    });
  });

  group('fetchLatestRelease', () {
    late HttpServer server;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        switch (r.uri.path) {
          // Like GitHub: /latest/download/… answers with a redirect.
          case '/latest':
            r.response
              ..statusCode = HttpStatus.found
              ..headers.set(HttpHeaders.locationHeader, '/real')
              ..close();
          case '/real':
            r.response
              ..write(_manifest())
              ..close();
          default:
            r.response
              ..statusCode = HttpStatus.notFound
              ..close();
        }
      });
    });
    tearDown(() => server.close(force: true));

    String at(String path) =>
        'http://${server.address.host}:${server.port}$path';

    test('follows a redirect', () async {
      expect((await fetchLatestRelease(url: at('/latest')))?.versionCode, 5);
    });

    test('a 404 or a dead server is just "no update"', () async {
      expect(await fetchLatestRelease(url: at('/nope')), isNull);
      final dead = at('/latest');
      await server.close(force: true);
      expect(await fetchLatestRelease(url: dead), isNull);
    });
  });
}
