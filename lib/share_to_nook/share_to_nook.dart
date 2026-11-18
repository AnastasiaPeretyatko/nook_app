// Includes the separately launched `shareMain` library in the application.
// ShareActivity selects it as a Dart entrypoint instead of starting MyApp.
export 'compact_share.dart' show shareMain;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:todo_app/pages/create_note_page.dart';
import 'package:todo_app/pages/note_view_page.dart';
import 'package:todo_app/utils/shared_note_content.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/diary/note_append_picker_sheet.dart';
import 'package:todo_app/widgets/app_toast.dart';

/// The Android half is intentionally a pull queue: the activity can receive a
/// share before Flutter has drawn its first frame, and a signal only says there
/// may be more text to take.
abstract interface class ShareToNookBridge {
  Future<List<SharedNoteContent>> takePending();

  void setOnAvailable(void Function()? listener);
}

/// Android's MethodChannel implementation of [ShareToNookBridge].
class AndroidShareToNookBridge implements ShareToNookBridge {
  AndroidShareToNookBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.yourname.todo_app/shared_content';
  static const _takePending = 'takePendingSharedText';
  static const _available = 'sharedTextAvailable';

  final MethodChannel _channel;
  void Function()? _onAvailable;

  @override
  Future<List<SharedNoteContent>> takePending() async {
    if (defaultTargetPlatform != TargetPlatform.android) return const [];
    final values = await _channel.invokeListMethod<String>(_takePending);
    return [
      for (final value in values ?? const <String>[]) SharedNoteContent(value),
    ];
  }

  @override
  void setOnAvailable(void Function()? listener) {
    _onAvailable = listener;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == _available) _onAvailable?.call();
    });
  }
}

typedef ShareToNookFlow =
    Future<void> Function(BuildContext context, SharedNoteContent content);

/// Serialises drain requests and user flows without deduplicating text.
///
/// Two shares carrying identical strings are still two distinct user actions.
class ShareToNookQueue {
  ShareToNookQueue(this._bridge, this._handle);

  final ShareToNookBridge _bridge;
  final Future<void> Function(SharedNoteContent) _handle;
  Future<void> _running = Future<void>.value();
  bool _requested = false;

  Future<void> get idle => _running;

  Future<void> start() {
    _bridge.setOnAvailable(_requestDrain);
    return _requestDrain();
  }

  Future<void> _requestDrain() {
    _requested = true;
    _running = _running.then((_) async {
      while (_requested) {
        _requested = false;
        final pending = await _bridge.takePending();
        for (final content in pending) {
          await _handle(content);
        }
      }
    });
    return _running;
  }

  void dispose() => _bridge.setOnAvailable(null);
}

/// Owns the Android share queue for the lifetime of the main application UI.
class ShareToNookScope extends StatefulWidget {
  const ShareToNookScope({
    super.key,
    required this.child,
    required this.onContent,
    this.bridge,
  });

  final Widget child;
  final ShareToNookFlow onContent;
  final ShareToNookBridge? bridge;

  @override
  State<ShareToNookScope> createState() => _ShareToNookScopeState();
}

class _ShareToNookScopeState extends State<ShareToNookScope> {
  late final ShareToNookQueue _queue = ShareToNookQueue(
    widget.bridge ?? AndroidShareToNookBridge(),
    (content) => widget.onContent(context, content),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_queue.start());
    });
  }

  @override
  void dispose() {
    _queue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The user flow for one shared text. Dismissing either sheet is cancellation:
/// no DAO call is made and the next queued share may proceed.
Future<void> showShareToNookFlow(
  BuildContext context,
  SharedNoteContent content,
) async {
  final choice = await showActionsSheet<_ShareChoice>(
    context,
    title: 'Добавить текст в дневник',
    actions: const [
      SheetAction(
        icon: Icons.note_add_outlined,
        label: 'Новая заметка',
        value: _ShareChoice.create,
      ),
      SheetAction(
        icon: Icons.playlist_add,
        label: 'Добавить в существующую',
        value: _ShareChoice.append,
      ),
    ],
  );
  if (!context.mounted || choice == null) return;

  if (choice == _ShareChoice.create) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CreateNotePage(initialBodyText: content.text),
      ),
    );
    return;
  }

  final overlay = Overlay.of(context, rootOverlay: true);
  final updated = await showNoteAppendPickerSheet(context, content: content);
  if (!context.mounted || updated == null) return;
  showAppToast(
    overlay,
    message: 'Текст добавлен в заметку',
    actionLabel: 'Открыть',
    onAction: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteViewPage(entryId: updated.id),
      ),
    ),
  );
}

enum _ShareChoice { create, append }
