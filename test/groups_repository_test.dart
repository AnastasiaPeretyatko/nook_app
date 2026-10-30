import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/groups/groups_repository.dart';

import 'support/fake_sync_api.dart';

/// The group actions against the server's `/groups/*`: what goes out, what the
/// user reads when it is refused, and the one sync afterwards.
void main() {
  late FakeSyncApi api;
  late int syncs;
  late GroupsRepository repo;

  setUp(() {
    api = FakeSyncApi();
    syncs = 0;
    repo = GroupsRepository(api, () async => syncs++);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('every action is one call, then one sync', () async {
    expect(await repo.createGroup('Семья'), 'group-1');
    expect(await repo.joinGroup('123 456'), 'group-1');
    await repo.renameGroup('g', 'Дом');
    await repo.leaveGroup('g');
    await repo.removeMember('g', 'u');
    await repo.deleteGroup('g');
    await settle();

    expect(api.calls, [
      'createGroup(Семья)',
      'joinGroup(123 456)',
      'renameGroup(g, Дом)',
      'leaveGroup(g)',
      'removeMember(g, u)',
      'deleteGroup(g)',
    ]);
    expect(syncs, 6);
  });

  test('the invite code is asked for on demand and starts no sync', () async {
    expect(await repo.inviteCode('g'), '123456');
    expect(await repo.regenerateInvite('g'), '654321');
    await settle();

    expect(api.calls, ['inviteCode(g)', 'regenerateInviteCode(g)']);
    expect(syncs, 0);
  });

  test('a refusal is told in words and starts no sync', () async {
    final cases = {
      'bad_code': 'Код не подошёл',
      'too_many_requests': 'Слишком много неверных кодов',
      'owner_cannot_leave': 'Владелец не может выйти',
      'not_owner': 'только владелец',
      'not_found': 'Такой группы нет',
      'validation_failed': 'от 1 до 100',
    };
    for (final entry in cases.entries) {
      api.error = ApiException(ApiFailure.server, status: 400, code: entry.key);
      await expectLater(
        repo.joinGroup('1'),
        throwsA(
          isA<GroupActionException>().having(
            (e) => e.message,
            'message',
            contains(entry.value),
          ),
        ),
      );
    }
    await settle();
    expect(syncs, 0);
  });

  test('no network and a dead session each have their own words', () async {
    api.error = const ApiException.offline();
    await expectLater(
      repo.createGroup('x'),
      throwsA(
        isA<GroupActionException>().having(
          (e) => e.message,
          'message',
          'Нет соединения с интернетом',
        ),
      ),
    );

    api.error = const ApiException.signInRequired();
    await expectLater(
      repo.createGroup('x'),
      throwsA(
        isA<GroupActionException>().having(
          (e) => e.message,
          'message',
          'Сначала войдите в аккаунт',
        ),
      ),
    );
  });

  test('a code the app has no words for still gets a plain answer', () async {
    api.error = const ApiException(
      ApiFailure.server,
      status: 500,
      code: 'internal',
    );
    await expectLater(
      repo.leaveGroup('g'),
      throwsA(
        isA<GroupActionException>().having(
          (e) => e.message,
          'message',
          contains('Попробуйте ещё раз'),
        ),
      ),
    );
  });
}
