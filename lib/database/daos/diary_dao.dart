import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../sync/merge.dart' show storedSeconds;
import '../../utils/note_labels.dart' show defaultNoteMoodUids;
import '../app_database.dart';

part 'diary_dao.g.dart';

/// Reads and writes diary entries.
///
/// Everything is streamed unfiltered and sorted newest-touched-first: the four
/// tabs of the diary are a filter over one list — three of them on
/// [DiaryEntries.status], one on [DiaryEntries.isFavorite] — so one stream feeds
/// them all instead of four queries racing each other.
///
/// ## The sync marks
///
/// Every write here also records *that* it happened, because a diary that syncs
/// has to be able to say what changed since last time. Three marks do it:
/// [DiaryEntries.uid] is the identity the server knows a row by,
/// [DiaryEntries.dirty] means "changed here, not sent yet", and a row in
/// [SyncTombstones] is the only trace a deletion leaves.
///
/// The marks are stamped in this file and nowhere else — the alternative was
/// SQL triggers, which write behind drift's back and would leave every `watch*`
/// stream in the app unaware that anything changed.
///
/// Note the asymmetry that runs through the methods below: a write **the user
/// made** is dirty, a write **the server sent** is not. That is what the
/// `applyRemote*` methods are for, and getting it wrong does not fail loudly —
/// it makes a row bounce between the two devices forever.
@DriftAccessor(
  tables: [
    DiaryEntries,
    NoteMoods,
    NoteTags,
    DiaryEntryMoods,
    DiaryEntryTags,
    SyncTombstones,
  ],
)
class DiaryDao extends DatabaseAccessor<AppDatabase> with _$DiaryDaoMixin {
  DiaryDao(super.db);

  static const _uuid = Uuid();

  Stream<List<DiaryEntry>> watchEntries() =>
      (select(diaryEntries)..orderBy([
            (e) =>
                OrderingTerm(expression: e.updatedAt, mode: OrderingMode.desc),
          ]))
          .watch();

  /// One entry, live: the view screen redraws itself when the note is starred,
  /// archived or edited, and reports null once it is deleted.
  Stream<DiaryEntry?> watchEntry(int id) =>
      (select(diaryEntries)..where((e) => e.id.equals(id))).watchSingleOrNull();

  Future<DiaryEntry?> getEntry(int id) =>
      (select(diaryEntries)..where((e) => e.id.equals(id))).getSingleOrNull();

  /// Writes a new note, giving it the identity the server will know it by.
  ///
  /// The uid is minted here rather than by the caller: a row without one is
  /// invisible to the sync, and a screen should not have to remember that.
  /// `dirty` needs no mention — the column defaults to true, which is exactly
  /// what a note nobody has sent yet is.
  Future<int> insertEntry(DiaryEntriesCompanion entry) => into(
    diaryEntries,
  ).insert(entry.uid.present ? entry : entry.copyWith(uid: Value(_uuid.v4())));

  /// Partial write: only the fields present in [entry] are touched, so a caller
  /// that knows about the title alone cannot blank the body.
  ///
  /// The one funnel every edit goes through — [setBody], [setStatus] and
  /// [setFavorite] all land here — which is why it is the single place that has
  /// to mark the note as changed. `dirty` is forced rather than defaulted, so a
  /// caller cannot leave an edit unsent by passing a companion of its own.
  ///
  /// `updatedAt` is forced too, and forced to be **strictly greater than it
  /// was**. Drift keeps a `DateTime` as whole seconds, so two edits inside one
  /// second are otherwise stored as the same instant — and [clearEntryDirty]
  /// decides whether an edit happened during a send by comparing exactly that.
  /// Equal stamps would make it drop the second edit, which nothing would ever
  /// send again. Stepping a second forward when the clock has not moved keeps
  /// every version of a note orderable, which is also what the diary's
  /// "newest touched first" sort assumes.
  ///
  /// The cost is that a burst of edits inside one second pushes the stamp a
  /// little ahead of the wall clock — a second per edit. Saving a note is
  /// user-paced, so the burst that would make this visible does not happen.
  Future<int> updateEntryById(int id, DiaryEntriesCompanion entry) {
    return transaction(() async {
      final current = await getEntry(id);
      final now = DateTime.now();
      // Compared **as stored**, not as held: `now` is always a fraction later
      // than a value read back from the database, and asking `isAfter` would
      // say so — then write the very same second and change nothing.
      final stamp =
          (current == null ||
              storedSeconds(now) > storedSeconds(current.updatedAt))
          ? now
          : current.updatedAt.add(const Duration(seconds: 1));

      return (update(diaryEntries)..where((e) => e.id.equals(id))).write(
        entry.copyWith(updatedAt: Value(stamp), dirty: const Value(true)),
      );
    });
  }

