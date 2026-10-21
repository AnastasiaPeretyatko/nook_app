import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/theme/app_palette.dart';

/// The "Иней" accents: a stored accent from before the redesign lands on its
/// nearest new one, and each accent brings its own dark tone.
void main() {
  String nameOf(int argb) => accentFor(Color(argb)).name;

  test('every new accent is its own answer', () {
    for (final accent in appAccents) {
      expect(accentFor(accent.light), same(accent));
    }
  });

  test('an accent saved before "Иней" maps onto its nearest family', () {
    expect(nameOf(0xFF8B7CF6), 'Барвинковый'); // violet
    expect(nameOf(0xFF76B894), 'Шалфей'); // green
    expect(nameOf(0xFF72B7D8), 'Морской'); // blue
    for (final warm in [0xFFD98BA8, 0xFFF5A76F, 0xFFF4C95D, 0xFFE97B70]) {
      expect(nameOf(warm), 'Пыльно-розовый');
    }
    expect(nameOf(0xFF1A1A1A), 'Барвинковый'); // graphite
  });

  test('nothing stored, or something unknown, is the default', () {
    expect(accentFromPrefs(null), appAccents.first.light);
    expect(accentFromPrefs(0xFF123456), appAccents.first.light);
  });

  test('the dark theme takes the accent\'s dark tone', () {
    for (final accent in appAccents) {
      final scheme = buildAppTheme(accent.light, Brightness.dark).colorScheme;
      expect(scheme.primary, accent.dark);
    }
  });

  test('the page and the card are the "Иней" tokens', () {
    final light = buildAppTheme(appAccents.first.light, Brightness.light);
    final dark = buildAppTheme(appAccents.first.light, Brightness.dark);
    expect(light.scaffoldBackgroundColor, const Color(0xFFF6F8FB));
    expect(light.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF101317));
    expect(dark.colorScheme.surface, const Color(0xFF181C21));
  });
}
