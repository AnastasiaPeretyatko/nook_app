import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// What the calendar adds to my own tasks: other members' tasks, but only of the
/// groups set to "show all".
void main() {
  final day = DateTime(2026, 10, 21);

  Task task(int id, String group, {String? assignee, String author = 'anya'}) =>
      Task(
        id: id,
        dirty: false,
        title: 'T$id',
        status: TaskStatus.active,
        trackingMode: TrackingMode.checkbox,
        createdAt: day,
        updatedAt: day,
        groupUid: group,
        assigneeUid: assignee,
        authorUid: author,
      );

  Future<List<String>> titles(Set<String> showAll) async {
    SharedPreferences.setMockInitialValues({
      'groups_show_all': showAll.toList(),
    });
    final prefs = await SharedPreferences.getInstance();
    final tasks = [
      task(1, 'g1', assignee: 'misha'), // anya's task for misha
      task(2, 'g1', assignee: 'me'), // mine
      task(3, 'g1'), // for everyone
      task(4, 'g2', assignee: 'misha'), // another group
    ];
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        myUidProvider.overrideWithValue('me'),
        allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
      ],
    );
    addTearDown(c.dispose);
    await c.read(allTasksProvider.future);
    return [for (final t in c.read(othersGroupTasksProvider)) t.title];
  }

  test('nothing is added while no group shows all', () async {
    expect(await titles({}), isEmpty);
  });

  test('a group set to show all adds the tasks that are not mine', () async {
    expect(await titles({'g1'}), ['T1']);
  });
}
