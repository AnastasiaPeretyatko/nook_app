import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/api/token_store.dart';
import 'package:todo_app/auth/auth_user.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/realtime_listener.dart';
import 'package:todo_app/sync/sync_controller.dart';
import 'package:todo_app/sync/sync_service.dart';
import 'support/fake_sync_api.dart';
import 'package:todo_app/sync/sync_status.dart';

/// A service that only counts: the question here is whether the controller asked
/// for a run, not what the run did.
class _CountingService extends SyncService {
  _CountingService(AppDatabase db)
    : super(
        dao: db.diaryDao,
        tasksDao: db.tasksDao,
        cycleDao: db.cycleDao,
        api: FakeSyncApi(),
        userId: () => null,
      );

  int runs = 0;
  int forcedRuns = 0;
  bool busy = false;

  @override
  bool get isRunning => busy;

  SyncOutcome outcome = SyncOutcome.done;

  @override
  Future<SyncOutcome> sync({bool force = false}) async {
    runs++;
    if (force) forcedRuns++;
    return outcome;
  }
}

class _FakeSocket implements WsConnection {
  final _incoming = StreamController<String>();
  bool closed = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String text) {}

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  void ring() => _incoming.add('{"t":"changed"}');
}

/// When the controller sends: by itself, only on Wi-Fi, or only when asked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final someone = AuthUser(id: 'a-user-id', email: 'me@example.com');

  late AppDatabase db;
  late _CountingService service;
  var onWifi = true;
  late StreamController<bool> network;
  late List<_FakeSocket> sockets;

  Future<List<Override>> overridesFor(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues({
      'sync_enabled': true,
      'sync_claimed_for': 'a-user-id',
      ...stored,
    });
    final prefs = await SharedPreferences.getInstance();
    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserProvider.overrideWithValue(someone),
      syncServiceProvider.overrideWithValue(service),
      onWifiProvider.overrideWithValue(() async => onWifi),
      networkAvailableChangesProvider.overrideWithValue(network.stream),
      // A token that needs no refresh, and a socket that goes nowhere.
      tokenStoreProvider.overrideWithValue(
        MemoryTokenStore(accessToken: 'tok'),
      ),
      deviceIdProvider.overrideWithValue('phone-1'),
      realtimeConnectorProvider.overrideWithValue((url) async {
        final socket = _FakeSocket();
        sockets.add(socket);
        return socket;
      }),
    ];
  }

  Future<ProviderContainer> container(Map<String, Object> stored) async {
    final c = ProviderContainer(overrides: await overridesFor(stored));
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    service = _CountingService(db);
    onWifi = true;
    sockets = [];
    network = StreamController<bool>.broadcast();
    addTearDown(network.close);
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

  group('when the connection comes back', () {
    test('an offline run is retried by itself, skipping the backoff', () async {
      final c = await container({});
      final controller = c.read(syncControllerProvider);
      service.outcome = SyncOutcome.offline;
      await controller.syncIfAuto();
      expect(service.runs, 1);

      service.outcome = SyncOutcome.done;
      network.add(false); // still nothing: no run
      await pumpEventQueue();
      expect(service.runs, 1);

      network.add(true);
      await pumpEventQueue();
      expect(service.runs, 2);
      expect(service.forcedRuns, 1);
      expect(c.read(syncStatusProvider).phase, SyncPhase.idle);
    });

    test(
      'a refusal by the server is not retried on a new connection',
      () async {
        final c = await container({});
        service.outcome = SyncOutcome.failed;
        await c.read(syncControllerProvider).syncIfAuto();

        network.add(true);
        await pumpEventQueue();

        expect(service.runs, 1);
      },
    );
  });

  test('the button skips the wait after a failure', () async {
    final c = await container({});

    await c.read(syncControllerProvider).syncNow();

    expect(service.forcedRuns, 1);
  });

  group('a run that is already going', () {
    test('is not overwritten by a turned-away one', () async {
      final c = await container({});
      final controller = c.read(syncControllerProvider);
      c.read(syncStatusProvider.notifier).reportRunning();
      service.busy = true;

      expect(await controller.syncNow(), SyncOutcome.skipped);
      expect(await controller.syncIfAuto(), SyncOutcome.skipped);

      // Back to "idle" here would be the card saying nothing is happening.
      expect(c.read(syncStatusProvider).phase, SyncPhase.running);
      expect(service.runs, 0);
    });
  });

  test('a press that could not start says why', () async {
    final c = await container({});
    service
      ..outcome = SyncOutcome.skipped
      ..lastError = 'Нет активной сессии';

    await c.read(syncControllerProvider).syncNow();

    final status = c.read(syncStatusProvider);
    expect(status.phase, SyncPhase.failed);
    expect(status.lastError, 'Нет активной сессии');
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

  group('the connection to the server\'s doorbell', () {
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('opening it is the sync: one connection, one run', () async {
      final c = await container({});
      c.read(syncControllerProvider).start();
      await settle();

      expect(sockets, hasLength(1));
      expect(service.runs, 1);
    });

    test('starting again leaves the open connection alone', () async {
      final c = await container({});
      final controller = c.read(syncControllerProvider);
      controller.start();
      await settle();
      controller.start();
      controller.start();
      await settle();

      expect(sockets, hasLength(1));
      expect(service.runs, 1);
    });

    test('a ring runs a sync', () async {
      final c = await container({});
      c.read(syncControllerProvider).start();
      await settle();

      sockets.single.ring();
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(service.runs, 2);
    });

    test('with "Автоматически" off there is no connection', () async {
      final c = await container({'sync_auto': false});
      c.read(syncControllerProvider).start();
      await settle();

      expect(sockets, isEmpty);
      expect(service.runs, 0);
    });

    test('with syncing off there is no connection', () async {
      final c = await container({'sync_enabled': false});
      c.read(syncControllerProvider).start();
      await settle();

      expect(sockets, isEmpty);
    });

    test('stopping hangs up', () async {
      final c = await container({});
      final controller = c.read(syncControllerProvider);
      controller.start();
      await settle();

      controller.stop();
      await settle();

      expect(sockets.single.closed, isTrue);
    });

    test('leaving the front sends what is waiting and hangs up', () async {
      final c = await container({});
      final controller = c.read(syncControllerProvider);
      controller.start();
      await settle();
      service.runs = 0;
      await db.tasksDao.insertTask(
        TasksCompanion.insert(title: 'Не отправлено'),
      );

      await controller.sendAndDisconnect();

      expect(sockets.single.closed, isTrue);
      expect(service.runs, 1, reason: 'sent at once, not after the 3 s');
    });

    test('leaving the front with nothing to send only hangs up', () async {
      final c = await container({});
      final controller = c.read(syncControllerProvider);
      controller.start();
      await settle();
      service.runs = 0;

      await controller.sendAndDisconnect();

      expect(sockets.single.closed, isTrue);
      expect(service.runs, 0);
    });

    testWidgets('no timer asks on its own, however long it is left', (
      tester,
    ) async {
      final c = ProviderContainer(overrides: await overridesFor({}));
      addTearDown(c.dispose);
      c.read(syncControllerProvider).start();
      await tester.pump();
      expect(service.runs, 1);

      await tester.pump(const Duration(hours: 2));

      expect(service.runs, 1);
      c.read(syncControllerProvider).stop();
      await tester.pump();
    });
  });

  group('the app going away and coming back', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...await overridesFor({}),
            diaryEntriesProvider.overrideWith((ref) => Stream.value(const [])),
            allTasksProvider.overrideWith((ref) => Stream.value(const [])),
            allLogsProvider.overrideWith((ref) => Stream.value(const [])),
            cycleDaysProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: const SyncScope(child: SizedBox()),
        ),
      );
      await tester.pump();
    }

    testWidgets('opening the app connects, once', (tester) async {
      await open(tester);

      expect(sockets, hasLength(1));
      expect(service.runs, 1);
    });

    testWidgets('going to the background hangs up; coming back connects', (
      tester,
    ) async {
      await open(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(sockets.single.closed, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(sockets, hasLength(2));
      expect(sockets.last.closed, isFalse);
      expect(service.runs, 2, reason: 'one sync per connection');
    });

    testWidgets('coming back when it never left does not reconnect', (
      tester,
    ) async {
      await open(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(sockets, hasLength(1));
      expect(service.runs, 1);
    });
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
