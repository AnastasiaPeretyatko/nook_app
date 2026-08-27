/// Turning a row into what the server stores, and back.
///
/// Pure on purpose — no database handle, no client, nothing to stub. This is
/// where the quiet mistakes live: a date sent in the wrong scale, an enum
/// spelled differently on the two sides, a null that arrives as the string
/// "null". None of those throw; they just corrupt a note. So they get tested
/// here, on plain maps, instead of at the far end of a network call.
///
/// ## What is deliberately not sent
///
/// `user_id` — the server fills it from `auth.uid()`, and a client that names
/// it can only ever get it wrong or lie.
///
/// `updated_at` — the server's own clock, set by trigger. Anything a client put
/// there would be overwritten anyway; sending it would just suggest otherwise.
///
/// The local `id`. It counts from 1 on each device and means nothing anywhere
/// else. `uid` goes in its place, as the primary key.
library;

import 'dart:ui' show Color;

import 'package:drift/drift.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/task_palette.dart';

/// The device's own idea of when a row was last edited.
///
/// A column of its own, beside the server's `updated_at`, because the two
/// answer different questions: the server's is "has this device seen this yet",
/// the client's is "which of two edits came first". Only the second is a
/// question about the user.
const _clientUpdatedAt = 'client_updated_at';

/// A note, as the server takes it.
Map<String, dynamic> entryToRow(DiaryEntry entry) => {
  'id': entry.uid,
  'title': entry.title,
  'body': entry.body,
  'cover_image': entry.coverImage,
  'images': entry.images,
  'is_favorite': entry.isFavorite,
  'status': entry.status.name,
  'created_at': _instant(entry.createdAt),
  _clientUpdatedAt: _instant(entry.updatedAt),
};

/// A note, as it came back.
///
/// `updatedAt` is read from [_clientUpdatedAt] and **not** from the server's
/// `updated_at`: what is being stored locally is when the note was edited, not
/// when this row happened to be written. Taking the server's stamp would make
/// every pulled note look freshly edited and jump it to the top of the diary.
DiaryEntriesCompanion entryFromRow(Map<String, dynamic> row) =>
    DiaryEntriesCompanion(
      title: Value(_text(row['title'])),
      body: Value(_text(row['body'])),
      coverImage: Value(row['cover_image'] as String?),
      images: Value(_text(row['images'], fallback: '[]')),
      isFavorite: Value(row['is_favorite'] as bool? ?? false),
      status: Value(_status(row['status'])),
      createdAt: Value(_moment(row['created_at']) ?? DateTime.now()),
      updatedAt: Value(_moment(row[_clientUpdatedAt]) ?? DateTime.now()),
    );

Map<String, dynamic> moodToRow(NoteMood mood) => {
  'id': mood.uid,
  'name': mood.name,
  'emoji': mood.emoji,
  'created_at': _instant(mood.createdAt),
  _clientUpdatedAt: _instant(mood.createdAt),
};

NoteMoodsCompanion moodFromRow(Map<String, dynamic> row) =>
    NoteMoodsCompanion.insert(
      name: _text(row['name']),
      emoji: _text(row['emoji']),
      createdAt: Value(_moment(row['created_at']) ?? DateTime.now()),
    );

Map<String, dynamic> tagToRow(NoteTag tag) => {
  'id': tag.uid,
  'name': tag.name,
  'color_key': tag.colorKey,
  'created_at': _instant(tag.createdAt),
  _clientUpdatedAt: _instant(tag.createdAt),
};

NoteTagsCompanion tagFromRow(Map<String, dynamic> row) =>
    NoteTagsCompanion.insert(
      name: _text(row['name']),
      colorKey: Value(_text(row['color_key'], fallback: fallbackTaskColorKey)),
      createdAt: Value(_moment(row['created_at']) ?? DateTime.now()),
    );

// -----------------------------------------------------------------------------
// Tasks, habits and their day marks
// -----------------------------------------------------------------------------