  /// Writes just the note's text — what ticking a check-box on the view screen
  /// changes. Through [updateEntryById] like everything else, so `updatedAt`
  /// moves with it: ticking an item is a change to the note, and the diary is
  /// ordered by when a note was last touched.
  Future<int> setBody(int id, String body) =>
      updateEntryById(id, DiaryEntriesCompanion(body: Value(body)));

  Future<int> setStatus(int id, DiaryEntryStatus status) =>
      updateEntryById(id, DiaryEntriesCompanion(status: Value(status)));

  Future<int> setFavorite(int id, bool isFavorite) =>
      updateEntryById(id, DiaryEntriesCompanion(isFavorite: Value(isFavorite)));

  /// Deletes the note **and the rows linking it to its moods and tags**.
  ///
  /// By hand, in one transaction, because nothing does it for us: the app never
  /// turns `PRAGMA foreign_keys` on, so the `references` in the table
  /// definitions document the shape and enforce nothing — a delete that only
  /// took the entry out would leave two orphan rows per label, invisible and
  /// forever. The links go first: a transaction makes the order moot, and this
  /// way the note is never on screen without them.
  ///
  /// A tombstone is written in the same transaction, and that is the only trace
  /// the deletion leaves. Every other edit can be found by comparing the row
  /// against the server's copy; a deleted note is simply gone, and "gone" reads
  /// exactly like "the other device has not sent it yet" — so without this the
  /// note would come straight back on the next pull.
  ///
  /// The uid has to be read **before** the row goes, which is why this is not a
  /// three-line delete any more.
  Future<int> deleteEntry(int id) {
    return transaction(() async {
      final entry = await getEntry(id);
      await (delete(diaryEntryMoods)..where((l) => l.entryId.equals(id))).go();
      await (delete(diaryEntryTags)..where((l) => l.entryId.equals(id))).go();
      final removed = await (delete(
        diaryEntries,
      )..where((e) => e.id.equals(id))).go();

      // No uid means the row predates the sync schema and the server has never
      // heard of it — there is nobody to tell.
      final uid = entry?.uid;
      if (uid != null) await _writeTombstone(diaryEntries, uid);
      return removed;
    });
  }

