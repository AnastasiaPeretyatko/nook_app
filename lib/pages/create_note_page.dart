import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/note_delta.dart';
import 'package:todo_app/utils/note_images.dart';
import 'package:todo_app/widgets/diary/note_body_view.dart';
import 'package:todo_app/widgets/diary/note_label_chips.dart';
import 'package:todo_app/widgets/diary/note_label_sheets.dart';
import 'package:todo_app/widgets/diary/tool_pill.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/form_header.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The note editor, opened by the nav bar's centre button while the diary is on
/// screen.
///
/// A pushed route, exactly like [CreateTaskPage]: the two things the centre
/// button creates open the same way, so the button's behaviour does not change
/// under the finger from one tab to the next. That also hands the keyboard to
/// the `Scaffold` — it shrinks the body and lifts the action button on its own,
/// which a scroll-controlled sheet does not do.
///
/// One screen for both jobs: [entry] null means a new note is being written,
/// non-null means that note is being edited. The two differ only in what the
/// form opens with and in whether saving inserts or updates — the cover slot,
/// the editor and the toolbar in between are the same, so there is one place
/// where a note is written and no second screen to keep in step.
class CreateNotePage extends ConsumerStatefulWidget {
  const CreateNotePage({super.key, this.entry});

  /// The note being edited, or null while a new one is being written.
  final DiaryEntry? entry;

  @override
  ConsumerState<CreateNotePage> createState() => _CreateNotePageState();
}

class _CreateNotePageState extends ConsumerState<CreateNotePage> {
  /// One inset for the whole form: every element on the page — the cover, both
  /// fields, the divider between them — stands the same distance off the screen
  /// edge, and the header's labels are already there by their own padding.
  static const double _inset = 16;

  final _picker = ImagePicker();
  final _titleController = TextEditingController();

  /// Built in [initState], because an edited note opens with its stored text
  /// already in it — a [FleatherController] is given its document at birth.
  late final FleatherController _body;
  final _bodyFocus = FocusNode();

  /// The form's own scroll, handed to the editor as well as to the list.
  ///
  /// The editor is `scrollable: false`, so it never scrolls anything itself —
  /// but Fleather's `bringIntoView` reaches for its scroll controller without
  /// asking whether it has one, and that is the first thing every drag of a
  /// selection handle calls. Left to build its own, the controller is attached
  /// to no scroll view, `position` throws, and the drag dies before the
  /// selection is ever moved: the caret can be placed by tapping and cannot be
  /// dragged. Sharing the list's controller both stops the throw and makes the
  /// call mean what it says — the page scrolls to keep the caret in sight.
  final _scroll = ScrollController();

  /// The note's cover, or null if it has none. A freshly picked one is still
  /// where the picker left it — the system's own cache — and copying it into the
  /// app's documents belongs to saving, so a new note that is abandoned leaves
  /// nothing behind.
  _FormImage? _cover;

  /// Set while the note is being written to disk, so "Сохранить" cannot run
  /// twice and copy every picture again.
  bool _isSaving = false;

  /// Pictures attached to the note, in the order they were added. They belong to
  /// the note rather than to a place in its text, which is why they are a list
  /// here and a JSON array in the database — not embeds inside the document.
  final _attachments = <_FormImage>[];

  /// The mood the note is marked with, as an id into the mood catalogue. One at
  /// a time — the picker hands out a single mood, even though the join table
  /// would take several.
  int? _moodId;

  /// The tags the note carries, as ids into the tag catalogue. A draft like every
  /// other field of the form: the links are written when the note is saved, so
  /// abandoning the form changes nothing about the note. The *catalogues* are a
  /// different matter — a tag invented in the picker is a shared row and is
  /// written there and then.
  final _tagIds = <int>{};

  /// Which of the toolbar's second rows is open, if any. One at a time: two
  /// stacked rows would push the editor halfway up the screen.
  _ToolbarPanel _panel = _ToolbarPanel.none;

  /// True while a note that already exists is being edited.
  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _body = _controllerFor(entry?.body);
    if (entry == null) return;

