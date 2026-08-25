/// The two pickers behind the note form's label strip: the mood, and the tags.
///
/// One file for both, because they are the same sheet with different contents —
/// a title, a wrap of chips, and a row for making a new one that is **not there
/// until it is asked for**. A form permanently showing an empty field for a tag
/// nobody is creating is the loudest thing in the sheet and the least used.
///
/// Neither sheet returns a value. They report every change through [onChanged]
/// as it happens, so the choice survives being dismissed by the scrim or the
/// back gesture rather than only by the "×" — a picker that quietly throws the
/// selection away depending on how it was closed is a picker nobody trusts.
///
/// What they *do* write directly is the catalogues: a mood or a tag the user
/// invents is a row shared by every note, so it is inserted the moment it is
/// made rather than waiting for the note to be saved. The link to the note is
/// the caller's business and still goes through the form's save.
library;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/note_labels.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/color_picker_row.dart';

/// Opens the mood picker. Reports the chosen mood's id, or null when the mood
/// that was on is tapped again.
///
/// Single choice, so it closes on a tap: the design shows one mood on a note,
/// and a sheet that stays open after the one decision it holds has been made is
/// a sheet the user has to dismiss for nothing.
Future<void> showMoodPickerSheet(
  BuildContext context, {
  required int? selected,
  required ValueChanged<int?> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MoodPickerSheet(selected: selected, onChanged: onChanged),
  );
}

/// Opens the tag picker. Reports the whole set every time it changes.
///
/// Stays open, unlike the mood sheet: tags are picked in handfuls, and closing
/// after each one would mean opening the sheet once per tag.
Future<void> showTagPickerSheet(
  BuildContext context, {
  required Set<int> selected,
  required ValueChanged<Set<int>> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TagPickerSheet(selected: selected, onChanged: onChanged),
  );
}

// -----------------------------------------------------------------------------
// The mood sheet.
// -----------------------------------------------------------------------------

class _MoodPickerSheet extends ConsumerStatefulWidget {
  const _MoodPickerSheet({required this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  ConsumerState<_MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends ConsumerState<_MoodPickerSheet> {
  final _nameController = TextEditingController();

  /// Whether the "Другое" row is open. The field is built on demand rather than
  /// hidden, so nothing is holding focus while it is away.
  bool _creating = false;

  /// The emoji picked for the mood being invented. A mood without one has
  /// nothing to be recognised by, so it is what gates the button.
  String? _emoji;

  /// Set while the insert is in flight, so a second tap cannot write the mood
  /// twice.
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moods = ref.watch(noteMoodsProvider).valueOrNull ?? const <NoteMood>[];

    return _SheetShell(
      title: 'Какое у вас настроение?',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mood in moods)
              _MoodOption(
                mood: mood,
                isSelected: mood.id == widget.selected,
                onTap: () => _pick(mood.id),
              ),
            // Last, and on whatever line is left: it is not one of the moods.
            _NewLabelChip(
              label: 'Другое',
              isOpen: _creating,
              onTap: () => setState(() => _creating = !_creating),
            ),
          ],
        ),
        if (_creating) ...[
          _CreationDivider(),
          _NameField(
            controller: _nameController,
            hint: 'Название настроения',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('Выберите смайл', style: _captionStyle(theme)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final emoji in noteMoodEmojis)
                _EmojiOption(
                  emoji: emoji,
                  isSelected: emoji == _emoji,
                  onTap: () => setState(() => _emoji = emoji),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _AddButton(
            // Both halves are required: a mood is a word *and* a glyph.
            onPressed:
                _saving ||
                    _nameController.text.trim().isEmpty ||
                    _emoji == null
                ? null
                : () => _create(moods),
          ),
        ],
      ],
    );
  }

  /// Selects a mood, or clears it when the one already on is tapped — the only
  /// way to take a mood off a note, since the strip's chip reopens this sheet.
  void _pick(int id) {
    widget.onChanged(id == widget.selected ? null : id);
    Navigator.of(context).pop();
  }

  Future<void> _create(List<NoteMood> moods) async {
    final name = _nameController.text.trim();
    final emoji = _emoji;
    if (name.isEmpty || emoji == null) return;

    setState(() => _saving = true);
    // A name that is already in the catalogue selects the mood that has it
    // instead of making a second one: two "Спокойствие" chips differing by
    // emoji is not a thing anyone meant to create.
    final existing = _byName(moods, name);
    final id =
        existing?.id ??
        await ref
            .read(diaryDaoProvider)
            .insertMood(name: name, emoji: emoji);

    widget.onChanged(id);
    if (mounted) Navigator.of(context).pop();
  }

  NoteMood? _byName(List<NoteMood> moods, String name) {
    final needle = name.toLowerCase();
    for (final mood in moods) {
      if (mood.name.toLowerCase() == needle) return mood;
    }
    return null;
  }
}

