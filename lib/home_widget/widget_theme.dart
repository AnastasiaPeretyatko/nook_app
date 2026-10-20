import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/home_widget/today_payload.dart';
import 'package:todo_app/main.dart' show buildAppTheme;
import 'package:todo_app/settings/theme_provider.dart';

/// The two palettes and the mode the widget is drawn with, taken from the app's
/// own theme.
///
/// A record rather than a class: it is three values handed straight to
/// [buildTodayWidgetPayload] and never stored.
typedef WidgetTheme = ({WidgetPalette light, WidgetPalette dark, String mode});

/// The widget's colours for an app accent and theme setting.
///
/// Both palettes are always built, whatever [mode] says. The extra work is a
/// handful of colour arithmetic, and it is what lets the launcher follow the
/// system theme on its own while the app is not running — see
/// [TodayWidgetPayload].
WidgetTheme widgetThemeFor({required Color accent, required ThemeMode mode}) =>
    (
      light: WidgetPalette.fromScheme(
        buildAppTheme(accent, Brightness.light).colorScheme,
      ),
      dark: WidgetPalette.fromScheme(
        buildAppTheme(accent, Brightness.dark).colorScheme,
      ),
      mode: mode.name,
    );

/// The same, for an isolate that has no providers.
///
/// The background isolate that answers a tap on the widget runs no `main`, so
/// there is no `ProviderScope` and nothing has read the settings. It reads them
/// itself, out of the store the notifiers write to, through the keys they now
/// expose.
WidgetTheme widgetThemeFromPrefs(SharedPreferences prefs) {
  return widgetThemeFor(
    accent: accentFromPrefs(prefs.getInt(AppColorNotifier.prefsKey)),
    mode: ThemeModeNotifier.decode(prefs.getString(ThemeModeNotifier.prefsKey)),
  );
}
