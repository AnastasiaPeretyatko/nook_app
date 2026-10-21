import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_note_page.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/note_delta.dart';
import 'package:todo_app/utils/note_images.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/diary/note_body_view.dart';
import 'package:todo_app/widgets/diary/note_gallery.dart';
import 'package:todo_app/widgets/diary/note_label_chips.dart';
import 'package:todo_app/widgets/page_header.dart';

/// A saved note, read (`JournalRead.dc.html`).
///
/// A pushed route like the archive, so it covers the bottom navigation bar and
/// its own back arrow is the only way out. Along the top: back, pin and "Ещё"
/// (copy the text, archive, delete); then the date, the title, the labels, the
/// check-list's progress and the text; the round pencil at the bottom edge opens
/// the editor.
///
/// **No cover.** The mock-up has none, and the editor does not offer one for now,
/// so a note's cover picture is simply not shown here. The file and the column
/// stay; the old cover-and-sheet layout is in git (commit 18e8172).
class NoteViewPage extends ConsumerWidget {
  const NoteViewPage({super.key, required this.entryId});

  final int entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final entryAsync = ref.watch(diaryEntryProvider(entryId));
    final imagesDirectory = ref.watch(noteImagesDirectoryProvider).valueOrNull;
    final entry = entryAsync.valueOrNull;

    if (entry == null) {
      // Either the stream has not arrived yet or the note is gone — deleted
      // from this very screen, in which case it is already closing.
      return Scaffold(
        backgroundColor: pageSurface(theme),
        body: Center(
          child: entryAsync.isLoading
              ? const CircularProgressIndicator()
              : const SizedBox.shrink(),
        ),
      );
    }

    // The lavender wash at the top is the light theme's; on the dark page it
    // would be a bright band, so there the page is plain.
    final wash = theme.brightness == Brightness.light;

