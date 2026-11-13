import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/habit_labels.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/habits/task_actions_sheet.dart';
import 'package:todo_app/widgets/habits/tasks_list.dart';
import 'package:todo_app/widgets/list_card.dart';
import 'package:todo_app/widgets/page_header.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/add_button.dart';

import 'projects_state.dart';
import 'projects_tab.dart';

final _projectSectionsProvider =
    StreamProvider.family<List<Section>, ({String userId, String projectId})>(
      (ref, scope) => ref
          .watch(sectionsDaoProvider)
          .watchSections(userId: scope.userId, projectId: scope.projectId),
    );

enum _SectionAction { rename, delete }

class ProjectDetailsPage extends ConsumerStatefulWidget {
  const ProjectDetailsPage({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<ProjectDetailsPage> createState() => _ProjectDetailsPageState();
}

class _ProjectDetailsPageState extends ConsumerState<ProjectDetailsPage> {
  static const _unsectionedGroupId = '__unsectioned__';

  final _expanded = <int>{};
  final _collapsedSections = <String>{};
  bool _archiving = false;

  Future<void> _archive() async {
    if (_archiving) return;
    final confirmed = await showConfirmDialog(
      context,
      icon: LucideIcons.archive,
      title: 'Архивировать проект?',
      body:
          'Проект будет перемещён в архив. Все задачи и их прогресс сохранятся.',
      action: 'Архивировать',
      destructive: false,
    );
    if (!mounted || !confirmed || _archiving) return;
    setState(() => _archiving = true);
    await ref.read(projectsStateProvider.notifier).archive(widget.projectId);
    if (!mounted) return;
    final error = ref.read(projectsStateProvider).error;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _archiving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось архивировать проект')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    final notifier = ref.read(projectsStateProvider.notifier);
    await notifier.loadProject(widget.projectId);
    if (mounted && ref.read(projectsStateProvider).error == null) {
      await notifier.loadTasks(widget.projectId);
    }
  }

  Future<void> _addTask() async {
    await showCreateTaskSheet(context, initialProjectUid: widget.projectId);
    if (mounted) await _load();
  }

  Future<void> _createSection(List<Section> sections, String? userId) async {
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы создавать разделы.')),
      );
      return;
    }
    final name = await showTextPromptDialog(
      context,
      title: 'Новый раздел',
      hint: 'Название раздела',
      action: 'Создать',
      asBottomSheet: true,
    );
    if (!mounted || name == null) return;
    await ref
        .read(sectionsDaoProvider)
        .createSection(
          userId: userId,
          projectId: widget.projectId,
          name: name,
          position: sections.length,
        );
  }

  Future<void> _showSectionActions(Section section, String userId) async {
    final action = await showActionsSheet<_SectionAction>(
      context,
      title: section.name,
      actions: const [
        SheetAction(
          icon: LucideIcons.pencil,
          label: 'Переименовать',
          value: _SectionAction.rename,
        ),
        SheetAction(
          icon: LucideIcons.trash_2,
          label: 'Удалить',
          value: _SectionAction.delete,
          destructive: true,
        ),
      ],
    );
    if (!mounted || action == null) return;

    final dao = ref.read(sectionsDaoProvider);
    if (action == _SectionAction.rename) {
      final name = await showTextPromptDialog(
        context,
        title: 'Переименовать раздел',
        hint: 'Название раздела',
        initial: section.name,
        action: 'Сохранить',
      );
      if (!mounted || name == null || name == section.name) return;
      await dao.updateSection(
        id: section.id,
        userId: userId,
        projectId: widget.projectId,
        name: name,
      );
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      icon: LucideIcons.trash_2,
      title: 'Удалить раздел?',
      body:
          'Задачи из раздела «${section.name}» останутся в проекте и перейдут в «Без раздела».',
      action: 'Удалить',
    );
    if (!mounted || !confirmed) return;
    await dao.deleteSection(
      id: section.id,
      userId: userId,
      projectId: widget.projectId,
    );
  }

