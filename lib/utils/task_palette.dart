import 'package:flutter/material.dart';
import 'package:todo_app/utils/task_colors.dart';

/// One colour of the task palette — a "Иней" family (DESIGN.md §2.4). A task
/// stores its [accent]; the [light] tone is what large areas are painted with —
/// the timeline pill, the tinted box behind an icon — so the accent stays a
/// small, saturated mark on top of it.
class TaskSwatch {
  const TaskSwatch({
    required this.key,
    required this.accent,
    required this.light,
    required this.strong,
    required this.darkFill,
    required this.darkInk,
    this.pickable = true,
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

  /// The design's `ink`: dots, done capsules, outlines. What a task stores.
  final Color accent;

  /// The design's `fill`: the tile behind an icon, an upcoming capsule.
  final Color light;

  /// Icons and large text on [light]; a fill with white text on it.
  final Color strong;

  /// The tile behind an icon in the dark theme.
  final Color darkFill;

  /// An icon or a dot in the dark theme.
  final Color darkInk;

  /// Offered in the pickers. False for the keys kept only so that what was
  /// saved under them still reads.
  final bool pickable;
}

const _sky = (
  fill: Color(0xFFDCE7FB),
  ink: Color(0xFF7FA3E3),
  strong: Color(0xFF3B66B5),
  darkFill: Color(0xFF1F2A44),
  darkInk: Color(0xFFA9C1F2),
);
const _ice = (
  fill: Color(0xFFD6EEF6),
  ink: Color(0xFF6FB3CE),
  strong: Color(0xFF2A7190),
  darkFill: Color(0xFF173440),
  darkInk: Color(0xFF9FD6EA),
);
const _lavender = (
  fill: Color(0xFFE3DEF8),
  ink: Color(0xFF9C8DDB),
  strong: Color(0xFF5D4DB0),
  darkFill: Color(0xFF272342),
  darkInk: Color(0xFFC7BDF3),
);
const _mint = (
  fill: Color(0xFFD9F0E6),
  ink: Color(0xFF6FB497),
  strong: Color(0xFF2B6E53),
  darkFill: Color(0xFF173A30),
  darkInk: Color(0xFFA8DEC8),
);
// The dark tones of teal are the handoff's proposal, not drawn in the mock-ups.
const _teal = (
  fill: Color(0xFFD4EEEC),
  ink: Color(0xFF6DAFB2),
  strong: Color(0xFF2A6D71),
  darkFill: Color(0xFF163A3B),
  darkInk: Color(0xFF9FD9D6),
);
const _rose = (
  fill: Color(0xFFF3DDE6),
  ink: Color(0xFFCF93AB),
  strong: Color(0xFF924C68),
  darkFill: Color(0xFF3A2530),
  darkInk: Color(0xFFE9C3D3),
);

typedef _Tones = ({
  Color fill,
  Color ink,
  Color strong,
  Color darkFill,
  Color darkInk,
});

TaskSwatch _swatch(String key, _Tones t, {bool pickable = true}) => TaskSwatch(
  key: key,
  accent: t.ink,
  light: t.fill,
  strong: t.strong,
  darkFill: t.darkFill,
  darkInk: t.darkInk,
  pickable: pickable,
);

/// The six "Иней" families — lavender first, as the default and the nearest to
/// the default accent — then the three warm keys of the old palette. Those have no family of their own any more and are painted
/// as the rose (PLAN.md, decision A); they stay here, unpicked, so a task or a
/// tag saved under them — on this device or by an older app elsewhere — still
/// resolves. A colour shared by two keys maps back to the first: `pink`.
final taskPalette = <TaskSwatch>[
  _swatch('violet', _lavender),
  _swatch('sky', _sky),
  _swatch('blue', _ice),
  _swatch('green', _mint),
  _swatch('teal', _teal),
  _swatch('pink', _rose),
  _swatch('red', _rose, pickable: false),
  _swatch('orange', _rose, pickable: false),
  _swatch('yellow', _rose, pickable: false),
];

/// The families the pickers offer.
final pickableTaskPalette = [
  for (final swatch in taskPalette)
    if (swatch.pickable) swatch,
];

/// The accents of the palette before "Иней", by key — what a task's
/// `colorValue` and a tag's old `color_value` held. Only migrations read it:
/// v13 (tags to keys) and v18 (tasks onto the new tones).
const legacyTaskAccents = <String, int>{
  'violet': 0xFF8B7CF6,
  'green': 0xFF76B894,
  'orange': 0xFFF5A76F,
  'blue': 0xFF72B7D8,
  'pink': 0xFFD98BA8,
  'yellow': 0xFFF4C95D,
  'red': 0xFFE97B70,
};

/// The light tones of the same old palette. A task saved by an early build may
/// hold one of these instead of the accent.
const legacyTaskLightTones = <String, int>{
  'violet': 0xFFE8E5FF,
  'green': 0xFFE2F2E7,
  'orange': 0xFFFCE8D8,
  'blue': 0xFFDFF1F8,
  'pink': 0xFFF6E1E9,
  'yellow': 0xFFFFF2CC,
  'red': 0xFFFFE3E0,
};

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

/// The colour a stored key names, falling back to [fallbackTaskColorKey].
Color taskColorForKey(String? key) =>
    (taskSwatchForKey(key) ?? taskSwatchForKey(fallbackTaskColorKey)!).accent;

/// The key naming [accent], or null when the colour is in no family.
///
/// Used by the sync, which sends a task's colour as a key, and by the tag
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
/// dark one a near-white box would shout, so it is the family's dark tile — or,
/// for a colour in no family, a wash of the accent over [surface]. Either way
/// ask [inkOn] for the glyph on top.
Color taskBadgeSurface(ThemeData theme, Color accent, Color surface) {
  if (theme.brightness == Brightness.light) return taskLightTone(accent);
  final argb = accent.toARGB32();
  for (final swatch in taskPalette) {
    if (swatch.accent.toARGB32() == argb) return swatch.darkFill;
  }
  return flattenOn(surface, accent.withValues(alpha: 0.22));
}

/// The glyph on [taskBadgeSurface]: the family's `strong` tone on a light
/// screen and its `darkInk` on a dark one (DESIGN.md §2.4). A colour in no
/// family is walked by [inkOn] until it reads on [fill].
Color taskBadgeInk(ThemeData theme, Color accent, Color fill) {
  final argb = accent.toARGB32();
  for (final swatch in taskPalette) {
    if (swatch.accent.toARGB32() == argb) {
      return theme.brightness == Brightness.light
          ? swatch.strong
          : swatch.darkInk;
    }
  }
  return inkOn(fill, accent);
}
