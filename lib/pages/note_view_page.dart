import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_note_page.dart';
import 'package:todo_app/utils/note_delta.dart';
import 'package:todo_app/utils/note_images.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/widgets/diary/note_body_view.dart';
import 'package:todo_app/widgets/diary/note_gallery.dart';
import 'package:todo_app/widgets/diary/note_label_chips.dart';
import 'package:todo_app/widgets/diary/tool_pill.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// A saved note, read.
///
/// A pushed route like the archive, so it covers the bottom navigation bar and
/// its own back arrow is the only way out.
///
/// **Only when the note has a cover.** Without one there is no picture to show
/// and no sheet to pull over it: the text opens flat, top to bottom, on the page
/// tone, with the two buttons drawn as plain icons instead of scrim discs. Half
/// a screen of stand-in picture is worse than no picture at all.
///
/// With a cover it takes the upper half of the screen and the content the lower
/// one, riding over the picture by [_overlap] with the same rounded top corners
/// the day schedule uses — but no drag handle.
///
/// A long note needs more than half a screen, so the content is a sheet that
/// pulls up: the same gesture that scrolls the text first grows the sheet, until
/// only [_strip] of the picture is left showing at the top — enough to read as
/// "the text has covered the image" and to keep the two buttons up there on the
/// picture they belong to. It never goes lower than where it starts.
class NoteViewPage extends ConsumerWidget {
  const NoteViewPage({super.key, required this.entryId});

  final int entryId;

  /// How far the content climbs over the cover at rest.
  static const double _overlap = 28;
  static const double _radius = 28;

  /// The band of the picture the sheet may never cover.
  static const double _strip = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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

    // Whether the note *has* a cover, not whether its file is still there: a
    // name that no longer resolves is a picture that went missing, and the
    // screen it was laid out for is the honest place to show that.
    if (entry.coverImage == null) {
      return Scaffold(
        backgroundColor: pageSurface(theme),
        body: Column(
          children: [
            _TopActions(entry: entry, onCover: false),
            Expanded(
              child: _Content(
                entry: entry,
                imagesDirectory: imagesDirectory,
                onBodyChanged: (body) =>
                    ref.read(diaryDaoProvider).setBody(entry.id, body),
                surface: pageSurface(theme),
                // Nothing to be raised above, so no corners and no second tone:
                // the page *is* the note.
                radius: 0,
              ),
            ),
          ],
        ),
      );
    }

    final cover = noteImagePath(imagesDirectory, entry.coverImage);

    // Fractions of the space actually handed to the body, which is not the same
    // as the screen: `DraggableScrollableSheet` measures itself against its
    // parent, so the seam would drift by the status bar's height if this came
    // from `MediaQuery`.
    return Scaffold(
      backgroundColor: pageSurface(theme),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxHeight;
          final coverHeight = available / 2;
          final atRest = (coverHeight + _overlap) / available;
          final pulledUp = (available - _strip) / available;

          // The stack has to be told to fill: `Scaffold` hands its body loose
          // constraints, so a stack left to itself takes the height of its
          // tallest unpositioned child — the cover — and everything measured
          // from the bottom edge then measures against half a screen.
          return SizedBox.expand(
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: coverHeight,
                  child: _Cover(path: cover),
                ),
                Positioned.fill(
                  child: DraggableScrollableSheet(
                    initialChildSize: atRest,
                    minChildSize: atRest,
                    maxChildSize: pulledUp,
                    // Settles at one of the two ends instead of stopping
                    // wherever the finger left it.
                    snap: true,
                    builder: (context, scrollController) => _Content(
                      entry: entry,
                      imagesDirectory: imagesDirectory,
                      onBodyChanged: (body) =>
                          ref.read(diaryDaoProvider).setBody(entry.id, body),
                      surface: raisedSurface(theme),
                      radius: _radius,
                      scrollController: scrollController,
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _TopActions(entry: entry),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The picture behind the content, or a stand-in for a note that has none: half
/// the screen cannot simply be left blank.
class _Cover extends StatelessWidget {
  const _Cover({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      alignment: Alignment.center,
      color: insetSurface(theme),
      child: Icon(LucideIcons.image, size: 44, color: labelInk),
    );

    final source = path;

    return SizedBox.expand(
      child: source == null
          ? placeholder
          : Image.file(
              File(source),
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => placeholder,
            ),
    );
  }
}

/// Back, and the note's own menu.
///
/// On a cover both ride on a scrim disc — no colour of the theme can be trusted
/// to contrast with an arbitrary photograph. On the page tone, where a note has
/// no cover, a black disc would be a blot: there they are plain icons.
class _TopActions extends ConsumerWidget {
  const _TopActions({required this.entry, this.onCover = true});

  final DiaryEntry entry;
  final bool onCover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = entry.status == DiaryEntryStatus.archived;

    // Top inset only: the row sits at the top of a column, and a bottom inset
    // here is empty space pushing the note down by the height of the home bar.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            _button(
              context,
              icon: LucideIcons.arrow_left,
              tooltip: 'Назад',
              onTap: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            _button(
              context,
              icon: LucideIcons.ellipsis,
              tooltip: 'Ещё',
              onTap: () => _showMenu(context, ref, archived: archived),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    if (onCover) {
      return _ScrimButton(icon: icon, tooltip: tooltip, onTap: onTap);
    }
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 22,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// The one action that lives nowhere else: putting the note away, and taking
  /// it back. Favourite and delete are on the bar below.
  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref, {
    required bool archived,
  }) async {
    final put = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          // A `Material` and not a painted `Container`: a `ListTile` puts its
          // own fill and its ink on the nearest `Material` above it, so a colour
          // painted in between hides both — the framework asserts as much, and
          // the tap was landing without a flicker of feedback.
          child: Material(
            color: raisedSurface(Theme.of(sheetContext)),
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ListTile(
                onTap: () => Navigator.of(sheetContext).pop(true),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(
                  archived ? LucideIcons.archive_restore : LucideIcons.archive,
                ),
                title: Text(archived ? 'Вернуть из архива' : 'В архив'),
              ),
            ),
          ),
        ),
      ),
    );
    if (put != true) return;

    await ref
        .read(diaryDaoProvider)
        .setStatus(
          entry.id,
          archived ? DiaryEntryStatus.normal : DiaryEntryStatus.archived,
        );
  }
}

class _ScrimButton extends StatelessWidget {
  const _ScrimButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// The lower part: what the note says, and what can be done to it.
///
/// Its height is the sheet's and changes as the sheet is pulled up; the action
/// bar stays at the bottom of it either way, which is the bottom of the screen.
class _Content extends StatelessWidget {
  const _Content({
    required this.entry,
    required this.imagesDirectory,
    required this.onBodyChanged,
    required this.surface,
    required this.radius,
    this.scrollController,
  });