    _titleController.text = entry.title;
    final cover = entry.coverImage;
    if (cover != null) _cover = _FormImage.stored(cover);
    _attachments.addAll(decodeImageNames(entry.images).map(_FormImage.stored));
    _loadLabels(entry.id);
  }

  /// Reads the note's moods and tags into the draft. Asynchronous, so the form is
  /// on screen a frame before its label strip is — which is why the strip draws
  /// the "Настроение" button in the meantime rather than a spinner: a note being
  /// edited is not blocked on its labels.
  ///
  /// Futures and not the streams the view screen uses, by the convention every
  /// form here follows: a draft the user is editing must not be rewritten by the
  /// database underneath them.
  Future<void> _loadLabels(int entryId) async {
    final dao = ref.read(diaryDaoProvider);
    final moods = await dao.getMoodIdsForEntry(entryId);
    final tags = await dao.getTagIdsForEntry(entryId);
    if (!mounted) return;
    setState(() {
      _moodId = moods.isEmpty ? null : moods.first;
      _tagIds.addAll(tags);
    });
  }

  /// Opens the mood picker on whatever the draft holds.
  Future<void> _pickMood() => showMoodPickerSheet(
    context,
    selected: _moodId,
    onChanged: (id) => setState(() => _moodId = id),
  );

  Future<void> _pickTags() => showTagPickerSheet(
    context,
    selected: _tagIds,
    onChanged: (ids) => setState(() {
      _tagIds
        ..clear()
        ..addAll(ids);
    }),
  );

  /// The stored text, ready to be typed into — and an empty document when there
  /// is none, or when what is stored is not the JSON it should be: a broken body
  /// has to open as an empty note rather than take the screen down.
  FleatherController _controllerFor(String? body) {
    if (body == null || body.trim().isEmpty) return FleatherController();
    try {
      return FleatherController(
        document: ParchmentDocument.fromJson(jsonDecode(body) as List),
      );
    } on Object {
      return FleatherController();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Opens the system image picker. One source, so there is no sheet in
  /// between: an intermediate menu with a single entry is a tap for nothing.
  ///
  /// On Android 13+ this is the platform Photo Picker, which is why the app asks
  /// for no storage permission at all; on iOS the reason string in `Info.plist`
  /// is what keeps it from being killed on launch of the picker.
  /// Opens the system image picker and hands back what was chosen, or null.
  ///
  /// The picker is a platform call, so it can fail for reasons that have nothing
  /// to do with the note: a refused permission, or a plugin whose native half is
  /// not in the running binary. Either way it must not take the frame down — the
  /// note being written is worth more than an image.
  Future<String?> _pickImage() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      return picked?.path;
    } on PlatformException {
      _reportPickerFailure();
      return null;
    }
  }

  /// The same picker, but for as many pictures as the user cares to tick.
  ///
  /// Attachments are a gallery, so they arrive in handfuls — picking six
  /// photographs one at a time means opening the picker six times. The cover
  /// stays on [_pickImage]: there is exactly one of it.
  Future<List<String>> _pickImages() async {
    try {
      final picked = await _picker.pickMultiImage();
      return [for (final file in picked) file.path];
    } on PlatformException {
      _reportPickerFailure();
      return const [];
    }
  }

  void _reportPickerFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось открыть галерею')),
    );
  }

  Future<void> _pickCover() async {
    final path = await _pickImage();
    if (path == null || !mounted) return;
    setState(() => _cover = _FormImage.picked(path));
  }

  void _removeCover() => setState(() => _cover = null);

  /// Attaches pictures to the note. They land after the text, in the order
  /// picked — the note's own gallery, not characters in its document.
  Future<void> _attachImages() async {
    final paths = await _pickImages();
    if (paths.isEmpty || !mounted) return;
    setState(() => _attachments.addAll(paths.map(_FormImage.picked)));
  }

  void _detachImage(int index) => setState(() => _attachments.removeAt(index));

  /// Writes the note — a new row, or the one being edited.
  ///
  /// Pictures come first and are the reason this is not a one-liner. A freshly
  /// picked path points into the picker's cache, which the system may clear at
  /// any time, so saving copies it into the app's own directory and stores the
  /// name it was given there; a picture the note already owns is left exactly as
  /// it is, so saving an edited note does not copy its cover again on every pass.
  /// A new note that is abandoned therefore leaves nothing behind, because
  /// nothing was copied until this moment.
  ///
  /// A *new* empty note is not written at all: a stray tap on "Сохранить" should
  /// not leave a blank row in the diary. An edited one is written whatever is
  /// left of it — emptying a note is not the same as deleting it, and the diary
  /// draws a note with no title as "Без названия" already.
  Future<void> _save() async {
    if (_isSaving) return;

    final title = _titleController.text.trim();
    final operations = jsonDecode(jsonEncode(_body.document.toDelta())) as List;
    final entry = widget.entry;
    if (entry == null &&
        title.isEmpty &&
        _attachments.isEmpty &&
        // A picked mood or tag counts as content: unlike a stray tap on
        // "Сохранить", choosing one took two deliberate taps through a sheet.
        _moodId == null &&
        _tagIds.isEmpty &&
        deltaPlainText(operations).trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSaving = true);
    try {
      final names = <String>[];
      for (final image in _attachments) {
        names.add(await image.store());
      }
      final coverName = await _cover?.store();

      final dao = ref.read(diaryDaoProvider);
      if (entry == null) {
        // The insert hands back the id the links need — there is no note to
        // point at until this returns.
        final id = await dao.insertEntry(
          DiaryEntriesCompanion.insert(
            title: Value(title),
            body: Value(jsonEncode(operations)),
            coverImage: Value(coverName),
            images: Value(encodeImageNames(names)),
          ),
        );
        await _saveLabels(dao, id);
      } else {
        await dao.updateEntryById(
          entry.id,
          // A partial write, but every field the form owns is present: an
          // explicit `Value(null)` is what takes a cover off the row, where
          // `Value.absent()` would leave the old one on it.
          DiaryEntriesCompanion(
            title: Value(title),
            body: Value(jsonEncode(operations)),
            coverImage: Value(coverName),
            images: Value(encodeImageNames(names)),
          ),
        );
        await _saveLabels(dao, entry.id);
        // After the write, never before: a file deleted first and a write that
        // then failed would leave the note pointing at nothing. And on its own
        // `try`, because the note *is* saved by now — a file that refuses to go
        // away is a leak, not a failed save, and must not be reported as one.
        try {
          await _deleteDropped(entry, kept: [...names, ?coverName]);
        } on FileSystemException {
          // Nothing to do and nothing to tell the user.
        }
      }
      if (mounted) Navigator.of(context).pop();
    } on FileSystemException {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить заметку')),
      );
    }
  }

  /// Writes the note's moods and tags — the join rows, not the catalogues.
  ///
  /// Replaces rather than adds: the form owns the whole set, so a label taken off
  /// the strip has to disappear from the note, and clearing everything has to
  /// clear the note. After the entry's own write, because a link needs a row to
  /// point at.
  Future<void> _saveLabels(DiaryDao dao, int entryId) async {
    await dao.setEntryMoods(entryId, [?_moodId]);
    await dao.setEntryTags(entryId, _tagIds);
  }

  /// Removes the files the edit dropped — a cover replaced, an attachment taken
  /// off. Nothing else refers to them, so leaving them in the directory is a leak
  /// nobody can find later.
  Future<void> _deleteDropped(
    DiaryEntry entry, {
    required List<String> kept,
  }) {
    final had = [?entry.coverImage, ...decodeImageNames(entry.images)];
    return deleteNoteImages(had.where((name) => !kept.contains(name)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Where a picture the note already owns is read from. Resolved once per app
    // run and cached by the provider, so an edited note's cover is on screen in
    // the first frame.
    final imagesDirectory = ref.watch(noteImagesDirectoryProvider).valueOrNull;

    // The draft holds ids; the strip draws rows. Resolved against the catalogues
    // rather than kept as objects in the state, so a mood renamed in the picker
    // is renamed on the form too — and a label whose row has gone simply drops
    // out instead of drawing a blank chip.
    final moods = <NoteMood>[
      for (final mood
          in ref.watch(noteMoodsProvider).valueOrNull ?? const <NoteMood>[])
        if (mood.id == _moodId) mood,
    ];
    final tags = <NoteTag>[
      for (final tag
          in ref.watch(noteTagsProvider).valueOrNull ?? const <NoteTag>[])
        if (_tagIds.contains(tag.id)) tag,
    ];

    return Scaffold(
      backgroundColor: pageSurface(theme),
      body: SafeArea(
        child: Column(
          children: [
            FormHeader(
              title: _isEdit ? 'Редактирование' : 'Новая заметка',
              onCancel: () => Navigator.of(context).pop(),
              onSave: _save,
              isBusy: _isSaving,
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(_inset, 8, _inset, 24),
                children: [
                  _CoverPicker(
                    coverPath: _cover?.pathIn(imagesDirectory),
                    onTap: _pickCover,
                    onRemove: _removeCover,
                  ),
                  const SizedBox(height: 20),
                  // No card, no underline: the title is written straight onto
                  // the page, and its own size is what marks it as the title.
                  // Nothing is focused on open either — the cover is the first
                  // thing on screen, and a keyboard would swallow it.
                  _NoteField(
                    controller: _titleController,
                    hint: 'Заголовок заметки',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Under the title and above the hairline: what the note is
                  // *about* belongs to its heading, not to its text.
                  NoteLabelsRow(
                    moods: moods,
                    tags: tags,
                    onEditMood: _pickMood,
                    onEditTags: _pickTags,
                    surface: pageSurface(theme),
                  ),
                  Divider(
                    height: 32,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  _NoteBody(
                    controller: _body,
                    focusNode: _bodyFocus,
                    scrollController: _scroll,
                  ),
                  if (_attachments.isNotEmpty)
                    _AttachmentsStrip(
                      paths: [
                        for (final image in _attachments)
                          image.pathIn(imagesDirectory),
                      ],
                      onRemove: _detachImage,
                    ),
                ],
              ),
            ),
            _NoteToolbar(
              controller: _body,
              panel: _panel,
              onTogglePanel: (panel) => setState(
                () => _panel = _panel == panel ? _ToolbarPanel.none : panel,
              ),
              onInsertImage: _attachImages,
              onAddTag: _pickTags,
            ),
          ],
        ),
      ),
    );
  }
}

/// One picture on the form.
///
/// A picture is in one of two places, and the difference matters only when the
/// note is saved: a **picked** one is still where the gallery left it — a cache
/// the system is free to clear — and has to be copied into the app's own
/// directory; a **stored** one is already there, is referred to by name, and is
/// left alone, so re-saving an edited note does not pile up copies of its
/// pictures.
class _FormImage {
  const _FormImage.picked(String path) : pickedPath = path, storedName = null;
  const _FormImage.stored(String name) : storedName = name, pickedPath = null;

  /// Absolute path into the picker's cache, or null once the note owns the
  /// picture. Exactly one of the two fields is set.
  final String? pickedPath;

  /// File name inside [noteImagesDirectory], or null for one just picked.
  final String? storedName;

  /// Where to read the picture from right now. A stored one depends on
  /// [directory], which is why it is passed in rather than remembered: the
  /// container the app's documents live in is not stable across launches.
  String? pathIn(Directory? directory) =>
      pickedPath ?? noteImagePath(directory, storedName);

  /// The name the note refers to the picture by, copying it in if that has not
  /// happened yet.
  Future<String> store() async =>
      storedName ?? await copyIntoNoteImages(pickedPath!);
}

class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.hint,
    required this.style,
  });

  final TextEditingController controller;
  final String hint;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: 1,
      textCapitalization: TextCapitalization.sentences,
      style: style,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        // The placeholder keeps the field's own size and weight so the first
        // typed letter lands exactly where the hint stood.
        hintStyle: style?.copyWith(color: labelInk),
      ),
    );
  }
}