    return Scaffold(
      backgroundColor: pageSurface(theme),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: wash
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFE3DEF8),
                    const Color(0xFFEEEBFA),
                    pageSurface(theme),
                  ],
                  stops: const [0, 0.16, 0.34],
                )
              : null,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                _TopActions(entry: entry),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      22,
                      24,
                      // Room for the pencil, which floats over the end of the text.
                      120 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: _Article(
                      entry: entry,
                      imagesDirectory: imagesDirectory,
                      onBodyChanged: (body) =>
                          ref.read(diaryDaoProvider).setBody(entry.id, body),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              right: 24,
              bottom: 32 + MediaQuery.paddingOf(context).bottom,
              child: _EditButton(
                background: p.textPrimary,
                glyph: p.background,
                // Nothing is passed back: the entry is streamed, so the screen
                // redraws itself the moment the edit is written.
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CreateNotePage(entry: entry),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Back, pin and the note's menu.
class _TopActions extends ConsumerWidget {
  const _TopActions({required this.entry});

  final DiaryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).colorScheme.primary;

    // Top inset only: the row sits at the top of a column, and a bottom inset
    // here is empty space pushing the note down by the height of the home bar.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(
          children: [
            RoundIconButton(
              icon: LucideIcons.arrow_left,
              tooltip: 'Назад',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            RoundIconButton(
              icon: LucideIcons.pin,
              tooltip: entry.isFavorite ? 'Открепить' : 'Закрепить',
              iconColor: entry.isFavorite ? accent : null,
              onPressed: () => ref
                  .read(diaryDaoProvider)
                  .setFavorite(entry.id, !entry.isFavorite),
            ),
            const SizedBox(width: 8),
            RoundIconButton(
              icon: LucideIcons.ellipsis,
              tooltip: 'Ещё',
              onPressed: () => _showMenu(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final archived = entry.status == DiaryEntryStatus.archived;
    final action = await showActionsSheet<_NoteAction>(
      context,
      actions: [
        const SheetAction(
          icon: LucideIcons.copy,
          label: 'Скопировать текст',
          value: _NoteAction.copy,
        ),
        SheetAction(
          icon: archived ? LucideIcons.archive_restore : LucideIcons.archive,
          label: archived ? 'Вернуть из архива' : 'В архив',
          value: _NoteAction.archive,
        ),
        const SheetAction(
          icon: LucideIcons.trash_2,
          label: 'Удалить',
          value: _NoteAction.delete,
          destructive: true,
        ),
      ],
    );
    if (!context.mounted) return;

    switch (action) {
      case _NoteAction.copy:
        _copy(context);
      case _NoteAction.archive:
        await ref
            .read(diaryDaoProvider)
            .setStatus(
              entry.id,
              archived ? DiaryEntryStatus.normal : DiaryEntryStatus.archived,
            );
      case _NoteAction.delete:
        await _delete(context, ref);
      case null:
        break;
    }
  }

  /// Sharing proper needs a plugin the project does not have, so this puts the
  /// note's text on the clipboard — the part of sharing that can be done with
  /// what is here.
  void _copy(BuildContext context) {
    final body = entry.body.trim();
    final text = body.isEmpty
        ? entry.title
        : '${entry.title}\n\n${deltaPlainText(jsonDecode(body) as List)}';
    Clipboard.setData(ClipboardData(text: text.trim()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Текст заметки скопирован')));
  }

  /// Deletes the note and the files it owns — its cover and everything attached.
  /// Nothing else refers to them, so leaving them behind would be a leak nobody
  /// can find later.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: DialogIcons.delete,
      title: 'Удалить заметку?',
      body: 'Вместе с ней удалятся её изображения.',
      action: 'Удалить',
    );
    if (confirmed != true) return;

    await deleteNoteImages([
      ?entry.coverImage,
      ...decodeImageNames(entry.images),
    ]);
    await ref.read(diaryDaoProvider).deleteEntry(entry.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

enum _NoteAction { copy, archive, delete }

/// The page itself: when the note was written and last touched, its title, the
/// labels, the check-list's progress and the text.
class _Article extends StatelessWidget {
  const _Article({
    required this.entry,
    required this.imagesDirectory,
    required this.onBodyChanged,
  });

  final DiaryEntry entry;
  final Directory? imagesDirectory;

  /// Writes the note's text back. The only thing that can change it from here is
  /// a check-box being ticked.
  final ValueChanged<String> onBodyChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final titled = entry.title.trim().isNotEmpty;
    final attached = decodeImageNames(entry.images);
    final day = toBeginningOfSentenceCase(
      DateFormat('EEEE, d MMMM', 'ru_RU').format(entry.createdAt),
    );
    final touched = DateFormat('HH:mm').format(entry.updatedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$day · изменено в $touched',
          style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          titled ? entry.title : 'Без названия',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.6,
            height: 1.15,
            color: titled ? p.textPrimary : labelInk,
          ),
        ),
        // The note's mood and tags, drawn exactly as the form draws them but
        // with nothing to tap: this screen reads a note, and the labels are
        // changed where the rest of it is — the pencil.
        _Labels(entryId: entry.id, surface: pageSurface(theme)),
        _ChecklistProgress(body: entry.body),
        const SizedBox(height: 18),
        NoteBodyView(body: entry.body, onChanged: onBodyChanged),
        if (attached.isNotEmpty) ...[
          const SizedBox(height: 18),
          _AttachmentsPreview(
            names: attached,
            imagesDirectory: imagesDirectory,
          ),
        ],
      ],
    );
  }
}

/// "ЧЕК-ЛИСТ  3 из 7" and a thin bar — only for a note that has check-boxes.
///
/// Counted from the stored text, so it moves the moment a box is ticked (the
/// note is streamed back after the write).
class _ChecklistProgress extends StatelessWidget {
  const _ChecklistProgress({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final (done, total) = _count();
    if (total == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final label = '$done из $total';

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Semantics(
        label: 'Чек-лист: $label',
        excludeSemantics: true,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ЧЕК-ЛИСТ',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                    color: p.textSecondary,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: done / total,
                minHeight: 4,
                backgroundColor: p.border,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A body that is empty, or not the JSON it should be, simply has no list.
  (int, int) _count() {
    if (body.trim().isEmpty) return (0, 0);
    try {
      return checklistProgress(jsonDecode(body) as List);
    } on Object {
      return (0, 0);
    }
  }
}

/// The round pencil at the bottom edge — the same dark rounded square as the
/// "+" of the other tabs.
class _EditButton extends StatelessWidget {
  const _EditButton({
    required this.background,
    required this.glyph,
    required this.onTap,
  });

  final Color background;
  final Color glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(20);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E1B2230),
            offset: Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: Material(
        color: background,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Tooltip(
            message: 'Редактировать',
            child: SizedBox.square(
              dimension: 56,
              child: Icon(LucideIcons.pencil, size: 21, color: glyph),
            ),
          ),
        ),
      ),
    );
  }
}

/// The note's mood and tags, live.
///
/// Its own widget and its own two streams, so the rest of the screen is not
/// rebuilt when a tag is renamed — and so [_Content] can stay a plain
/// `StatelessWidget` with no `ref` of its own.
///
/// Nothing at all while there is neither: a note with no labels must not open a
/// gap above its text where a strip would have been.
class _Labels extends ConsumerWidget {
  const _Labels({required this.entryId, required this.surface});

  final int entryId;

  /// What the chips sit on — the sheet's raised tone over a cover, the page tone
  /// without one. A tag's fill is mixed against it in the dark theme.
  final Color surface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moods =
        ref.watch(entryMoodsProvider(entryId)).valueOrNull ??
        const <NoteMood>[];
    final tags =
        ref.watch(entryTagsProvider(entryId)).valueOrNull ?? const <NoteTag>[];
    if (moods.isEmpty && tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: NoteLabelsRow(moods: moods, tags: tags, surface: surface),
    );
  }
}

/// The note's pictures: the first few, then a tile saying how many are left.
///
/// A tap opens the whole set full screen at the picture tapped — including the
/// "+N" tile, which lands on the first one it is standing in for.
class _AttachmentsPreview extends StatelessWidget {
  const _AttachmentsPreview({
    required this.names,
    required this.imagesDirectory,
  });

  final List<String> names;
  final Directory? imagesDirectory;

  static const int _shown = 3;
  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = names.take(_shown).toList();
    final hidden = names.length - visible.length;

    // Every picture the note owns, in order — what the gallery swipes through,
    // not only the tiles that fit here. One name that does not resolve yet means
    // the directory has not arrived, and then a tap would open a gallery of
    // holes: nothing is openable until all of them are there.
    final paths = <String>[
      for (final name in names) ?noteImagePath(imagesDirectory, name),
    ];
    final resolved = paths.length == names.length;

    void open(int index) =>
        showNoteGallery(context, paths: paths, initialIndex: index);

    return Row(
      children: [
        for (var index = 0; index < visible.length; index++) ...[
          GestureDetector(
            onTap: resolved ? () => open(index) : null,
            child: _Tile(
              path: noteImagePath(imagesDirectory, visible[index]),
              size: _size,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (hidden > 0)
          GestureDetector(
            // Straight to the first picture it stands for, not back to the top.
            onTap: resolved ? () => open(_shown) : null,
            child: Container(
              width: _size,
              height: _size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: insetSurface(theme),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '+$hidden',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: labelInk,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.path, required this.size});

  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: insetSurface(theme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(LucideIcons.image_off, size: 18, color: labelInk),
    );

    final source = path;
    if (source == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(source),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, _, _) => placeholder,
      ),
    );
  }
}
