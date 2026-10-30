import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/api/sync_api.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/notifications/permission_prompt.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/sync_controller.dart';

/// What a group action failed with, already in words for the screen.
class GroupActionException implements Exception {
  const GroupActionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Creating, joining, leaving and managing groups — each one call to the
/// server's `/groups/*`, then a sync so the screens catch up (the list of groups
/// itself only ever comes down inside a pull).
///
/// Needs the network, unlike a task edit: these are not queued. A group is a
/// thing several accounts agree on, and there is nothing useful to show for one
/// the server has not accepted yet. Repeating a call is harmless — leaving,
/// removing and deleting answer 204 again — so a lost answer can simply be
/// retried by the user.
class GroupsRepository {
  GroupsRepository(this._api, this._afterChange, {this.onFirstGroup});

  final SyncApi _api;
  final Future<void> Function() _afterChange;

  /// Called after a group was created or joined — the moment pushes about it
  /// become possible, and so the moment to ask for the permission to show them.
  final Future<void> Function()? onFirstGroup;

  Future<String> createGroup(String name) => _call(() async {
    final id = await _api.createGroup(name);
    unawaited(onFirstGroup?.call());
    return id;
  });

  /// Returns the id of the group joined. A wrong code is `bad_code`; ten wrong
  /// ones within the hour lock the account out, and then even the right code is
  /// refused until it passes (`too_many_requests`).
  Future<String> joinGroup(String code) => _call(() async {
    final id = await _api.joinGroup(code);
    unawaited(onFirstGroup?.call());
    return id;
  });

  Future<void> renameGroup(String groupUid, String name) =>
      _call(() => _api.renameGroup(groupUid, name));

  Future<void> leaveGroup(String groupUid) =>
      _call(() => _api.leaveGroup(groupUid));

  Future<void> removeMember(String groupUid, String userUid) =>
      _call(() => _api.removeMember(groupUid, userUid));

  Future<void> deleteGroup(String groupUid) =>
      _call(() => _api.deleteGroup(groupUid));

  /// The code to hand out — the group's owner only. Asked for when the owner
  /// taps "Пригласить", never in advance: it is not part of any pull.
  Future<String?> inviteCode(String groupUid) =>
      _guard(() => _api.inviteCode(groupUid));

  Future<String> regenerateInvite(String groupUid) =>
      _guard(() => _api.regenerateInviteCode(groupUid));

  Future<T> _call<T>(Future<T> Function() body) => _guard(() async {
    final result = await body();
    // Not awaited by the screen's spinner: the action itself is done, and
    // a slow sync must not make it look as if it were still going.
    unawaited(_afterChange());
    return result;
  });

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ApiException catch (error) {
      throw GroupActionException(_textFor(error));
    } catch (error) {
      if (ApiException.isNetworkError(error)) {
        throw const GroupActionException(_offlineText);
      }
      rethrow;
    }
  }
}

const _offlineText = 'Нет соединения с интернетом';

String _textFor(ApiException error) {
  if (error.isOffline) return _offlineText;
  if (error.failure == ApiFailure.signInRequired) {
    return 'Сначала войдите в аккаунт';
  }
  return groupErrorText(error.code ?? '');
}

/// The server's error codes, as the user should read them.
String groupErrorText(String serverCode) {
  for (final (word, text) in const [
    ('validation_failed', 'Название — от 1 до 100 символов'),
    ('bad_code', 'Код не подошёл. Проверьте его у владельца группы'),
    ('not_owner', 'Это может только владелец группы'),
    ('too_many_requests', 'Слишком много неверных кодов. Попробуйте через час'),
    ('owner_cannot_leave', 'Владелец не может выйти — только удалить группу'),
    (
      'not_found',
      'Такой группы нет: её могли удалить или вас из неё убрали. '
          'Потяните вниз, чтобы обновить',
    ),
  ]) {
    if (serverCode == word) return text;
  }
  return 'Не получилось. Попробуйте ещё раз';
}

/// Null while nobody is signed in, which is every widget test that does not
/// ask for one.
final groupsRepositoryProvider = Provider<GroupsRepository?>((ref) {
  if (ref.watch(currentUserProvider) == null) return null;
  return GroupsRepository(
    ref.watch(syncApiProvider),
    () => ref.read(syncControllerProvider).syncNow(),
    onFirstGroup: () =>
        ref.read(offerNotificationPermissionProvider)(NotificationAsk.group),
  );
});
