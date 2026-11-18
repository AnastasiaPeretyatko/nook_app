import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/share_to_nook/editor_lock_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/editor-lock');
  const bridge = MethodChannelEditorLockBridge(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps the native editor-lock contract', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'newOwner':
              return 'owner-1';
            case 'tryAcquire':
              return true;
            case 'release':
              return true;
            case 'isLocked':
              return false;
            case 'getLockedIds':
              return [1, 2];
            case 'releaseAll':
              return 2;
          }
          return null;
        });

    expect(await bridge.newOwner(), 'owner-1');
    expect(await bridge.tryAcquire(noteId: 4, ownerId: 'owner-1'), isTrue);
    expect(await bridge.release(noteId: 4, ownerId: 'owner-1'), isTrue);
    expect(await bridge.isLocked(4), isFalse);
    expect(await bridge.getLockedIds(), [1, 2]);
    expect(await bridge.releaseAll('owner-1'), 2);
    expect(calls.map((call) => call.method), [
      'newOwner',
      'tryAcquire',
      'release',
      'isLocked',
      'getLockedIds',
      'releaseAll',
    ]);
  });

  test('fails closed when native bool results are missing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    expect(await bridge.tryAcquire(noteId: 4, ownerId: 'owner-1'), isFalse);
    expect(await bridge.isLocked(4), isTrue);
    expect(bridge.newOwner(), throwsStateError);
  });
}
