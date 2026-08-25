import 'package:drift/drift.dart';
import 'enums.dart';

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get parentId => integer().nullable().references(Tasks, #id)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status =>
      textEnum<TaskStatus>().withDefault(const Constant('active'))();

  TextColumn get repeatType => textEnum<RepeatType>().nullable()();
  IntColumn get repeatInterval => integer().nullable()();

  /// Bitmask of the days a repeating task lands on, where day `d` sets bit
  /// `d - 1`. What a day means depends on [repeatType]: for
  /// [RepeatType.weekly] it is [DateTime.weekday] (Monday = bit 0 … Sunday =
  /// bit 6), for [RepeatType.monthly] it is the day of the month (1 … 31).
  /// Null means "not specified" — such tasks fall back to the weekday or day of
  /// month of their anchor date, as they did before this column existed.
  /// [RepeatType.daily] and [RepeatType.custom] ignore it.
  IntColumn get repeatDaysMask => integer().nullable()();

  TextColumn get trackingMode =>
      textEnum<TrackingMode>().withDefault(const Constant('checkbox'))();
  IntColumn get targetDurationMinutes => integer().nullable()();
  RealColumn get targetValue => real().nullable()();

  /// Key into `taskIcons` — see [lib/utils/task_icons.dart]. What the app
  /// reads and writes.
  TextColumn get iconKey => text().nullable()();

  /// Legacy: the Material Icons code point tasks carried before [iconKey].
  /// Kept only so the schema v10 migration can translate old rows; nothing in
  /// the app reads it.
  IntColumn get iconCodePoint => integer().nullable()();
  IntColumn get colorValue => integer().nullable()();

  IntColumn get scheduledTimeMinutes => integer().nullable()();
  IntColumn get endTimeMinutes => integer().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class TaskLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId => integer().references(Tasks, #id)();
  DateTimeColumn get date => dateTime()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  RealColumn get value => real().nullable()();
}

class TaskSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId => integer().references(Tasks, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
}

class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get type =>
      textEnum<EventType>().withDefault(const Constant('personal'))();
}

/// A diary entry — a note.
///
/// Nothing here is derived: unlike a task's archive, which follows from "done
/// and its day has passed", a note is put away by hand, so [status] is stored.
class DiaryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();

  /// The note's text as a Parchment (Quill.js) Delta, JSON-encoded. Plain text
  /// cannot hold what the editor produces — headings, lists, pictures — and the
  /// format is the one both Fleather and Quill read, so the choice of editor is
  /// not baked into the data.
  ///
  /// Image operations inside it carry a **file name**, not a path; see
  /// [noteImagesDirectory].
  TextColumn get body => text().withDefault(const Constant(''))();

  /// File name of the cover inside the app's note-images directory, never an
  /// absolute path: the container the directory lives in is not stable across
  /// launches on iOS, so a stored path goes dead after an update.
  TextColumn get coverImage => text().nullable()();

  /// The pictures attached to the note, in the order they were added, as a JSON
  /// array of file names in the same directory as [coverImage].
  ///
  /// They belong to the note as a whole and are shown after its text, so they
  /// are not part of [body]: an attachment is not a character in the document,
  /// and reordering or dropping one must not rewrite the text around it. SQLite
  /// has no array type, hence JSON in a text column rather than a table of its
  /// own — nothing ever queries a single picture.
  TextColumn get images => text().withDefault(const Constant('[]'))();

  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get status =>
      textEnum<DiaryEntryStatus>().withDefault(const Constant('normal'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// A mood a note can be marked with — the emoji and the word shown on its chip.
///
/// A row rather than a constant in Dart, because the user adds their own
/// ("Другое" in the picker) and a note has to keep pointing at one after that:
/// a mood the app shipped with and a mood the user invented have to be the same
/// kind of thing, or the link table would need two columns and every reader a
/// branch. The eight the app opens with are seeded by the migration.
class NoteMoods extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// What the chip says — "Спокойствие". Unique in practice, not by constraint:
  /// the picker refuses a name it already holds, which is a better place to say
  /// so than a failed insert.
  TextColumn get name => text()();

  /// The emoji itself, as text — 🌿, not a code point. It is drawn by the
  /// platform's emoji font, which the app neither ships nor subsets, so there is
  /// nothing to look a glyph up in and nothing that could go stale.
  TextColumn get emoji => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A tag a note can carry. Unlike a mood it has no glyph and does have a colour:
/// tags are read as a set, side by side, and the colour is what tells them apart
/// at a glance.
class NoteTags extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Without the leading "#" — that is punctuation the chip draws, not part of
  /// the name, and storing it would put it into every comparison.
  TextColumn get name => text()();

  /// One of the accents of `taskPalette`, stored the way a task stores its
  /// colour: `Color(v)`. Not nullable — a tag with no colour has nothing to be
  /// recognised by.
  IntColumn get colorValue => integer()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Which moods a note is marked with — the many-to-many join between
/// [DiaryEntries] and [NoteMoods].
///
/// A join table and not a column on the note, even though the picker hands out
/// one mood at a time: the moods are a catalogue shared by every note, so the
/// note has to refer to a row rather than hold a copy of its name and emoji —
/// renaming a mood must not leave the notes already marked with it behind. That
/// the UI allows one at a time is a rule of the picker; the data does not need
/// changing if it ever allows two.
class DiaryEntryMoods extends Table {
  IntColumn get entryId => integer().references(DiaryEntries, #id)();
  IntColumn get moodId => integer().references(NoteMoods, #id)();

  /// The pair is the row: a note cannot carry the same mood twice, and the index
  /// SQLite builds for it is what makes "the moods of this note" a lookup.
  @override
  Set<Column> get primaryKey => {entryId, moodId};
}

/// Which tags a note carries — the many-to-many join between [DiaryEntries] and
/// [NoteTags]. Same shape as [DiaryEntryMoods], and here the "many" on both
/// sides is what the screen actually shows: several tags on one note, one tag
/// across many notes.
class DiaryEntryTags extends Table {
  IntColumn get entryId => integer().references(DiaryEntries, #id)();
  IntColumn get tagId => integer().references(NoteTags, #id)();

  @override
  Set<Column> get primaryKey => {entryId, tagId};
}
