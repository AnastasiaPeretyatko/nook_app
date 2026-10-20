import 'package:flutter/material.dart';

/// The neutral tokens of the "Иней" design — the colours `ColorScheme` has no
/// slot for. Values are `docs/design-handoff/DESIGN.md` §2; that document wins
/// over the screen mock-ups where the two disagree.
///
/// Attached to the theme by `buildAppTheme`; read it with [AppPalette.of],
/// which also answers for a bare `ThemeData` (a test's), by brightness.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.segmentTrack,
    required this.segmentSelected,
    required this.chip,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.iconMuted,
    required this.switchOff,
    required this.link,
    required this.danger,
    required this.dangerSoft,
    required this.navBar,
    required this.navInactive,
    required this.lateSoft,
  });

  /// The page behind the cards.
  final Color background;

  /// A card, the bottom bar, a field.
  final Color surface;

  /// A card inside a sheet.
  final Color surfaceMuted;
  final Color segmentTrack;
  final Color segmentSelected;
  final Color chip;
  final Color border;
  final Color borderStrong;
  final Color divider;

  /// An empty checkbox, a dashed outline.
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;

  /// Secondary content only — 3.1:1 on white in the light theme.
  final Color textTertiary;
  final Color iconMuted;
  final Color switchOff;
  final Color link;
  final Color danger;
  final Color dangerSoft;
  final Color navBar;
  final Color navInactive;

  /// A day ticked late, in the week analytics.
  final Color lateSoft;

  static const light = AppPalette(
    background: Color(0xFFF6F8FB),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF4F6F9),
    segmentTrack: Color(0xFFE9EDF3),
    segmentSelected: Color(0xFFFFFFFF),
    chip: Color(0xFFEEF1F5),
    border: Color(0xFFE8ECF2),
    borderStrong: Color(0xFFE3E8F0),
    divider: Color(0xFFEEF1F5),
    outline: Color(0xFFD3D9E3),
    textPrimary: Color(0xFF1B2230),
    textSecondary: Color(0xFF5F6878),
    textTertiary: Color(0xFF8A92A1),
    iconMuted: Color(0xFFB4BBC7),
    switchOff: Color(0xFFC9CFD9),
    link: Color(0xFF4F5FB8),
    danger: Color(0xFFA2574A),
    dangerSoft: Color(0xFFF7E6E2),
    navBar: Color(0xFFFFFFFF),
    navInactive: Color(0xFF5F6878),
    lateSoft: Color(0xFFC8D0F2),
  );

  // link, danger, dangerSoft, switchOff and lateSoft are not drawn in the dark
  // mock-ups; these are the handoff's proposals.
  static const dark = AppPalette(
    background: Color(0xFF101317),
    surface: Color(0xFF181C21),
    surfaceMuted: Color(0xFF1A1E24),
    segmentTrack: Color(0xFF1A1E24),
    segmentSelected: Color(0xFF2A3039),
    chip: Color(0xFF23282F),
    border: Color(0xFF23282F),
    borderStrong: Color(0xFF262B33),
    divider: Color(0xFF23282F),
    outline: Color(0xFF3A414B),
    textPrimary: Color(0xFFE8ECF2),
    textSecondary: Color(0xFF98A1B0),
    textTertiary: Color(0xFF6E7684),
    iconMuted: Color(0xFF6E7684),
    switchOff: Color(0xFF3A414B),
    link: Color(0xFFAEB8F5),
    danger: Color(0xFFE29A8C),
    dangerSoft: Color(0xFF3A2522),
    navBar: Color(0xFF15181D),
    navInactive: Color(0xFF8B94A3),
    lateSoft: Color(0xFF3A4170),
  );

  static AppPalette of(ThemeData theme) =>
      theme.extension<AppPalette>() ??
      (theme.brightness == Brightness.light ? light : dark);

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      segmentTrack: l(segmentTrack, other.segmentTrack),
      segmentSelected: l(segmentSelected, other.segmentSelected),
      chip: l(chip, other.chip),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      divider: l(divider, other.divider),
      outline: l(outline, other.outline),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      iconMuted: l(iconMuted, other.iconMuted),
      switchOff: l(switchOff, other.switchOff),
      link: l(link, other.link),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      navBar: l(navBar, other.navBar),
      navInactive: l(navInactive, other.navInactive),
      lateSoft: l(lateSoft, other.lateSoft),
    );
  }
}

/// An interface accent: one tone per theme (DESIGN.md §2.3).
class AppAccent {
  const AppAccent(this.name, this.light, this.dark);
  final String name;
  final Color light;
  final Color dark;
}

/// The six accents, the default first. What is stored is [AppAccent.light].
const appAccents = <AppAccent>[
  AppAccent('Барвинковый', Color(0xFF5B6DCB), Color(0xFF9AA8F2)),
  AppAccent('Небесный', Color(0xFF3B66B5), Color(0xFFA9C1F2)),
  AppAccent('Морской', Color(0xFF2A7190), Color(0xFF9FD6EA)),
  AppAccent('Бирюзовый', Color(0xFF2A6D71), Color(0xFF9FD9D6)),
  AppAccent('Шалфей', Color(0xFF2B6E53), Color(0xFFA8DEC8)),
  AppAccent('Пыльно-розовый', Color(0xFF924C68), Color(0xFFE9C3D3)),
];

/// The accent a stored colour stands for. An accent saved before "Иней" maps
/// onto its nearest new family — the warm ones onto the rose, as the task
/// colours do (PLAN.md, decision A) — and anything unknown onto the default.
AppAccent accentFor(Color stored) {
  final argb = stored.toARGB32();
  for (final accent in appAccents) {
    if (accent.light.toARGB32() == argb) return accent;
  }
  return switch (argb) {
    0xFF76B894 => appAccents[4], // green → sage
    0xFF72B7D8 => appAccents[2], // blue → sea
    0xFFD98BA8 || // pink
    0xFFF5A76F || // orange
    0xFFF4C95D || // yellow
    0xFFE97B70 => appAccents[5], // red → rose
    _ => appAccents.first, // violet, graphite, unknown
  };
}
