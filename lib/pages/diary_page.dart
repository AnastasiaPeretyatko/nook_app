import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/pages/create_note_page.dart';
import 'package:todo_app/widgets/empty_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/note_view_page.dart';
import 'package:todo_app/settings/diary_view.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/diary_groups.dart';
import 'package:todo_app/utils/note_delta.dart';
import 'package:todo_app/utils/note_images.dart';
import 'package:todo_app/utils/note_search.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/diary/note_label_chips.dart';
import 'package:todo_app/widgets/list_card.dart';
import 'package:todo_app/widgets/page_header.dart';

/// The "Дневник" tab (`Journal.dc.html`): how many notes there are, a search box
/// that is always there, the pinned notes as coloured tiles, then everything
/// else in sections by date.
///
/// "Закреплённые" is the old "Избранное" under a new name — the same flag, said
/// differently on screen. The tabs are gone: drafts sit in the list with a mark
/// on them, and the archive is a page of its own behind the header's button,
/// the way the habits screen keeps its archive.
class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key});

  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends ConsumerState<DiaryPage> {
  final _search = TextEditingController();

  /// What is being looked for, already cut into terms. Kept beside the
  /// controller rather than derived in the list on every rebuild: cutting one
  /// string per keystroke is enough.
  List<String> _terms = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) =>
      setState(() => _terms = searchTerms(query));

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(diaryViewModeProvider);
    // Archived notes are not "записи" of the diary proper: they are put away.
    final count = (ref.watch(diaryEntriesProvider).valueOrNull ?? const [])
        .where((e) => e.status != DiaryEntryStatus.archived)
        .length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              caption: diaryCountLabel(count),
              title: 'Дневник',
              actions: [
                RoundIconButton(
                  icon: LucideIcons.archive,
                  tooltip: 'Архив',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DiaryArchivePage(),
                    ),
                  ),
                ),
                RoundIconButton(
                  icon: mode == DiaryViewMode.grid
                      ? LucideIcons.layout_grid
                      : LucideIcons.layout_list,
                  tooltip: mode == DiaryViewMode.grid
                      ? 'Вид: плитки'
                      : 'Вид: список',
                  onPressed: _onViewTapped,
                ),
              ],
            ),
            _SearchBar(controller: _search, onChanged: _onQueryChanged),
            Expanded(child: _DiaryList(terms: _terms)),
          ],
        ),
      ),
    );
  }

  /// How the notes are drawn: a sheet rather than a popup menu, like every other
  /// choice in the app.
  Future<void> _onViewTapped() async {
    final current = ref.read(diaryViewModeProvider);
    final chosen = await showModalBottomSheet<DiaryViewMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ViewModeSheet(current: current),
    );
    if (chosen == null) return;
    await ref.read(diaryViewModeProvider.notifier).setMode(chosen);
  }
}

/// The archive of notes, on a page of its own: what was put away, newest first.
/// Tapping a note opens it; a long press offers to bring it back.
class DiaryArchivePage extends ConsumerWidget {
  const DiaryArchivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(diaryEntriesProvider);
    final moods = ref.watch(moodsByEntryProvider).valueOrNull ?? const {};
    final tags = ref.watch(tagsByEntryProvider).valueOrNull ?? const {};

