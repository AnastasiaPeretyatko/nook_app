import 'package:flutter/material.dart';
import 'package:todo_app/utils/task_colors.dart';

/// One colour of the task palette. A task stores its [accent]; the [light] tone
/// is what large areas are painted with — the timeline pill, the tinted box
/// behind an icon — so the accent stays a small, saturated mark on top of it.
class TaskSwatch {
  const TaskSwatch({required this.accent, required this.light});

  final Color accent;
  final Color light;
}

/// Seven families, accent + light tone each. The accents double as the app's
/// primary colours ([appColorPalette] in `settings/theme_provider.dart`).
const taskPalette = <TaskSwatch>[
  TaskSwatch(accent: Color(0xFF8B7CF6), light: Color(0xFFE8E5FF)), // violet
  TaskSwatch(accent: Color(0xFF76B894), light: Color(0xFFE2F2E7)), // green
  TaskSwatch(accent: Color(0xFFF5A76F), light: Color(0xFFFCE8D8)), // orange
  TaskSwatch(accent: Color(0xFF72B7D8), light: Color(0xFFDFF1F8)), // blue
  TaskSwatch(accent: Color(0xFFD98BA8), light: Color(0xFFF6E1E9)), // pink
  TaskSwatch(accent: Color(0xFFF4C95D), light: Color(0xFFFFF2CC)), // yellow
  TaskSwatch(accent: Color(0xFFE97B70), light: Color(0xFFFFE3E0)), // red
];

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
