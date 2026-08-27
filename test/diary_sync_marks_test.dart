import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';

/// The marks the diary leaves so that a sync can tell what changed: a `uid` to
/// be known by, a `dirty` flag for "changed here", and a tombstone for the one
/// edit that otherwise leaves nothing behind.
///
/// Nothing here touches a network — that is the whole point of putting the
/// marks in the DAO. What is being pinned is the asymmetry: a write the *user*
/// made is dirty, a write the *server* sent is not.
void main() {
  late AppDatabase db;
  late DiaryDao dao;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    dao = db.diaryDao;
  });

  tearDown(() => db.close());

  Future<int> addNote(String title) =>
      dao.insertEntry(DiaryEntriesCompanion.insert(title: Value(title)));

  Future<DiaryEntry> note(int id) async => (await dao.getEntry(id))!;

  group('what the user writes', () {
    test('a new note is given a uid and starts out unsent', () async {
      final id = await addNote('Первая');
      final saved = await note(id);

      expect(saved.uid, isNotNull);
      expect(saved.uid, isNotEmpty);
      expect(saved.dirty, isTrue);
    });

    test('two notes do not share a uid', () async {
      final first = await note(await addNote('Одна'));
      final second = await note(await addNote('Другая'));

      expect(first.uid, isNot(second.uid));
    });

    test('an edit marks the note unsent again', () async {
      final id = await addNote('Заметка');
      await dao.clearEntryDirty({(await note(id)).uid!: DateTime.now()});
      expect((await note(id)).dirty, isFalse);

      await dao.setBody(id, 'новый текст');

      expect((await note(id)).dirty, isTrue);
    });

    test('starring counts as an edit', () async {
      final id = await addNote('Заметка');
      await dao.clearEntryDirty({(await note(id)).uid!: DateTime.now()});

      await dao.setFavorite(id, true);

      expect((await note(id)).dirty, isTrue);
    });

    test('a mood and a tag are given uids', () async {
      final moodId = await dao.insertMood(name: 'Своё', emoji: '🎈');
      final tagId = await dao.insertTag(name: 'идеи', colorKey: 'blue');

      final moods = await db.select(db.noteMoods).get();
      final tags = await db.select(db.noteTags).get();

      expect(moods.firstWhere((m) => m.id == moodId).uid, isNotNull);
      expect(tags.firstWhere((t) => t.id == tagId).uid, isNotNull);
    });
  });

  group('labels', () {
    test('changing them marks the note, because links carry no mark of their '
        'own', () async {
      final id = await addNote('Заметка');
      final moodId = await dao.insertMood(name: 'Своё', emoji: '🎈');
      await dao.clearEntryDirty({(await note(id)).uid!: DateTime.now()});

      await dao.setEntryMoods(id, [moodId]);

      // Without this the link rows would never be sent: `diary_entry_moods` has
      // no uid and no dirty column, so a dirty parent is the only signal there
      // is.
      expect((await note(id)).dirty, isTrue);
    });

    test('clearing them marks the note too', () async {
      final id = await addNote('Заметка');
      final tagId = await dao.insertTag(name: 'идеи', colorKey: 'blue');
      await dao.setEntryTags(id, [tagId]);
      await dao.clearEntryDirty({(await note(id)).uid!: DateTime.now()});

      await dao.setEntryTags(id, const []);

      expect((await note(id)).dirty, isTrue);
      expect(await dao.getTagIdsForEntry(id), isEmpty);
    });
  });

  group('deleting', () {
    test('leaves a tombstone carrying the note\'s uid', () async {
      final id = await addNote('Прощай');
      final uid = (await note(id)).uid;

      await dao.deleteEntry(id);

      final graves = await dao.pendingTombstones();
      expect(graves, hasLength(1));
      expect(graves.single.uid, uid);
      expect(graves.single.sourceTable, 'diary_entries');
      expect(await dao.getEntry(id), isNull);
    });

    test('takes the link rows with it', () async {
      final id = await addNote('Прощай');
      final moodId = await dao.insertMood(name: 'Своё', emoji: '🎈');
      await dao.setEntryMoods(id, [moodId]);

      await dao.deleteEntry(id);

      expect(await dao.getMoodIdsForEntry(id), isEmpty);
    });

    test('the same note twice does not throw', () async {
      // The tombstone key is (sourceTable, uid); re-recording a deletion is the
      // same fact, not a second one. A plain insert would fail here.
      final id = await addNote('Прощай');
      final uid = (await note(id)).uid!;

      await dao.deleteEntry(id);
      await db
          .into(db.syncTombstones)
          .insert(
            SyncTombstonesCompanion.insert(
              sourceTable: 'diary_entries',
              uid: uid,
            ),
            mode: InsertMode.insertOrReplace,
          );

      expect(await dao.pendingTombstones(), hasLength(1));
    });

    test('a tombstone survives until it is explicitly forgotten', () async {
      final id = await addNote('Прощай');
      final uid = (await note(id)).uid!;
      await dao.deleteEntry(id);

      await dao.clearTombstones([uid]);

      expect(await dao.pendingTombstones(), isEmpty);
    });
  });

  group('what the server sends', () {
    test('does not come back marked as ours', () async {
      final id = await addNote('Заметка');
      final uid = (await note(id)).uid!;

      final applied = await dao.applyRemoteEntry(
        uid,
        DiaryEntriesCompanion(title: const Value('С другого устройства')),
      );

      expect(applied, isTrue);
      final saved = await note(id);
      expect(saved.title, 'С другого устройства');
      // The bug this guards against does not throw and does not log: a row
      // marked dirty by the very write that brought it down is sent straight
      // back, and the two devices hand it to each other forever.
      expect(saved.dirty, isFalse);
    });

    test('reports when there was nothing to update', () async {
      final applied = await dao.applyRemoteEntry(
        'a-uid-this-device-has-never-seen',
        const DiaryEntriesCompanion(title: Value('Чужая')),
      );

      expect(applied, isFalse);
    });

    test('a note new to this device arrives clean', () async {
      await dao.insertRemoteEntry(
        'uid-from-the-server',
        const DiaryEntriesCompanion(title: Value('Оттуда')),
      );

      final saved = await dao.entryByUid('uid-from-the-server');
      expect(saved, isNotNull);
      expect(saved!.title, 'Оттуда');
      expect(saved.dirty, isFalse);
    });

    test('a mood and a tag arrive clean too', () async {
      await dao.insertRemoteMood(
        'mood-uid',
        NoteMoodsCompanion.insert(name: 'Радость', emoji: '😊'),
      );
      await dao.insertRemoteTag(
        'tag-uid',
        NoteTagsCompanion.insert(name: 'идеи', colorKey: const Value('blue')),
      );

      expect((await dao.moodByUid('mood-uid'))!.dirty, isFalse);
      expect((await dao.tagByUid('tag-uid'))!.dirty, isFalse);
    });
  });

  group('clearing the mark after a send', () {
    test('an edit made while the send was in flight is not lost', () async {
      final id = await addNote('Заметка');
      final sent = await note(id);

      // The send is away; the user keeps typing. Both writes land inside the
      // same wall-clock second, which is the whole difficulty: drift keeps
      // whole seconds, so only `updateEntryById` stepping the stamp forward
      // makes the two versions tellable apart. Without that the clear below
      // swallows this edit and nothing ever sends it again.
      await dao.setBody(id, 'правка во время отправки');

      await dao.clearEntryDirty({sent.uid!: sent.updatedAt});

      expect((await note(id)).dirty, isTrue);
      expect(
        (await note(id)).updatedAt.isAfter(sent.updatedAt),
        isTrue,
        reason: 'an edit must be orderable after the version that was sent',
      );
    });

    test('a second edit inside the same second still moves the stamp', () async {
      final id = await addNote('Заметка');
      final first = await note(id);
      await dao.setBody(id, 'раз');
      final second = await note(id);
      await dao.setBody(id, 'два');
      final third = await note(id);

      expect(second.updatedAt.isAfter(first.updatedAt), isTrue);
      expect(third.updatedAt.isAfter(second.updatedAt), isTrue);
    });

    test('an untouched note is cleared', () async {
      final id = await addNote('Заметка');
      final saved = await note(id);

      await dao.clearEntryDirty({saved.uid!: saved.updatedAt});

      expect((await note(id)).dirty, isFalse);
    });
  });

  group('pending reads', () {
    test('list only what has not been sent', () async {
      final kept = await addNote('Не отправлена');
      final sent = await addNote('Отправлена');
      final sentNote = await note(sent);
      await dao.clearEntryDirty({sentNote.uid!: sentNote.updatedAt});

      final pending = await dao.pendingEntries();

      expect(pending.map((e) => e.id), [kept]);
    });

    test('the seeded moods are pending until they are sent', () async {
      // They arrive with the migration and have never been near a server, so
      // "dirty" is the truth about them.
      expect(await dao.pendingMoods(), hasLength(8));
    });
  });
}
