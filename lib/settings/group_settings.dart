import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/settings/theme_provider.dart';

/// The groups whose **every** task is shown on the timeline and in the calendar,
/// not only the ones handed to me or to everyone.
///
/// Off for a group unless switched on from its page: a family group where the
/// others' errands fill my day is the case it exists for. It decides what the
/// day screen draws and nothing else — the group's own page always lists all.
///
/// Kept on the phone, one string list in the same prefs as the theme, and never
/// synced: how crowded one wants a day to look is not the group's business.
final groupsShowAllProvider =
    NotifierProvider<GroupsShowAllNotifier, Set<String>>(
      GroupsShowAllNotifier.new,
    );

class GroupsShowAllNotifier extends Notifier<Set<String>> {
  static const _prefsKey = 'groups_show_all';

  @override
  Set<String> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return (prefs.getStringList(_prefsKey) ?? const <String>[]).toSet();
  }

  Future<void> setShowAll(String groupUid, bool showAll) async {
    if (state.contains(groupUid) == showAll) return;
    state = showAll ? {...state, groupUid} : ({...state}..remove(groupUid));
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(_prefsKey, state.toList());
  }
}
