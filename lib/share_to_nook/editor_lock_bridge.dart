import 'package:flutter/services.dart';

const editorLockChannelName = 'com.yourname.todo_app/editor_lock';

/// The cross-engine native editor-lock contract.
abstract interface class EditorLockBridge {
  Future<String> newOwner();
  Future<bool> tryAcquire({required int noteId, required String ownerId});
  Future<bool> release({required int noteId, required String ownerId});
  Future<bool> isLocked(int noteId);
  Future<List<int>> getLockedIds();
  Future<int> releaseAll(String ownerId);
}

class MethodChannelEditorLockBridge implements EditorLockBridge {
  const MethodChannelEditorLockBridge({
    this.channel = const MethodChannel(editorLockChannelName),
  });

  final MethodChannel channel;

  @override
  Future<String> newOwner() async {
    final ownerId = await channel.invokeMethod<String>('newOwner');
    if (ownerId == null || ownerId.isEmpty) {
      throw StateError('Native editor lock did not return an owner ID');
    }
    return ownerId;
  }

  @override
  Future<bool> tryAcquire({
    required int noteId,
    required String ownerId,
  }) async =>
      await channel.invokeMethod<bool>('tryAcquire', {
        'noteId': noteId,
        'ownerId': ownerId,
      }) ??
      false;

  @override
  Future<bool> release({required int noteId, required String ownerId}) async =>
      await channel.invokeMethod<bool>('release', {
        'noteId': noteId,
        'ownerId': ownerId,
      }) ??
      false;

  @override
  Future<bool> isLocked(int noteId) async =>
      await channel.invokeMethod<bool>('isLocked', {'noteId': noteId}) ?? true;

  @override
  Future<List<int>> getLockedIds() async {
    final ids =
        await channel.invokeMethod<List<dynamic>>('getLockedIds') ?? const [];
    return [
      for (final id in ids)
        if (id is num) id.toInt(),
    ];
  }

  @override
  Future<int> releaseAll(String ownerId) async =>
      await channel.invokeMethod<int>('releaseAll', {'ownerId': ownerId}) ?? 0;
}