/// One mood in the picker. Selected, it takes the accent's wash and a hairline
/// of the accent — the same "chosen cell" the icon picker draws, so the two
/// sheets do not each invent a way of saying it.
class _MoodOption extends StatelessWidget {
  const _MoodOption({
    required this.mood,
    required this.isSelected,
    required this.onTap,
  });

  final NoteMood mood;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = noteMoodChipTones(theme);

    return _OptionChip(
      fill: isSelected ? tones.fill : insetSurface(theme),
      border: isSelected ? tones.ink.withValues(alpha: 0.45) : null,
      onTap: onTap,
      children: [
        Text(mood.emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 6),
        Text(
          mood.name,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: isSelected ? tones.ink : theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// One emoji offered to a mood being invented.
class _EmojiOption extends StatelessWidget {
  const _EmojiOption({
    required this.emoji,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = noteMoodChipTones(theme);

    return _OptionChip(
      fill: isSelected ? tones.fill : insetSurface(theme),
      border: isSelected ? tones.ink.withValues(alpha: 0.45) : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      onTap: onTap,
      children: [Text(emoji, style: const TextStyle(fontSize: 18))],
    );
  }
}

// -----------------------------------------------------------------------------
// The tag sheet.
// -----------------------------------------------------------------------------

class _TagPickerSheet extends ConsumerStatefulWidget {
  const _TagPickerSheet({required this.selected, required this.onChanged});

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  @override
  ConsumerState<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<_TagPickerSheet> {
  final _nameController = TextEditingController();

  /// The sheet's own copy of the note's tags. It stays open while they are being
  /// picked, so it needs the selection to draw itself; [_TagPickerSheet.onChanged]
  /// is what keeps the form in step.
  late final Set<int> _selected = {...widget.selected};

  bool _creating = false;
  Color? _color;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = ref.watch(noteTagsProvider).valueOrNull ?? const <NoteTag>[];

    // The suggestions the user has not taken yet. It empties itself as they are
    // used, which is what makes it a way past a blank first run rather than a
    // second copy of the list above.
    final taken = {for (final tag in tags) tag.name.toLowerCase()};
    final suggestions = [
      for (final name in suggestedNoteTags)
        if (!taken.contains(name.toLowerCase())) name,
    ];

    return _SheetShell(
      title: 'Теги',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags)
              _TagOption(
                tag: tag,
                isSelected: _selected.contains(tag.id),
                onTap: () => _toggle(tag.id),
              ),
            _NewLabelChip(
              label: 'Новый тег',
              isOpen: _creating,
              onTap: _toggleCreating,
            ),
          ],
        ),
        if (_creating) ...[
          _CreationDivider(),
          _NameField(
            controller: _nameController,
            hint: 'Название тега',
            // The "#" is punctuation the chip draws, so it is not typed and not
            // stored — see `NoteTags.name`.
            prefixText: '#',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          Text('Выберите цвет', style: _captionStyle(theme)),
          // The task colour picker, unchanged: a tag's colour is one of the
          // seven families a task can be, so there is one palette in the app and
          // not two.
          ColorPickerRow(
            selected: _color,
            onChanged: (color) => setState(() => _color = color),
          ),
          const SizedBox(height: 6),
          _AddButton(
            onPressed: _saving || _nameController.text.trim().isEmpty
                ? null
                : () => _create(tags),
          ),
        ],
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Популярные', style: _captionStyle(theme)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in suggestions)
                _SuggestionChip(
                  name: name,
                  onTap: _saving ? null : () => _createNamed(tags, name),
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
    // A fresh set each time: handing out the one the sheet is drawing from
    // would let the form mutate it from under this screen.
    widget.onChanged({..._selected});
  }

  void _toggleCreating() {
    setState(() {
      _creating = !_creating;
      // Opened on a colour nothing else uses, so two tags made one after the
      // other do not come out the same.
      _color ??= nextNoteTagColor([
        for (final tag in ref.read(noteTagsProvider).valueOrNull ?? const [])
          Color(tag.colorValue),
      ]);
    });
  }

  /// Creates the tag in the field and selects it. Unlike the mood sheet this
  /// does not close: the tag just made is one of possibly several.
  Future<void> _create(List<NoteTag> tags) =>
      _add(tags, _nameController.text.trim(), _color);

  /// Creates a tag from a suggestion under "Популярные" — the same path, with
  /// the name given and the colour left to be picked for it.
  Future<void> _createNamed(List<NoteTag> tags, String name) =>
      _add(tags, name, null);

  Future<void> _add(List<NoteTag> tags, String name, Color? color) async {
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      // A name already in the catalogue selects the tag that has it: a second
      // "#работа" in another colour is a duplicate, not a new tag.
      final existing = _byName(tags, name);
      final id =
          existing?.id ??
          await ref.read(diaryDaoProvider).insertTag(
            name: name,
            colorValue:
                (color ??
                        nextNoteTagColor([
                          for (final tag in tags) Color(tag.colorValue),
                        ]))
                    .toARGB32(),
          );

      if (!mounted) return;
      setState(() {
        _selected.add(id);
        // The field has done its job; the row folds away and the sheet is back
        // to being a list of tags.
        _creating = false;
        _nameController.clear();
        _color = null;
        _saving = false;
      });
      widget.onChanged({..._selected});
    } on Object catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  NoteTag? _byName(List<NoteTag> tags, String name) {
    final needle = name.toLowerCase();
    for (final tag in tags) {
      if (tag.name.toLowerCase() == needle) return tag;
    }
    return null;
  }
}

/// One tag in the picker.
///
/// Off, it is an [insetSurface] cell with the tag's colour carried by the text
/// alone; on, the cell is the family's own light tone with a hairline of its ink.
/// Both states show the colour — that is what a tag is recognised by — and the
/// fill is what says which of them it is.
class _TagOption extends StatelessWidget {
  const _TagOption({
    required this.tag,
    required this.isSelected,
    required this.onTap,
  });

  final NoteTag tag;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(tag.colorValue);
    final tones = noteTagChipTones(theme, color);
    final off = insetSurface(theme);

    return _OptionChip(
      fill: isSelected ? tones.fill : off,
      border: isSelected ? tones.ink.withValues(alpha: 0.5) : null,
      onTap: onTap,
      children: [
        Text(
          '#${tag.name}',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: isSelected ? tones.ink : inkOn(off, color),
          ),
        ),
      ],
    );
  }
}

/// A tag the app suggests but the user does not have. Deliberately flatter than
/// [_TagOption]: it is not one of their tags until it is tapped, and a "+" says
/// tapping it makes one.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.name, required this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _OptionChip(
      fill: insetSurface(theme).withValues(alpha: 0.6),
      onTap: onTap,
      children: [
        Text(
          '#$name',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: labelInk,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Shared parts.
// -----------------------------------------------------------------------------

/// The shape both sheets have: a raised rounded card standing off the screen
/// edges, a title with the "×" that closes it, and the contents under it.
///
/// Scrollable and capped in height, because either sheet can grow: the mood one
/// opens a grid of emoji and the tag one a colour row, and with the keyboard up
/// there is half a screen left to put them in. The keyboard's own inset is added
/// at the bottom, which is what lifts the sheet instead of letting it hide under
/// it.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Material(
            color: raisedSurface(theme),
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(LucideIcons.x, size: 20),
                          style: IconButton.styleFrom(
                            backgroundColor: insetSurface(theme),
                            shape: const CircleBorder(),
                            minimumSize: const Size(34, 34),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chip that opens the creation row — "Другое", "Новый тег". Dashed-looking
/// it is not: a "+" and the accent while it is open is enough, and the sheet
/// already has the dashed outline vocabulary spoken for by the cover slot.
class _NewLabelChip extends StatelessWidget {
  const _NewLabelChip({
    required this.label,
    required this.isOpen,
    required this.onTap,
  });

  final String label;
  final bool isOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = noteMoodChipTones(theme);
    final ink = isOpen ? tones.ink : labelInk;

    return _OptionChip(
      fill: isOpen ? tones.fill : insetSurface(theme),
      border: isOpen ? tones.ink.withValues(alpha: 0.45) : null,
      onTap: onTap,
      children: [
        Icon(isOpen ? LucideIcons.x : LucideIcons.plus, size: 15, color: ink),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ],
    );
  }
}

/// The hairline between the chips and the row for making a new one: what is
/// below it is not one more choice, it is a different act.
class _CreationDivider extends StatelessWidget {
  const _CreationDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 28,
    thickness: 1,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// The name of the mood or tag being made. Focused as it appears — it is the
/// only reason the row is open.
class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.prefixText,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final String? prefixText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      autofocus: true,
      maxLines: 1,
      textCapitalization: TextCapitalization.sentences,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: labelInk),
        prefixText: prefixText,
        prefixStyle: theme.textTheme.bodyLarge?.copyWith(color: labelInk),
        isDense: true,
        filled: true,
        fillColor: insetSurface(theme),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Commits what the creation row holds. Full width, because it is the one thing
/// to do at that point; disabled until there is something to commit, which is
/// also what keeps a double tap from writing two rows.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Text('Добавить'),
      ),
    );
  }
}

/// One chip in either picker: a fill, an optional hairline, and a row of
/// whatever it is showing. The pickers' own chips rather than the strip's — this
/// one has a selected state and a bigger tap target, the strip's is read.
class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.fill,
    required this.children,
    this.onTap,
    this.border,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  final Color fill;
  final Color? border;
  final List<Widget> children;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final line = border;

    // `shape` only, never alongside `borderRadius`: `Material` asserts when it
    // is handed both, and the hairline needs a shape to live on.
    return Material(
      color: fill,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: line == null
            ? BorderSide.none
            : BorderSide(color: line, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// The tone a caption inside a sheet is written in — "Выберите смайл",
/// "Популярные".
TextStyle? _captionStyle(ThemeData theme) =>
    theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: labelInk,
    );