/// The cover slot, in either of its two states.
///
/// Empty, it is a dashed outline in the app accent over [_accentWash], so it
/// reads as a place something goes rather than as content; the outline and the
/// label take [inkOn], since the pale families (yellow) are not readable as
/// their own accent. Filled, it is the picture itself, with a tap to replace it
/// and a button to take it off.
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.coverPath,
    required this.onTap,
    required this.onRemove,
  });

  final String? coverPath;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  static const double _height = 120;
  static const double _filledHeight = 180;
  static const double _radius = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = accentWash(theme);
    final ink = inkOn(fill, theme.colorScheme.primary);
    final path = coverPath;

    if (path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: Stack(
          children: [
            GestureDetector(
              onTap: onTap,
              child: Image.file(
                File(path),
                height: _filledHeight,
                width: double.infinity,
                fit: BoxFit.cover,
                // The picker hands back a path into a cache the system is free
                // to clear, so the file can be gone by the next rebuild.
                errorBuilder: (context, _, _) => _CoverPlaceholder(
                  fill: fill,
                  ink: ink,
                  height: _filledHeight,
                  label: 'Обложка недоступна',
                  icon: LucideIcons.image_off,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _CoverRemoveButton(onTap: onRemove),
            ),
          ],
        ),
      );
    }

    return CustomPaint(
      // A foreground painter, not a background one: the child's own fill would
      // cover a border drawn underneath it.
      foregroundPainter: _DashedBorderPainter(
        color: ink.withValues(alpha: 0.55),
        radius: _radius,
      ),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(_radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: _CoverPlaceholder(
            fill: fill,
            ink: ink,
            height: _height,
            label: 'Добавить обложку',
            icon: LucideIcons.image,
          ),
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({
    required this.fill,
    required this.ink,
    required this.height,
    required this.label,
    required this.icon,
  });

  final Color fill;
  final Color ink;
  final double height;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: height,
      width: double.infinity,
      color: fill,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: ink),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Takes the cover off again. A scrim disc rather than a themed chip: it sits on
/// an arbitrary photograph, and nothing else can be relied on to contrast with
/// one.
class _CoverRemoveButton extends StatelessWidget {
  const _CoverRemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(LucideIcons.x, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// Draws the dashed rounded rectangle around the cover slot. Flutter has no
/// dashed [Border], so the outline is walked by hand: the rounded path is
/// measured and every other stretch of it is extracted and stroked.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _strokeWidth = 1.4;
  static const double _dash = 7;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    // Inset by half the stroke, or the outer half of it falls off the box.
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(_strokeWidth / 2),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// The note's pictures, after its text, in the order they were attached.
///
/// A carousel rather than a grid: while the note is being written every
/// attachment is shown, so there is nothing to fold behind a "+2" — that is the
/// list's problem, where space is the constraint.
class _AttachmentsStrip extends StatelessWidget {
  const _AttachmentsStrip({required this.paths, required this.onRemove});

  final List<String?> paths;
  final ValueChanged<int> onRemove;

  static const double _size = 120;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: _size,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: paths.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => _Attachment(
            path: paths[index],
            size: _size,
            onRemove: () => onRemove(index),
          ),
        ),
      ),
    );
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment({
    required this.path,
    required this.size,
    required this.onRemove,
  });

  /// Null while the directory a stored picture lives in is still being
  /// resolved — the same stand-in as a file that has gone missing.
  final String? path;
  final double size;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: insetSurface(theme),
      child: Icon(LucideIcons.image_off, size: 20, color: labelInk),
    );
    final source = path;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          if (source == null)
            placeholder
          else
            Image.file(
              File(source),
              width: size,
              height: size,
              fit: BoxFit.cover,
              // A picked file is still the picker's cache until the note is
              // saved, so it can be swept out from under a picture already
              // attached.
              errorBuilder: (context, _, _) => placeholder,
            ),
          Positioned(
            top: 6,
            right: 6,
            child: _CoverRemoveButton(onTap: onRemove),
          ),
        ],
      ),
    );
  }
}

