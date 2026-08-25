import 'package:flutter/material.dart';

/// The neutral tones the forms and sheets are built from.
///
/// They used to be hard-coded greys and whites, which made every one of those
/// screens a white slab in the dark theme. The light values are kept exactly as
/// they were; the dark ones come from the neutral surface ladder pinned in
/// `buildAppTheme`, lightest surface = most raised.

/// The tone every label and placeholder is written in — a field's hint, a
/// section caption, anything naming a control rather than holding its content.
///
/// One fixed value in both themes, unlike the surfaces around it: it is light
/// enough to stay legible on the dark ladder and grey enough to sit back on a
/// light page, which is the whole job of a label.
const Color labelInk = Color(0xFF999AB3);

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

/// The page behind a form's cards.
Color pageSurface(ThemeData theme) => theme.brightness == Brightness.light
    ? const Color(0xFFF3F3F3)
    : theme.colorScheme.surface;

/// A card, a bottom sheet, a dialog — raised above [pageSurface].
Color raisedSurface(ThemeData theme) => theme.brightness == Brightness.light
    ? Colors.white
    : theme.colorScheme.surfaceContainerLow;

/// An inset control inside a card: a chip, an unselected cell, a text field.
Color insetSurface(ThemeData theme) => theme.brightness == Brightness.light
    ? const Color(0xFFF5F5F5)
    : theme.colorScheme.surfaceContainerHigh;

/// An inset control that is currently unavailable — a shade flatter than
/// [insetSurface].
Color disabledInsetSurface(ThemeData theme) =>
    theme.brightness == Brightness.light
    ? const Color(0xFFFAFAFA)
    : theme.colorScheme.surfaceContainer;

/// Shadow under a raised surface. Barely there on white, heavier in the dark
/// theme, where a faint shadow on near-black shows nothing at all.
Color surfaceShadow(ThemeData theme, {double light = 0.05}) =>
    Colors.black.withValues(
      alpha: theme.brightness == Brightness.light ? light : 0.45,
    );

/// A row in a grouped list, raised a shade off the page it sits on.
Color rowSurface(ThemeData theme) => theme.brightness == Brightness.light
    ? const Color(0xFFF7F7F8)
    : theme.colorScheme.surfaceContainerLow;

/// A filled neutral chip: the selected tab, today's circle in the calendar, a
/// habit card that is already done. Ask `onTaskColor` for what goes on top.
Color neutralChip(ThemeData theme) => theme.brightness == Brightness.light
    ? const Color(0xFFD1D1D6)
    : theme.colorScheme.surfaceContainerHighest;
