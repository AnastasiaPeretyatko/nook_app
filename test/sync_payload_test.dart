import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/sync/payload.dart';
import 'package:todo_app/utils/task_palette.dart';

/// Turning a row into what the server stores, and back.
///
/// Every failure this guards against is silent. A date sent in the wrong scale
/// still arrives; an enum spelled differently still parses as *something*; a
/// missing field still yields a note. Nothing throws — the note is just quietly
/// wrong, on the device the user is not looking at.
void main() {
  DiaryEntry note({
    String uid = 'note-uid',
    String title = 'Заголовок',
    DiaryEntryStatus status = DiaryEntryStatus.normal,
    String? cover,
    bool favorite = false,
  }) => DiaryEntry(
    id: 1,
    uid: uid,
    dirty: true,
    title: title,
    body: '[{"insert":"текст\\n"}]',
    coverImage: cover,
    images: '[]',
    isFavorite: favorite,
    status: status,
    createdAt: DateTime.utc(2026, 8, 26, 9),
    updatedAt: DateTime.utc(2026, 8, 26, 10),
  );

  group('going up', () {
    test('sends the uid as the identity, never the local id', () {
      final row = entryToRow(note());

      expect(row['id'], 'note-uid');
      // The local id counts from 1 on every device. Sending it would make two
      // phones claim the same note.
      expect(row.containsKey('local_id'), isFalse);
    });

    test('leaves user_id and updated_at to the server', () {
      final row = entryToRow(note());

      // `user_id` defaults to auth.uid() and `updated_at` is set by trigger;
      // a client that names either can only be wrong or lying.
      expect(row.containsKey('user_id'), isFalse);
      expect(row.containsKey('updated_at'), isFalse);
    });

    test('dates go up as UTC with a zone on them', () {
      final row = entryToRow(note());

      // Postgres reads a bare timestamp as its own zone, so a stamp without a
      // marker drifts by however far the two clocks are apart — and only for
      // users outside UTC, which is why it would never be noticed here.
      expect(row['client_updated_at'], endsWith('Z'));
      expect(row['created_at'], endsWith('Z'));
      expect(
        DateTime.parse(row['client_updated_at'] as String).toUtc(),
        DateTime.utc(2026, 8, 26, 10),
      );
    });

    test('a local time is converted, not relabelled', () {
      final local = DateTime.utc(2026, 8, 26, 10).toLocal();
      final row = entryToRow(
        DiaryEntry(
          id: 1,
          uid: 'u',
          dirty: true,
          title: '',
          body: '',
          images: '[]',
          isFavorite: false,
          status: DiaryEntryStatus.normal,
          createdAt: local,
          updatedAt: local,
        ),
      );

      expect(
        DateTime.parse(row['client_updated_at'] as String).toUtc(),
        DateTime.utc(2026, 8, 26, 10),
      );
    });

    test('the status travels as the name the app uses', () {
      expect(
        entryToRow(note(status: DiaryEntryStatus.archived))['status'],
        'archived',
      );
    });

    test('a missing cover stays missing', () {
      expect(entryToRow(note())['cover_image'], isNull);
      expect(entryToRow(note(cover: 'a.jpg'))['cover_image'], 'a.jpg');
    });
  });

  group('coming back', () {
    Map<String, dynamic> row({
      Object? status = 'normal',
      Object? clientUpdated = '2026-08-26T10:00:00Z',
      Object? deleted,
    }) => {
      'id': 'note-uid',
      'title': 'Заголовок',
      'body': '[]',
      'cover_image': null,
      'images': '[]',
      'is_favorite': true,
      'status': status,
      'created_at': '2026-08-26T09:00:00Z',
      'client_updated_at': clientUpdated,
      'updated_at': '2026-08-26T11:00:00Z',
      'deleted_at': deleted,
    };

    test('takes the note\'s own edit time, not the server\'s', () {
      final companion = entryFromRow(row());

      // The server's `updated_at` is when the row was written, which is later
      // than the edit and unrelated to it. Taking it would make every pulled
      // note look freshly touched and jump it to the top of the diary.
      expect(
        companion.updatedAt,
        Value(DateTime.parse('2026-08-26T10:00:00Z')),
      );
    });

    test('survives a status it has never heard of', () {
      // A newer version of the app may add one. An older phone should still be
      // able to read the note rather than take the whole sync down.
      expect(
        entryFromRow(row(status: 'something_new')).status.value,
        DiaryEntryStatus.normal,
      );
    });

    test('survives a missing or malformed date', () {
      expect(entryFromRow(row(clientUpdated: null)).updatedAt.present, isTrue);
      expect(
        entryFromRow(row(clientUpdated: 'вчера')).updatedAt.present,
        isTrue,
      );
    });

    test('reads the deletion mark', () {
      expect(isDeleted(row()), isFalse);
      expect(isDeleted(row(deleted: '2026-08-26T12:00:00Z')), isTrue);
    });

    test('keeps the server stamp for the watermark alone', () {
      expect(serverUpdatedAt(row()), DateTime.parse('2026-08-26T11:00:00Z'));
      expect(clientUpdatedAt(row()), DateTime.parse('2026-08-26T10:00:00Z'));
    });
  });

  group('there and back', () {
    test('a note survives the round trip unchanged', () {
      final original = note(
        title: 'Про рыбалку',
        status: DiaryEntryStatus.archived,
        cover: 'cover.jpg',
        favorite: true,
      );

      final returned = entryFromRow({
        ...entryToRow(original),
        'updated_at': '2026-08-26T11:00:00Z',
        'deleted_at': null,
      });

      expect(returned.title.value, original.title);
      expect(returned.body.value, original.body);
      expect(returned.coverImage.value, original.coverImage);
      expect(returned.images.value, original.images);
      expect(returned.isFavorite.value, original.isFavorite);
      expect(returned.status.value, original.status);
      expect(returned.createdAt.value.toUtc(), original.createdAt.toUtc());
      expect(returned.updatedAt.value.toUtc(), original.updatedAt.toUtc());
    });

    test('an unknown colour key falls back rather than failing', () {
      // A key written by a newer version of the app names a family this one has
      // never heard of. The tag should still be readable.
      final back = tagFromRow({
        'id': 'tag-uid',
        'name': 'идеи',
        'color_key': 'teal-that-does-not-exist-yet',
        'created_at': '2026-08-26T09:00:00Z',
      });
      expect(back.colorKey.value, 'teal-that-does-not-exist-yet');
      expect(taskColorForKey(back.colorKey.value), taskPalette.first.accent);
    });

    test('a mood and a tag survive it too', () {
      final mood = NoteMood(
        id: 1,
        uid: 'mood-uid',
        dirty: true,
        name: 'Радость',
        emoji: '😊',
        createdAt: DateTime.utc(2026, 8, 26, 9),
      );
      final tag = NoteTag(
        id: 1,
        uid: 'tag-uid',
        dirty: true,
        name: 'идеи',
        colorKey: 'violet',
        createdAt: DateTime.utc(2026, 8, 26, 9),
      );

      final backMood = moodFromRow(moodToRow(mood));
      final backTag = tagFromRow(tagToRow(tag));

      expect(backMood.name.value, 'Радость');
      expect(backMood.emoji.value, '😊');
      expect(backTag.name.value, 'идеи');
      expect(backTag.colorKey.value, 'violet');
      // A key, not a colour. `0xFF8B7CF6` is a fact about this version of the
      // palette; `violet` is a fact about the tag, so the design can be
      // repainted and every tag ever written follows without a migration.
      //
      // It also settles a mismatch that only ever appeared at the boundary: an
      // opaque ARGB starts with `0xFF` and so exceeds 2^31, which SQLite stored
      // without comment and Postgres `integer` refused outright.
      expect(tagToRow(tag)['color_key'], 'violet');
    });
  });

  group('tasks going up and coming back', () {
    Task habit({
      String uid = 'task-uid',
      int? parentId,
      String title = 'Зарядка',
      RepeatType? repeatType = RepeatType.weekly,
      TrackingMode trackingMode = TrackingMode.counter,
      int? colorValue = 0xFF9C8DDB, // violet: the lavender family
      DateTime? startDate,
    }) => Task(
      id: 1,
      uid: uid,
      dirty: true,
      parentId: parentId,
      title: title,
      description: 'по утрам',
      status: TaskStatus.active,
      repeatType: repeatType,
      repeatInterval: 2,
      repeatDaysMask: 0x15,
      trackingMode: trackingMode,
      targetDurationMinutes: 30,
      targetValue: 8,
      iconKey: 'dumbbell',
      iconCodePoint: 0xe1a5,
      colorValue: colorValue,
      scheduledTimeMinutes: 480,
      endTimeMinutes: 540,
      startDate: startDate ?? DateTime(2026, 8, 26),
      createdAt: DateTime.utc(2026, 8, 1, 9),
      updatedAt: DateTime.utc(2026, 8, 26, 10),
    );

    TaskLog mark({DateTime? on, bool completed = true, double? value = 3}) =>
        TaskLog(
          id: 1,
          taskId: 1,
          date: on ?? DateTime(2026, 8, 26),
          completed: completed,
          value: value,
          dirty: true,
          updatedAt: DateTime.utc(2026, 8, 26, 10),
        );

    test('sends the uid as the identity, never the local id', () {
      final row = taskToRow(habit());

      expect(row['id'], 'task-uid');
      expect(row.containsKey('local_id'), isFalse);
      expect(row.containsKey('id_local'), isFalse);
    });

    test('leaves user_id and updated_at to the server', () {
      final row = taskToRow(habit());

      // The server fills the first from `auth.uid()` and stamps the second on
      // its own clock. A client that named either could only get it wrong.
      expect(row.containsKey('user_id'), isFalse);
      expect(row.containsKey('updated_at'), isFalse);
      expect(row.containsKey('client_updated_at'), isTrue);
    });

    test('a parent is named by uid, and a root by nothing', () {
      // The one thing this file cannot work out for itself: a parent is a local
      // integer here and a uuid there, so the engine hands the uid in.
      expect(
        taskToRow(habit(parentId: 7), parentUid: 'parent-uid')['parent_id'],
        'parent-uid',
      );
      expect(taskToRow(habit())['parent_id'], isNull);
    });

    test('the dead icon code point is not sent', () {
      // It is the Material code point tasks carried before `icon_key`; nothing
      // reads it, and a code point means something only inside one font.
      final row = taskToRow(habit());

      expect(row.containsKey('icon_code_point'), isFalse);
      expect(row['icon_key'], 'dumbbell');
    });

    test('the colour goes as a palette key, not as a number', () {
      // `0xFF8B7CF6` is a fact about this version of the palette. It is also
      // above 2^31, which SQLite stores without comment and a Postgres
      // `integer` refuses outright — the mismatch that bit the tags at 002.
      final row = taskToRow(habit());

      expect(row['color_key'], 'violet');
      expect(row.containsKey('color_value'), isFalse);
    });

    test('no colour survives the trip as no colour', () {
      // A real state, not a missing one: the screens draw such a task in the
      // first family, and it must not come back having been given a colour.
      final row = taskToRow(habit(colorValue: null));

      expect(row['color_key'], isNull);
      expect(taskFromRow(row).colorValue.value, isNull);
    });

    test('a colour comes back as the number the app draws with', () {
      final back = taskFromRow(taskToRow(habit()));

      expect(back.colorValue.value, taskColorForKey('violet').toARGB32());
    });

    test('a key the app has never heard of reads as no colour', () {
      // A newer version with an eighth family. Better a task with no colour
      // than a sync that stops.
      final back = taskFromRow({'color_key': 'chartreuse'});

      expect(back.colorValue.value, isNull);
    });

    test('everything else round-trips', () {
      final back = taskFromRow(taskToRow(habit()));

      expect(back.title.value, 'Зарядка');
      expect(back.description.value, 'по утрам');
      expect(back.status.value, TaskStatus.active);
      expect(back.repeatType.value, RepeatType.weekly);
      expect(back.repeatInterval.value, 2);
      expect(back.repeatDaysMask.value, 0x15);
      expect(back.trackingMode.value, TrackingMode.counter);
      expect(back.targetDurationMinutes.value, 30);
      expect(back.targetValue.value, 8);
      expect(back.iconKey.value, 'dumbbell');
      expect(back.scheduledTimeMinutes.value, 480);
      expect(back.endTimeMinutes.value, 540);
    });

    test('a one-off task keeps its lack of a repeat rule', () {
      // Null `repeatType` is what separates the two tabs of the app. Reading it
      // as a fallback would turn every task into a daily habit.
      final back = taskFromRow(taskToRow(habit(repeatType: null)));

      expect(back.repeatType.value, isNull);
    });

    test('an unknown enum value falls back rather than throwing', () {
      // Written by a newer version of the app. A task from a newer phone should
      // still be readable rather than taking the whole sync down.
      final back = taskFromRow({
        'status': 'hibernating',
        'tracking_mode': 'telepathy',
        'repeat_type': 'fortnightly',
      });

      expect(back.status.value, TaskStatus.active);
      expect(back.trackingMode.value, TrackingMode.checkbox);
      expect(back.repeatType.value, isNull);
    });

    test('a day mark is the pair and nothing else', () {
      final row = logToRow(mark(), taskUid: 'task-uid');

      expect(row['task_id'], 'task-uid');
      expect(row['date'], '2026-08-26');
      // No identity of its own: the pair *is* the row, here and on the server.
      expect(row.containsKey('id'), isFalse);
      expect(row.containsKey('uid'), isFalse);
    });

    test('a day mark round-trips its answer', () {
      final back = logFromRow(logToRow(mark(), taskUid: 'task-uid'));

      expect(back.completed.value, isTrue);
      expect(back.value.value, 3);
      expect(back.date.value, DateTime(2026, 8, 26));
    });
  });

  // ---------------------------------------------------------------------------

  group('the calendar day', () {
    // The conversion that would go wrong silently and only for some people.
    //
    // A day mark and a task's start date are **days**, not moments. Locally they
    // are midnight *in the device's own zone*, so `2026-08-26 00:00` in Moscow
    // is `2026-08-25 21:00` as an instant. Sent as an instant into a
    // `timestamptz`, that day comes back as the 25th for everyone east of
    // Greenwich — every habit mark off by one, quietly, and only for part of the
    // users.
    //
    // Every assertion here holds in **any** zone, because both directions go
    // through the local `y/m/d` and never through an instant. The zone-dependent
    // half was checked by running this file under `TZ=Asia/Tokyo` (+09) and
    // `TZ=America/Sao_Paulo` (−03), where an instant-based conversion moves the
    // day and this one does not.

    TaskLog markOn(DateTime at) => TaskLog(
      id: 1,
      taskId: 1,
      date: at,
      completed: true,
      value: null,
      dirty: true,
      updatedAt: DateTime.utc(2026, 8, 26, 10),
    );

    String sentDay(DateTime at) =>
        logToRow(markOn(at), taskUid: 'u')['date'] as String;

    test('is spelled out digit by digit, not as an instant', () {
      expect(sentDay(DateTime(2026, 8, 26)), '2026-08-26');
      // Not an ISO timestamp: no time, no zone, nothing to be wrong about.
      expect(sentDay(DateTime(2026, 8, 26)), isNot(contains('T')));
      expect(sentDay(DateTime(2026, 8, 26)), isNot(contains('Z')));
    });

    test('pads a single-digit month and day', () {
      // `2026-1-5` is not a date Postgres will read the same way every time.
      expect(sentDay(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('a time of day never leaks into it', () {
      for (var hour = 0; hour < 24; hour++) {
        expect(
          sentDay(DateTime(2026, 8, 26, hour, 31)),
          '2026-08-26',
          reason: 'the day moved at $hour:31',
        );
      }
    });

    test('local midnight comes back as local midnight', () {
      for (final day in [
        DateTime(2026, 8, 26),
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
        // A month end and a leap day, where an off-by-one shows up as a
        // different month or a date that does not exist.
        DateTime(2026, 2, 28),
        DateTime(2028, 2, 29),
        DateTime(2026, 3, 29),
      ]) {
        final back = logFromRow(logToRow(markOn(day), taskUid: 'u'));
        expect(back.date.value, day, reason: 'the day moved: $day');
      }
    });

    test("a task's start date takes the same road", () {
      final task = Task(
        id: 1,
        uid: 'task-uid',
        dirty: true,
        title: 'Зарядка',
        status: TaskStatus.active,
        trackingMode: TrackingMode.checkbox,
        startDate: DateTime(2026, 8, 26),
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 26),
      );

      expect(taskToRow(task)['start_date'], '2026-08-26');
      expect(
        taskFromRow(taskToRow(task)).startDate.value,
        DateTime(2026, 8, 26),
      );
    });

    test('no start date stays no start date', () {
      // Null means a backlog task with no day of its own, not a missing value.
      final back = taskFromRow({'start_date': null});
      expect(back.startDate.value, isNull);
    });

    test('a malformed day reads as none rather than as a wrong one', () {
      expect(taskFromRow({'start_date': 'yesterday'}).startDate.value, isNull);
      expect(taskFromRow({'start_date': '2026-08'}).startDate.value, isNull);
    });
  });
}
