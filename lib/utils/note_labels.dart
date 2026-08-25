/// What the diary opens with, and what the pickers offer beyond it: the moods
/// the app ships, the emoji a new mood can be given, and the tag names it
/// suggests.
///
/// None of it is the *data* — a mood and a tag are rows, see `NoteMoods` and
/// `NoteTags`. These are the seeds: the eight moods are written into the table
/// once, by the migration, and from then on they are ordinary rows the user can
/// add to. Nothing here is looked up at runtime to draw a note, so a mood
/// removed from this list later does not take the notes marked with it down.
library;

import 'package:flutter/material.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';

/// One entry of the seed list. Not a database row and not a widget's model —
/// only what the migration needs to write one.
class NoteMoodPreset {
  const NoteMoodPreset(this.emoji, this.name);

  final String emoji;
  final String name;
}

/// The moods the diary starts with, in the order the picker shows them.
const defaultNoteMoods = <NoteMoodPreset>[
  NoteMoodPreset('😊', 'Радость'),
  NoteMoodPreset('🌿', 'Спокойствие'),
  NoteMoodPreset('🤔', 'Размышления'),
  NoteMoodPreset('😢', 'Грусть'),
  NoteMoodPreset('😴', 'Усталость'),
  NoteMoodPreset('🙏', 'Благодарность'),
  NoteMoodPreset('😰', 'Тревога'),
  NoteMoodPreset('❤️', 'Любовь'),
];

/// The emoji offered when a mood is being invented — "Другое" in the picker.
///
/// A fixed set rather than a keyboard: a mood is drawn as one glyph next to one
/// word, and a field that accepts anything accepts a sentence, which is not a
/// glyph. Deliberately wider than [defaultNoteMoods] and deliberately not
/// including the eight already taken.
const noteMoodEmojis = <String>[
  '🙂', '😄', '🥳', '😌', '🤗', '😇', '🤩', '😎',
  '🥰', '😅', '😐', '😕', '😔', '😞', '😡', '😨',
  '🤯', '🥱', '🤒', '🌧', '⛅', '☀️', '🌙', '⭐',
  '🔥', '🌊', '🍀', '🌸', '☕', '📚', '🎧', '✍️',
];

/// Tag names the picker offers under "Популярные".
///
/// Only the ones the user does not already have are shown, so the section empties
/// itself as they are taken — it is a way past the blank first run, not a second
/// list of the same tags.
const suggestedNoteTags = <String>[
  'идеи',
  'дневник',
  'цели',
  'вдохновение',
  'работа',
  'мысли',
  'здоровье',
  'путешествия',
];

/// The colour a tag created from a suggestion or from the "Новый тег" field
/// starts on: the next family of [taskPalette] after the ones already in use, so
/// two tags made one after the other do not come out the same colour.
///
/// [used] is what the existing tags hold. Once every family is taken it wraps
/// round by count — there are more possible tags than colours, and repeating is
/// the honest outcome.
Color nextNoteTagColor(Iterable<Color> used) {
  final taken = used.map((c) => c.toARGB32()).toSet();
  for (final swatch in taskPalette) {
    if (!taken.contains(swatch.accent.toARGB32())) return swatch.accent;
  }
  return taskPalette[taken.length % taskPalette.length].accent;
}

/// The pair of tones a tag's chip is painted with: the fill, and the ink to put
/// on it.
///
/// Straight through the task palette's own rules — [taskBadgeSurface] gives the
/// family's light tone on a light screen and a wash of the accent on a dark one,
/// and [inkOn] walks the accent until it can be read on whichever came out. So a
/// tag chip is the same object as the tinted icon box on a task row, and nothing
/// here hard-codes a colour.
({Color fill, Color ink}) noteTagChipTones(
  ThemeData theme,
  Color color, {
  Color? on,
}) {
  final surface = on ?? raisedSurface(theme);
  final fill = taskBadgeSurface(theme, color, surface);
  return (fill: fill, ink: inkOn(fill, color));
}

/// The tones a mood's chip is painted with when it is the chosen one.
///
/// The app accent, not a colour of its own: a mood has no colour column, and
/// inventing one per mood would make the picker a second palette to keep in step
/// with the first. Unchosen, a mood chip is [insetSurface] like any other
/// unselected cell.
({Color fill, Color ink}) noteMoodChipTones(ThemeData theme) {
  final fill = accentWash(theme);
  return (fill: fill, ink: inkOn(fill, theme.colorScheme.primary));
}
