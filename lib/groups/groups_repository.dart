import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/sync/sync_controller.dart';

/// What a group action failed with, already in words for the screen.
class GroupActionException implements Exception {
  const GroupActionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Creating, joining, leaving and managing groups — each one call to a server
/// function of `supabase/005_groups.sql`, then a sync so the screens catch up.
///
/// Needs the network, unlike a task edit: these are not queued. A group is a
/// thing several accounts agree on, and there is nothing useful to show for one
/// the server has not accepted yet.
class GroupsRepository {
  GroupsRepository(this._client, this._afterChange);

  final SupabaseClient _client;
  final Future<void> Function() _afterChange;

  Future<String> createGroup(String name) =>
      _call('create_group', {'p_name': name});

  /// Returns the id of the group joined. The server answers a wrong code with
  /// null rather than an error — an error would undo the count of wrong
  /// guesses, see `supabase/006_numeric_invite_codes.sql`.
  Future<String> joinGroup(String code) async {
    final group = await _call<String?>('join_group', {'p_code': code});
    if (group == null) throw GroupActionException(groupErrorText('bad_code'));
    return group;
  }

  Future<void> renameGroup(String groupUid, String name) =>
      _call('rename_group', {'p_group': groupUid, 'p_name': name});

  Future<void> leaveGroup(String groupUid) =>
      _call('leave_group', {'p_group': groupUid});

  Future<void> removeMember(String groupUid, String userUid) =>
      _call('remove_member', {'p_group': groupUid, 'p_user': userUid});

  Future<void> deleteGroup(String groupUid) =>
      _call('delete_group', {'p_group': groupUid});

  /// The code to hand out — readable by the group's owner only.
  Future<String?> inviteCode(String groupUid) => _guard(() async {
    final row = await _client
        .from('group_invites')
        .select('code')
        .eq('group_id', groupUid)
        .maybeSingle();
    return row?['code'] as String?;
  });

  Future<String> regenerateInvite(String groupUid) =>
      _call('regenerate_invite', {'p_group': groupUid});

  Future<T> _call<T>(String function, Map<String, dynamic> params) =>
      _guard(() async {
        final result = await _client.rpc(function, params: params);
        // Not awaited by the screen's spinner: the action itself is done, and
        // a slow sync must not make it look as if it were still going.
        unawaited(_afterChange());
        return result as T;
      });

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (error) {
      throw GroupActionException(groupErrorText(error.message));
    } on SocketException {
      throw const GroupActionException('Нет соединения с интернетом');
    } on TimeoutException {
      throw const GroupActionException('Нет соединения с интернетом');
    } on AuthRetryableFetchException {
      throw const GroupActionException('Нет соединения с интернетом');
    }
  }
}

/// The server's fixed error words, as the user should read them.
String groupErrorText(String serverMessage) {
  for (final (word, text) in const [
    ('not_signed_in', 'Сначала войдите в аккаунт'),
    ('bad_name', 'Название — от 1 до 100 символов'),
    ('bad_code', 'Код не подошёл. Проверьте его у владельца группы'),
    ('not_owner', 'Это может только владелец группы'),
    ('too_many_attempts', 'Слишком много неверных кодов. Попробуйте через час'),
    ('owner_cannot_leave', 'Владелец не может выйти — только удалить группу'),
  ]) {
    if (serverMessage.contains(word)) return text;
  }
  return 'Не получилось: $serverMessage';
}

/// Null when Supabase never came up, which is every widget test.
final groupsRepositoryProvider = Provider<GroupsRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return GroupsRepository(
    client,
    () => ref.read(syncControllerProvider).syncNow(),
  );
});
