import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A registry, not UI state: the picker consults it before allowing an append
/// into a note that has an unsaved editor draft.
final openNoteEditorsProvider = Provider<OpenNoteEditors>(
  (ref) => OpenNoteEditors(),
);

class _OpenNoteEditor {
  const _OpenNoteEditor(this.token);

  final Object token;
}

class OpenNoteEditors {
  final _editors = <int, _OpenNoteEditor>{};

  void register(int id, Object token) {
    _editors[id] = _OpenNoteEditor(token);
  }

  void unregister(int id, Object token) {
    final editor = _editors[id];
    if (editor == null || editor.token != token) return;
    _editors.remove(id);
  }

  bool contains(int id) => _editors.containsKey(id);
}
