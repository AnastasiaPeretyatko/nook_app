import 'package:drift/drift.dart';
import '../app_database.dart';

part 'diary_dao.g.dart';

/// Reads and writes diary entries.
///
/// Everything is streamed unfiltered and sorted newest-touched-first: the four
/// tabs of the diary are a filter over one list — three of them on
/// [DiaryEntries.status], one on [DiaryEntries.isFavorite] — so one stream feeds
/// them all instead of four queries racing each other.
@DriftAccessor(
  tables: [
    DiaryEntries,
    NoteMoods,
    NoteTags,
    DiaryEntryMoods,
    DiaryEntryTags,
  ],
)
class DiaryDao extends DatabaseAccessor<AppDatabase> with _$DiaryDaoMixin {
  DiaryDao(super.db);

  Stream<List<DiaryEntry>> watchEntries() =>
      (select(diaryEntries)..orderBy([
            (e) => OrderingTerm(
              expression: e.updatedAt,
              mode: OrderingMode.desc,
            ),
          ]))
          .watch();

  /// One entry, live: the view screen redraws itself when the note is starred,
  /// archived or edited, and reports null once it is deleted.
  Stream<DiaryEntry?> watchEntry(int id) =>
      (select(diaryEntries)..where((e) => e.id.equals(id))).watchSingleOrNull();

  Future<DiaryEntry?> getEntry(int id) =>
      (select(diaryEntries)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<int> insertEntry(DiaryEntriesCompanion entry) =>
      into(diaryEntries).insert(entry);

  /// Partial write: only the fields present in [entry] are touched, so a caller
  /// that knows about the title alone cannot blank the body.
  Future<int> updateEntryById(int id, DiaryEntriesCompanion entry) =>
      (update(diaryEntries)..where((e) => e.id.equals(id))).write(
        entry.copyWith(updatedAt: Value(DateTime.now())),
      );

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
  Future<int> deleteEntry(int id) {
    return transaction(() async {
      await (delete(diaryEntryMoods)..where((l) => l.entryId.equals(id))).go();
      await (delete(diaryEntryTags)..where((l) => l.entryId.equals(id))).go();
      return (delete(diaryEntries)..where((e) => e.id.equals(id))).go();
    });
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
  Stream<List<NoteMood>> watchMoods() =>
      (select(noteMoods)..orderBy([(m) => OrderingTerm(expression: m.id)]))
          .watch();

  /// Every tag, oldest first — same reasoning as [watchMoods].
  Stream<List<NoteTag>> watchTags() =>
      (select(noteTags)..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .watch();

  /// Adds a mood and hands back its id, so the picker can select what it just
  /// created without waiting for the stream to come round.
  Future<int> insertMood({required String name, required String emoji}) =>
      into(noteMoods).insert(
        NoteMoodsCompanion.insert(name: name, emoji: emoji),
      );

  Future<int> insertTag({required String name, required int colorValue}) =>
      into(noteTags).insert(
        NoteTagsCompanion.insert(name: name, colorValue: colorValue),
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
    final rows =
        await (select(diaryEntryMoods)
              ..where((l) => l.entryId.equals(entryId)))
            .get();
    return [for (final row in rows) row.moodId];
  }

  Future<List<int>> getTagIdsForEntry(int entryId) async {
    final rows =
        await (select(diaryEntryTags)..where((l) => l.entryId.equals(entryId)))
            .get();
    return [for (final row in rows) row.tagId];
  }

  /// Makes the note's moods exactly [moodIds] — the form owns the whole set, so
  /// it is replaced rather than added to, and an empty list clears it.
  ///
  /// Delete-then-insert inside a transaction, rather than working out what
  /// changed: the sets are two or three rows long, and a diff would be more code
  /// than it saves. `updatedAt` on the note is deliberately **not** touched —
  /// [updateEntryById] has already moved it in the same save, and a screen that
  /// only changes labels does not exist.
  Future<void> setEntryMoods(int entryId, Iterable<int> moodIds) {
    return transaction(() async {
      await (delete(diaryEntryMoods)
            ..where((l) => l.entryId.equals(entryId)))
          .go();
      if (moodIds.isEmpty) return;
      await batch((b) {
        b.insertAll(diaryEntryMoods, [
          for (final moodId in moodIds)
            DiaryEntryMoodsCompanion.insert(entryId: entryId, moodId: moodId),
        ]);
      });
    });
  }

  Future<void> setEntryTags(int entryId, Iterable<int> tagIds) {
    return transaction(() async {
      await (delete(diaryEntryTags)..where((l) => l.entryId.equals(entryId)))
          .go();
      if (tagIds.isEmpty) return;
      await batch((b) {
        b.insertAll(diaryEntryTags, [
          for (final tagId in tagIds)
            DiaryEntryTagsCompanion.insert(entryId: entryId, tagId: tagId),
        ]);
      });
    });
  }
}
