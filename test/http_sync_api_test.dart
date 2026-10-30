import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo_app/api/api_client.dart';
import 'package:todo_app/api/http_sync_api.dart';
import 'package:todo_app/api/token_store.dart';

void main() {
  // Each call -> the request the server must see, and the answer it gives.
  late List<String> seen;
  late HttpSyncApi api;

  setUp(() {
    seen = [];
    api = HttpSyncApi(
      ApiClient(
        baseUrl: 'https://x.test',
        tokens: MemoryTokenStore(accessToken: 'a', refreshToken: 'r'),
        client: MockClient((req) async {
          seen.add(
            '${req.method} ${req.url.path}'
            '${req.url.hasQuery ? '?${req.url.query}' : ''} ${req.body}',
          );
          final body = switch (req.url.path) {
            '/groups' || '/groups/join' => {'id': 'g1'},
            final p when p.endsWith('/invite') || p.endsWith('/regenerate') => {
              'code': '123456',
            },
            _ => {'rejected': [], 'id': 'u'},
          };
          return req.method == 'GET' ||
                  req.url.path == '/groups' ||
                  req.url.path == '/groups/join' ||
                  req.url.path.endsWith('/regenerate') ||
                  req.url.path.startsWith('/sync') ||
                  req.url.path == '/me/profile'
              ? http.Response(jsonEncode(body), 200)
              : http.Response('', 204);
        }),
      ),
    );
  });

  test('pull always asks for tasks and leaves out an empty since', () async {
    await api.pull(include: {'diary', 'cycle'}, limit: 50);
    await api.pull(since: '2026-01-01T00:00:00.000000Z');
    expect(seen, [
      'GET /sync/pull?include=tasks%2Cdiary%2Ccycle&limit=50 ',
      'GET /sync/pull?since=2026-01-01T00%3A00%3A00.000000Z&include=tasks&limit=500 ',
    ]);
  });

  test('push, groups, devices and profile hit the contract routes', () async {
    await api.push({'tasks': []});
    expect(await api.createGroup('Дом'), 'g1');
    expect(await api.joinGroup('123-456'), 'g1');
    await api.renameGroup('g', 'N');
    await api.leaveGroup('g');
    await api.removeMember('g', 'm');
    await api.deleteGroup('g');
    expect(await api.inviteCode('g'), '123456');
    expect(await api.regenerateInviteCode('g'), '123456');
    await api.registerDevice('tok');
    await api.unregisterDevice('tok');
    await api.updateProfile(displayName: null, avatarUrl: 'https://i/a.png');
    expect(seen.map((s) => s.split(' ').take(2).join(' ')), [
      'POST /sync/push',
      'POST /groups',
      'POST /groups/join',
      'PATCH /groups/g',
      'POST /groups/g/leave',
      'DELETE /groups/g/members/m',
      'DELETE /groups/g',
      'GET /groups/g/invite',
      'POST /groups/g/invite/regenerate',
      'PUT /devices',
      'DELETE /devices',
      'PUT /me/profile',
    ]);
    expect(
      seen.last,
      endsWith('{"displayName":null,"avatarUrl":"https://i/a.png"}'),
    );
  });
}