/// A task, as the server takes it.
///
/// [parentUid] rather than the row's own `parentId`, and that is the one place
/// this file is not a pure function of a row: a parent is a local integer id
/// here and a uuid there, so the translation needs the *other* row and only the
/// engine has it. Null for a root task, and null too for the impossible-in-
/// practice case of a parent that somehow has no uid — better a task that
/// arrives at the top level than one Postgres refuses outright.
///
/// `icon_code_point` is not sent. It is the Material code point tasks carried
/// before `icon_key`, nothing in the app reads it, and a code point means
/// something only inside one version of one font — the very reason v10 replaced
/// it with a key.
Map<String, dynamic> taskToRow(Task task, {String? parentUid}) => {
  'id': task.uid,
  'parent_id': parentUid,
  'title': task.title,
  'description': task.description,
  'status': task.status.name,
  'repeat_type': task.repeatType?.name,
  'repeat_interval': task.repeatInterval,
  'repeat_days_mask': task.repeatDaysMask,
  'tracking_mode': task.trackingMode.name,
  'target_duration_minutes': task.targetDurationMinutes,
  'target_value': task.targetValue,
  'icon_key': task.iconKey,
  // A **key** into the palette, not the colour itself, for exactly the reasons
  // a tag's went that way at v13: `0xFF8B7CF6` means something only inside one
  // version of one palette, while `violet` is the same fact on any device and
  // after any repaint — and an opaque ARGB starts with `0xFF`, so it is above
  // 2^31 and a Postgres `integer` refuses it outright.
  //
  // Only the boundary changes. `tasks.color_value` stays an ARGB locally, since
  // every widget in the app reads it as a colour; the translation lives here and
  // nowhere else.
  'color_key': _colorKey(task.colorValue),
  'scheduled_time_minutes': task.scheduledTimeMinutes,
  'end_time_minutes': task.endTimeMinutes,
  // A calendar day, not a moment — see [_calendarDay].
  'start_date': _calendarDay(task.startDate),
  'created_at': _instant(task.createdAt),
  _clientUpdatedAt: _instant(task.updatedAt),
};

/// A task, as it came back. `parentId` is left absent: only the engine can turn
/// the parent's uid into a local id, and a companion that named it would either
/// guess or blank it.
TasksCompanion taskFromRow(Map<String, dynamic> row) => TasksCompanion(
  title: Value(_text(row['title'])),
  description: Value(row['description'] as String?),
  status: Value(_enum(row['status'], TaskStatus.values, TaskStatus.active)),
  repeatType: Value(_enumOrNull(row['repeat_type'], RepeatType.values)),
  repeatInterval: Value(_int(row['repeat_interval'])),
  repeatDaysMask: Value(_int(row['repeat_days_mask'])),
  trackingMode: Value(
    _enum(row['tracking_mode'], TrackingMode.values, TrackingMode.checkbox),
  ),
  targetDurationMinutes: Value(_int(row['target_duration_minutes'])),
  targetValue: Value(_double(row['target_value'])),
  iconKey: Value(row['icon_key'] as String?),
  colorValue: Value(_colorValue(row['color_key'])),
  scheduledTimeMinutes: Value(_int(row['scheduled_time_minutes'])),
  endTimeMinutes: Value(_int(row['end_time_minutes'])),
  startDate: Value(_day(row['start_date'])),
  createdAt: Value(_moment(row['created_at']) ?? DateTime.now()),
  updatedAt: Value(_moment(row[_clientUpdatedAt]) ?? DateTime.now()),
);

/// A day mark, as the server takes it.
///
/// No `id`: the row's identity is the pair `(task, day)`, and on the server that
/// pair is the primary key. [taskUid] is what the local `taskId` becomes.
Map<String, dynamic> logToRow(TaskLog log, {required String taskUid}) => {
  'task_id': taskUid,
  'date': _calendarDay(log.date),
  'completed': log.completed,
  'value': log.value,
  _clientUpdatedAt: _instant(log.updatedAt),
};

/// A day mark, as it came back. `taskId` is left absent for the same reason
/// `parentId` is in [taskFromRow].
TaskLogsCompanion logFromRow(Map<String, dynamic> row) => TaskLogsCompanion(
  date: Value(_day(row['date']) ?? DateTime.now()),
  completed: Value(row['completed'] as bool? ?? false),
  value: Value(_double(row['value'])),
  updatedAt: Value(_moment(row[_clientUpdatedAt]) ?? DateTime.now()),
);

/// The uid of the task a day mark belongs to.
String? taskUidOf(Map<String, dynamic> row) => row['task_id'] as String?;

/// When the row was last edited, according to the device that edited it.
DateTime? clientUpdatedAt(Map<String, dynamic> row) =>
    _moment(row[_clientUpdatedAt]);

/// The server's own stamp — the pull watermark, and nothing else.
DateTime? serverUpdatedAt(Map<String, dynamic> row) => _moment(row['updated_at']);

/// Whether the row says it has been deleted elsewhere.
bool isDeleted(Map<String, dynamic> row) => row['deleted_at'] != null;

/// The identity both sides know the row by.
String? uidOf(Map<String, dynamic> row) => row['id'] as String?;

