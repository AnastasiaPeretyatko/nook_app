import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// How the diary draws its notes.
enum DiaryViewMode {
  /// One note per row: thumbnail, title, an excerpt of the text.
  list,

  /// Two columns of cards, the cover on top and the title under it. Shows less
  /// of what a note *says* and more of what it looks like.
  grid,
}

/// The chosen view, remembered.
///
/// A preference rather than screen state: it is a decision about how the diary
/// should look, and having to make it again after every launch would make it
/// worthless. Stored like the theme and the accent — the same
/// [sharedPreferencesProvider], one string key.
final diaryViewModeProvider =
    NotifierProvider<DiaryViewModeNotifier, DiaryViewMode>(
      DiaryViewModeNotifier.new,
    );

class DiaryViewModeNotifier extends Notifier<DiaryViewMode> {
  static const _prefsKey = 'diary_view_mode';

  @override
  DiaryViewMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    // The list is the default: it is the view that shows what a note says, and
    // a diary of untitled thoughts is unreadable as a wall of covers.
    return prefs.getString(_prefsKey) == DiaryViewMode.grid.name
        ? DiaryViewMode.grid
        : DiaryViewMode.list;
  }

  Future<void> setMode(DiaryViewMode mode) async {
    if (mode == state) return;
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_prefsKey, mode.name);
  }
}