  /// Records that [uid] is gone, replacing any earlier note of the same.
  ///
  /// `insertOrReplace` because the key is the pair `(sourceTable, uid)`: a
  /// deletion re-recorded after a failed send is the same fact, not a second
  /// one, and a plain insert would throw the second time.
  Future<void> _writeTombstone(
    TableInfo<Table, dynamic> table,
    String uid,
  ) async {
    await into(syncTombstones).insert(
      SyncTombstonesCompanion.insert(
        // From the schema rather than a string literal, so a renamed table
        // cannot leave the tombstones pointing at one that no longer exists.
        sourceTable: table.actualTableName,
        uid: uid,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  // ---------------------------------------------------------------------------
  // Moods and tags.
  //
  // Two catalogues shared by every note, and two join tables pointing at them.
  // The catalogues are small — a handful of rows each — and every picker wants
  // all of them, so they are streamed whole and never queried by name.
  // ---------------------------------------------------------------------------

  /// Every mood, oldest first, which keeps the eight the app seeded in the order
  /// the design lists them and puts anything the user invents after them.
  Stream<List<NoteMood>> watchMoods() => (select(
    noteMoods,
  )..orderBy([(m) => OrderingTerm(expression: m.id)])).watch();

  /// Every tag, oldest first — same reasoning as [watchMoods].
  Stream<List<NoteTag>> watchTags() => (select(
    noteTags,
  )..orderBy([(t) => OrderingTerm(expression: t.id)])).watch();

  /// Adds a mood and hands back its id, so the picker can select what it just
  /// created without waiting for the stream to come round.
  ///
  /// A fresh uid, unlike the eight seeded moods, which carry the fixed ones of
  /// `defaultNoteMoods` so that two devices do not send the same feeling up
  /// twice. A mood the user invents exists on one device until it is synced,
  /// and there is nothing for it to agree with.
  Future<int> insertMood({required String name, required String emoji}) =>
      into(noteMoods).insert(
        NoteMoodsCompanion.insert(
          name: name,
          emoji: emoji,
          uid: Value(_uuid.v4()),
        ),
      );

  /// [colorKey] names a family of `taskPalette` — `violet`, `red` — rather
  /// than carrying the colour itself, so a repaint of the design reaches
  /// every tag ever written without a migration.
  Future<int> insertTag({required String name, required String colorKey}) =>
      into(noteTags).insert(
        NoteTagsCompanion.insert(
          name: name,
          colorKey: Value(colorKey),
          uid: Value(_uuid.v4()),
        ),
      );

  /// The moods of one note, live: what the view screen draws under the title.
  ///
  /// A join rather than two reads, so a mood renamed in the picker shows up on
  /// the note without anything having to invalidate anything.
  Stream<List<NoteMood>> watchMoodsForEntry(int entryId) {
    final query = select(diaryEntryMoods).join([
      innerJoin(noteMoods, noteMoods.id.equalsExp(diaryEntryMoods.moodId)),
    ])..where(diaryEntryMoods.entryId.equals(entryId));
    return query.watch().map(
      (rows) => [for (final row in rows) row.readTable(noteMoods)],
    );
  }

  Stream<List<NoteTag>> watchTagsForEntry(int entryId) {
    final query = select(diaryEntryTags).join([
      innerJoin(noteTags, noteTags.id.equalsExp(diaryEntryTags.tagId)),
    ])..where(diaryEntryTags.entryId.equals(entryId));
    return query.watch().map(
      (rows) => [for (final row in rows) row.readTable(noteTags)],
    );
  }

  /// Every note's moods at once, keyed by note id.
  ///
  /// What a *list* of cards needs: one query for the whole screen instead of
  /// [watchMoodsForEntry] per row. A family provider per card would open a query
  /// for every note the diary draws and hold it open, and the diary draws as
  /// many cards as there are notes.
  Stream<Map<int, List<NoteMood>>> watchMoodsByEntry() {
    final query = select(diaryEntryMoods).join([
      innerJoin(noteMoods, noteMoods.id.equalsExp(diaryEntryMoods.moodId)),
    ])..orderBy([OrderingTerm(expression: noteMoods.id)]);
    return query.watch().map((rows) {
      final byEntry = <int, List<NoteMood>>{};
      for (final row in rows) {
        final entryId = row.readTable(diaryEntryMoods).entryId;
        (byEntry[entryId] ??= []).add(row.readTable(noteMoods));
      }
      return byEntry;
    });
  }

  /// Every note's tags at once — same reasoning as [watchMoodsByEntry], and the
  /// catalogue's own order inside each note, so two cards never list the same
  /// pair of tags the other way round.
  Stream<Map<int, List<NoteTag>>> watchTagsByEntry() {
    final query = select(diaryEntryTags).join([
      innerJoin(noteTags, noteTags.id.equalsExp(diaryEntryTags.tagId)),
    ])..orderBy([OrderingTerm(expression: noteTags.id)]);
    return query.watch().map((rows) {
      final byEntry = <int, List<NoteTag>>{};
      for (final row in rows) {
        final entryId = row.readTable(diaryEntryTags).entryId;
        (byEntry[entryId] ??= []).add(row.readTable(noteTags));
      }
      return byEntry;
    });
  }

  /// The ids alone, once — what the form opens with. A future and not a stream,
  /// by the convention every other form on this app follows: a draft the user is
  /// editing must not be overwritten by the database underneath them.
  Future<List<int>> getMoodIdsForEntry(int entryId) async {
    final rows = await (select(
      diaryEntryMoods,
    )..where((l) => l.entryId.equals(entryId))).get();
    return [for (final row in rows) row.moodId];
  }

  Future<List<int>> getTagIdsForEntry(int entryId) async {
    final rows = await (select(
      diaryEntryTags,
    )..where((l) => l.entryId.equals(entryId))).get();
    return [for (final row in rows) row.tagId];
  }

  /// Makes the note's moods exactly [moodIds] — the form owns the whole set, so
  /// it is replaced rather than added to, and an empty list clears it.
  ///
  /// Delete-then-insert inside a transaction, rather than working out what
  /// changed: the sets are two or three rows long, and a diff would be more code
  /// than it saves.
  ///
  /// The note itself is marked as changed, and that is **load-bearing**, not
  /// bookkeeping: the link tables carry no `uid` and no `dirty` of their own —
  /// a link has no identity, it travels as the pair of its parents' uids — so a
  /// dirty note is the only signal by which the sync ever learns that the
  /// labels moved. Leave it out and the links never go anywhere.
  ///
  /// (This is also why the note's `updatedAt` moves, which it used not to. In
  /// practice nothing changes: labels are only ever saved from the note form,
  /// which writes the note in the same breath.)
  Future<void> setEntryMoods(int entryId, Iterable<int> moodIds) {
    return transaction(() async {
      await (delete(
        diaryEntryMoods,
      )..where((l) => l.entryId.equals(entryId))).go();
      await _touchEntry(entryId);
      if (moodIds.isEmpty) return;
      await batch((b) {
        b.insertAll(diaryEntryMoods, [
          for (final moodId in moodIds)
            DiaryEntryMoodsCompanion.insert(entryId: entryId, moodId: moodId),
        ]);
      });
    });
  }

  /// Same shape as [setEntryMoods], and the note is marked for the same reason.
  Future<void> setEntryTags(int entryId, Iterable<int> tagIds) {
    return transaction(() async {
      await (delete(
        diaryEntryTags,
      )..where((l) => l.entryId.equals(entryId))).go();
      await _touchEntry(entryId);
      if (tagIds.isEmpty) return;
      await batch((b) {
        b.insertAll(diaryEntryTags, [
          for (final tagId in tagIds)
            DiaryEntryTagsCompanion.insert(entryId: entryId, tagId: tagId),
        ]);
      });
    });
  }

  /// Marks the note changed without changing anything on it.
  ///
  /// An empty companion is not an empty write: [updateEntryById] adds
  /// `updatedAt` and `dirty` to whatever it is handed, so this reuses the one
  /// funnel rather than becoming a second place that knows about the marks.
  Future<void> _touchEntry(int entryId) =>
      updateEntryById(entryId, const DiaryEntriesCompanion());

  // ---------------------------------------------------------------------------
  // What the sync engine talks to.
  //
  // Two directions, and the difference between them is the whole point: the
  // `pending*` reads say what this device changed, and the `applyRemote*`
  // writes bring in what another one did — **without** marking it as ours. A
  // row written as if the user had touched it would be sent straight back, and
  // the two devices would hand it to each other forever.
  //
  // Nothing here reaches the network. It is the surface the engine will use;
  // the engine itself is a later step.
  // ---------------------------------------------------------------------------

  /// The notes changed here and not sent yet.
  Future<List<DiaryEntry>> pendingEntries() =>
      (select(diaryEntries)..where((e) => e.dirty.equals(true))).get();

  /// The moods waiting to be sent — the ones the user invented, never the eight
  /// the app seeded.
  ///
  /// A seeded mood is a constant of the app, not somebody's data: it is written
  /// out in `defaultNoteMoods`, it arrives with the install, and nothing here
  /// can rename or delete it. The server keeps **one** shared row for each,
  /// owned by nobody, so a device that sent its copy would be claiming a
  /// constant — and, because those uuids are the same on every install on
  /// earth, would collide with whichever account got there first. That
  /// collision is what took the whole push down: moods go up before tags,
  /// notes, links and tasks, so an account that could not send them sent
  /// nothing at all, ever. See `supabase/004_shared_moods.sql`.
  ///
  /// A mood with no uid falls out here too — `uid NOT IN (...)` is null for a
  /// null uid, so the row is not returned. That is the right answer for a
  /// different reason: there is nothing to address such a row by, and it would
  /// be sent as an `id` of null and refused.
  Future<List<NoteMood>> pendingMoods() =>
      (select(noteMoods)..where(
            (m) =>
                m.dirty.equals(true) &
                m.uid.isNotIn(defaultNoteMoodUids.toList()),
          ))
          .get();

  Future<List<NoteTag>> pendingTags() =>
      (select(noteTags)..where((t) => t.dirty.equals(true))).get();

  /// How many notes are waiting to be sent.
  ///
  /// What the "there are N notes here, upload them?" question counts. On a
  /// first sync that is every note on the device, which is exactly what the
  /// question is about.
  /// How many notes are on the device at all. The twin of
  /// [TasksDao.taskCount] — why it is not [unsentEntryCount] is written there.
  Future<int> entryCount() async {
    final count = diaryEntries.id.count();
    final row = await (selectOnly(
      diaryEntries,
    )..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> unsentEntryCount() async {
    final count = diaryEntries.id.count();
    final row =
        await (selectOnly(diaryEntries)
              ..addColumns([count])
              ..where(diaryEntries.dirty.equals(true)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Answers "no" to that question: everything here stays here.
  ///
  /// The marks are cleared without anything being sent, so the notes are simply
  /// never offered to the server. Editing one later marks it again and it does
  /// go up — which is worth saying out loud in the dialog, because otherwise
  /// the behaviour looks like the answer was ignored.
  ///
  /// The catalogues are **not** cleared. A mood or a tag is not a note, both
  /// devices already carry the same eight seeded moods, and — the load-bearing
  /// reason — a link sent for a future note would be rejected outright by
  /// Postgres if the label it points at had never been uploaded.
  Future<void> keepExistingEntriesLocal() {
    return transaction(() async {
      await update(
        diaryEntries,
      ).write(const DiaryEntriesCompanion(dirty: Value(false)));
      // The catalogues as well, or the answer is only part honoured: a tag the
      // user invented is unsent data of theirs exactly as a note is, and
      // leaving its mark on would send it up on the next run while the dialog
      // said nothing would go. The eight seeded moods are already settled and
      // are never offered anyway — see [pendingMoods] — so this reaches only
      // the ones somebody made.
      await update(
        noteTags,
      ).write(const NoteTagsCompanion(dirty: Value(false)));
      await update(
        noteMoods,
      ).write(const NoteMoodsCompanion(dirty: Value(false)));
      // Deletions of notes that are staying here are nobody else's news.
      await delete(syncTombstones).go();
    });
  }

  /// Every note, label and link on this device, gone. The twin of
  /// [TasksDao.wipeAllTasks], and always run with it.
  ///
  /// The eight seeded moods **stay**. They are not the user's data — they are a
  /// constant of the app, written out in `defaultNoteMoods` and shared by every
  /// account on the server — and deleting them would empty the mood picker for
  /// whoever signs in next. Everything a person actually made goes, including a
  /// mood they invented: that one is theirs, and it is exactly what the next
  /// account must not find waiting.
  ///
  /// A mood with no uid goes too. It cannot be a seeded one — those carry
  /// theirs from the list — so it is somebody's, and `uid NOT IN (...)` alone
  /// would answer null for it and leave it behind.
  ///
  /// The image **files** are not this method's to remove: they live on disk,
  /// not in the database. [wipeAccountData] deletes them around this call.
  Future<void> wipeAllEntries() {
    return transaction(() async {
      await delete(diaryEntryMoods).go();
      await delete(diaryEntryTags).go();
      await delete(diaryEntries).go();
      await delete(noteTags).go();
      await (delete(noteMoods)..where(
            (m) => m.uid.isNull() | m.uid.isNotIn(defaultNoteMoodUids.toList()),
          ))
          .go();
      await (delete(
        syncTombstones,
      )..where((t) => t.sourceTable.equals(diaryEntries.actualTableName))).go();
    });
  }

  /// Fresh identities for the notes and the labels somebody made, and the marks
  /// to send them again. The twin of [TasksDao.remintTaskUids] — the reasoning
  /// is written out there.
  ///
  /// The seeded moods are left alone, and that is the whole point of telling
  /// them apart: their uuids are constants shared with the server and every
  /// other install, so a new one would not be a fresh identity but a mood
  /// nobody else has ever heard of.
  Future<void> remintEntryUids() {
    return transaction(() async {
      for (final entry in await select(diaryEntries).get()) {
        await (update(diaryEntries)..where((e) => e.id.equals(entry.id))).write(
          DiaryEntriesCompanion(
            uid: Value(_uuid.v4()),
            dirty: const Value(true),
          ),
        );
      }
      for (final tag in await select(noteTags).get()) {
        await (update(noteTags)..where((t) => t.id.equals(tag.id))).write(
          NoteTagsCompanion(uid: Value(_uuid.v4()), dirty: const Value(true)),
        );
      }
      final mine =
          await (select(noteMoods)..where(
                (m) =>
                    m.uid.isNull() |
                    m.uid.isNotIn(defaultNoteMoodUids.toList()),
              ))
              .get();
      for (final mood in mine) {
        await (update(noteMoods)..where((m) => m.id.equals(mood.id))).write(
          NoteMoodsCompanion(uid: Value(_uuid.v4()), dirty: const Value(true)),
        );
      }
      await (delete(
        syncTombstones,
      )..where((t) => t.sourceTable.equals(diaryEntries.actualTableName))).go();
    });
  }

  /// The deletions this device has to report. Cleared by [clearTombstones]
  /// once the server has been told, and not before: a tombstone dropped after a
  /// failed send is a note that quietly returns.
  Future<List<SyncTombstone>> pendingTombstones() =>
      select(syncTombstones).get();

  /// Writes a note as the server has it, by [uid].
  ///
  /// Not through [updateEntryById]: this must **not** set `dirty`, and it must
  /// not move `updatedAt` either — the timestamp is part of what came down, and
  /// overwriting it with the local clock would make the row look newer than the
  /// copy it was just taken from.
  ///
  /// Returns whether a row was there to update. False means the note is new to
  /// this device and the caller should insert it instead — that is the caller's
  /// decision because only it knows the note's local parent ids.
  Future<bool> applyRemoteEntry(String uid, DiaryEntriesCompanion entry) async {
    final changed =
        await (update(diaryEntries)..where((e) => e.uid.equals(uid))).write(
          entry.copyWith(uid: Value(uid), dirty: const Value(false)),
        );
    return changed > 0;
  }

  Future<bool> applyRemoteMood(String uid, NoteMoodsCompanion mood) async {
    final changed = await (update(noteMoods)..where((m) => m.uid.equals(uid)))
        .write(mood.copyWith(uid: Value(uid), dirty: const Value(false)));
    return changed > 0;
  }

  Future<bool> applyRemoteTag(String uid, NoteTagsCompanion tag) async {
    final changed = await (update(noteTags)..where((t) => t.uid.equals(uid)))
        .write(tag.copyWith(uid: Value(uid), dirty: const Value(false)));
    return changed > 0;
  }

  /// Takes a note the server has and this device has not.
  ///
  /// Separate from [insertEntry] because that one mints a uid and leaves the
  /// row dirty — right for a note the user just wrote, wrong for one that came
  /// down the wire already carrying both answers.
  Future<int> insertRemoteEntry(String uid, DiaryEntriesCompanion entry) =>
      into(
        diaryEntries,
      ).insert(entry.copyWith(uid: Value(uid), dirty: const Value(false)));

  Future<int> insertRemoteMood(String uid, NoteMoodsCompanion mood) => into(
    noteMoods,
  ).insert(mood.copyWith(uid: Value(uid), dirty: const Value(false)));

  Future<int> insertRemoteTag(String uid, NoteTagsCompanion tag) => into(
    noteTags,
  ).insert(tag.copyWith(uid: Value(uid), dirty: const Value(false)));

  /// Finds a note by the identity the server knows it by.
  Future<DiaryEntry?> entryByUid(String uid) =>
      (select(diaryEntries)..where((e) => e.uid.equals(uid))).getSingleOrNull();

  Future<NoteMood?> moodByUid(String uid) =>
      (select(noteMoods)..where((m) => m.uid.equals(uid))).getSingleOrNull();

  Future<NoteTag?> tagByUid(String uid) =>
      (select(noteTags)..where((t) => t.uid.equals(uid))).getSingleOrNull();

  /// Marks the listed notes as sent. Called **after** the server has taken
  /// them, never before — a row cleared optimistically is an edit thrown away.
  ///
  /// Matched by uid rather than id, and only where the row is still the one
  /// that was sent: an edit made while the send was in flight has moved
  /// `updatedAt` on, and clearing that would lose it.
  Future<void> clearEntryDirty(Map<String, DateTime> sentAt) async {
    for (final entry in sentAt.entries) {
      await (update(diaryEntries)..where(
            (e) =>
                e.uid.equals(entry.key) &
                e.updatedAt.isSmallerOrEqualValue(entry.value),
          ))
          .write(const DiaryEntriesCompanion(dirty: Value(false)));
    }
  }

  /// The catalogues have no `updatedAt`, so there is no such race to guard
  /// against — a mood is written once and never edited by anything in the app.
  Future<void> clearMoodDirty(Iterable<String> uids) =>
      (update(noteMoods)..where((m) => m.uid.isIn(uids))).write(
        const NoteMoodsCompanion(dirty: Value(false)),
      );

  Future<void> clearTagDirty(Iterable<String> uids) =>
      (update(noteTags)..where((t) => t.uid.isIn(uids))).write(
        const NoteTagsCompanion(dirty: Value(false)),
      );

  /// Forgets deletions the server has been told about.
  Future<void> clearTombstones(Iterable<String> uids) =>
      (delete(syncTombstones)..where((t) => t.uid.isIn(uids))).go();

  // ---------------------------------------------------------------------------
  // Links, in the terms the server uses.
  //
  // A link is a pair of local integer ids here and a pair of uuids there, so
  // every crossing needs translating. It happens in these four methods and
  // nowhere else.
  // ---------------------------------------------------------------------------

  /// The uids of a note's moods — what a push sends in place of local ids.
  Future<List<String>> moodUidsForEntry(int entryId) async {
    final query = select(diaryEntryMoods).join([
      innerJoin(noteMoods, noteMoods.id.equalsExp(diaryEntryMoods.moodId)),
    ])..where(diaryEntryMoods.entryId.equals(entryId));
    final rows = await query.get();
    // The null-aware element drops a row whose uid is somehow missing
    // rather than sending "null" up as an identity.
    return [for (final row in rows) ?row.readTable(noteMoods).uid];
  }

  Future<List<String>> tagUidsForEntry(int entryId) async {
    final query = select(diaryEntryTags).join([
      innerJoin(noteTags, noteTags.id.equalsExp(diaryEntryTags.tagId)),
    ])..where(diaryEntryTags.entryId.equals(entryId));
    final rows = await query.get();
    // The null-aware element drops a row whose uid is somehow missing
    // rather than sending "null" up as an identity.
    return [for (final row in rows) ?row.readTable(noteTags).uid];
  }

  /// Makes the note's moods exactly [moodIds], the way the server has them.
  ///
  /// The twin of [setEntryMoods], and the difference is the whole reason it
  /// exists: this one does **not** touch the note. Marking it here would send
  /// the labels straight back up as if this device had chosen them, and the
  /// two phones would trade the same set forever.
  Future<void> applyRemoteEntryMoods(int entryId, Iterable<int> moodIds) {
    return transaction(() async {
      await (delete(
        diaryEntryMoods,
      )..where((l) => l.entryId.equals(entryId))).go();
      if (moodIds.isEmpty) return;
      await batch((b) {
        b.insertAll(diaryEntryMoods, [
          for (final moodId in moodIds)
            DiaryEntryMoodsCompanion.insert(entryId: entryId, moodId: moodId),
        ]);
      });
    });
  }

  Future<void> applyRemoteEntryTags(int entryId, Iterable<int> tagIds) {
    return transaction(() async {
      await (delete(
        diaryEntryTags,
      )..where((l) => l.entryId.equals(entryId))).go();
      if (tagIds.isEmpty) return;
      await batch((b) {
        b.insertAll(diaryEntryTags, [
          for (final tagId in tagIds)
            DiaryEntryTagsCompanion.insert(entryId: entryId, tagId: tagId),
        ]);
      });
    });
  }

  /// Removes a note the server says is gone, links and all.
  ///
  /// Not [deleteEntry]: that one writes a tombstone, and a tombstone for a
  /// deletion this device is merely *learning about* would be sent back as
  /// news. Returns whether there was anything to remove.
  Future<bool> deleteEntryByUid(String uid) {
    return transaction(() async {
      final entry = await entryByUid(uid);
      if (entry == null) return false;
      await (delete(
        diaryEntryMoods,
      )..where((l) => l.entryId.equals(entry.id))).go();
      await (delete(
        diaryEntryTags,
      )..where((l) => l.entryId.equals(entry.id))).go();
      await (delete(diaryEntries)..where((e) => e.id.equals(entry.id))).go();
      return true;
    });
  }
}
