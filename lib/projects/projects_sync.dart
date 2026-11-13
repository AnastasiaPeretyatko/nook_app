import 'local_projects_store.dart';
import 'project.dart';
import 'projects_api.dart';

/// Flushes projects before their tasks and downloads the server snapshot.
class ProjectsSync {
  ProjectsSync(this.local, this.api);
  final LocalProjectsStore local;
  final ProjectsApi api;
  final List<Project> _archiveAfterTasks = [];

  Future<void> pull() async {
    final active = await api.getProjects();
    final archived = await api.getProjects(archived: true);
    for (final project in [...active, ...archived]) {
      await local.mergeRemote(project);
    }
  }

  Future<void> beforeTasks() async {
    _archiveAfterTasks.clear();
    for (final project in await local.pending()) {
      final created = await api.createProject(
        CreateProjectRequest(
          id: project.id,
          name: project.name,
          description: project.description,
          color: project.color,
        ),
      );
      if (created.id != project.id) {
        throw StateError('Server did not preserve the project id');
      }
      await api.restoreProject(project.id);
      await api.updateProject(
        project.id,
        UpdateProjectRequest(
          name: project.name,
          description: PatchValue(project.description),
          color: PatchValue(project.color),
        ),
      );
      if (project.isArchived) {
        _archiveAfterTasks.add(project);
      } else {
        await local.markSynced(project.id, project.updatedAt);
      }
    }
  }

  Future<void> afterTasks() async {
    for (final project in _archiveAfterTasks) {
      if (await local.hasPendingTasks(project.id)) continue;
      await api.archiveProject(project.id);
      await local.markSynced(project.id, project.updatedAt);
    }
    _archiveAfterTasks.clear();
  }
}
