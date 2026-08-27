import 'package:flutter/material.dart';
import 'package:todo_app/utils/task_colors.dart';

/// One colour of the task palette. A task stores its [accent]; the [light] tone
/// is what large areas are painted with — the timeline pill, the tinted box
/// behind an icon — so the accent stays a small, saturated mark on top of it.
class TaskSwatch {
  const TaskSwatch({
    required this.key,
    required this.accent,
    required this.light,
  });

  /// What names this family *outside* the app.
  ///
  /// A colour is a fact about this version of the design; a key is a fact about
  /// the diary. A note's tag stores the key, so the palette can be repainted —
  /// a shade nudged, a family made warmer — and every tag ever written follows
  /// along, on every device, without a migration.
  ///
  /// The same move the task icons already made: they used to store a Material
  /// code point, which only means something inside one font, and migration v10
  /// turned them into keys into [taskIcons].
  ///
  /// **Never rename one.** A key that changes is a tag whose colour is suddenly
  /// unknown everywhere it was already saved.
  final String key;

  final Color accent;
  final Color light;
}

/// Seven families, accent + light tone each. The accents double as the app's
/// primary colours ([appColorPalette] in `settings/theme_provider.dart`).
const taskPalette = <TaskSwatch>[
  TaskSwatch(
    key: 'violet',
    accent: Color(0xFF8B7CF6),
    light: Color(0xFFE8E5FF),
  ),
  TaskSwatch(key: 'green', accent: Color(0xFF76B894), light: Color(0xFFE2F2E7)),
  TaskSwatch(
    key: 'orange',
    accent: Color(0xFFF5A76F),
    light: Color(0xFFFCE8D8),
  ),
  TaskSwatch(key: 'blue', accent: Color(0xFF72B7D8), light: Color(0xFFDFF1F8)),
  TaskSwatch(key: 'pink', accent: Color(0xFFD98BA8), light: Color(0xFFF6E1E9)),
  TaskSwatch(
    key: 'yellow',
    accent: Color(0xFFF4C95D),
    light: Color(0xFFFFF2CC),
  ),
  TaskSwatch(key: 'red', accent: Color(0xFFE97B70), light: Color(0xFFFFE3E0)),
];

/// The family a stored key names, or null when nothing here answers to it.
///
/// Null is an ordinary answer, not a fault: a key written by a newer version of
/// the app is one this one has never heard of, and a tag with an unfamiliar
/// colour should still be readable. Callers fall back to [fallbackTaskColorKey].
TaskSwatch? taskSwatchForKey(String? key) {
  for (final swatch in taskPalette) {
    if (swatch.key == key) return swatch;
  }
  return null;
}

/// The colour a stored key names, falling back to the first family.
Color taskColorForKey(String? key) =>
    (taskSwatchForKey(key) ?? taskPalette.first).accent;

/// The key naming [accent], or null when the colour is in no family.
///
/// Used by the migration that turned stored colours into keys, and by the tag
/// picker, which hands out colours and has to write down which one was taken.
String? taskColorKeyOf(Color accent) {
  for (final swatch in taskPalette) {
    if (swatch.accent.toARGB32() == accent.toARGB32()) return swatch.key;
  }
  return null;
}

/// What a tag falls back to when its key means nothing here.
const fallbackTaskColorKey = 'violet';

/// How much white the palette's light tones carry over their accent. Used to
/// stand in for a colour that predates the palette, so an old task still gets a
/// sensible pair instead of falling back to a stranger's pink.
const _lightBlend = 0.78;

/// The light tone belonging to [accent].
///
/// A task saved before this palette existed holds a colour that is in no family,
/// so its light tone is mixed on the spot — the same relation the palette itself
/// has between its two rows.
Color taskLightTone(Color accent) {
  for (final swatch in taskPalette) {
    if (swatch.accent.toARGB32() == accent.toARGB32()) return swatch.light;
    // An old task may already hold what is now a light tone; keep it as it is.
    if (swatch.light.toARGB32() == accent.toARGB32()) return swatch.light;
  }
  return Color.lerp(accent, Colors.white, _lightBlend)!;
}

/// How far the tail of a gradient turns around the colour wheel and how much
/// lighter it gets.
///
/// Both are deliberately small. The area still has to read as the colour the
/// user picked, and a bigger turn walks the saturated families straight into a
/// different one — the yellow accent at +20° is acid lime.
const double _gradientHueTurn = 8;
const double _gradientLift = 0.07;

/// Luminance the tail may not pass, kept under the 0.75 where [onBrandFill]
/// gives up on white: one card cannot want white ink at the top and black ink
/// at the bottom. The yellow family starts at 0.618, so the lift it gets is
/// whatever is left before the ceiling.
const double _gradientMaxLuminance = 0.70;

/// The second stop of [taskGradient]: [accent] turned a shade warmer and
/// lighter, then walked back down until it clears [_gradientMaxLuminance].
/// Exposed so a caller can ask what its content sits on in the far corner.
Color taskGradientTail(Color accent) {
  final base = HSLColor.fromColor(accent);
  var hsl = base
      .withHue((base.hue + _gradientHueTurn) % 360)
      .withLightness((base.lightness + _gradientLift).clamp(0.0, 1.0));
  // Lightness alone says nothing about how bright a hue reads: the same 0.73 is
  // a mid violet and a glaring yellow. 2% steps, as in [inkOn].
  for (var i = 0; i < 50; i++) {
    if (hsl.toColor().computeLuminance() <= _gradientMaxLuminance) break;
    final next = hsl.lightness - 0.02;
    if (next <= 0) break;
    hsl = hsl.withLightness(next);
  }
  return hsl.toColor();
}

/// The two-stop wash a large area in a task's colour is painted with: the
/// accent itself in the top-left corner, [taskGradientTail] in the
/// bottom-right.
///
/// Works on any colour, palette or not — the tail is derived, not looked up —
/// so a near-grey (a habit card that is done for today is repainted neutral)
/// simply gets a gradient nobody can see rather than a special case.
LinearGradient taskGradient(Color accent) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [accent, taskGradientTail(accent)],
);

/// The tinted box an icon of a task sits in — a list row's leading square, the
/// 44px badge at the top of a sheet.
///
/// On a light screen it is the family's light tone, as the palette intends. On a
/// dark one a near-white box would shout, so it is a wash of the accent over
/// [surface] instead; either way ask [inkOn] for the glyph on top.
Color taskBadgeSurface(ThemeData theme, Color accent, Color surface) =>
    theme.brightness == Brightness.light
    ? taskLightTone(accent)
    : flattenOn(surface, accent.withValues(alpha: 0.22));