/// A moment as the server wants it: ISO 8601, in UTC.
///
/// The `Z` matters. Postgres reads a bare timestamp as being in the server's
/// time zone, so a stamp sent without one drifts by however far the two are
/// apart — silently, and only for users who are not on UTC.
String _instant(DateTime moment) => moment.toUtc().toIso8601String();

/// A moment as it came back, or null when the field is missing or malformed.
///
/// Tolerant rather than strict: this is data written by another copy of the app
/// — possibly a newer one — and one unreadable field should cost that field,
/// not the whole note.
DateTime? _moment(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}

String _text(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

/// A **calendar day** as the server wants it: `YYYY-MM-DD`, built from the
/// local `y/m/d` and nothing else.
///
/// This is the one conversion in the file that would go wrong silently and only
/// for some people. A day mark and a task's start date are days, not moments:
/// locally they are midnight *in the device's own zone*, so `2026-08-26 00:00`
/// in Moscow is `2026-08-25 21:00` as an instant. Sent through [_instant] and
/// stored in a `timestamptz`, that day would come back as **the 25th** for
/// everyone east of Greenwich — every habit mark off by one, quietly, and only
/// for part of the users.
///
/// So the day is spelled out digit by digit and the server column is `date`,
/// which has no zone to be wrong about. [_day] puts it back together as local
/// midnight on the other side.
String? _calendarDay(DateTime? day) {
  if (day == null) return null;
  final month = day.month.toString().padLeft(2, '0');
  final dayOfMonth = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$dayOfMonth';
}

/// A calendar day as it came back: local midnight of the day the server named.
///
/// Built through `DateTime(y, m, d)` rather than parsed, because parsing
/// `2026-08-26` yields midnight *UTC* in some readings and local in others, and
/// the app compares these against `DateTime(now.year, ...)` everywhere. A value
/// that is not the expected shape gives null rather than a wrong day.
DateTime? _day(Object? value) {
  if (value is! String) return null;
  final parts = value.split('T').first.split('-');
  if (parts.length < 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

/// Postgres hands `numeric`/`integer` back as either an `int` or a `double`
/// depending on the column and the driver, and a task's targets are read as
/// both. Tolerant on the way in, exact on the way out.
int? _int(Object? value) => switch (value) {
  int() => value,
  double() => value.round(),
  String() => int.tryParse(value),
  _ => null,
};

double? _double(Object? value) => switch (value) {
  double() => value,
  int() => value.toDouble(),
  String() => double.tryParse(value),
  _ => null,
};

/// A task's stored ARGB as the palette key naming it, for the trip out.
///
/// Null stays null: a task with no colour is a real state — the screens fall
/// back to the first family for it — and it has to survive the round trip as
/// itself rather than as a colour somebody picked.
///
/// A colour in **no** family also becomes null. That can only be a row from
/// before the palette existed: [ColorPickerRow.colors] is exactly the seven
/// accents, so every colour the app has ever handed out has a key. Such a row
/// loses its colour rather than being given a stranger's, and since a task with
/// no colour is drawn in the first family anyway, the two look the same on
/// screen.
String? _colorKey(int? argb) =>
    argb == null ? null : taskColorKeyOf(Color(argb));

/// The same, coming back. An unknown key — written by a newer version of the
/// app with an eighth family — reads as "no colour" rather than taking the sync
/// down, which is the bargain [taskSwatchForKey] is built on.
int? _colorValue(Object? key) =>
    taskSwatchForKey(key is String ? key : null)?.accent.toARGB32();

/// An enum by the name the Dart side uses, falling back rather than throwing.
///
/// A later version of the app may add a value, and a task written on a newer
/// phone should still be readable on an older one instead of taking the whole
/// sync down with it. The same bargain `_status` strikes for a note.
T _enum<T extends Enum>(Object? value, List<T> values, T fallback) {
  for (final option in values) {
    if (option.name == value) return option;
  }
  return fallback;
}

/// The same, where absent is a meaning of its own: a task with no `repeatType`
/// is a one-off, not a broken habit.
T? _enumOrNull<T extends Enum>(Object? value, List<T> values) {
  for (final option in values) {
    if (option.name == value) return option;
  }
  return null;
}

/// The status, by the name the Dart enum uses.
///
/// An unknown value becomes `normal` instead of throwing: a later version of
/// the app may add one, and a note written on a newer phone should still be
/// readable on an older one rather than taking the sync down.
DiaryEntryStatus _status(Object? value) {
  for (final status in DiaryEntryStatus.values) {
    if (status.name == value) return status;
  }
  return DiaryEntryStatus.normal;
}
