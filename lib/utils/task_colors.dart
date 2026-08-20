import 'package:flutter/material.dart';

/// Black and white contrast equally against a background of this luminance
/// (4.58:1 each). Below it white reads better, above it black does — so picking
/// the winner keeps *any* background legible, never worse than 4.58:1.
///
/// The same number decides `onPrimary` in `buildAppTheme`, so a task colour and
/// the app accent flip their text at the same point.
const double _foregroundCrossover = 0.179;

/// Whether content drawn on [surface] has to be light.
bool taskSurfaceIsDark(Color surface) =>
    surface.computeLuminance() <= _foregroundCrossover;

/// Foreground for titles and primary icons drawn on a task colour.
///
/// A task colour is user-picked from the whole palette — pale mint through deep
/// strawberry — so nothing on top of it can be a fixed black or a fixed white.
/// Pass the colour that actually shows through: for a translucent layer over
/// the task colour, flatten it with [flattenOn] first.
Color onTaskColor(Color surface) => taskSurfaceIsDark(surface)
    ? Colors.white.withValues(alpha: 0.96)
    : Colors.black.withValues(alpha: 0.85);

/// Foreground for secondary content on a task colour: time labels, counters,
/// the icon inside a coloured circle.
Color onTaskColorMuted(Color surface) => taskSurfaceIsDark(surface)
    ? Colors.white.withValues(alpha: 0.82)
    : Colors.black.withValues(alpha: 0.60);

/// Foreground for decoration on a task colour: hint icons, dots, hairlines.
/// Not for anything that has to be read.
Color onTaskColorFaint(Color surface) => taskSurfaceIsDark(surface)
    ? Colors.white.withValues(alpha: 0.55)
    : Colors.black.withValues(alpha: 0.30);

/// The opaque colour that shows when [overlay] is painted over [surface].
/// Use it before [onTaskColor] whenever the thing under the text is a
/// translucent layer — a white "glass" button or a progress fill — rather than
/// the task colour itself.
Color flattenOn(Color surface, Color overlay) =>
    Color.alphaBlend(overlay, surface);

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// [color] used as *ink* on [surface] — an icon, a label, a dot — moved along
/// its own hue until it reads at 4.5:1, and left alone when it already does.
///
/// Needed in both directions: the semantic colours of the action sheets (indigo
/// "изменить", amber "архив") vanish on a near-black sheet, and a pale task
/// swatch such as mint vanishes on a white one. Only lightness moves, so the
/// colour stays recognisably itself.
///
/// [minContrast] defaults to the 4.5:1 text minimum; pass 3 for a graphic that
/// only has to be *seen* — a dot, an icon, a hairline.
Color inkOn(Color surface, Color color, {double minContrast = 4.5}) {
  if (_contrast(color, surface) >= minContrast) return color;

  final lighten = surface.computeLuminance() < 0.5;
  var hsl = HSLColor.fromColor(color);
  // 2% steps: 50 of them cover the whole lightness range.
  for (var i = 0; i < 50; i++) {
    final next = hsl.lightness + (lighten ? 0.02 : -0.02);
    if (next <= 0 || next >= 1) break;
    hsl = hsl.withLightness(next);
    if (_contrast(hsl.toColor(), surface) >= minContrast) break;
  }
  return hsl.toColor();
}