/// The note itself: a Fleather rich-text editor rather than a plain field, so
/// the toolbar has something to format.
///
/// It is laid out non-scrollable inside the page's own list — an editor that
/// scrolls itself would fight that list for the drag. It has no placeholder of
/// its own either, so the hint is drawn behind it while the document is empty,
/// and a minimum height gives the empty note an area to tap.
class _NoteBody extends StatelessWidget {
  const _NoteBody({
    required this.controller,
    required this.focusNode,
    required this.scrollController,
  });

  final FleatherController controller;
  final FocusNode focusNode;

  /// The page's scroll, not one of the editor's own — see
  /// [_CreateNotePageState._scroll].
  final ScrollController scrollController;

  static const double _minHeight = 220;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Plain-text emptiness is not enough: applying a list or a heading to
        // an empty note adds no characters, but it does draw a marker — and the
        // hint would sit right on top of it. Any operation carrying attributes
        // means the note has been started.
        final document = controller.document;
        final empty =
            document.toPlainText().trim().isEmpty &&
            !document.toDelta().toList().any((op) => op.isNotPlain);

        return GestureDetector(
          // Translucent, not opaque: a tap below the last line still has to
          // reach the editor's own gesture handling.
          behavior: HitTestBehavior.translucent,
          onTap: focusNode.requestFocus,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minHeight),
            child: Stack(
              children: [
                if (empty)
                  Text(
                    'Начните писать свою заметку...',
                    style: theme.textTheme.bodyLarge?.copyWith(color: labelInk),
                  ),
                CheckboxTheme(
                  data: noteCheckboxTheme(context),
                  child: FleatherTheme(
                    data: noteEditorTheme(context),
                    child: FleatherEditor(
                      controller: controller,
                      focusNode: focusNode,
                      scrollable: false,
                      scrollController: scrollController,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Which second row of the toolbar is showing.
enum _ToolbarPanel { none, styles, lists }

/// The formatting bar.
///
/// Last child of the page's column, which is what puts it where it belongs: the
/// `Scaffold` shrinks its body by the keyboard's height, so the bar sits on the
/// screen's bottom edge while the keyboard is down and rides on top of it while
/// it is up. No plugin is involved.
///
/// "Aa" opens a second row of text styles above it, and the list button opens
/// the choice between bullets, numbers and checkboxes. An inline row rather than
/// a popup menu on purpose: a menu is a route, and pushing one takes the focus
/// off the editor, which closes the keyboard and drops the selection. For the
/// same reason the buttons themselves cannot take focus.
class _NoteToolbar extends StatelessWidget {
  const _NoteToolbar({
    required this.controller,
    required this.panel,
    required this.onTogglePanel,
    required this.onInsertImage,
    required this.onAddTag,
  });

  final FleatherController controller;
  final _ToolbarPanel panel;
  final ValueChanged<_ToolbarPanel> onTogglePanel;
  final VoidCallback onInsertImage;
  final VoidCallback onAddTag;

  bool _isOn(ParchmentAttribute attribute) =>
      controller.getSelectionStyle().containsSame(attribute);

  void _toggle(ParchmentAttribute attribute) => controller.formatSelection(
    _isOn(attribute) ? attribute.unset : attribute,
  );

  @override
  Widget build(BuildContext context) {
    final bullets = ParchmentAttribute.block.bulletList;
    final numbers = ParchmentAttribute.block.numberList;
    final checks = ParchmentAttribute.block.checkList;

    // Rebuilt on every controller change: a button's on/off state is read from
    // the style at the cursor, which moves with every keystroke and tap — so
    // every such read has to happen inside this builder, not above it.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(
          _CreateNotePageState._inset,
          0,
          _CreateNotePageState._inset,
          8,
        ),
        child: Column(
          children: [
            if (panel == _ToolbarPanel.lists) ...[
              ToolPill(
                children: [
                  ToolButton(
                    icon: LucideIcons.list,
                    active: _isOn(bullets),
                    onTap: () => _toggle(bullets),
                  ),
                  ToolButton(
                    icon: LucideIcons.list_ordered,
                    active: _isOn(numbers),
                    onTap: () => _toggle(numbers),
                  ),
                  ToolButton(
                    icon: LucideIcons.list_checks,
                    active: _isOn(checks),
                    onTap: () => _toggle(checks),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (panel == _ToolbarPanel.styles) ...[
              ToolPill(
                children: [
                  ToolButton(
                    icon: LucideIcons.bold,
                    active: _isOn(ParchmentAttribute.bold),
                    onTap: () => _toggle(ParchmentAttribute.bold),
                  ),
                  ToolButton(
                    icon: LucideIcons.italic,
                    active: _isOn(ParchmentAttribute.italic),
                    onTap: () => _toggle(ParchmentAttribute.italic),
                  ),
                  ToolButton(
                    icon: LucideIcons.underline,
                    active: _isOn(ParchmentAttribute.underline),
                    onTap: () => _toggle(ParchmentAttribute.underline),
                  ),
                  ToolButton(
                    icon: LucideIcons.strikethrough,
                    active: _isOn(ParchmentAttribute.strikethrough),
                    onTap: () => _toggle(ParchmentAttribute.strikethrough),
                  ),
                  ToolButton(
                    label: 'H1',
                    active: _isOn(ParchmentAttribute.heading.level1),
                    onTap: () => _toggle(ParchmentAttribute.heading.level1),
                  ),
                  ToolButton(
                    label: 'H2',
                    active: _isOn(ParchmentAttribute.heading.level2),
                    onTap: () => _toggle(ParchmentAttribute.heading.level2),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            ToolPill(
              children: [
                ToolButton(
                  label: 'Aa',
                  active: panel == _ToolbarPanel.styles,
                  onTap: () => onTogglePanel(_ToolbarPanel.styles),
                ),
                // Opens the choice of list rather than toggling one: it also
                // reads as active while the cursor sits inside a list, so the
                // button says both "there is a choice here" and "you are in
                // one".
                ToolButton(
                  icon: LucideIcons.list,
                  active:
                      panel == _ToolbarPanel.lists ||
                      _isOn(bullets) ||
                      _isOn(numbers) ||
                      _isOn(checks),
                  onTap: () => onTogglePanel(_ToolbarPanel.lists),
                ),
                ToolButton(icon: LucideIcons.image, onTap: onInsertImage),
                ToolButton(icon: LucideIcons.tag, onTap: onAddTag),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