    return Scaffold(
      backgroundColor: pageSurface(theme),
      body: SafeArea(
        child: Column(
          children: [
            const BackHeader(title: 'Архив'),
            Expanded(
              child: entries.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Ошибка: $error')),
                data: (all) {
                  final archived = all
                      .where((e) => e.status == DiaryEntryStatus.archived)
                      .toList();
                  if (archived.isEmpty) {
                    return Center(
                      child: Text(
                        'В архиве пусто',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: labelInk,
                        ),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.only(top: 16, bottom: 32),
                    children: [
                      RowsCard(
                        dividerIndent: 16,
                        children: [
                          for (final entry in archived)
                            _NoteRow(
                              entry: entry,
                              moods: moods[entry.id] ?? const [],
                              tags: tags[entry.id] ?? const [],
                              onTap: () => _open(context, entry),
                              onLongPress: () =>
                                  _noteActions(context, ref, entry),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _open(BuildContext context, DiaryEntry entry) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NoteViewPage(entryId: entry.id)),
    );

/// The long press on a note: pin it, or put it away — or, in the archive, bring
/// it back. The two things the tabs used to be for, one gesture away.
Future<void> _noteActions(
  BuildContext context,
  WidgetRef ref,
  DiaryEntry entry,
) async {
  final archived = entry.status == DiaryEntryStatus.archived;
  final action = await showActionsSheet<String>(
    context,
    title: entry.title.trim().isEmpty ? 'Без названия' : entry.title,
    actions: [
      if (!archived)
        SheetAction(
          icon: entry.isFavorite ? LucideIcons.pin_off : LucideIcons.pin,
          label: entry.isFavorite ? 'Открепить' : 'Закрепить',
          value: 'pin',
        ),
      SheetAction(
        icon: archived ? LucideIcons.archive_restore : LucideIcons.archive,
        label: archived ? 'Вернуть из архива' : 'В архив',
        value: 'archive',
      ),
    ],
  );
  final dao = ref.read(diaryDaoProvider);
  switch (action) {
    case 'pin':
      await dao.setFavorite(entry.id, !entry.isFavorite);
    case 'archive':
      await dao.setStatus(
        entry.id,
        archived ? DiaryEntryStatus.normal : DiaryEntryStatus.archived,
      );
  }
}

/// The search box under the header — always on screen, grey, with a cross that
/// comes and goes with the text.
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        // The palette's own track is the dark card's colour, so in the dark
        // theme the box would vanish.
        color: theme.brightness == Brightness.light
            ? palette.segmentTrack
            : palette.chip,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 17, color: palette.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 15, color: palette.textPrimary),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Поиск по записям',
                hintStyle: TextStyle(fontSize: 15, color: palette.textTertiary),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        LucideIcons.x,
                        size: 18,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The notes, as sections of one scroll: pinned tiles, then the rest — in rows
/// grouped by date, or in tiles, as the view mode says.
class _DiaryList extends ConsumerWidget {
  const _DiaryList({this.terms = const []});

  /// What is being searched for. Empty means no search is on, and then no note's
  /// body is decoded at all — see [_found].
  final List<String> terms;

  /// Whether the note answers the search. Title first and body second, because
  /// the title is already a string while the body is a Delta that has to be
  /// decoded — and with no search on, nothing is decoded at all.
  bool _found(DiaryEntry entry) {
    if (terms.isEmpty) return true;
    if (matchesTerms(entry.title, terms)) return true;
    return matchesTerms(plainNoteBody(entry.body), terms);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entriesAsync = ref.watch(diaryEntriesProvider);
    final mode = ref.watch(diaryViewModeProvider);
    // Two queries for the whole screen, not one per row — see
    // `moodsByEntryProvider`. An empty map while they are in flight, so a row
    // draws without its labels for a frame rather than not at all.
    final moods = ref.watch(moodsByEntryProvider).valueOrNull ?? const {};
    final tags = ref.watch(tagsByEntryProvider).valueOrNull ?? const {};
    // The pictures live in a directory that has to be asked for; until the
    // answer arrives a tile simply draws without its cover.
    final imagesDirectory = ref.watch(noteImagesDirectoryProvider).valueOrNull;

    return entriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Ошибка: $error')),
      data: (entries) {
        // The archive is its own page, so it never turns up here — not even
        // when it would match the search.
        final shown = entries
            .where((e) => e.status != DiaryEntryStatus.archived)
            .where(_found)
            .toList();
        if (shown.isEmpty && terms.isEmpty) {
          return EmptyScreen(
            family: 'violet',
            icon: LucideIcons.pencil,
            title: 'Здесь будут ваши записи',
            body: 'Мысли, идеи, списки. Первая запись — в один тап.',
            actionLabel: 'Написать запись',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CreateNotePage()),
            ),
          );
        }
        if (shown.isEmpty) {
          return Center(
            child: Text(
              'Ничего не найдено',
              style: theme.textTheme.bodyMedium?.copyWith(color: labelInk),
            ),
          );
        }

        // Pinned notes get their own block — unless a search is on, when it is
        // one list of what matched and a note's pin is not what was asked.
        final searching = terms.isNotEmpty;
        final pinned = searching
            ? const <DiaryEntry>[]
            : shown.where((e) => e.isFavorite).toList();
        final rest = searching
            ? shown
            : shown.where((e) => !e.isFavorite).toList();
        final groups = groupDiaryByDate(rest, DateTime.now());

        return CustomScrollView(
          slivers: [
            if (pinned.isNotEmpty) ...[
              const SliverToBoxAdapter(child: _PinnedCaption()),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 112,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _PinnedTile(
                      entry: pinned[i],
                      onTap: () => _open(context, pinned[i]),
                      onLongPress: () => _noteActions(context, ref, pinned[i]),
                    ),
                    childCount: pinned.length,
                  ),
                ),
              ),
            ],
            if (mode == DiaryViewMode.grid && rest.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    // Room for a cover and two lines under it. The picture takes
                    // whatever the title and the date leave, so a tile is the
                    // same height whatever it holds and the two columns stay
                    // level.
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _DiaryTile(
                      entry: rest[i],
                      imagesDirectory: imagesDirectory,
                      terms: terms,
                      onOpen: () => _open(context, rest[i]),
                      onLongPress: () => _noteActions(context, ref, rest[i]),
                    ),
                    childCount: rest.length,
                  ),
                ),
              )
            else
              // One section per item, built as it scrolls into view.
              SliverList.builder(
                itemCount: groups.length,
                itemBuilder: (context, i) {
                  final group = groups[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionCaption(title: group.title),
                      RowsCard(
                        dividerIndent: 16,
                        children: [
                          for (final entry in group.notes)
                            _NoteRow(
                              entry: entry,
                              terms: terms,
                              moods: moods[entry.id] ?? const [],
                              tags: tags[entry.id] ?? const [],
                              onTap: () => _open(context, entry),
                              onLongPress: () =>
                                  _noteActions(context, ref, entry),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            // Clears the floating navigation bar.
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }
}

/// "📌 ЗАКРЕПЛЁННЫЕ" over the coloured tiles.
class _PinnedCaption extends StatelessWidget {
  const _PinnedCaption();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: Row(
        children: [
          Icon(LucideIcons.pin, size: 13, color: palette.textSecondary),
          const SizedBox(width: 6),
          Text(
            'ЗАКРЕПЛЁННЫЕ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.04,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pinned note as a tile in one of the six task colours — which one is fixed
/// by the note, so it keeps its colour from one visit to the next.
class _PinnedTile extends StatelessWidget {
  const _PinnedTile({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  final DiaryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final accent =
        pickableTaskPalette[entry.id % pickableTaskPalette.length].accent;
    final fill = taskBadgeSurface(theme, accent, pageSurface(theme));
    final strong = taskBadgeInk(theme, accent, fill);
    final titled = entry.title.trim().isNotEmpty;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                titled ? entry.title : 'Без названия',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: titled ? palette.textPrimary : palette.textSecondary,
                ),
              ),
              Text(
                'Изменено ${_changedLabel(entry.updatedAt)}',
                style: TextStyle(fontSize: 12, color: strong),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "сегодня", "вчера", "12 окт" — for the line under a pinned tile.
String _changedLabel(DateTime at) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final local = at.toLocal();
  final days = today
      .difference(DateTime(local.year, local.month, local.day))
      .inDays;
  if (days <= 0) return 'сегодня';
  if (days == 1) return 'вчера';
  return DateFormat(
    local.year == now.year ? 'd MMM' : 'd MMM yyyy',
    'ru_RU',
  ).format(local);
}

/// One note in a section: the day and weekday on the left, the title and two
/// lines of the text beside them — and, under those, the mood and tags when the
/// note has any.
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.entry,
    required this.moods,
    required this.tags,
    required this.onTap,
    required this.onLongPress,
    this.terms = const [],
  });

  final DiaryEntry entry;
  final List<NoteMood> moods;
  final List<NoteTag> tags;
  final List<String> terms;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// How many tags a row shows before it starts counting them instead.
  static const int _tagsShown = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final at = entry.updatedAt.toLocal();
    final weekday = DateFormat('E', 'ru_RU').format(at);
    // Wound to the match, so a note found by its seventh paragraph does not
    // answer with its first.
    final excerpt = excerptAround(plainNoteBody(entry.body), terms);
    final titled = entry.title.trim().isNotEmpty;
    final hidden = tags.length - _tagsShown;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 38,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  children: [
                    Text(
                      '${at.day}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                        color: palette.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '${weekday[0].toUpperCase()}${weekday.substring(1)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Highlighted(
                          text: titled ? entry.title : 'Без названия',
                          terms: terms,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: titled
                                ? palette.textPrimary
                                : palette.textTertiary,
                          ),
                        ),
                      ),
                      if (entry.status == DiaryEntryStatus.draft) ...[
                        const SizedBox(width: 8),
                        const _DraftMark(),
                      ],
                    ],
                  ),
                  if (excerpt.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _Highlighted(
                      text: excerpt,
                      terms: terms,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                  if (moods.isNotEmpty || tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final mood in moods)
                          MoodChip(
                            mood: mood,
                            // No fill on a row: the tag chips beside it are
                            // coloured already, and a filled mood next to them
                            // makes the line a row of boxes.
                            filled: false,
                            surface: raisedSurface(theme),
                          ),
                        for (final tag in tags.take(_tagsShown))
                          NoteTagChip(tag: tag, surface: raisedSurface(theme)),
                        if (hidden > 0) _MoreTagsChip(count: hidden),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Черновик" beside a draft's title — the tab that used to hold drafts is gone,
/// so the list says which ones they are.
class _DraftMark extends StatelessWidget {
  const _DraftMark();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.chip,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        'Черновик',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

/// The body is a Delta; a row shows its text with the formatting dropped, and
/// the search reads the same string. A note saved before anything was typed
/// holds an empty string, which is not JSON — hence the guard rather than a
/// try/catch.
String plainNoteBody(String body) {
  if (body.trim().isEmpty) return '';
  final operations = jsonDecode(body) as List;
  return deltaPlainText(operations).trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Time for a note touched today, a date for anything older: a bare "08:30" on a
/// note from last week says nothing. Read by the tile, so the grid dates a note
/// the same way.
String formatNoteTime(DateTime date) {
  final now = DateTime.now();
  final sameDay =
      date.year == now.year && date.month == now.month && date.day == now.day;
  return sameDay
      ? DateFormat('HH:mm', 'ru_RU').format(date)
      : DateFormat('d MMM', 'ru_RU').format(date);
}

/// The choice between the two views.
///
/// Pops the mode that was tapped and lets the page store it; the sheet itself
/// knows nothing about preferences.
class _ViewModeSheet extends StatelessWidget {
  const _ViewModeSheet({required this.current});

  final DiaryViewMode current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        // A `Material` and not a painted `Container`: a `ListTile` puts its own
        // fill and its ink on the nearest `Material` above it, so a colour
        // painted in between hides both — the framework asserts as much.
        child: Material(
          color: raisedSurface(theme),
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewModeTile(
                  mode: DiaryViewMode.list,
                  current: current,
                  icon: LucideIcons.list,
                  label: 'Отображение списком',
                ),
                _ViewModeTile(
                  mode: DiaryViewMode.grid,
                  current: current,
                  icon: LucideIcons.layout_grid,
                  label: 'Отображение плитками',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewModeTile extends StatelessWidget {
  const _ViewModeTile({
    required this.mode,
    required this.current,
    required this.icon,
    required this.label,
  });

  final DiaryViewMode mode;
  final DiaryViewMode current;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = mode == current;
    // The accent read against the sheet, since the pale families are not
    // readable as their own colour.
    final accent = inkOn(raisedSurface(theme), theme.colorScheme.primary);

    return ListTile(
      onTap: () => Navigator.of(context).pop(mode),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(
        icon,
        color: selected ? accent : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          color: selected ? accent : theme.colorScheme.onSurface,
        ),
      ),
      // A tick rather than a highlighted row: the sheet is a choice, and the
      // one already made has to be readable at a glance.
      trailing: selected
          ? Icon(LucideIcons.check, size: 20, color: accent)
          : null,
    );
  }
}

/// "+2" where the rest of a note's tags would be. Neutral, not one of the tag
/// colours: it stands for several of them and has no colour of its own to claim.
class _MoreTagsChip extends StatelessWidget {
  const _MoreTagsChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: insetSurface(theme),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '+$count',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: labelInk,
        ),
      ),
    );
  }
}

/// A card's text with the search terms picked out of it.
///
/// The accent read through [inkOn] and a heavier weight, no highlighter box: a
/// row of coloured slabs across a list of cards reads as damage, and the point
/// is only to show *why* this note is in the answer.
class _Highlighted extends StatelessWidget {
  const _Highlighted({
    required this.text,
    required this.terms,
    required this.style,
    required this.maxLines,
  });

  final String text;
  final List<String> terms;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ranges = matchRanges(text, terms);
    if (ranges.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final theme = Theme.of(context);
    final hit = (style ?? const TextStyle()).copyWith(
      color: inkOn(pageSurface(theme), theme.colorScheme.primary),
      fontWeight: FontWeight.w700,
    );

    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in ranges) {
      if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
      spans.add(TextSpan(text: text.substring(start, end), style: hit));
      at = end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// The picture standing for the note: its cover, or the first thing attached to
/// it if it has no cover of its own. Both views ask the same question, so both
/// get the same answer.
String? noteThumbnail(DiaryEntry entry, Directory? directory) {
  final cover = entry.coverImage;
  if (cover != null) return noteImagePath(directory, cover);
  final attached = decodeImageNames(entry.images);
  return attached.isEmpty ? null : noteImagePath(directory, attached.first);
}

/// One note as a tile: the cover with the title and the date under it.
///
/// The picture is what carries this view, so it takes every pixel the two lines
/// of text do not — which also keeps both columns level, since the text block is
/// a fixed height and only the image gives.
///
/// No excerpt. A tile is half a row wide and the covers are the point of it; a
/// two-word fragment of the text would only be noise.
class _DiaryTile extends ConsumerWidget {
  const _DiaryTile({
    required this.entry,
    required this.imagesDirectory,
    required this.terms,
    required this.onOpen,
    required this.onLongPress,
  });

  final DiaryEntry entry;
  final Directory? imagesDirectory;
  final List<String> terms;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final titled = entry.title.trim().isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: raisedSurface(theme),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: surfaceShadow(theme),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // The ink has to be clipped to the same shape, or a tap flashes square
      // corners over the rounded ones.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _TilePicture(
                        path: noteThumbnail(entry, imagesDirectory),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      // Its own gesture, on top of the card's: starring a note
                      // must not open it.
                      child: _FavouriteChip(
                        favourite: entry.isFavorite,
                        onTap: () => ref
                            .read(diaryDaoProvider)
                            .setFavorite(entry.id, !entry.isFavorite),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Highlighted(
                      text: titled ? entry.title : 'Без названия',
                      terms: terms,
                      maxLines: 1,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: titled ? theme.colorScheme.onSurface : labelInk,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatNoteTime(entry.updatedAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: labelInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tile's cover, filling whatever it is given, or a stand-in when the note has
/// no picture at all — half the tile cannot be left blank.
class _TilePicture extends StatelessWidget {
  const _TilePicture({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: insetSurface(theme),
      child: Center(
        child: Icon(LucideIcons.file_text, size: 26, color: labelInk),
      ),
    );

    final source = path;
    if (source == null) return placeholder;

    return Image.file(
      File(source),
      fit: BoxFit.cover,
      errorBuilder: (context, _, _) => placeholder,
    );
  }
}

/// The star on a tile's cover.
///
/// A pale disc rather than the black scrim the note screens use: here it sits on
/// a small picture inside a light card, and a black dot on every tile would read
/// as a hole punched through the grid. The star is asked against that disc, so a
/// pale accent is darkened until it is visible; unstarred, it is the label tone —
/// Lucide has no filled variant to switch to, so colour carries the state.
class _FavouriteChip extends StatelessWidget {
  const _FavouriteChip({required this.favourite, required this.onTap});

  final bool favourite;
  final VoidCallback onTap;

  static const Color _disc = Color(0xF2FFFFFF);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: _disc,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: favourite ? 'Открепить' : 'Закрепить',
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              LucideIcons.pin,
              size: 16,
              color: favourite
                  ? inkOn(_disc, theme.colorScheme.primary)
                  : labelInk,
            ),
          ),
        ),
      ),
    );
  }
}