  final DiaryEntry entry;
  final Directory? imagesDirectory;

  /// Writes the note's text back. The only thing that can change it from here is
  /// a check-box being ticked.
  final ValueChanged<String> onBodyChanged;

  /// The tone under the text: raised, when it is a sheet lying on the cover;
  /// the page itself, when it is the whole screen.
  final Color surface;

  final double radius;

  /// The sheet's own controller. The text has to scroll through it, or the drag
  /// that grows the sheet and the drag that scrolls the text become two
  /// different gestures. Null where there is no sheet — then the scroll view
  /// keeps its own.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titled = entry.title.trim().isNotEmpty;
    final attached = decodeImageNames(entry.images);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titled ? entry.title : 'Без названия',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: titled ? theme.colorScheme.onSurface : labelInk,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(LucideIcons.clock, size: 14, color: labelInk),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat(
                          'd MMMM, HH:mm',
                          'ru_RU',
                        ).format(entry.updatedAt),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: labelInk,
                        ),
                      ),
                    ],
                  ),
                  // The note's mood and tags, drawn exactly as the form draws
                  // them but with nothing to tap: this screen reads a note, and
                  // the labels are changed where the rest of it is — the pencil.
                  _Labels(entryId: entry.id, surface: surface),
                  // Splits what the note is *about* from the note itself, the
                  // same hairline the editor draws under its title.
                  Divider(
                    height: 28,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  NoteBodyView(body: entry.body, onChanged: onBodyChanged),
                  if (attached.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _AttachmentsPreview(
                      names: attached,
                      imagesDirectory: imagesDirectory,
                    ),
                  ],
                ],
              ),
            ),
          ),
          _ActionBar(entry: entry),
        ],
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

/// Four actions along the bottom of the sheet, in the same washed strip the
/// editor's toolbar uses — the tools under a note being read look like the tools
/// under a note being written because they are the same widget.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.entry});

  final DiaryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: ToolPill(
          children: [
            ToolButton(
              icon: LucideIcons.share,
              tooltip: 'Скопировать текст',
              onTap: () => _copy(context),
            ),
            ToolButton(
              icon: entry.isFavorite ? LucideIcons.star : LucideIcons.star,
              tooltip: entry.isFavorite
                  ? 'Убрать из избранного'
                  : 'В избранное',
              active: entry.isFavorite,
              onTap: () => ref
                  .read(diaryDaoProvider)
                  .setFavorite(entry.id, !entry.isFavorite),
            ),
            // Opens the note form on this note. Nothing is passed back: the
            // entry is streamed, so the screen redraws itself the moment the
            // edit is written.
            ToolButton(
              icon: LucideIcons.pencil,
              tooltip: 'Редактировать',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CreateNotePage(entry: entry),
                ),
              ),
            ),
            ToolButton(
              icon: LucideIcons.trash_2,
              tooltip: 'Удалить',
              onTap: () => _delete(context, ref),
            ),
          ],
        ),
      ),
    );
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Вместе с ней удалятся её изображения.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
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
