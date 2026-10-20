import 'package:flutter/material.dart';
import 'package:todo_app/theme/app_palette.dart';

/// The neutral tones the screens are built from, by role. The values are the
/// "Иней" tokens ([AppPalette]); these names are what the widgets ask for, so a
/// repaint of the design changes this file and not a hundred call sites.

/// The tone every label and placeholder is written in — a field's hint, a
/// section caption, anything naming a control rather than holding its content.
///
/// One fixed value in both themes, unlike the surfaces around it: the light
/// theme's `textTertiary`, light enough to stay legible on the dark ladder and
/// grey enough to sit back on a light page, which is the whole job of a label.
const Color labelInk = Color(0xFF8A92A1);

/// A wash of the app accent over [pageSurface] — what the diary paints its
/// tool strips and its empty cover slot with.
///
/// Fainter than the palette's light row, which is meant for a small tinted
/// badge; over an area this size that tone becomes the loudest thing on a page
/// that is otherwise text. Heavier in the dark theme, where 7% over near-black
/// is nothing at all.
Color accentWash(ThemeData theme) => Color.alphaBlend(
  theme.colorScheme.primary.withValues(
    alpha: theme.brightness == Brightness.light ? 0.07 : 0.16,
  ),
  pageSurface(theme),
);

/// The page behind the cards.
Color pageSurface(ThemeData theme) => AppPalette.of(theme).background;

/// A card, a bottom sheet, a dialog — raised above [pageSurface].
Color raisedSurface(ThemeData theme) => AppPalette.of(theme).surface;

/// An inset control inside a card: a chip, an unselected cell, a text field.
Color insetSurface(ThemeData theme) => AppPalette.of(theme).chip;

/// An inset control that is currently unavailable — a shade flatter than
/// [insetSurface].
Color disabledInsetSurface(ThemeData theme) =>
    AppPalette.of(theme).surfaceMuted;

/// Shadow under a raised surface. Barely there on white, heavier in the dark
/// theme, where a faint shadow on near-black shows nothing at all.
Color surfaceShadow(ThemeData theme, {double light = 0.05}) => Colors.black
    .withValues(alpha: theme.brightness == Brightness.light ? light : 0.45);

/// A row in a grouped list: a white card on the page.
Color rowSurface(ThemeData theme) => AppPalette.of(theme).surface;

/// A filled neutral chip: the selected tab, today's circle in the calendar, a
/// habit card that is already done. Ask `onTaskColor` for what goes on top.
Color neutralChip(ThemeData theme) => theme.brightness == Brightness.light
    ? AppPalette.light.chip
    : AppPalette.dark.segmentSelected;
