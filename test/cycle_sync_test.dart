import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/sync/payload.dart';
import 'package:todo_app/utils/cycle_marks.dart';

/// The cycle's day marks: the table, its migration, and what goes to the server.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late CycleDao dao;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    dao = db.cycleDao;
  });
  tearDown(() => db.close());

  final day = DateTime(2026, 10, 16);

  group('CycleDao', () {
    test(
      'a saved day reads back, on the calendar day and marked unsent',
      () async {
        await dao.saveDay(
          DateTime(2026, 10, 16, 21, 30),
          flow: 2,
          mood: 1,
          symptoms: {3, 0},
          discharge: 4,
          sex: 1,
          pill: true,
          note: '  устала  ',
        );

        final saved = (await dao.getDay(day))!;
        expect(saved.date, day);
        expect(saved.flow, 2);
        expect(saved.mood, 1);
        expect(saved.symptoms, '0,3');
        expect(saved.discharge, 4);
        expect(saved.sex, 1);
        expect(saved.pill, isTrue);
        expect(saved.note, 'устала');
        expect(saved.dirty, isTrue);
      },
    );

    test('saving a day again is one row, never two', () async {
      await dao.saveDay(day, flow: 1);
      await dao.saveDay(day, flow: 3);

      final rows = await db.select(db.cycleDays).get();
      expect(rows, hasLength(1));
      expect(rows.single.flow, 3);
    });

    test(
      'taking everything back keeps an empty row, which still goes up',
      () async {
        await dao.saveDay(day, flow: 2, mood: 1, note: 'x');
        await dao.clearDirty(await dao.pending());
        expect(await dao.pending(), isEmpty);

        await dao.saveDay(day);

        final row = (await dao.getDay(day))!;
        expect(
          [row.flow, row.mood, row.symptoms, row.discharge, row.sex, row.note],
          [0, null, '', null, null, null],
        );
        expect(await dao.pending(), hasLength(1));
      },
    );

    test('an edit made while the send was in flight keeps its mark', () async {
      await dao.saveDay(day, flow: 1);
      final sent = await dao.pending();

      // The user edits again before the server has answered.
      await dao.saveDay(day, flow: 2);
      await dao.clearDirty(sent);

      expect(await dao.pending(), hasLength(1));
    });

    test('what comes down is not sent straight back', () async {
      await dao.applyRemote(
        CycleDaysCompanion(
          date: Value(DateTime(2026, 10, 16, 15)),
          flow: const Value(4),
          updatedAt: Value(DateTime(2026, 10, 17)),
        ),
      );

      final row = (await dao.getDay(day))!;
      expect(row.flow, 4);
      expect(row.dirty, isFalse);
      expect(await dao.pending(), isEmpty);
    });

    test('keep-local, adopt and wipe', () async {
      await dao.saveDay(day, flow: 1);
      await dao.keepLocal();
      expect(await dao.pending(), isEmpty);

      await dao.markAllDirty();
      expect(await dao.pending(), hasLength(1));

      await dao.wipeAll();
      expect(await db.select(db.cycleDays).get(), isEmpty);
    });
  });

  test(
    'the v19 migration adds the table and its one-row-per-day index',
    () async {
      final dir = await Directory.systemTemp.createTemp('cycle_migration');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');

      // A database exactly as v18 left it: everything but the new table.
      final old = AppDatabase.forExecutor(NativeDatabase(file));
      await old.customSelect('select 1').get();
      await old.customStatement('DROP TABLE cycle_days');
      await old.customStatement('PRAGMA user_version = 18');
      await old.close();

      final upgraded = AppDatabase.forExecutor(NativeDatabase(file));
      addTearDown(upgraded.close);
      // The upsert resolves on the unique index: without it this throws.
      await upgraded.cycleDao.saveDay(day, flow: 1);
      await upgraded.cycleDao.saveDay(day, flow: 2);
      expect(await upgraded.select(upgraded.cycleDays).get(), hasLength(1));
    },
  );

  group('the payload', () {
    test('a day goes up with its account and its calendar date', () async {
      await dao.saveDay(day, flow: 2, mood: 3, symptoms: {4, 1}, sex: 2);
      final row = cycleDayToRow((await dao.getDay(day))!, userId: 'me');

      expect(row['user_id'], 'me');
      expect(row['date'], '2026-10-16');
      expect(row['flow'], 2);
      expect(row['mood'], 3);
      expect(row['symptoms'], [1, 4]);
      expect(row['discharge'], isNull);
      expect(row['sex'], 2);
      expect(row['pill'], isFalse);
      expect(row['client_updated_at'], isA<String>());
    });

    test('and comes back as the same day', () async {
      await dao.saveDay(day, flow: 2, mood: 3, symptoms: {4, 1}, note: 'n');
      final row = cycleDayToRow((await dao.getDay(day))!, userId: 'me');
      final back = cycleDayFromRow(row);

      expect(back.date.value, day);
      expect(back.flow.value, 2);
      expect(back.mood.value, 3);
      expect(back.symptoms.value, '1,4');
      expect(back.note.value, 'n');
    });

    test('numbers this version has no name for read as "not marked"', () {
      final back = cycleDayFromRow({
        'date': '2026-10-16',
        'flow': 9,
        'mood': 99,
        'symptoms': [1, 42, 'x'],
        'discharge': -1,
        'sex': 7,
      });

      expect(back.flow.value, 0);
      expect(back.mood.value, isNull);
      expect(back.symptoms.value, '1');
      expect(back.discharge.value, isNull);
      expect(back.sex.value, isNull);
    });
  });

  test('symptoms are stored sorted and tolerate junk', () {
    expect(encodeSymptoms([3, 0, 3]), '0,3');
    expect(parseSymptoms('0, 3,x,,-2'), {0, 3});
    expect(parseSymptoms(''), isEmpty);
  });
}
