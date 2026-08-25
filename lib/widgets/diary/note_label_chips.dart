import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/note_labels.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';

/// The strip of labels under a note's title: its mood, then its tags.
///
/// One widget for the form and for the note being read, on the same reasoning as the
/// diary's tool strip: the two have to look identical, and the surest way to keep them so
/// is for them to be one thing. What separates the two uses is whether the
/// callbacks are given — with them the strip carries the buttons that open the
/// pickers, without them it is text.
///
/// Nothing here writes anything. The strip is handed the rows to draw and reports
/// taps; who owns the selection — a draft on the form, the database on the view
/// screen — is the caller's business.
class NoteLabelsRow extends StatelessWidget {
  const NoteLabelsRow({
    super.key,
    required this.moods,
    required this.tags,
    this.onEditMood,
    this.onEditTags,
    this.surface,
  });

  /// The note's moods. The picker hands out one at a time, so this is normally
  /// empty or a single row — it is a list because the join table allows more and
  /// a widget that would break on two of them is a trap.
  final List<NoteMood> moods;

  final List<NoteTag> tags;

  /// Opens the mood picker. Null means the strip is being read rather than
  /// edited: no caret on the chip, and no "Настроение" button when there is no
  /// mood to show.
  final VoidCallback? onEditMood;

  /// Opens the tag picker. Null for the same reason.
  final VoidCallback? onEditTags;

  /// What the chips are drawn on. A tag's fill is mixed against it in the dark
  /// theme — see [noteTagChipTones] — so a strip on the page tone and one on a
  /// raised sheet do not come out the same.
  final Color? surface;

  bool get _isEditable => onEditMood != null || onEditTags != null;

  /// Whether the strip would draw nothing at all, so a caller can leave out the
  /// spacing around it rather than opening a gap over an empty row.
  bool get isEmpty => moods.isEmpty && tags.isEmpty && !_isEditable;

  @override
  Widget build(BuildContext context) {
    final editMood = onEditMood;
    final editTags = onEditTags;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (moods.isEmpty && editMood != null)
          _AddLabelButton(
            icon: LucideIcons.face_slightly_smiling,
            label: 'Настроение',
            onTap: editMood,
          )
        else
          for (final mood in moods)
            MoodChip(mood: mood, onTap: editMood, showCaret: editMood != null),
        if (tags.isEmpty && editTags != null)
          _AddLabelButton(
            icon: LucideIcons.tag,
            label: 'Добавить теги',
            onTap: editTags,
          )
        else ...[
          for (final tag in tags)
            NoteTagChip(tag: tag, onTap: editTags, surface: surface),
          // Only once the note already has tags: with none, the wide button
          // above says the same thing in words.
          if (editTags != null) _AddTagButton(onTap: editTags),
        ],
      ],
    );
  }
}

/// A note's mood: the emoji, the word, and — while the strip is editable — the
/// caret that says tapping it opens the choice again.
///
/// Painted in the app accent's wash rather than a colour of its own: a mood has
/// no colour column, and the emoji is what identifies it. See
/// [noteMoodChipTones].
///
/// [filled] takes the wash away, for the diary's list rows: there the mood sits
/// on the same line as the date, one line of small print among several on a card
/// that already carries coloured tag chips, and a second filled shape up there
/// turns the line into a row of boxes. Unfilled it is the emoji and the word, in
/// the accent asked against [surface].
class MoodChip extends StatelessWidget {
  const MoodChip({
    super.key,
    required this.mood,
    this.onTap,
    this.showCaret = false,
    this.filled = true,
    this.surface,
  });

  final NoteMood mood;
  final VoidCallback? onTap;
  final bool showCaret;
  final bool filled;

  /// What it is drawn on, which is what its ink is asked against once there is
  /// no fill of its own to ask against. Defaults to the page tone.
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = filled
        ? noteMoodChipTones(theme)
        : (
            fill: Colors.transparent,
            ink: inkOn(
              surface ?? pageSurface(theme),
              theme.colorScheme.primary,
            ),
          );

    return _ChipShell(
      fill: tones.fill,
      // No fill, no padding: the chip's inset only exists to keep the words off
      // the edge of a shape that is no longer there, and here it would push the
      // mood away from the dot that introduces it.
      padding: filled
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
          : EdgeInsets.zero,
      onTap: onTap,
      children: [
        Text(mood.emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(mood.name, style: _labelStyle(theme, tones.ink)),
        if (showCaret) ...[
          const SizedBox(width: 4),
          Icon(LucideIcons.chevron_down, size: 14, color: tones.ink),
        ],
      ],
    );
  }
}

/// One tag, in its own colour, with the "#" the name does not carry.
class NoteTagChip extends StatelessWidget {
  const NoteTagChip({super.key, required this.tag, this.onTap, this.surface});

  final NoteTag tag;
  final VoidCallback? onTap;

  /// What the chip sits on; see [NoteLabelsRow.surface].
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = noteTagChipTones(theme, Color(tag.colorValue), on: surface);

    return _ChipShell(
      fill: tones.fill,
      onTap: onTap,
      children: [Text('#${tag.name}', style: _labelStyle(theme, tones.ink))],
    );
  }
}

/// The button that opens a picker while the note has nothing of that kind yet —
/// "☺ Настроение", "🏷 Добавить теги" on the form.
///
/// No fill: it is an invitation, not content, and a filled chip next to the
/// note's own filled chips would read as a label the note carries.
class _AddLabelButton extends StatelessWidget {
  const _AddLabelButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _ChipShell(
      fill: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      onTap: onTap,
      children: [
        Icon(icon, size: 15, color: labelInk),
        const SizedBox(width: 6),
        Text(label, style: _labelStyle(theme, labelInk)),
      ],
    );
  }
}

/// Adds one more tag to a note that already has some: a "+" the width of a chip
/// and nothing else, so the row reads as "these, and more if you like".
class _AddTagButton extends StatelessWidget {
  const _AddTagButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _ChipShell(
      fill: insetSurface(theme),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      onTap: onTap,
      children: [Icon(LucideIcons.plus, size: 15, color: labelInk)],
    );
  }
}

/// The one shape every chip on the strip has: a rounded fill, an optional tap,
/// and a row inside it. Pulled out so a mood, a tag and a button cannot drift
/// apart by a pixel of padding.
class _ChipShell extends StatelessWidget {
  const _ChipShell({
    required this.fill,
    required this.children,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  });

  final Color fill;
  final List<Widget> children;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              // The note's editor keeps the focus: a focusable chip would close
              // the keyboard the moment a label is picked.
              canRequestFocus: false,
              child: content,
            ),
    );
  }
}

/// The one text style on the strip. Small and semi-bold: a label is a word, not
/// a sentence, and at this size a regular weight goes grey against the fills.
TextStyle? _labelStyle(ThemeData theme, Color ink) => theme
    .textTheme
    .labelMedium
    ?.copyWith(fontWeight: FontWeight.w600, color: ink);
