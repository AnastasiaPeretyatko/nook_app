import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/groups/groups_repository.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/pages/account_page.dart';
import 'package:todo_app/settings/group_settings.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/sync_controller.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_audience.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/habits/task_actions_sheet.dart';
import 'package:todo_app/widgets/list_card.dart';
import 'package:todo_app/widgets/member_avatar.dart';
import 'package:todo_app/widgets/page_header.dart';

/// The "Группы" block of the settings screen (`Settings.dc.html`): the groups
/// this account is in, and the two ways into one — making it, or joining it
/// with a code from its owner. Opening a group pushes [GroupPage].
///
/// Lives in the settings list instead of a screen of its own. It asks the
/// database nothing until the account can actually have groups, so a settings
/// screen opened without one never touches it.
class GroupsSection extends ConsumerWidget {
  const GroupsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(groupsRepositoryProvider);
    final me = ref.watch(myUidProvider);
    final active = ref.watch(syncActiveProvider);

    final Widget card;
    if (repo == null || me == null) {
      card = const RowsCard(
        horizontalMargin: 0,
        dividerIndent: 16,
        children: [
          _Hint('Войдите в аккаунт, чтобы создавать группы и вступать в них.'),
        ],
      );
    } else if (!active) {
      // Groups travel only through the sync: without it nothing would arrive.
      card = RowsCard(
        horizontalMargin: 0,
        dividerIndent: 16,
        children: [
          const _Hint(
            'Группам нужна синхронизация — включите её, и группы появятся здесь.',
          ),
          _ActionRow(
            icon: LucideIcons.refresh_cw,
            label: 'Открыть синхронизацию',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AccountPage())),
          ),
        ],
      );
    } else {
      card = _GroupRows(me: me, repo: repo);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(title: 'Группы', horizontalInset: 8),
        card,
      ],
    );
  }
}

/// The rows of the block once groups are possible: each group, then the actions.
class _GroupRows extends ConsumerWidget {
  const _GroupRows({required this.me, required this.repo});

  final String me;
  final GroupsRepository repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider).valueOrNull ?? const <TaskGroup>[];
    final members =
        ref.watch(groupMembersProvider).valueOrNull ?? const <GroupMember>[];
    final tasks = ref.watch(allTasksProvider).valueOrNull ?? const <Task>[];

    return RowsCard(
      horizontalMargin: 0,
      dividerIndent: 16,
      children: [
        for (final group in groups)
          _GroupRow(
            group: group,
            members: [
              for (final m in members)
                if (m.groupUid == group.uid) m,
            ],
            taskCount: tasks
                .where(
                  (t) =>
                      t.groupUid == group.uid && t.status == TaskStatus.active,
                )
                .length,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GroupPage(groupUid: group.uid)),
            ),
          ),
        _ActionRow(
          icon: LucideIcons.plus,
          label: 'Создать группу',
          onTap: () => _create(context, repo),
        ),
        _ActionRow(
          icon: LucideIcons.log_in,
          label: 'Присоединиться',
          onTap: () => _join(context, repo),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, GroupsRepository repo) async {
    final name = await showTextPromptDialog(
      context,
      title: 'Новая группа',
      hint: 'Например, Семья',
      action: 'Создать',
    );
    if (name == null || !context.mounted) return;
    await _run(context, () => repo.createGroup(name), done: 'Группа создана');
  }

  Future<void> _join(BuildContext context, GroupsRepository repo) async {
    final joined = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JoinSheet(join: repo.joinGroup),
    );
    if (joined == true && context.mounted) _snack(context, 'Вы в группе');
  }
}

