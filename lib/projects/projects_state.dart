import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/database/app_database.dart'
    show LocalProject, Task, TaskLog;

import 'http_projects_api.dart';
import 'project.dart';
import 'projects_api.dart';
import 'projects_repository.dart';
import 'local_projects_store.dart';

final projectsApiProvider = Provider<ProjectsApi>(
  (ref) => HttpProjectsApi(ref.watch(apiClientProvider)),
);

final localProjectsStoreProvider = Provider<LocalProjectsStore>(
  (ref) => LocalProjectsStore(ref.watch(databaseProvider)),
);

final localProjectsChangesProvider = StreamProvider<List<LocalProject>>(
  (ref) => ref.watch(localProjectsStoreProvider).watchAll(),
);

final projectsRepositoryProvider = Provider<ProjectsRepository>(
  (ref) => ProjectsRepository(
    ref.watch(projectsApiProvider),
    local: ref.watch(localProjectsStoreProvider),
  ),
);

final projectsStateProvider = NotifierProvider<ProjectsNotifier, ProjectsState>(
  ProjectsNotifier.new,
);

/// One source of truth for the server-backed Project list and detail cache.
class ProjectsState {
  const ProjectsState({
    this.projects = const [],
    this.archivedProjects = const [],
    this.details = const {},
    this.taskPages = const {},
    this.isLoading = false,
    this.error,
    this.activeLoaded = false,
    this.archivedLoaded = false,
  });

  final List<Project> projects;
  final List<Project> archivedProjects;
  final Map<String, Project> details;
  final Map<String, ProjectTasksPage> taskPages;
  final bool isLoading;
  final Object? error;
  final bool activeLoaded;
  final bool archivedLoaded;

  ProjectsState copyWith({
    List<Project>? projects,
    List<Project>? archivedProjects,
    Map<String, Project>? details,
    Map<String, ProjectTasksPage>? taskPages,
    bool? isLoading,
    Object? error = _stateUnset,
    bool? activeLoaded,
    bool? archivedLoaded,
  }) => ProjectsState(
    projects: projects ?? this.projects,
    archivedProjects: archivedProjects ?? this.archivedProjects,
    details: details ?? this.details,
    taskPages: taskPages ?? this.taskPages,
    isLoading: isLoading ?? this.isLoading,
    error: identical(error, _stateUnset) ? this.error : error,
    activeLoaded: activeLoaded ?? this.activeLoaded,
    archivedLoaded: archivedLoaded ?? this.archivedLoaded,
  );
}

class ProjectsNotifier extends Notifier<ProjectsState> {
  ProjectsRepository get _repository => ref.read(projectsRepositoryProvider);

  @override
  ProjectsState build() {
    if (ref.watch(projectsRepositoryProvider).local != null) {
      void refreshLocal(Object? _, Object? next) {
        if (state.activeLoaded && !state.isLoading) unawaited(refresh());
      }

      ref.listen(localProjectsChangesProvider, (_, next) {
        if (next.hasValue && state.activeLoaded && !state.isLoading) {
          unawaited(refresh());
        }
      });
      ref.listen<AsyncValue<List<Task>>>(allTasksProvider, refreshLocal);
      ref.listen<AsyncValue<List<TaskLog>>>(allLogsProvider, refreshLocal);
    }
    return const ProjectsState();
  }

  Future<void> load({bool archived = false}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final projects = await _repository.list(archived: archived);
      state = state.copyWith(
        projects: archived ? null : _unique(projects),
        archivedProjects: archived ? _unique(projects) : null,
        details: {
          ...state.details,
          for (final project in projects)
            if (state.details.containsKey(project.id)) project.id: project,
        },
        isLoading: false,
        activeLoaded: archived ? null : true,
        archivedLoaded: archived ? true : null,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  /// Reloads every list that has been requested already.
  Future<void> refresh() async {
    await load();
    if (state.archivedLoaded) await load(archived: true);
  }

  Future<void> loadProject(String projectId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      _storeProject(await _repository.get(projectId));
      state = state.copyWith(isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<Project?> create(CreateProjectRequest request) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final project = await _repository.create(request);
      _storeProject(project);
      state = state.copyWith(isLoading: false);
      return project;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
      return null;
    }
  }

  Future<void> update(String projectId, UpdateProjectRequest request) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      _storeProject(await _repository.update(projectId, request));
      state = state.copyWith(isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> archive(String projectId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      _storeProject(await _repository.archive(projectId));
      state = state.copyWith(isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> restore(String projectId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      _storeProject(await _repository.restore(projectId));
      state = state.copyWith(isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> loadTasks(
    String projectId, {
    bool? completed,
    int? limit,
    int? offset,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repository.tasks(
        projectId,
        completed: completed,
        limit: limit,
        offset: offset,
      );
      state = state.copyWith(
        taskPages: {...state.taskPages, projectId: page},
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  /// Call after a task is confirmed by the task/sync layer.
  ///
  /// Refreshing only the affected projects avoids a second task store while
  /// ensuring server-calculated counts cannot remain stale after completion,
  /// deletion, creation, association removal, or reassignment.
  Future<void> taskChanged({
    String? previousProjectId,
    String? projectId,
  }) async {
    final affected = {previousProjectId, projectId}.nonNulls.toSet();
    if (affected.isEmpty) return;
    final pages = Map<String, ProjectTasksPage>.from(state.taskPages);
    for (final id in affected) {
      pages.remove(id);
    }
    state = state.copyWith(taskPages: pages, isLoading: true, error: null);
    try {
      final refreshed = await Future.wait([
        for (final id in affected) _repository.get(id),
      ]);
      for (final project in refreshed) {
        _storeProject(project);
      }
      state = state.copyWith(isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> taskCreated(String? projectId) =>
      taskChanged(projectId: projectId);

  Future<void> taskCompleted(String? projectId) =>
      taskChanged(projectId: projectId);

  Future<void> taskDeleted(String? projectId) =>
      taskChanged(projectId: projectId);

  Future<void> taskReassigned({String? from, String? to}) =>
      taskChanged(previousProjectId: from, projectId: to);

  void _storeProject(Project project) {
    final details = {...state.details, project.id: project};
    if (project.isArchived) {
      state = state.copyWith(
        projects: _without(state.projects, project.id),
        archivedProjects: _upsert(state.archivedProjects, project),
        details: details,
      );
    } else {
      state = state.copyWith(
        projects: _upsert(state.projects, project),
        archivedProjects: _without(state.archivedProjects, project.id),
        details: details,
      );
    }
  }
}

List<Project> _unique(Iterable<Project> projects) {
  final byId = <String, Project>{};
  for (final project in projects) {
    byId[project.id] = project;
  }
  return byId.values.toList(growable: false);
}

List<Project> _without(Iterable<Project> projects, String id) => [
  for (final project in projects)
    if (project.id != id) project,
];

List<Project> _upsert(Iterable<Project> projects, Project next) => [
  ..._without(projects, next.id),
  next,
];

class _StateUnset {
  const _StateUnset();
}

const _stateUnset = _StateUnset();
