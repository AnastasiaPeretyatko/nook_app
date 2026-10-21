import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/task_audience.dart';

/// Something another member did in a group that is worth a toast.
class GroupEvent {
  const GroupEvent({
    required this.completed,
    required this.taskTitle,
    required this.groupUid,
    required this.groupName,
    required this.actorUid,
    required this.actorName,
    required this.forEveryone,
  });

  /// True for "someone did the task", false for "a task was handed over".
  final bool completed;
  final String taskTitle;
  final String groupUid;
  final String groupName;
  final String actorUid;
  final String actorName;

  /// The task has no assignee: it is for the whole group.
  final bool forEveryone;

  // No verb in the past tense: it would have to agree with the member's gender,
  // which the app does not know.
  String get headline => completed
      ? 'Выполнено: $actorName'
      : forEveryone
      ? 'Новая задача для всех от $actorName'
      : 'Новая задача от $actorName';

  String get subline =>
      groupName.isEmpty ? taskTitle : '$taskTitle · $groupName';
}

/// What the phone knew about group tasks the last time [groupEventsSince] ran.
///
/// Only a record of what has already been told or shown, never stored: it starts
/// from whatever is on the device when the app opens, so nothing that happened
/// while the app was closed is announced.
class GroupSeen {
  const GroupSeen({this.assignees = const {}, this.done = const {}});

  /// Task uid → its assignee's uid (null = for everyone).
  final Map<String, String?> assignees;

  /// `taskUid|member|day` of every other member's mark that is ticked.
  final Set<String> done;
}

/// A task that arrives this long after it was made is not news: it is the
/// backlog coming down after joining a group or signing in.
const _freshFor = Duration(hours: 1);

/// What changed in the groups since [seen], as far as [me] should be told, and
/// the new [GroupSeen] to hand in next time.
///
/// The rule, in one place:
/// * a task made by someone else is news when it is **for me** or **for
///   everyone**; the author is never told about their own task;
/// * a mark by someone else is news when the task is for everyone, or I handed
///   it out myself; the one who ticked is never told;
/// * a task that is itself new brings its marks with it silently.
({List<GroupEvent> events, GroupSeen seen}) groupEventsSince(
  GroupSeen seen, {
  required String? me,
  required DateTime now,
  required List<Task> tasks,
  required List<GroupMark> marks,
  required List<GroupMember> members,
  required List<TaskGroup> groups,
}) {
  final groupTasks = [
    for (final t in tasks)
      if (t.groupUid != null && t.uid != null && t.parentId == null) t,
  ];
  final uidById = {for (final t in groupTasks) t.id: t};
  final groupName = {for (final g in groups) g.uid: g.name};

  String nameOf(String groupUid, String userUid) => memberName(
    members
        .where((m) => m.groupUid == groupUid && m.userUid == userUid)
        .firstOrNull,
  );

  final events = <GroupEvent>[];
  final newTasks = <String>{};

  for (final t in groupTasks) {
    final known = seen.assignees.containsKey(t.uid);
    final reassigned = known && seen.assignees[t.uid] != t.assigneeUid;
    final isNew =
        (!known && now.difference(t.createdAt) < _freshFor) ||
        (reassigned && t.assigneeUid == me);
    if (!known) newTasks.add(t.uid!);

    final author = t.authorUid;
    if (me == null || author == null || author == me) continue;
    if (!isNew || t.status != TaskStatus.active) continue;
    if (t.assigneeUid != me && t.assigneeUid != null) continue;
    events.add(
      GroupEvent(
        completed: false,
        taskTitle: t.title,
        groupUid: t.groupUid!,
        groupName: groupName[t.groupUid] ?? '',
        actorUid: author,
        actorName: nameOf(t.groupUid!, author),
        forEveryone: t.assigneeUid == null,
      ),
    );
  }

  String key(Task t, GroupMark m) => '${t.uid}|${m.userUid}|${m.date}';
  final done = <String>{};
  for (final m in marks) {
    final t = uidById[m.taskId];
    if (t == null || !m.completed) continue;
    final k = key(t, m);
    done.add(k);
    if (seen.done.contains(k) || newTasks.contains(t.uid)) continue;
    if (me == null || m.userUid == me) continue;
    if (t.assigneeUid != null && t.authorUid != me) continue;
    events.add(
      GroupEvent(
        completed: true,
        taskTitle: t.title,
        groupUid: t.groupUid!,
        groupName: groupName[t.groupUid] ?? '',
        actorUid: m.userUid,
        actorName: nameOf(t.groupUid!, m.userUid),
        forEveryone: t.assigneeUid == null,
      ),
    );
  }

  return (
    events: events,
    seen: GroupSeen(
      assignees: {for (final t in groupTasks) t.uid!: t.assigneeUid},
      done: done,
    ),
  );
}
