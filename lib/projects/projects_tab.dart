import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/empty_screen.dart';
import 'package:todo_app/widgets/list_card.dart';
import 'package:todo_app/widgets/page_header.dart';
import 'package:todo_app/widgets/habits/tasks_list.dart';

import 'project.dart';
import 'projects_state.dart';
import 'project_details_page.dart';

Future<Project?> showProjectForm(BuildContext context, [Project? project]) =>
    showModalBottomSheet<Project>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProjectForm(project: project),
    );

class ProjectsTab extends ConsumerStatefulWidget {
  const ProjectsTab({super.key, this.headerFooter});

  final Widget? headerFooter;

  @override
  ConsumerState<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends ConsumerState<ProjectsTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted && !ref.read(projectsStateProvider).activeLoaded) {
        ref.read(projectsStateProvider.notifier).load();
      }
    });
  }

  void _form([Project? project]) {
    showProjectForm(context, project);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      PageHeader(
        caption: 'Активные проекты',
        title: 'Проекты',
        actions: [
          RoundIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Создать проект',
            onPressed: _form,
          ),
          RoundIconButton(
            icon: LucideIcons.archive,
            tooltip: 'Архив проектов',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CompletedTasksPage(initialTab: 1),
              ),
            ),
          ),
        ],
      ),
      if (widget.headerFooter != null) widget.headerFooter!,
      Expanded(child: _content(context)),
    ],
  );

  Widget _content(BuildContext context) {
    final state = ref.watch(projectsStateProvider);
    if (!state.activeLoaded && state.error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.activeLoaded && state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить проекты'),
            TextButton(
              onPressed: () => ref.read(projectsStateProvider.notifier).load(),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    final projects = state.projects
        .where((project) => !project.isArchived)
        .toList();
    if (projects.isEmpty) {
      return EmptyScreen(
        family: 'blue',
        icon: LucideIcons.folder,
        title: 'Пока нет проектов',
        body:
            'Объединяйте связанные задачи в проекты и отслеживайте их выполнение.',
        actionLabel: 'Создать проект',
        onAction: () => _form(),
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(projectsStateProvider.notifier).load(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        itemCount: projects.length,
        itemBuilder: (context, index) {
          final project = projects[index];
          final color =
              taskSwatchForKey(project.color)?.accent ??
              Theme.of(context).colorScheme.primary;
          final stats = project.statistics;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RowsCard(
              horizontalMargin: 0,
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProjectDetailsPage(projectId: project.id),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                    child: Row(
                      children: [
                        Icon(LucideIcons.folder, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                project.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${stats.completed} из ${stats.total} задач выполнено',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: (stats.progress / 100).clamp(0.0, 1.0),
                                color: color,
                                backgroundColor: AppPalette.of(
                                  Theme.of(context),
                                ).chip,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${stats.progress}%'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProjectForm extends ConsumerStatefulWidget {
  const _ProjectForm({this.project});
  final Project? project;

  @override
  ConsumerState<_ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends ConsumerState<_ProjectForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  String? _color;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.project?.name ?? '');
    _description = TextEditingController(
      text: widget.project?.description ?? '',
    );
    _color = widget.project?.color;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final notifier = ref.read(projectsStateProvider.notifier);
    final description = _description.text.isEmpty ? null : _description.text;
    final project = widget.project;
    Project? created;
    if (project == null) {
      created = await notifier.create(
        CreateProjectRequest(
          name: _name.text.trim(),
          description: description,
          color: _color,
        ),
      );
    } else {
      await notifier.update(
        project.id,
        UpdateProjectRequest(
          name: _name.text.trim(),
          description: PatchValue(description),
          color: PatchValue(_color),
        ),
      );
    }
    if (!mounted) return;
    final error = ref.read(projectsStateProvider).error;
    if (error == null) {
      setState(() => _saving = false);
      Navigator.of(context).pop(created);
      return;
    }
    setState(() {
      _saving = false;
      _error = error is ApiException && error.isOffline
          ? 'Нет соединения с интернетом'
          : error is ApiException && error.message != null
          ? error.message
          : 'Не удалось сохранить проект. Попробуйте ещё раз.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final ink = taskSwatchForKey(_color)?.accent ?? ColorPickerRow.colors.first;
    final fill = taskBadgeSurface(theme, ink, raisedSurface(theme));
    final strong = taskBadgeInk(theme, ink, fill);
    return PopScope(
      canPop: !_saving,
      child: AppSheet(
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ProjectHeaderButton(
                    tooltip: 'Закрыть',
                    icon: LucideIcons.x,
                    color: palette.textPrimary,
                    onTap: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  widget.project == null
                      ? 'Новый проект'
                      : 'Редактировать проект',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.17,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 44,
                          child: Center(
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : _ProjectHeaderButton(
                          tooltip: 'Сохранить',
                          icon: LucideIcons.check,
                          color: strong,
                          fill: fill,
                          borderColor: ink,
                          onTap: _save,
                        ),
                ),
              ),
            ],
          ),
          Form(
            key: _key,
            child: Column(
              children: [
                TextFormField(
                  key: const Key('project-name'),
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Название'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Введите название'
                      : null,
                ),
                TextFormField(
                  key: const Key('project-description'),
                  controller: _description,
                  enabled: !_saving,
                  maxLength: 50000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Описание'),
                ),
              ],
            ),
          ),
          ColorPickerRow(
            selected: taskSwatchForKey(_color)?.accent,
            onChanged: (color) {
              if (!_saving) setState(() => _color = taskColorKeyOf(color));
            },
          ),
          if (_color != null)
            TextButton(
              onPressed: _saving ? null : () => setState(() => _color = null),
              child: const Text('Без цвета'),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}

class _ProjectHeaderButton extends StatelessWidget {
  const _ProjectHeaderButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.fill,
    this.borderColor,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Color? fill;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return Tooltip(
      message: tooltip,
      child: Material(
        color: fill ?? palette.surface,
        shape: CircleBorder(
          side: BorderSide(
            color: borderColor ?? palette.borderStrong,
            width: borderColor == null ? 1 : 1.5,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
