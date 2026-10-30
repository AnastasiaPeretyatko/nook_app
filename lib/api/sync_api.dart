/// Everything the sync engine and the group screens ask of the server
/// (contract: BACKEND_PLAN.md §4.2–4.4). Rows travel as plain JSON maps: their
/// keys are the ones `lib/sync/payload.dart` already builds and reads.
///
/// An abstract class so that tests talk to `FakeSyncApi` instead of a network;
/// the real one is [HttpSyncApi]. Sign-in is not here — that is `AuthRepository`.
abstract class SyncApi {
  /// `GET /sync/pull`. [since] is an ISO UTC instant with `Z`, or null for
  /// everything; [include] is any of `diary`, `cycle` (`tasks` is implied).
  Future<Map<String, dynamic>> pull({
    String? since,
    Set<String> include = const {},
    int limit = 500,
  });

  /// `POST /sync/push` → `{rejected: [{table, id, reason}], server_time}`.
  Future<Map<String, dynamic>> push(Map<String, dynamic> body);

  /// `POST /groups` → the new group's id.
  Future<String> createGroup(String name);
  Future<void> renameGroup(String groupId, String name);

  /// `POST /groups/join` → the id of the group joined.
  Future<String> joinGroup(String code);
  Future<void> leaveGroup(String groupId);
  Future<void> removeMember(String groupId, String memberId);
  Future<void> deleteGroup(String groupId);

  /// `GET /groups/:id/invite` → the 6-digit code.
  Future<String> inviteCode(String groupId);
  Future<String> regenerateInviteCode(String groupId);

  /// `PUT` / `DELETE /devices`: the FCM token of this phone.
  Future<void> registerDevice(String token);
  Future<void> unregisterDevice(String token);

  /// `PUT /me/profile` — both keys are required, `null` clears one. Returns
  /// the `user` object.
  Future<Map<String, dynamic>> updateProfile({
    required String? displayName,
    required String? avatarUrl,
  });
}
