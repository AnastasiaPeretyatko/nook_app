import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/note_labels.dart';

/// What happens to a phone when the account on it changes.
///
/// The local database has no notion of who owns a row — there is no `user_id`
/// column in it and there never was — so the previous account's tasks are
/// simply still there when somebody else signs in: on the screen, editable, and
/// impossible to sync, since their uids are the primary keys of rows the other
/// account owns on the server. These are the two ways out of that: remove them,
/// or take them over properly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TasksDao tasks;
  late DiaryDao diary;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    tasks = db.tasksDao;
    diary = db.diaryDao;
  });

  tearDown(() => db.close());

  Future<int> addTask(String title) =>
      tasks.insertTask(TasksCompanion.insert(title: title));

  Future<int> addNote(String title) =>
      diary.insertEntry(DiaryEntriesCompanion.insert(title: Value(title)));

  group('wiping what the previous account left', () {
    test('removes every task, day mark and timer run', () async {
      final id = await addTask('Зарядка');
      await tasks.setLog(id, DateTime(2026, 8, 28), completed: true);
      await tasks.startTimer(id, DateTime(2026, 8, 28, 9), targetSeconds: 600);

      await tasks.wipeAllTasks();

      expect(await db.select(db.tasks).get(), isEmpty);
      expect(await db.select(db.taskLogs).get(), isEmpty);
      // A run left open is a timer ticking against a task that no longer
      // exists; the next `startTimer` would try to bank it into nothing.
      expect(await db.select(db.taskSessions).get(), isEmpty);
    });

    test('removes every note, label and link', () async {
      final note = await addNote('Личное');
      final tag = await diary.insertTag(name: 'Работа', colorKey: 'blue');
      await diary.setEntryTags(note, [tag]);

      await diary.wipeAllEntries();

      expect(await db.select(db.diaryEntries).get(), isEmpty);
      expect(await db.select(db.noteTags).get(), isEmpty);
      expect(await db.select(db.diaryEntryTags).get(), isEmpty);
    });

    test('keeps the eight seeded moods', () async {
      await diary.wipeAllEntries();

      final left = await db.select(db.noteMoods).get();

      // They are a constant of the app, shared by every account on the server,
      // and deleting them would leave whoever signs in next with an empty mood
      // picker.
      expect(left.map((m) => m.uid), unorderedEquals(defaultNoteMoodUids));
    });

    test('removes a mood the user invented', () async {
      await diary.insertMood(name: 'Вдохновение', emoji: '✨');

      await diary.wipeAllEntries();

      // That one is somebody's, and it is exactly what the next account must
      // not find waiting for them.
      expect(await db.select(db.noteMoods).get(), hasLength(8));
    });

    test('drops the tombstones', () async {
      final id = await addTask('Убрать');
      await tasks.deleteTaskCascade(id);
      expect(await diary.pendingTombstones(), hasLength(1));

      await tasks.wipeAllTasks();

      // They name uids belonging to the other account. Sending them would ask
      // the server to delete that account's rows.
      expect(await diary.pendingTombstones(), isEmpty);
    });
  });

  group('taking the data over instead', () {
    test('every task gets a new identity and is marked to send', () async {
      final id = await addTask('Зарядка');
      final before = (await db.select(db.tasks).get()).single;
      await tasks.clearTaskDirty({before.uid!: before.updatedAt});

      await tasks.remintTaskUids();

      final after = (await db.select(db.tasks).get()).single;
      expect(after.id, id, reason: 'the row itself stays where it is');
      expect(after.uid, isNot(before.uid));
      // Both halves matter. Without the mark nothing would ever offer the row;
      // without the new uid the offer would be refused, because the old one is
      // the primary key of a row the other account owns.
      expect(after.dirty, isTrue);
    });

    test('the day marks are marked too', () async {
      final id = await addTask('Зарядка');
      await tasks.setLog(id, DateTime(2026, 8, 28), completed: true);
      final log = (await db.select(db.taskLogs).get()).single;
      await tasks.clearLogDirty([log]);
      expect(await tasks.pendingLogs(), isEmpty);

      await tasks.remintTaskUids();

      // A mark has no identity of its own — it is its task and its day — so it
      // is re-keyed for free by the task's new uid and needs only the mark.
      expect(await tasks.pendingLogs(), hasLength(1));
    });

    test('notes and invented labels get new identities', () async {
      await addNote('Личное');
      await diary.insertTag(name: 'Работа', colorKey: 'blue');
      final noteBefore = (await db.select(db.diaryEntries).get()).single;
      final tagBefore = (await db.select(db.noteTags).get()).single;

      await diary.remintEntryUids();

      final noteAfter = (await db.select(db.diaryEntries).get()).single;
      final tagAfter = (await db.select(db.noteTags).get()).single;
      expect(noteAfter.uid, isNot(noteBefore.uid));
      expect(tagAfter.uid, isNot(tagBefore.uid));
      expect(noteAfter.dirty, isTrue);
      expect(tagAfter.dirty, isTrue);
    });

    test('the seeded moods keep theirs', () async {
      await diary.remintEntryUids();

      final moods = await db.select(db.noteMoods).get();

      // A new uuid here would not be a fresh identity but a mood nobody else
      // has ever heard of: those uuids are constants shared with the server and
      // with every other install.
      expect(moods.map((m) => m.uid), unorderedEquals(defaultNoteMoodUids));
      expect(moods.every((m) => !m.dirty), isTrue);
    });
  });

  group('counting what is on the device', () {
    test('counts rows that have already been sent', () async {
      final id = await addTask('Зарядка');
      final task = (await db.select(db.tasks).get()).single;
      await tasks.clearTaskDirty({task.uid!: task.updatedAt});
      await addNote('Личное');
      final note = (await db.select(db.diaryEntries).get()).single;
      await diary.clearEntryDirty({note.uid!: note.updatedAt});

      // The whole point of not reusing `unsentTaskCount` here. The previous
      // account's rows went up under that account and carry no mark at all, so
      // counting the unsent would find none of them and the dialog protecting
      // them would never open.
      expect(await tasks.unsentTaskCount(), 0);
      expect(await diary.unsentEntryCount(), 0);
      expect(await tasks.taskCount(), 1);
      expect(await diary.entryCount(), 1);
      expect(id, isPositive);
    });

    test('counts root tasks only', () async {
      final parent = await addTask('Уборка');
      await tasks.insertTask(
        TasksCompanion.insert(title: 'Пылесос', parentId: Value(parent)),
      );

      // A subtask is never a row on any screen, and a number the user cannot
      // see is a number they cannot check.
      expect(await tasks.taskCount(), 1);
    });
  });

  group('the seeded moods are never offered to a server', () {
    test('not even when something has marked them', () async {
      await db
          .update(db.noteMoods)
          .write(const NoteMoodsCompanion(dirty: Value(true)));

      // The filter in `pendingMoods` is the single source of truth, not the
      // marks: a device upgraded from a version that seeded them dirty, or one
      // where a pull touched them, must still never send a constant.
      expect(await diary.pendingMoods(), isEmpty);
    });
  });
}
