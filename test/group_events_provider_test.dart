import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/groups/group_events_provider.dart';
import 'package:todo_app/utils/group_events.dart';

/// The provider keeps its own memory: the first look only takes a baseline, and
/// later changes of the mirror are what it announces.
void main() {
  final now = DateTime.now();

  Task task(int id, {String? assignee}) => Task(
    id: id,
    uid: 't$id',
    dirty: false,
    title: 'Оплатить коммуналку',
    status: TaskStatus.active,
    trackingMode: TrackingMode.checkbox,
    createdAt: now,
    updatedAt: now,
    groupUid: 'g',
    assigneeUid: assignee,
    authorUid: 'anya',
  );

  test(
    'opening the app announces nothing; a task that arrives later does',
    () async {
      final tasks = StreamController<List<Task>>();
      final container = ProviderContainer(
        overrides: [
          myUidProvider.overrideWithValue('me'),
          allTasksProvider.overrideWith((ref) => tasks.stream),
          groupMarksProvider.overrideWith((ref) => Stream.value(const [])),
          groupsProvider.overrideWith(
            (ref) => Stream.value(const [
              TaskGroup(uid: 'g', name: 'Семья', ownerUid: 'anya'),
            ]),
          ),
          groupMembersProvider.overrideWith(
            (ref) => Stream.value(const [
              GroupMember(groupUid: 'g', userUid: 'anya', displayName: 'Аня'),
            ]),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await tasks.close();
      });

      final heard = <List<GroupEvent>>[];
      container.listen(groupEventsProvider, (_, e) {
        if (e.isNotEmpty) heard.add(e);
      }, fireImmediately: true);

      // What is on the phone already — even a fresh task made by someone else.
      tasks.add([task(1, assignee: 'me')]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(heard, isEmpty);

      tasks.add([task(1, assignee: 'me'), task(2)]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(heard, hasLength(1));
      expect(heard.single.single.headline, 'Новая задача для всех от Аня');
    },
  );
}
