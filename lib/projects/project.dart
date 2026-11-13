/// A personal project exactly as the Projects API returns it.
///
/// The API intentionally does not expose `user_id`: ownership comes from the
/// bearer token, and the server treats another user's project as not found.
class Project {
  const Project({
    required this.id,
    required this.name,
    this.description,
    this.color,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
    this.statistics = const ProjectStatistics(),
  });

  final String id;
  final String name;
  final String? description;
  final String? color;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final ProjectStatistics statistics;

  bool get isArchived => archivedAt != null;

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: _requiredText(json, 'id'),
    name: _requiredText(json, 'name'),
    description: _nullableText(json, 'description'),
    color: _nullableText(json, 'color'),
    createdAt: _requiredDate(json, 'created_at'),
    updatedAt: _requiredDate(json, 'updated_at'),
    archivedAt: _nullableDate(json, 'archived_at'),
    statistics: ProjectStatistics.fromJson(json),
  );

  Project copyWith({
    String? name,
    Object? description = _unset,
    Object? color = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? archivedAt = _unset,
    ProjectStatistics? statistics,
  }) => Project(
    id: id,
    name: name ?? this.name,
    description: identical(description, _unset)
        ? this.description
        : description as String?,
    color: identical(color, _unset) ? this.color : color as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: identical(archivedAt, _unset)
        ? this.archivedAt
        : archivedAt as DateTime?,
    statistics: statistics ?? this.statistics,
  );
}

/// The live counts the API attaches to every Project response.
class ProjectStatistics {
  const ProjectStatistics({
    this.total = 0,
    this.completed = 0,
    this.progress = 0,
  });

  final int total;
  final int completed;
  final int progress;

  factory ProjectStatistics.fromJson(Map<String, dynamic> json) =>
      ProjectStatistics(
        total: _requiredInt(json, 'total_tasks'),
        completed: _requiredInt(json, 'completed_tasks'),
        progress: _requiredInt(json, 'progress'),
      );

  @override
  bool operator ==(Object other) =>
      other is ProjectStatistics &&
      other.total == total &&
      other.completed == completed &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(total, completed, progress);
}

/// Body for `POST /projects`.
class CreateProjectRequest {
  const CreateProjectRequest({
    this.id,
    required this.name,
    this.description,
    this.color,
  });

  final String? id;
  final String name;
  final String? description;
  final String? color;

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    if (description != null) 'description': description,
    if (color != null) 'color': color,
  };
}

/// A value whose presence matters in a PATCH request.
///
/// `PatchValue(null)` clears a nullable field, while the default absent value
/// leaves it untouched. This mirrors the backend's `undefined`/`null`
/// distinction without making UI code depend on JSON maps.
class PatchValue<T> {
  const PatchValue(this.value) : present = true;
  const PatchValue.absent() : value = null, present = false;

  final T? value;
  final bool present;
}

/// Body for `PATCH /projects/:id`.
class UpdateProjectRequest {
  const UpdateProjectRequest({
    this.name,
    this.description = const PatchValue.absent(),
    this.color = const PatchValue.absent(),
  });

  final String? name;
  final PatchValue<String?> description;
  final PatchValue<String?> color;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (description.present) 'description': description.value,
    if (color.present) 'color': color.value,
  };
}

/// The cursor-style result of `GET /projects/:id/tasks`.
///
/// Tasks stay in the application's existing task/sync model. The endpoint
/// returns task wire maps, so this type owns only the page envelope rather than
/// creating a second task model.
class ProjectTasksPage {
  const ProjectTasksPage({
    this.tasks = const [],
    this.hasMore = false,
    this.nextOffset,
  });

  final List<Map<String, dynamic>> tasks;
  final bool hasMore;
  final int? nextOffset;

  factory ProjectTasksPage.fromJson(Map<String, dynamic> json) {
    final rawTasks = json['tasks'];
    if (rawTasks is! List) throw const FormatException('Expected tasks list');
    final tasks = <Map<String, dynamic>>[];
    for (final item in rawTasks) {
      if (item is! Map) throw const FormatException('Expected task object');
      try {
        tasks.add(Map<String, dynamic>.from(item));
      } on TypeError {
        throw const FormatException('Expected task object');
      }
    }
    final hasMore = json['has_more'];
    if (hasMore is! bool) throw const FormatException('Expected has_more flag');
    final nextOffset = json['next_offset'];
    if (nextOffset != null && nextOffset is! int) {
      throw const FormatException('Expected next_offset integer');
    }
    return ProjectTasksPage(
      tasks: tasks,
      hasMore: hasMore,
      nextOffset: nextOffset as int?,
    );
  }
}

class _Unset {
  const _Unset();
}

const _unset = _Unset();

String _requiredText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected non-empty $key');
}

String? _nullableText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Expected $key text or null');
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) {
    final date = DateTime.tryParse(value);
    if (date != null) return date;
  }
  throw FormatException('Expected ISO-8601 $key');
}

DateTime? _nullableDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) {
    final date = DateTime.tryParse(value);
    if (date != null) return date;
  }
  throw FormatException('Expected ISO-8601 $key or null');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Expected integer $key');
}
