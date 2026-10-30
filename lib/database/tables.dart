import 'package:drift/drift.dart';
import 'enums.dart';

@TableIndex(name: 'tasks_uid', unique: true, columns: {#uid})
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The task's identity across devices — see [SyncTombstones] for why the
  /// local [id] cannot be it.
  TextColumn get uid => text().nullable()();

  /// Changed here and not yet sent. See [SyncTombstones].
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

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

  /// The [TaskGroups.uid] this task is shared in; null for a personal task.
  /// Fixed at creation — the server ignores a change, see
  /// BACKEND_PLAN.md §4.3.
  TextColumn get groupUid => text().nullable()();

  /// Which member the group task is handed to; null means "for everyone",
  /// each member ticking it for themselves.
  TextColumn get assigneeUid => text().nullable()();

  /// Who wrote the group task — with the group's owner, the only one who may
  /// edit it. Null for a personal task: on this device that is always "me".
  TextColumn get authorUid => text().nullable()();
}

/// A group this account is in. Mirrored whole from the server on every sync —
/// never edited here, so it carries no sync marks. Changes go through the
/// server's `/groups/*` routes (BACKEND_PLAN.md §4.3).
///
/// `task_groups`, not `groups`: GROUPS is an SQLite keyword.
class TaskGroups extends Table {
  TextColumn get uid => text()();
  TextColumn get name => text()();
  TextColumn get ownerUid => text()();

  @override
  Set<Column> get primaryKey => {uid};
}

/// The current members of [TaskGroups], with the name and picture each one
/// published. Mirrored whole like the groups.
class GroupMembers extends Table {
  TextColumn get groupUid => text()();
  TextColumn get userUid => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();

  @override
  Set<Column> get primaryKey => {groupUid, userUid};
}

/// **Other members'** marks on group tasks — what "2 из 3" is read from.
///
/// A table apart from [TaskLogs] on purpose: that one holds exactly one row per
/// task and day, and everything that ticks, counts and reads a habit relies on
/// it. Here the key carries the member too. Only ever written by a pull, never
/// sent: a member's marks are theirs to change.
class GroupMarks extends Table {
  IntColumn get taskId => integer().references(Tasks, #id)();
  TextColumn get userUid => text()();

  /// Local midnight, like [TaskLogs.date].
  DateTimeColumn get date => dateTime()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {taskId, userUid, date};
}

/// One task's answer for one day: ticked, and how much of it was done.
///
/// ## Why the pair is unique, and why that had to be built rather than assumed
///
/// The row's identity is `(taskId, date)` — the task and the calendar day — and
/// unlike everything else that syncs it needs no `uid`. That is the whole reason
/// the marks below are two columns and not three: with random uuids, two devices
/// that ticked today's habit independently would arrive with **two** rows for one
/// day and something would have to merge them. With a natural key they converge
/// on their own.
///
/// The index enforcing it is not decoration. [TasksDao.getLogForDate] reads
/// through `getSingleOrNull()`, which **throws** on a second row, so a duplicate
/// does not make a habit slightly wrong — it makes `setLog`, `incrementCounter`,
/// `toggleCompletion` and the task form stop working outright. Nothing enforced
/// the pair before, which was survivable only because the app was the single
/// writer; a pull is a second writer and therefore a factory for duplicates.
///
/// The index also relies on [date] being a **day** rather than an instant. It
/// used to be midnight by convention alone — `HomePage` opens on
/// `DateTime.now()` and the timeline ticks against whatever it is handed — so an
/// index over the raw timestamp would have been built happily and then lied,
/// letting `2026-08-26 14:32` and `2026-08-26 00:00` sit side by side. The v14
/// migration folds the old rows onto their days and [TasksDao] strips the time
/// on the way in, so the column now means what the index assumes.
@TableIndex(name: 'task_logs_task_day', unique: true, columns: {#taskId, #date})
class TaskLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId => integer().references(Tasks, #id)();

  /// The calendar day this row is about, as **local midnight**. Never an
  /// instant: see the class comment, and [TasksDao.dayOf], which is the only
  /// thing that writes it.
  DateTimeColumn get date => dateTime()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  RealColumn get value => real().nullable()();

  /// The moment the day was ticked; null while it is not, and on every row
  /// ticked before v17 — that time was never recorded and cannot be recovered.
  /// Not [date] with a time on it: [date] is half of the row's key. No default,
  /// for the reason spelled out on [updatedAt].
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// Changed here and not yet sent. See [SyncTombstones].
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  /// When the **device** last changed this row. Needed because the merge rule
  /// compares edit times and a log had no notion of one.
  ///
  /// The default is a bare constant — the epoch — and that is not laziness.
  /// SQLite refuses `ALTER TABLE ... ADD COLUMN` when the default is not
  /// constant: `CURRENT_TIMESTAMP`, which is what drift emits for
  /// `currentDateAndTime`, fails with "Cannot add a column with non-constant
  /// default". Worse, it fails **only on a table that already has rows** — an
  /// empty one accepts it — so the obvious spelling migrates a developer's
  /// device and bricks every phone that has ever ticked a day. The v14
  /// migration stamps the existing rows itself, and every write in [TasksDao]
  /// passes a value, so the epoch is never what a row actually carries.
  DateTimeColumn get updatedAt => dateTime().withDefault(
    Constant(DateTime.fromMillisecondsSinceEpoch(0)),
  )();
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
@TableIndex(name: 'diary_entries_uid', unique: true, columns: {#uid})
class DiaryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The note's identity across devices — see [SyncTombstones] for why the
  /// local [id] cannot be it.
  TextColumn get uid => text().nullable()();

  /// Changed here and not yet sent. See [SyncTombstones].
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
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
@TableIndex(name: 'note_moods_uid', unique: true, columns: {#uid})
class NoteMoods extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Identity across devices. The eight seeded moods carry the **fixed** uids
  /// of `defaultNoteMoods` rather than fresh ones: the seeding runs separately
  /// on every device, so without that two phones would send the same eight
  /// moods up as sixteen rows.
  TextColumn get uid => text().nullable()();

  /// Changed here and not yet sent. See [SyncTombstones].
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

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
@TableIndex(name: 'note_tags_uid', unique: true, columns: {#uid})
class NoteTags extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Identity across devices. See [SyncTombstones].
  TextColumn get uid => text().nullable()();

  /// Changed here and not yet sent. See [SyncTombstones].
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  /// Without the leading "#" — that is punctuation the chip draws, not part of
  /// the name, and storing it would put it into every comparison.
  TextColumn get name => text()();

  /// Which family of `taskPalette` the chip is painted in — `violet`, `red`,
  /// and so on. A **key**, not the colour itself.
  ///
  /// A task stores its raw ARGB, and a tag used to as well. The difference is
  /// that a tag travels: it goes to the server and comes back on another phone,
  /// possibly running a different version of the app. A number like
  /// `0xFF8B7CF6` only means something inside one version of one palette —
  /// exactly the reason task icons stopped storing a Material code point in
  /// migration v10 and started storing a key into `taskIcons`.
  ///
  /// With a key the design can be repainted and every tag ever written follows,
  /// everywhere, with no migration. It also sidesteps a mismatch that only
  /// showed up at the boundary: an opaque ARGB begins with `0xFF` and so
  /// exceeds 2^31, which SQLite stored without comment and Postgres `integer`
  /// refused outright.
  TextColumn get colorKey => text().withDefault(const Constant('violet'))();

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

/// What was deleted here, so the other devices can be told.
///
/// A deletion is the one change that leaves nothing behind to notice. Every
/// other edit is a row that can be compared against the server's copy; a
/// deleted note is simply absent, and absent is indistinguishable from "not
/// yet seen" — so without a record of it the note would come straight back on
/// the next pull.
///
/// A table of its own rather than a `deletedAt` column on each row, which is
/// the other usual answer: soft deletion would make **every existing query in
/// the app** responsible for filtering the deleted out, and there are dozens.
/// The deletions stay hard, and this records that they happened.
///
/// A row is written by the DAO inside the same transaction as the delete, and
/// removed once the server has been told.
///
/// ## Why the local id cannot be the identity
///
/// Every table here keys on `integer().autoIncrement()`, which counts from 1 on
/// each device independently. Two phones both call the third note they make
/// "3", so an id says nothing outside the device that issued it. Hence [uid]:
/// a uuid minted where the row is born and never changed again.
///
/// It is a column beside the primary key rather than the primary key itself
/// deliberately. Local joins, the two link tables and every `family` provider
/// in the app are keyed by `int`; moving the primary key would rewrite all of
/// them and every screen behind them. Adding a column rewrites nothing, and the
/// translation between the two lives in the sync layer alone.
class SyncTombstones extends Table {
  /// Which table the row was in — `diary_entries`, `note_moods`, `note_tags`,
  /// `tasks`. A plain string: this table outlives the row it describes, so it
  /// cannot point at one. Not `tableName`, which is drift's own on [Table].
  ///
  /// It is also the name the **server** knows the table by, because that is
  /// what the push uses to address the row it has to mark deleted. The two
  /// spellings have to stay the same on both sides.
  TextColumn get sourceTable => text()();

  /// The [DiaryEntries.uid] or [Tasks.uid] of what was deleted.
  ///
  /// [TaskLogs] never appears here, and that is a property of the app rather
  /// than an omission: the only statement in it that deletes a log deletes
  /// every log of one task, so a log's disappearance is always already told by
  /// its task's. On the server the same fact is a foreign key.
  TextColumn get uid => text()();

  DateTimeColumn get deletedAt => dateTime().withDefault(currentDateAndTime)();

  /// The pair is the row. Deleting the same uid twice is not two facts, and a
  /// tombstone re-written after a failed send must replace rather than pile up.
  @override
  Set<Column> get primaryKey => {sourceTable, uid};
}

/// What a woman marked on one day of her cycle (`CycleDay.dc.html`): the flow,
/// the mood, symptoms, discharge, the pill, sex and a note.
///
/// **One row per calendar day, and the day is the identity** — the same shape as
/// [TaskLogs], for the same reason: two phones that marked one day converge on
/// the pair `(user, date)` without anything having to merge them. So there is no
/// `uid` here and no tombstone: taking a mark back saves the day *empty* (flow 0,
/// the rest unset) rather than deleting the row, which is how a task log keeps
/// `completed = false`. An empty row is not shown anywhere as a mark.
///
/// The options are small integers, **indexes into the lists in
/// `utils/cycle_marks.dart`** — they travel to the server as numbers, so the
/// order of those lists is a stored format and may only ever be appended to.
///
/// Health data: it goes up only while "Синхронизировать цикл" is on, and the
/// server shows it to its owner alone. See BACKEND_PLAN.md §4.2.
@TableIndex(name: 'cycle_days_date', unique: true, columns: {#date})
class CycleDays extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The calendar day, as **local midnight** — see [TaskLogs.date].
  DateTimeColumn get date => dateTime()();

  /// 0 = none … 4 = heavy.
  IntColumn get flow => integer().withDefault(const Constant(0))();

  /// Null = not marked.
  IntColumn get mood => integer().nullable()();

  /// The chosen symptoms, as comma-separated indexes: `"0,3"`. Empty = none.
  TextColumn get symptoms => text().withDefault(const Constant(''))();
  IntColumn get discharge => integer().nullable()();

  /// 0 = no, 1 = protected, 2 = unprotected; null = not marked.
  IntColumn get sex => integer().nullable()();
  BoolColumn get pill => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();

  /// Changed here and not yet sent. See [SyncTombstones].
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  /// When the device last changed the day; the merge compares it. The epoch
  /// default is a bare constant for the reason spelled out on
  /// [TaskLogs.updatedAt] — and every write in `CycleDao` passes a real one.
  DateTimeColumn get updatedAt => dateTime().withDefault(
    Constant(DateTime.fromMillisecondsSinceEpoch(0)),
  )();
}