/// A group: its first members' letters overlapping, its name, and how many
/// people and tasks it has.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.members,
    required this.taskCount,
    required this.onTap,
  });

  final TaskGroup group;
  final List<GroupMember> members;
  final int taskCount;
  final VoidCallback onTap;

  static const _shown = 3;
  static const _size = 30.0;
  static const _overlap = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final faces = members.take(_shown).toList();
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        child: Row(
          children: [
            SizedBox(
              width:
                  _size +
                  (faces.length - 1).clamp(0, _shown) * (_size - _overlap),
              height: _size,
              child: Stack(
                children: [
                  for (final (i, m) in faces.indexed)
                    Positioned(
                      left: i * (_size - _overlap),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: raisedSurface(theme),
                        ),
                        child: MemberAvatar(
                          name: memberName(m),
                          size: _size - 4,
                          accent: memberAccent(m.userUid),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: palette.textPrimary),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${members.length} '
                    '${_plural(members.length, 'участник', 'участника', 'участников')}'
                    ' · $taskCount '
                    '${_plural(taskCount, 'задача', 'задачи', 'задач')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevron_right, size: 16, color: palette.iconMuted),
          ],
        ),
      ),
    );
  }
}

/// A row of the block that does something: the link-coloured "+ Создать группу".
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final link = AppPalette.of(Theme.of(context)).link;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 18, color: link),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: link,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Присоединиться": the six digits of an owner's code, one cell to a digit.
///
/// A single hidden field takes the typing — keyboard, deleting and the system's
/// own one-time-code suggestions all work on it — and the cells only draw what
/// it holds. The sheet stays open on a refusal and says why in place: the server
/// allows only ten wrong codes an hour, so a code is sent on the button and
/// never on the sixth digit by itself.
class _JoinSheet extends StatefulWidget {
  const _JoinSheet({required this.join});

