import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/sync_controller.dart';
import 'package:todo_app/sync/sync_service.dart';
import 'package:todo_app/sync/sync_status.dart';

/// A service that only counts: the question here is whether the controller asked
/// for a run, not what the run did.
class _CountingService extends SyncService {
  _CountingService(AppDatabase db)
    : super(
        dao: db.diaryDao,
        tasksDao: db.tasksDao,
        cycleDao: db.cycleDao,
        client: null,
      );

  int runs = 0;
  SyncOutcome outcome = SyncOutcome.done;

  @override
  Future<SyncOutcome> sync() async {
    runs++;
    return outcome;
  }
}

/// When the controller sends: by itself, only on Wi-Fi, or only when asked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final someone = User(
    id: 'a-user-id',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: DateTime.utc(2026).toIso8601String(),
  );

  late AppDatabase db;
  late _CountingService service;
  var onWifi = true;

  Future<ProviderContainer> container(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues({
      'sync_enabled': true,
      'sync_claimed_for': 'a-user-id',
      ...stored,
    });
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseReadyProvider.overrideWithValue(true),
        currentUserProvider.overrideWithValue(someone),
        syncServiceProvider.overrideWithValue(service),
        onWifiProvider.overrideWithValue(() async => onWifi),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    service = _CountingService(db);
    onWifi = true;
  });

  test('automatic runs are on by default', () async {
    final c = await container({});

    await c.read(syncControllerProvider).syncIfAuto();

    expect(service.runs, 1);
  });

  group('after a failed run', () {
    test('automatic runs stop until the user asks again', () async {
      final c = await container({});
      final controller = c.read(syncControllerProvider);
      service.outcome = SyncOutcome.offline;

      await controller.syncIfAuto();
      expect(service.runs, 1);

      // Back online, but nobody pressed "Повторить": the app stays quiet.
      service.outcome = SyncOutcome.done;
      await controller.syncIfAuto();
      expect(service.runs, 1);
      expect(c.read(syncStatusProvider).phase, SyncPhase.offline);

      // The user's own run goes through, and a good one lifts the pause.
      await controller.syncNow();
      expect(service.runs, 2);
      await controller.syncIfAuto();
      expect(service.runs, 3);
    });

    test(
      'a refusal pauses them too, and a failed retry keeps the pause',
      () async {
        final c = await container({});
        final controller = c.read(syncControllerProvider);
        service.outcome = SyncOutcome.failed;

        await controller.syncIfAuto();
        await controller.syncNow();
        await controller.syncIfAuto();

        expect(service.runs, 2);
      },
    );
  });

  group('with "Автоматически" off', () {
    test('the app does not start a run by itself', () async {
      final c = await container({'sync_auto': false});

      await c.read(syncControllerProvider).syncIfAuto();

      expect(service.runs, 0);
    });

    test('the button still works', () async {
      final c = await container({'sync_auto': false});

      await c.read(syncControllerProvider).syncNow();

      expect(service.runs, 1);
    });
  });

  group('with "Только по Wi-Fi" on', () {
    test('an automatic run waits while there is only mobile data', () async {
      onWifi = false;
      final c = await container({'sync_wifi_only': true});

      await c.read(syncControllerProvider).syncIfAuto();

      expect(service.runs, 0);
    });

    test('and goes ahead on Wi-Fi', () async {
      final c = await container({'sync_wifi_only': true});

      await c.read(syncControllerProvider).syncIfAuto();

      expect(service.runs, 1);
    });

    test('a run the user asked for is not held back', () async {
      onWifi = false;
      final c = await container({'sync_wifi_only': true});

      await c.read(syncControllerProvider).syncNow();

      expect(service.runs, 1);
    });

    test('mobile data is no obstacle while the setting is off', () async {
      onWifi = false;
      final c = await container({});

      await c.read(syncControllerProvider).syncIfAuto();

      expect(service.runs, 1);
    });
  });

  test('nothing runs at all while syncing is off', () async {
    final c = await container({'sync_enabled': false});

    await c.read(syncControllerProvider).syncNow();

    expect(service.runs, 0);
  });

  group('the diary switch', () {
    test('is on by default', () async {
      final c = await container({});
      expect(c.read(syncDiaryProvider), isTrue);
    });

    test('turning it back on reads everything again', () async {
      final c = await container({
        'sync_diary': false,
        'sync_pulled_through_v2': '2026-10-01T00:00:00.000Z',
      });
      expect(c.read(syncWatermarkProvider), isNotNull);

      await c.read(syncDiarySetterProvider)(true);

      // Notes changed elsewhere while it was off sit behind the position tasks
      // moved forward; only a read from the start finds them.
      expect(c.read(syncDiaryProvider), isTrue);
      expect(c.read(syncWatermarkProvider), isNull);
    });

    test('turning it off leaves the position alone', () async {
      final c = await container({
        'sync_pulled_through_v2': '2026-10-01T00:00:00.000Z',
      });

      await c.read(syncDiarySetterProvider)(false);

      expect(c.read(syncDiaryProvider), isFalse);
      expect(c.read(syncWatermarkProvider), isNotNull);
    });
  });
}
