import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Available primary colors for the app: the accents of [taskPalette], so the
/// interface and the tasks share one palette. Unlike a task's light tone these
/// are only ever used for elements whose foreground is derived from the accent's
/// own luminance, so mid-tone colors are fine here.
const appColorPalette = <Color>[
  Color(0xFF8B7CF6), // violet
  Color(0xFF76B894), // green
  Color(0xFFF5A76F), // orange
  Color(0xFF72B7D8), // blue
  Color(0xFFD98BA8), // pink
  Color(0xFFF4C95D), // yellow
  Color(0xFFE97B70), // red
  Color(0xFF1A1A1A), // graphite — the neutral, no-accent option
];

final appColorProvider = NotifierProvider<AppColorNotifier, Color>(
  AppColorNotifier.new,
);

class AppColorNotifier extends Notifier<Color> {
  /// Public for the same reason as [ThemeModeNotifier.prefsKey].
  static const prefsKey = 'app_color';

  @override
  Color build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getInt(prefsKey);
    return stored != null ? Color(stored) : appColorPalette.first;
  }

  Future<void> setColor(Color color) async {
    if (color.toARGB32() == state.toARGB32()) return;
    state = color;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(prefsKey, color.toARGB32());
  }
}
