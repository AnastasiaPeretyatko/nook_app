import 'api_client.dart';
import 'sync_api.dart';

class HttpSyncApi implements SyncApi {
  HttpSyncApi(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> _map(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async =>
      await _api.request(method, path, query: query, body: body)
          as Map<String, dynamic>;

  Future<String> _string(
    String method,
    String path,
    String key, {
    Object? body,
  }) async => (await _map(method, path, body: body))[key] as String;

  @override
  Future<Map<String, dynamic>> pull({
    String? since,
    Set<String> include = const {},
    int limit = 500,
  }) => _map(
    'GET',
    '/sync/pull',
    query: {
      'since': ?since,
      'include': ['tasks', ...include].join(','),
      'limit': '$limit',
    },
  );

  @override
  Future<Map<String, dynamic>> push(Map<String, dynamic> body) =>
      _map('POST', '/sync/push', body: body);

  @override
  Future<String> createGroup(String name) =>
      _string('POST', '/groups', 'id', body: {'name': name});

  @override
  Future<void> renameGroup(String groupId, String name) =>
      _api.request('PATCH', '/groups/$groupId', body: {'name': name});

  @override
  Future<String> joinGroup(String code) =>
      _string('POST', '/groups/join', 'id', body: {'code': code});

  @override
  Future<void> leaveGroup(String groupId) =>
      _api.request('POST', '/groups/$groupId/leave');

  @override
  Future<void> removeMember(String groupId, String memberId) =>
      _api.request('DELETE', '/groups/$groupId/members/$memberId');

  @override
  Future<void> deleteGroup(String groupId) =>
      _api.request('DELETE', '/groups/$groupId');

  @override
  Future<String> inviteCode(String groupId) =>
      _string('GET', '/groups/$groupId/invite', 'code');

  @override
  Future<String> regenerateInviteCode(String groupId) =>
      _string('POST', '/groups/$groupId/invite/regenerate', 'code');

  @override
  Future<void> registerDevice(String token) =>
      _api.request('PUT', '/devices', body: {'token': token});

  @override
  Future<void> unregisterDevice(String token) =>
      _api.request('DELETE', '/devices', body: {'token': token});

  @override
  Future<Map<String, dynamic>> updateProfile({
    required String? displayName,
    required String? avatarUrl,
  }) => _map(
    'PUT',
    '/me/profile',
    body: {'displayName': displayName, 'avatarUrl': avatarUrl},
  );
}
