import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/theme/app_palette.dart';

/// Overridden in [main] with an actual [SharedPreferences] instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  /// Public because the home-screen widget is rebuilt in a background isolate
  /// that has no providers — see `lib/home_widget/widget_theme.dart`. It reads
  /// the setting straight out of the same store, through this key and [decode].
  static const prefsKey = 'theme_mode';

  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return decode(prefs.getString(prefsKey));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(prefsKey, mode.name);
  }

  static ThemeMode decode(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}

/// The accents the settings offer, as stored: each one's light-theme tone. The
/// dark tone is looked up from it — see [appAccents].
final appColorPalette = [for (final accent in appAccents) accent.light];

/// The accent a stored preference names. One saved before "Иней" comes back as
/// its nearest new accent ([accentFor]); nothing is rewritten in the store.
Color accentFromPrefs(int? stored) =>
    stored != null ? accentFor(Color(stored)).light : appColorPalette.first;

final appColorProvider = NotifierProvider<AppColorNotifier, Color>(
  AppColorNotifier.new,
);

class AppColorNotifier extends Notifier<Color> {
  /// Public for the same reason as [ThemeModeNotifier.prefsKey].
  static const prefsKey = 'app_color';

  @override
  Color build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return accentFromPrefs(prefs.getInt(prefsKey));
  }

  Future<void> setColor(Color color) async {
    if (color.toARGB32() == state.toARGB32()) return;
    state = color;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(prefsKey, color.toARGB32());
  }
}
