import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/group_events.dart';

/// What other members just did in this account's groups, for a toast.
///
/// Rebuilt whenever the mirror changes — which is what a sync, started by a
/// Realtime event or by anything else, does to it — and compares with what it
/// saw the time before. The first run only takes the baseline, so opening the
/// app announces nothing that is already on the phone.
///
/// State is the events **new since the last run**: usually empty, and a listener
/// is meant to look only at the non-empty ones.
final groupEventsProvider =
    NotifierProvider<GroupEventsNotifier, List<GroupEvent>>(
      GroupEventsNotifier.new,
    );

class GroupEventsNotifier extends Notifier<List<GroupEvent>> {
  GroupSeen? _seen;

  @override
  List<GroupEvent> build() {
    final tasks = ref.watch(allTasksProvider).valueOrNull;
    final marks = ref.watch(groupMarksProvider).valueOrNull;
    final members = ref.watch(groupMembersProvider).valueOrNull;
    final groups = ref.watch(groupsProvider).valueOrNull;
    final me = ref.watch(myUidProvider);
    // Wait until everything has a value: a half-loaded mirror would read as
    // "every task is new".
    if (tasks == null || marks == null || members == null || groups == null) {
      return const [];
    }

    final result = groupEventsSince(
      _seen ?? const GroupSeen(),
      me: me,
      now: DateTime.now(),
      tasks: tasks,
      marks: marks,
      members: members,
      groups: groups,
    );
    final first = _seen == null;
    _seen = result.seen;
    return first ? const [] : result.events;
  }
}
