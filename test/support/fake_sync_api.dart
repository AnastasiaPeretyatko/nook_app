import 'package:todo_app/api/sync_api.dart';

/// A server that lives in a list. Every call is written to [calls] as
/// `name(args)`; set [error] to make every call throw it (an `ApiException`
/// for "no connection", say).
class FakeSyncApi implements SyncApi {
  final calls = <String>[];

  /// What `pull` answers, one per call; the last one repeats.
  final pullAnswers = <Map<String, dynamic>>[
    {
      'next': null,
      'has_more': false,
      'tasks': [],
      'logs': [],
      'groups': {'groups': [], 'members': []},
    },
  ];

  /// The bodies given to `push`, in order.
  final pushed = <Map<String, dynamic>>[];

  /// What `push` answers (`rejected` lists what the "server" refused).
  List<Map<String, dynamic>> rejected = [];

  Object? error;

  var _pulls = 0;

  T _call<T>(String call, T answer) {
    calls.add(call);
    if (error != null) throw error!;
    return answer;
  }

  @override
  Future<Map<String, dynamic>> pull({
    String? since,
    Set<String> include = const {},
    int limit = 500,
  }) async {
    final answer =
        pullAnswers[_pulls < pullAnswers.length
            ? _pulls
            : pullAnswers.length - 1];
    _pulls++;
    return _call(
      'pull(since: $since, include: ${(include.toList()..sort()).join(',')}, limit: $limit)',
      answer,
    );
  }

  @override
  Future<Map<String, dynamic>> push(Map<String, dynamic> body) async {
    pushed.add(body);
    return _call('push', {
      'rejected': rejected,
      'server_time': '2026-01-01T00:00:00.000000Z',
    });
  }

  @override
  Future<String> createGroup(String name) async =>
      _call('createGroup($name)', 'group-1');

  @override
  Future<void> renameGroup(String groupId, String name) async =>
      _call('renameGroup($groupId, $name)', null);

  @override
  Future<String> joinGroup(String code) async =>
      _call('joinGroup($code)', 'group-1');

  @override
  Future<void> leaveGroup(String groupId) async =>
      _call('leaveGroup($groupId)', null);

  @override
  Future<void> removeMember(String groupId, String memberId) async =>
      _call('removeMember($groupId, $memberId)', null);

  @override
  Future<void> deleteGroup(String groupId) async =>
      _call('deleteGroup($groupId)', null);

  @override
  Future<String> inviteCode(String groupId) async =>
      _call('inviteCode($groupId)', '123456');

  @override
  Future<String> regenerateInviteCode(String groupId) async =>
      _call('regenerateInviteCode($groupId)', '654321');

  @override
  Future<void> registerDevice(String token) async =>
      _call('registerDevice($token)', null);

  @override
  Future<void> unregisterDevice(String token) async =>
      _call('unregisterDevice($token)', null);

  @override
  Future<Map<String, dynamic>> updateProfile({
    required String? displayName,
    required String? avatarUrl,
  }) async => _call('updateProfile($displayName, $avatarUrl)', {
    'id': 'u',
    'email': 'a@b.c',
    'displayName': displayName,
    'avatarUrl': avatarUrl,
  });
}