  Future<void> _reorderSections(
    List<Section> sections,
    int oldIndex,
    int newIndex,
    String userId,
  ) async {
    final reordered = [...sections];
    final section = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, section);
    await ref
        .read(sectionsDaoProvider)
        .reorderSections(
          userId: userId,
          projectId: widget.projectId,
          orderedIds: reordered.map((section) => section.id).toList(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectsStateProvider);
    final project = state.details[widget.projectId];
    final tasks = ref.watch(allTasksProvider).valueOrNull ?? const <Task>[];
    final logs = ref.watch(allLogsProvider).valueOrNull ?? const <TaskLog>[];
    final members = tasks
        .where(
          (task) =>
              task.projectUid == widget.projectId && task.parentId == null,
        )
        .toList();
    final userId = ref.watch(myUidProvider);
    final sections = userId == null
        ? const <Section>[]
        : ref
                  .watch(
                    _projectSectionsProvider((
                      userId: userId,
                      projectId: widget.projectId,
                    )),
                  )
                  .valueOrNull ??
              const <Section>[];
    final sectionIds = sections.map((section) => section.id).toSet();
    final unsectioned = [
      for (final task in members)
        if (task.sectionId == null || !sectionIds.contains(task.sectionId))
          task,
    ];
    final page = state.taskPages[widget.projectId];
    final localUids = tasks.map((task) => task.uid).toSet();
    final missingRemote =
        page?.tasks.any((row) => !localUids.contains(row['id'])) ?? false;
    final color =
        taskSwatchForKey(project?.color)?.accent ??
        Theme.of(context).colorScheme.primary;

    Widget body;
    if (project == null && state.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (project == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить проект'),
            TextButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      );
    } else {
      final stats = project.statistics;
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (project.description != null && project.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(project.description!),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stats.completed} из ${stats.total} задач выполнено · ${stats.progress}%',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (stats.progress / 100).clamp(0.0, 1.0),
                  color: color,
                  backgroundColor: AppPalette.of(Theme.of(context)).chip,
                ),
              ],
            ),
          ),
          if (state.error != null)
            TextButton(
              onPressed: _load,
              child: const Text('Не удалось загрузить задачи. Повторить'),
            ),
          if (missingRemote || (page?.hasMore ?? false))
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Не все задачи проекта доступны на устройстве. Синхронизируйте данные.',
              ),
            ),
          if (members.isEmpty &&
              sections.isEmpty &&
              !state.isLoading &&
              !missingRemote &&
              !(page?.hasMore ?? false))
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('В проекте пока нет задач'),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('create-project-section'),
              onPressed: () => _createSection(sections, userId),
              icon: const Icon(Icons.add),
              label: const Text('Создать раздел'),
            ),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: sections.length,
            onReorderItem: userId == null
                ? (_, _) {}
                : (oldIndex, newIndex) =>
                      _reorderSections(sections, oldIndex, newIndex, userId),
            itemBuilder: (context, index) {
              final section = sections[index];
              return _sectionGroup(
                key: ValueKey('reorderable-section-${section.id}'),
                id: section.id,
                title: section.name,
                members: [
                  for (final task in members)
                    if (task.sectionId == section.id) task,
                ],
                tasks: tasks,
                logs: logs,
                color: color,
                reorderIndex: index,
                onActions: userId == null
                    ? null
                    : () => _showSectionActions(section, userId),
              );
            },
          ),
          if (unsectioned.isNotEmpty)
            _sectionGroup(
              id: _unsectionedGroupId,
              title: 'Без раздела',
              members: unsectioned,
              tasks: tasks,
              logs: logs,
              color: color,
            ),
        ],
      );
    }
    return Scaffold(
      floatingActionButton: project == null
          ? null
          : AddButton(tooltip: 'Новая задача', onPressed: _addTask),
      body: SafeArea(
        child: Column(
          children: [
            BackHeader(
              title: project?.name ?? 'Проект',
              trailingWidth: project == null ? 44 : 96,
              trailing: project == null
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _archiving
                            ? const SizedBox.square(
                                dimension: 44,
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : RoundIconButton(
                                icon: LucideIcons.archive,
                                tooltip: 'Архивировать проект',
                                onPressed: _archive,
                              ),
                        const SizedBox(width: 8),
                        RoundIconButton(
                          icon: LucideIcons.pencil,
                          tooltip: 'Редактировать проект',
                          onPressed: () => showProjectForm(context, project),
                        ),
                      ],
                    ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _sectionGroup({
    Key? key,
    required String id,
    required String title,
    required List<Task> members,
    required List<Task> tasks,
    required List<TaskLog> logs,
    required Color color,
    int? reorderIndex,
    VoidCallback? onActions,
  }) {
    final collapsed = _collapsedSections.contains(id);
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: !collapsed,
          label: '$title, ${members.length}',
          child: InkWell(
            key: Key('project-section-$id'),
            onTap: () => setState(() {
              if (!_collapsedSections.add(id)) _collapsedSections.remove(id);
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  Icon(
                    collapsed
                        ? LucideIcons.chevron_down
                        : LucideIcons.chevron_up,
                    size: 20,
                    color: AppPalette.of(Theme.of(context)).textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.04,
                        color: AppPalette.of(Theme.of(context)).textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '${members.length}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.of(Theme.of(context)).textSecondary,
                    ),
                  ),
                  if (reorderIndex != null)
                    ReorderableDelayedDragStartListener(
                      index: reorderIndex,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(LucideIcons.grip_horizontal, size: 20),
                      ),
                    ),
                  if (onActions != null)
                    IconButton(
                      key: Key('project-section-actions-$id'),
                      tooltip: 'Действия с разделом',
                      icon: Icon(LucideIcons.ellipsis_vertical),
                      onPressed: onActions,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!collapsed)
          for (final task in members) _taskCard(task, tasks, logs, color),
      ],
    );
  }

  Widget _taskCard(
    Task task,
    List<Task> tasks,
    List<TaskLog> logs,
    Color color,
  ) {
    final subtasks = tasks.where((child) => child.parentId == task.id).toList();
    final anchor = task.startDate ?? task.createdAt;
    final date = DateTime(anchor.year, anchor.month, anchor.day);
    bool done(int id) => logs.any(
      (log) =>
          log.taskId == id &&
          log.date.year == date.year &&
          log.date.month == date.month &&
          log.date.day == date.day &&
          log.completed,
    );
    final when = [
      if (task.startDate != null)
        DateFormat('d.MM.yyyy').format(task.startDate!),
      if (task.scheduledTimeMinutes != null)
        clockLabel(task.scheduledTimeMinutes!),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RowsCard(
        horizontalMargin: 0,
        children: [
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TaskRow(
                      accentColor: color,
                      alignTop: true,
                      task: task,
                      when: when,
                      completed: done(task.id),
                      subtasks: subtasks.isEmpty
                          ? null
                          : (
                              subtasks.where((s) => done(s.id)).length,
                              subtasks.length,
                            ),
                      onToggle: () => ref
                          .read(tasksDaoProvider)
                          .toggleCompletion(task.id, date),
                      onTap: () => showTaskActionsSheet(
                        context,
                        task: task,
                        completed: done(task.id),
                      ),
                    ),
                  ),
                  if (subtasks.isNotEmpty)
                    IconButton(
                      tooltip: _expanded.contains(task.id)
                          ? 'Свернуть подзадачи'
                          : 'Показать подзадачи',
                      icon: Icon(
                        _expanded.contains(task.id)
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      onPressed: () => setState(() {
                        if (!_expanded.add(task.id)) _expanded.remove(task.id);
                      }),
                    ),
                ],
              ),
              if (_expanded.contains(task.id))
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 16, 8),
                  child: Column(
                    children: [
                      for (final subtask in subtasks)
                        InkWell(
                          onTap: () => ref
                              .read(tasksDaoProvider)
                              .toggleCompletion(subtask.id, date),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TaskCompletionToggle(
                                  title: subtask.title,
                                  completed: done(subtask.id),
                                  color: color,
                                  onToggle: () => ref
                                      .read(tasksDaoProvider)
                                      .toggleCompletion(subtask.id, date),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      subtask.title,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
