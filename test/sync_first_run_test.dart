import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/providers.dart';

/// The gate in front of the very first sync: what happens to the notes already
/// on this device, and — the case actually worth the machinery — what happens
/// when a *second* account signs into the same phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DiaryDao dao;

  User person(String id) => User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: DateTime.utc(2026).toIso8601String(),
  );

  Future<ProviderContainer> container({
    Map<String, Object> stored = const {},
    User? user,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseReadyProvider.overrideWithValue(true),
        currentUserProvider.overrideWithValue(user),
        databaseProvider.overrideWithValue(db),
      ],
    );
  }

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    dao = db.diaryDao;
  });

  tearDown(() => db.close());

  Future<void> addNote(String title) =>
      dao.insertEntry(DiaryEntriesCompanion.insert(title: Value(title)));

  group('nothing syncs until the question is answered', () {
    test(
      'a switch turned on by an account that never answered is inert',
      () async {
        final c = await container(
          stored: {'sync_enabled': true},
          user: person('user-a'),
        );
        addTearDown(c.dispose);

        expect(c.read(syncNeedsDecisionProvider), isTrue);
        expect(c.read(syncActiveProvider), isFalse);
      },
    );

    test('an answered account syncs', () async {
      final c = await container(
        stored: {'sync_enabled': true, 'sync_claimed_for': 'user-a'},
        user: person('user-a'),
      );
      addTearDown(c.dispose);

      expect(c.read(syncNeedsDecisionProvider), isFalse);
      expect(c.read(syncActiveProvider), isTrue);
    });

    test('a different account on the same phone is asked again', () async {
      // The failure this exists to prevent: a phone that already holds one
      // person's diary is handed to another account, and starts syncing into
      // it without anybody being asked.
      final c = await container(
        stored: {'sync_enabled': true, 'sync_claimed_for': 'user-a'},
        user: person('user-b'),
      );
      addTearDown(c.dispose);

      expect(c.read(syncNeedsDecisionProvider), isTrue);
      expect(c.read(syncActiveProvider), isFalse);
    });

    test('with sync off there is nothing to decide', () async {
      final c = await container(user: person('user-a'));
      addTearDown(c.dispose);

      expect(c.read(syncNeedsDecisionProvider), isFalse);
    });

    test('signed out there is nothing to decide either', () async {
      final c = await container(stored: {'sync_enabled': true});
      addTearDown(c.dispose);

      expect(c.read(syncNeedsDecisionProvider), isFalse);
    });
  });

  group('answering "keep them here"', () {
    test('leaves the notes unsent, and unsendable until edited', () async {
      await addNote('Личное');
      await addNote('Тоже личное');
      expect(await dao.unsentEntryCount(), 2);

      await dao.keepExistingEntriesLocal();

      expect(await dao.unsentEntryCount(), 0);
      expect(await dao.pendingEntries(), isEmpty);
    });

    test('drops deletions of notes that are staying', () async {
      final id = await dao.insertEntry(
        DiaryEntriesCompanion.insert(title: const Value('Удалённая')),
      );
      await dao.deleteEntry(id);
      expect(await dao.pendingTombstones(), hasLength(1));

      await dao.keepExistingEntriesLocal();

      // A note nobody else has ever seen being deleted is not news for anyone.
      expect(await dao.pendingTombstones(), isEmpty);
    });

    test('clears the catalogues too', () async {
      // A tag somebody invented is unsent data of theirs exactly as a note is,
      // and leaving its mark on would send it up on the next run while the
      // dialog said nothing would go. The answer has to reach every table it
      // claimed to.
      await dao.insertTag(name: 'Личное', colorKey: 'violet');
      await dao.insertMood(name: 'Вдохновение', emoji: '✨');

      await dao.keepExistingEntriesLocal();

      expect(await dao.pendingTags(), isEmpty);
      expect(await dao.pendingMoods(), isEmpty);
    });

    test('a label edited afterwards does go up', () async {
      await dao.insertTag(name: 'Личное', colorKey: 'violet');
      await dao.keepExistingEntriesLocal();

      await dao.insertTag(name: 'Работа', colorKey: 'blue');

      // The same bargain the notes get: "не загружать" is about what is here
      // now, not a promise never to sync anything again.
      expect((await dao.pendingTags()).map((t) => t.name), ['Работа']);
    });

    test('a note edited afterwards does go up', () async {
      await addNote('Личное');
      await dao.keepExistingEntriesLocal();
      final note = (await db.select(db.diaryEntries).get()).single;

      await dao.setBody(note.id, 'передумала');

      expect(await dao.unsentEntryCount(), 1);
    });
  });

  group('answering "upload"', () {
    test('leaves every note marked, so the next run carries them', () async {
      await addNote('Первая');
      await addNote('Вторая');

      // "Upload" changes nothing about the marks — it only stops standing in
      // the way of what would have happened anyway.
      expect(await dao.unsentEntryCount(), 2);
    });
  });

  group('the watermark', () {
    // The key carries a `_v2` because it was retired at v14: one position covers
    // every table, and a device holding one from before tasks were synced would
    // ask for "tasks changed since X" and never be told about the ones written
    // before X. The rename is the reset.
    test('is stored and read back', () async {
      final c = await container(
        stored: {'sync_pulled_through_v2': '2026-08-26T10:00:00.000Z'},
      );
      addTearDown(c.dispose);

      expect(
        c.read(syncWatermarkProvider),
        DateTime.parse('2026-08-26T10:00:00.000Z'),
      );
    });

    test('can be cleared, which is what an account change needs', () async {
      // It measures progress through *an account's* history. Carried into
      // another account it would make that pull start in the middle and skip
      // everything written before — with nothing that would ever go back.
      final c = await container(
        stored: {'sync_pulled_through_v2': '2026-08-26T10:00:00.000Z'},
      );
      addTearDown(c.dispose);

      await c.read(syncWatermarkProvider.notifier).set(null);

      expect(c.read(syncWatermarkProvider), isNull);
    });
  });

  group('claiming', () {
    test('records the account and unblocks syncing', () async {
      final c = await container(
        stored: {'sync_enabled': true},
        user: person('user-a'),
      );
      addTearDown(c.dispose);
      expect(c.read(syncActiveProvider), isFalse);

      await c.read(syncClaimProvider.notifier).claimFor('user-a');

      expect(c.read(syncActiveProvider), isTrue);
    });
  });
}