  /// Throws [GroupActionException] with words for the screen when refused.
  final Future<String> Function(String code) join;

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  static const _length = 6;

  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;
  String _typed = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // The controller also fires for a moved cursor or lost focus, which must
      // not wipe a refusal the user has not had time to read.
      if (_controller.text == _typed) return;
      _typed = _controller.text;
      setState(() => _error = null);
    });
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _code => _controller.text;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    _controller.text = digits.length > _length
        ? digits.substring(0, _length)
        : digits;
    _focus.requestFocus();
  }

  Future<void> _submit() async {
    if (_code.length != _length || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.join(_code);
      if (mounted) Navigator.of(context).pop(true);
    } on GroupActionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    // The cell the next digit goes to.
    final current = _code.length.clamp(0, _length - 1);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Material(
        color: raisedSurface(theme),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Вступить в группу',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Введите 6 цифр, которые вам передал владелец группы.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 60,
                  child: Stack(
                    children: [
                      // The field fills the row under the cells, so a tap on any
                      // cell lands on it; its own text and cursor are invisible.
                      Positioned.fill(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          autofocus: true,
                          expands: true,
                          maxLines: null,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(_length),
                          ],
                          style: const TextStyle(color: Colors.transparent),
                          cursorColor: Colors.transparent,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      IgnorePointer(
                        child: Row(
                          children: [
                            for (var i = 0; i < _length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  height: 60,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: palette.surfaceMuted,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _focus.hasFocus && i == current
                                          ? palette.textPrimary
                                          : palette.border,
                                      width: _focus.hasFocus && i == current
                                          ? 1.5
                                          : 1,
                                    ),
                                  ),
                                  child: Text(
                                    i < _code.length ? _code[i] : '',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w600,
                                      color: palette.textPrimary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.textPrimary,
                      foregroundColor: palette.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _code.length == _length && !_busy
                        ? _submit
                        : null,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Вступить'),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _busy ? null : _paste,
                  child: const Text('Вставить из буфера'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One group (`Group.dc.html`): its members, who is doing what, and what its
/// owner can do with it.
class GroupPage extends ConsumerStatefulWidget {
  const GroupPage({super.key, required this.groupUid});

  final String groupUid;

  @override
  ConsumerState<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends ConsumerState<GroupPage> {
  String get groupUid => widget.groupUid;

  /// Whose tasks the list shows: null is everyone's, otherwise a member's uid
  /// (the "Мои" chip is the account's own).
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final repo = ref.watch(groupsRepositoryProvider);
    final me = ref.watch(myUidProvider);
    final group = (ref.watch(groupsProvider).valueOrNull ?? const <TaskGroup>[])
        .where((g) => g.uid == groupUid)
        .firstOrNull;

    if (group == null) {
      // Left, removed or deleted — the next sync took it off the device.
      return Scaffold(
        appBar: AppBar(),
        body: const _Hint('Этой группы больше нет в вашем списке.'),
      );
    }

    final isOwner = group.ownerUid == me;
    final showAllOnDay = ref.watch(
      groupsShowAllProvider.select((s) => s.contains(groupUid)),
    );
    final members = [
      for (final m
          in ref.watch(groupMembersProvider).valueOrNull ??
              const <GroupMember>[])
        if (m.groupUid == groupUid) m,
    ];
    final byUid = {for (final m in members) m.userUid: m};
    final allTasks = [
      for (final t in ref.watch(allTasksProvider).valueOrNull ?? const <Task>[])
        if (t.groupUid == groupUid && t.status == TaskStatus.active) t,
    ]..sort((a, b) => taskAnchorDate(a).compareTo(taskAnchorDate(b)));
    final myLogs = ref.watch(allLogsProvider).valueOrNull ?? const <TaskLog>[];
    final marks = ref.watch(groupMarksProvider).valueOrNull ?? const [];

    bool doneByMe(Task t) => myLogs.any(
      (l) =>
          l.taskId == t.id &&
          l.completed &&
          _sameDay(l.date, taskAnchorDate(t)),
    );
    Set<String> doneBy(Task t) => groupTaskDoneBy(
      t,
      taskAnchorDate(t),
      me: me,
      doneByMe: doneByMe(t),
      marks: marks,
    );
    // Finished for the group: its assignee has done it, or — for everyone — any
    // member has (`myLogs` already counts their ticks, see [withSharedTicks]).
    bool finished(Task t) =>
        t.assigneeUid == null ? doneByMe(t) : doneBy(t).contains(t.assigneeUid);

    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    final thisWeek = [
      for (final t in allTasks)
        if (t.startDate != null &&
            !t.startDate!.isBefore(monday) &&
            t.startDate!.isBefore(nextMonday))
          t,
    ];
    final weekDone = thisWeek.where(finished).length;

    final shown = [
      for (final t in allTasks)
        if (_filter == null ||
            t.assigneeUid == null ||
            t.assigneeUid == _filter)
          t,
    ];
    int countFor(String uid) => allTasks
        .where((t) => t.assigneeUid == null || t.assigneeUid == uid)
        .length;

    return Scaffold(
      backgroundColor: pageSurface(theme),
      body: SafeArea(
        child: Stack(
          children: [
            // Pull down to fetch the group now: a member who has just joined, or
            // has just published their name, shows up without waiting for the
            // next scheduled sync.
            RefreshIndicator(
              onRefresh: () => ref.read(syncControllerProvider).syncNow(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 112),
                children: [
                  BackHeader(
                    title: 'Группа',
                    trailing: repo == null
                        ? null
                        : RoundIconButton(
                            icon: LucideIcons.ellipsis,
                            tooltip: 'Настройки группы',
                            onPressed: () =>
                                _showMenu(context, repo, group, isOwner),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.6,
                            height: 1.2,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          thisWeek.isEmpty
                              ? 'На этой неделе задач нет'
                              : 'На этой неделе выполнено $weekDone из '
                                    '${thisWeek.length} '
                                    '${_plural(thisWeek.length, 'задачи', 'задач', 'задач')}',
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _MembersCard(
                    members: members,
                    me: me,
                    countFor: countFor,
                    onInvite: isOwner && repo != null
                        ? () => _invite(context, repo)
                        : null,
                    onMember: isOwner && repo != null
                        ? (m) =>
                              m.userUid == me ? null : _remove(context, repo, m)
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: RowsCard(
                      children: [
                        ToggleRow(
                          label: 'Все задачи на таймлайне',
                          sub: showAllOnDay
                              ? 'В таймлайне и календаре — все задачи группы'
                              : 'Только назначенные на вас и на всех',
                          value: showAllOnDay,
                          onChanged: (v) => ref
                              .read(groupsShowAllProvider.notifier)
                              .setShowAll(groupUid, v),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _FilterChip(
                          label: 'Все',
                          selected: _filter == null,
                          onTap: () => setState(() => _filter = null),
                        ),
                        if (me != null)
                          _FilterChip(
                            label: 'Мои',
                            selected: _filter == me,
                            onTap: () => setState(() => _filter = me),
                          ),
                        for (final m in members)
                          if (m.userUid != me)
                            _FilterChip(
                              label: memberName(m),
                              selected: _filter == m.userUid,
                              onTap: () => setState(() => _filter = m.userUid),
                            ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: _cardDecoration(theme),
                    child: shown.isEmpty
                        ? const _Hint(
                            'Задач пока нет. Нажмите «+» и создайте первую.',
                          )
                        : Column(
                            children: [
                              for (final (i, task) in shown.indexed) ...[
                                if (i > 0)
                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: palette.divider,
                                  ),
                                _GroupTaskRow(
                                  task: task,
                                  assignee: byUid[task.assigneeUid],
                                  // My own state for what is mine, the assignee's
                                  // for what is not.
                                  done:
                                      task.assigneeUid == null ||
                                          task.assigneeUid == me
                                      ? doneByMe(task)
                                      : doneBy(task).contains(task.assigneeUid),
                                  sharedStatus: task.assigneeUid == null
                                      ? sharedTaskStatus(
                                          task,
                                          taskAnchorDate(task),
                                          me: me,
                                          done: doneByMe(task),
                                          marks: marks,
                                          members: members,
                                        )
                                      : null,
                                  canTick: isMyTask(task, me),
                                  onTick: () => ref
                                      .read(tasksDaoProvider)
                                      .toggleCompletion(
                                        task.id,
                                        taskAnchorDate(task),
                                      ),
                                  onTap: () => showTaskActionsSheet(
                                    context,
                                    task: task,
                                    completed: doneByMe(task),
                                    completionDate: taskAnchorDate(task),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 24,
              bottom: 32,
              child: _AddTaskButton(
                onTap: () =>
                    showCreateTaskSheet(context, initialGroupUid: groupUid),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _invite(BuildContext context, GroupsRepository repo) async {
    String? code;
    try {
      code = await repo.inviteCode(groupUid);
    } on GroupActionException catch (error) {
      if (context.mounted) _snack(context, error.message);
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteSheet(
        initialCode: code,
        regenerate: () => repo.regenerateInvite(groupUid),
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    GroupsRepository repo,
    GroupMember member,
  ) async {
    final sure = await showConfirmDialog(
      context,
      icon: DialogIcons.removeMember,
      title: 'Исключить ${memberName(member)}?',
      body:
          'Задачи, назначенные на этого участника, останутся в группе без исполнителя.',
      action: 'Исключить',
    );
    if (!sure || !context.mounted) return;
    await _run(context, () => repo.removeMember(groupUid, member.userUid));
  }

  /// The "⋯" button: what the owner or a member can do with the group itself.
  Future<void> _showMenu(
    BuildContext context,
    GroupsRepository repo,
    TaskGroup group,
    bool isOwner,
  ) async {
    final action = await showActionsSheet<String>(
      context,
      title: group.name,
      actions: [
        if (isOwner) ...const [
          SheetAction(
            icon: LucideIcons.pencil,
            label: 'Переименовать',
            value: 'rename',
          ),
          SheetAction(
            icon: LucideIcons.trash_2,
            label: 'Удалить группу',
            value: 'delete',
            destructive: true,
          ),
        ] else
          const SheetAction(
            icon: LucideIcons.log_out,
            label: 'Выйти из группы',
            value: 'leave',
            destructive: true,
          ),
      ],
    );
    if (action == null || !context.mounted) return;
    await _menu(context, repo, group, action);
  }

  Future<void> _menu(
    BuildContext context,
    GroupsRepository repo,
    TaskGroup group,
    String action,
  ) async {
    switch (action) {
      case 'rename':
        final name = await showTextPromptDialog(
          context,
          title: 'Название группы',
          hint: group.name,
          initial: group.name,
          action: 'Сохранить',
        );
        if (name == null || !context.mounted) return;
        await _run(context, () => repo.renameGroup(groupUid, name));
      case 'delete':
        final sure = await showConfirmDialog(
          context,
          icon: DialogIcons.delete,
          title: 'Удалить группу «${group.name}»?',
          body: 'Все её задачи и отметки удалятся у всех участников.',
          action: 'Удалить',
        );
        if (!sure || !context.mounted) return;
        await _run(context, () => repo.deleteGroup(groupUid));
        if (context.mounted) Navigator.of(context).pop();
      case 'leave':
        final sure = await showConfirmDialog(
          context,
          icon: DialogIcons.leave,
          title: 'Выйти из группы «${group.name}»?',
          body: 'Её задачи пропадут с этого телефона. Вернуться можно по коду.',
          action: 'Выйти',
        );
        if (!sure || !context.mounted) return;
        await _run(context, () => repo.leaveGroup(groupUid));
        if (context.mounted) Navigator.of(context).pop();
    }
  }
}

/// White card with a hairline: the members and the task list.
BoxDecoration _cardDecoration(ThemeData theme) => BoxDecoration(
  color: raisedSurface(theme),
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: AppPalette.of(theme).border),
);

/// The members in a row — a coloured letter, a name, how many tasks they have —
/// and, for the owner, "Пригласить" at its end.
class _MembersCard extends StatelessWidget {
  const _MembersCard({
    required this.members,
    required this.me,
    required this.countFor,
    required this.onInvite,
    required this.onMember,
  });

  final List<GroupMember> members;
  final String? me;
  final int Function(String uid) countFor;

  /// Null for a member who is not the owner: the server shows the code to the
  /// owner only.
  final VoidCallback? onInvite;

  /// The owner tapping a member — to remove them. Null for everyone else.
  final void Function(GroupMember member)? onMember;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDecoration(theme),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in members) ...[
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onMember == null || m.userUid == me
                    ? null
                    : () => onMember!(m),
                child: SizedBox(
                  width: 56,
                  child: Column(
                    children: [
                      MemberAvatar(
                        name: memberName(m),
                        size: 44,
                        accent: memberAccent(m.userUid),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m.userUid == me ? 'Я' : memberName(m),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${countFor(m.userUid)} '
                        '${_plural(countFor(m.userUid), 'задача', 'задачи', 'задач')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
            if (onInvite != null)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onInvite,
                child: SizedBox(
                  width: 76,
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.iconMuted,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          LucideIcons.plus,
                          size: 16,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Пригласить',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: palette.link,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A chip of the "whose tasks" filter: dark when selected, white otherwise.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return Material(
      color: selected ? palette.textPrimary : palette.surface,
      shape: StadiumBorder(
        side: selected
            ? BorderSide.none
            : BorderSide(color: palette.borderStrong),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // `widthFactor`: a chip is as wide as its text, not the whole row.
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: selected ? palette.background : palette.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One task of the group: a ring to tick, the title and when, and who it is for.
class _GroupTaskRow extends StatelessWidget {
  const _GroupTaskRow({
    required this.task,
    required this.assignee,
    required this.done,
    required this.sharedStatus,
    required this.canTick,
    required this.onTick,
    required this.onTap,
  });

  final Task task;
  final GroupMember? assignee;

  /// The ring: my own tick for a task that is mine, the assignee's otherwise.
  final bool done;

  /// "ждёт" / "выполнено: Миша" for a task for everyone; null for the others.
  final String? sharedStatus;

  /// Only a task that is mine can be ticked from here.
  final bool canTick;
  final VoidCallback onTick;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final everyone = task.assigneeUid == null;
    final colour = inkOn(
      raisedSurface(theme),
      task.colorValue != null
          ? Color(task.colorValue!)
          : ColorPickerRow.colors.first,
      minContrast: 3,
    );
    final when =
        _whenLine(task) + (sharedStatus != null ? ' · $sharedStatus' : '');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        child: Row(
          children: [
            Tooltip(
              message: done
                  ? 'Снять отметку: ${task.title}'
                  : 'Отметить выполненной: ${task.title}',
              child: InkResponse(
                onTap: canTick ? onTick : null,
                radius: 22,
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? colour : null,
                        border: done
                            ? null
                            : Border.all(color: colour, width: 2),
                      ),
                      child: done
                          ? Icon(
                              LucideIcons.check,
                              size: 12,
                              color: onBrandFill(colour),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: done
                            ? palette.textTertiary
                            : palette.textPrimary,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      when,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (everyone)
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.chip,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  'Все',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
              )
            else
              Semantics(
                label: 'Для: ${memberName(assignee)}',
                child: MemberAvatar(
                  name: memberName(assignee),
                  size: 26,
                  accent: memberAccent(task.assigneeUid!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Сегодня, 19:00" / "Сб, 17 окт · 2 ч" / "Без даты".
String _whenLine(Task task) {
  final date = task.startDate;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  String day;
  if (date == null) {
    day = 'Без даты';
  } else {
    final diff = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(today).inDays;
    if (diff == 0) {
      day = 'Сегодня';
    } else if (diff == 1) {
      day = 'Завтра';
    } else if (diff == -1) {
      day = 'Вчера';
    } else {
      final weekday = DateFormat('E', 'ru_RU').format(date);
      final pattern = date.year == now.year ? 'd MMM' : 'd MMM yyyy';
      day =
          '${weekday[0].toUpperCase()}${weekday.substring(1)}, '
          '${DateFormat(pattern, 'ru_RU').format(date)}';
    }
  }
  final start = task.scheduledTimeMinutes;
  if (start == null) return day;
  String clock(int m) =>
      '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  final end = task.endTimeMinutes;
  final length = end != null && end > start ? end - start : null;
  final lengthText = length == null
      ? ''
      : ' · ${length ~/ 60 > 0 ? '${length ~/ 60} ч' : ''}'
            '${length ~/ 60 > 0 && length % 60 > 0 ? ' ' : ''}'
            '${length % 60 > 0 ? '${length % 60} мин' : ''}';
  return '$day, ${clock(start)}$lengthText';
}

/// Russian plural form for [n]: 1 задача, 2 задачи, 5 задач.
String _plural(int n, String one, String few, String many) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  final mod10 = n % 10;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}

/// The round dark "+" at the corner: a new task for this group.
class _AddTaskButton extends StatelessWidget {
  const _AddTaskButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Tooltip(
      message: 'Новая задача для группы',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1B2230).withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: palette.textPrimary,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 56,
              child: Icon(
                LucideIcons.plus,
                size: 22,
                color: palette.background,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The owner's invite code, one tile to a digit, with copy and "make a new one".
class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.initialCode, required this.regenerate});

  final String? initialCode;
  final Future<String> Function() regenerate;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  late String? _code = widget.initialCode;
  bool _busy = false;
  bool _copied = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final code = _code;
    return Material(
      color: raisedSurface(theme),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Код приглашения',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Передайте этот код человеку, которого хотите добавить. Он '
                'введёт его в «Группы» → «Вступить в группу».',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
              const SizedBox(height: 20),
              // Six tiles, one per digit. A group with no code yet shows dashes.
              Row(
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.surfaceMuted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          code != null && code.length == 6 ? code[i] : '–',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.textPrimary,
                    foregroundColor: palette.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: code == null
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: code));
                          if (mounted) setState(() => _copied = true);
                        },
                  child: Text(_copied ? 'Скопировано' : 'Скопировать'),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy ? null : _regenerate,
                child: Text(code == null ? 'Создать код' : 'Сменить код'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _regenerate() async {
    setState(() => _busy = true);
    try {
      final code = await widget.regenerate();
      setState(() {
        _code = code;
        _copied = false;
        _error = null;
      });
    } on GroupActionException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Runs a group action and says how it went.
Future<void> _run(
  BuildContext context,
  Future<void> Function() action, {
  String? done,
}) async {
  try {
    await action();
    if (done != null && context.mounted) _snack(context, done);
  } on GroupActionException catch (error) {
    if (context.mounted) _snack(context, error.message);
  }
}
