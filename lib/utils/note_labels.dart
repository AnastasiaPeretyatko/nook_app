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
  const NoteMoodPreset(this.uid, this.emoji, this.name);

  /// The identity this mood is written with, the same on every device.
  ///
  /// Written out rather than generated, and this is the whole point of it: the
  /// seeding runs once per device, so a phone and a tablet each mint their own
  /// eight moods. With fresh uuids the server would end up holding sixteen rows
  /// for the same eight feelings, and a note marked "Радость" on one device
  /// would point at a mood the other has never heard of. Fixed uuids make the
  /// two sets the same set.
  ///
  /// They are ordinary v4 uuids, generated once and then frozen. **Never change
  /// one**: a device that already seeded with the old value would treat the new
  /// one as a different mood.
  final String uid;

  final String emoji;
  final String name;
}

/// The moods the diary starts with, in the order the picker shows them.
const defaultNoteMoods = <NoteMoodPreset>[
  NoteMoodPreset('0f8a4c3e-1d92-4b7a-9c15-6e2f8a01b4d3', '😊', 'Радость'),
  NoteMoodPreset('2b6d91f7-84ca-4e35-b0d8-77c4e9a12f56', '🌿', 'Спокойствие'),
  NoteMoodPreset('5c31e0a8-2f47-4d69-8b3e-91da6c25f087', '🤔', 'Размышления'),
  NoteMoodPreset('7e94b2d1-6a08-4c52-9f7b-38e5c1470ab9', '😢', 'Грусть'),
  NoteMoodPreset('9a07f3c5-4b81-4e20-a6d9-52fb8c364e1a', '😴', 'Усталость'),
  NoteMoodPreset('b3d85e19-7c62-4a0f-8e41-6db29f057c34', '🙏', 'Благодарность'),
  NoteMoodPreset('d51c7a26-9e34-4f8b-b273-40a6e8d91cf5', '😰', 'Тревога'),
  NoteMoodPreset('f28b60d4-3a15-4c97-9e56-18c7b2f4a06e', '❤️', 'Любовь'),
];

/// The emoji offered when a mood is being invented — "Другое" in the picker.
///
/// A fixed set rather than a keyboard: a mood is drawn as one glyph next to one
/// word, and a field that accepts anything accepts a sentence, which is not a
/// glyph. Deliberately wider than [defaultNoteMoods] and deliberately not
/// including the eight already taken.
const noteMoodEmojis = <String>[
  '🙂',
  '😄',
  '🥳',
  '😌',
  '🤗',
  '😇',
  '🤩',
  '😎',
  '🥰',
  '😅',
  '😐',
  '😕',
  '😔',
  '😞',
  '😡',
  '😨',
  '🤯',
  '🥱',
  '🤒',
  '🌧',
  '⛅',
  '☀️',
  '🌙',
  '⭐',
  '🔥',
  '🌊',
  '🍀',
  '🌸',
  '☕',
  '📚',
  '🎧',
  '✍️',
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

/// The family a tag created from a suggestion or from the "Новый тег" field
/// starts on: the next one of [taskPalette] after those already in use, so two
/// tags made one after the other do not come out the same colour.
///
/// Keys in, key out. A tag stores which family it belongs to rather than what
/// colour that family currently is — see `TaskSwatch.key` — so this compares
/// the same thing the tags hold.
///
/// [used] is what the existing tags hold. Once every family is taken it wraps
/// round by count: there are more possible tags than colours, and repeating is
/// the honest outcome.
String nextNoteTagColorKey(Iterable<String> used) {
  final taken = used.toSet();
  for (final swatch in taskPalette) {
    if (!taken.contains(swatch.key)) return swatch.key;
  }
  return taskPalette[taken.length % taskPalette.length].key;
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
