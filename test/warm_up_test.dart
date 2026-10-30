import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo_app/api/warm_up.dart';

void main() {
  test('asks /health without a token', () async {
    final seen = <http.Request>[];
    warmUpServer(
      client: MockClient((req) async {
        seen.add(req);
        return http.Response('{"ok":true}', 200);
      }),
      baseUrl: 'https://x.test',
    );
    await Future<void>.delayed(Duration.zero);
    expect(seen.single.url.toString(), 'https://x.test/health');
    expect(seen.single.headers.containsKey('authorization'), isFalse);
  });

  test('a dead network is swallowed', () async {
    warmUpServer(
      client: MockClient((_) async => throw const SocketException('down')),
      baseUrl: 'https://x.test',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
}
