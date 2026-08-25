import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/note_view_page.dart';
import 'package:todo_app/utils/note_delta.dart';
import 'package:todo_app/utils/note_images.dart';
import 'package:todo_app/utils/note_search.dart';
import 'package:todo_app/settings/diary_view.dart';
import 'package:todo_app/widgets/diary/note_label_chips.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key});

  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

/// What each tab keeps out of the one list of entries. Three of the four are a
/// value of [DiaryEntryStatus]; "Избранное" is the flag instead, and it hides
/// what has been put away — otherwise a star would drag an archived note back
/// into view.
enum _DiaryFilter { all, favorites, drafts, archive }

class _DiaryPageState extends ConsumerState<DiaryPage> {
  /// The tab bar's thumb and the page transition move together, so they share
  /// one duration and curve.
  static const _tabSwitch = Duration(milliseconds: 250);
  static const _tabCurve = Curves.easeInOutCubic;

  int _selectedTab = 0;
  final _pages = PageController();

  /// Whether the header has given itself over to the search box.
  bool _searching = false;
  final _search = TextEditingController();

  /// What is being looked for, already cut into terms. Kept beside the
  /// controller rather than derived on the fly in every list: four lists read it
  /// on every keystroke, and cutting one string four times per letter is work
  /// for nothing.
  List<String> _terms = const [];

  @override
  void dispose() {
    _pages.dispose();
    _search.dispose();
    super.dispose();
  }

  /// The search box filters **within the open tab**, on top of its own rule,
  /// rather than across the whole diary. The tabs keep meaning what they say —
  /// and the query stays put while they are switched, so a note that is not in
  /// "Все" is one swipe away rather than a search away.
  void _onQueryChanged(String query) =>
      setState(() => _terms = searchTerms(query));

  void _closeSearch() {
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = false;
      _search.clear();
      _terms = const [];
    });
  }

  /// A tap on the tab bar. The swipe reports itself through [_onPageChanged]
  /// instead — animating there would fight the finger.
  void _onTabTapped(int index) {
    if (index == _selectedTab) return;
    setState(() => _selectedTab = index);
    _pages.animateToPage(index, duration: _tabSwitch, curve: _tabCurve);
  }

  void _onPageChanged(int index) {
    // Also fires at the end of [_onTabTapped]'s animation, where the state is
    // already there.
    if (index == _selectedTab) return;
    setState(() => _selectedTab = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              // The box takes the header's place rather than pushing it aside:
              // while a search is on, the name of the screen is the least useful
              // thing on it, and a row that grows would shift everything below.
              child: _searching
                  ? _SearchField(
                      controller: _search,
                      onChanged: _onQueryChanged,
                      onClear: () {
                        _search.clear();
                        _onQueryChanged('');
                      },
                      onClose: _closeSearch,
                    )
                  : Row(
                      children: [
                        Icon(
                          LucideIcons.book_open_text,
                          size: 26,
                          color: theme.colorScheme.onSurface,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Дневник',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        _HeaderButton(
                          icon: LucideIcons.search,
                          tooltip: 'Поиск',
                          onPressed: _onSearchTapped,
                        ),
                        _HeaderButton(
                          icon: LucideIcons.ellipsis_vertical,
                          tooltip: 'Ещё',
                          onPressed: _onMenuTapped,
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: _DiaryTabBar(
                tabs: _tabs,
                selectedIndex: _selectedTab,
                onChanged: _onTabTapped,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: _onPageChanged,
                children: [
                  for (final filter in _DiaryFilter.values)
                    _DiaryList(filter: filter, terms: _terms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSearchTapped() => setState(() => _searching = true);

  /// The header's menu, which so far holds one decision: how the notes are
  /// drawn. A sheet rather than a popup menu, like every other choice in the
  /// app.
  Future<void> _onMenuTapped() async {
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

const _tabs = ['Все', 'Избранное', 'Черновики', 'Архив'];

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
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

/// The header while a search is on: back out on the left, the field itself, and
/// a cross that empties it without leaving.
///
/// Two buttons rather than one that does both: a single × that clears a full
/// field and closes an empty one is a button whose meaning depends on state, and
/// the state is a glance away.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onClose,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        _HeaderButton(
          icon: LucideIcons.arrow_left,
          tooltip: 'Закрыть поиск',
          onPressed: onClose,
        ),
        Expanded(
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: insetSurface(theme),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.search, size: 18, color: labelInk),
                const SizedBox(width: 8),
                Expanded(
                  // Rebuilt as the field changes so the cross can come and go
                  // with the text — the page above only hears about terms.
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Поиск по заметкам',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: labelInk,
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox(width: 4)
                      : GestureDetector(
                          onTap: onClear,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              LucideIcons.x,
                              size: 18,
                              color: labelInk,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}

/// The same pill strip the habits screen uses, without the icons: four Russian
/// labels leave no room for them.
class _DiaryTabBar extends StatelessWidget {
  const _DiaryTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The track stays neutral; the thumb is the app accent, so the selected tab
    // reads as a brand fill and takes [onBrandFill] for its label.
    final thumb = theme.colorScheme.primary;
    final selectedInk = onBrandFill(thumb);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: insetSurface(theme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / tabs.length;
          return Stack(
            children: [
              AnimatedAlign(
                duration: _DiaryPageState._tabSwitch,
                curve: _DiaryPageState._tabCurve,
                alignment: Alignment(
                  tabs.length == 1
                      ? 0
                      : -1 + 2 * selectedIndex / (tabs.length - 1),
                  0,
                ),
                child: Container(
                  width: tabWidth,
                  height: 36,
                  decoration: BoxDecoration(
                    color: thumb,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: SizedBox(
                          height: 36,
                          child: Center(
                            child: Text(
                              tabs[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: i == selectedIndex
                                    ? selectedInk
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One tab's worth of notes.
class _DiaryList extends ConsumerWidget {
  const _DiaryList({required this.filter, this.terms = const []});

  final _DiaryFilter filter;

  /// What is being searched for. Empty means no search is on, and then no note's
  /// body is decoded at all — see [_found].
  final List<String> terms;

  bool _keeps(DiaryEntry entry) => switch (filter) {
    _DiaryFilter.all => entry.status == DiaryEntryStatus.normal,
    _DiaryFilter.favorites =>
      entry.isFavorite && entry.status != DiaryEntryStatus.archived,
    _DiaryFilter.drafts => entry.status == DiaryEntryStatus.draft,
    _DiaryFilter.archive => entry.status == DiaryEntryStatus.archived,
  };

  /// Whether the note answers the search. Title first and body second, because
  /// the title is already a string while the body is a Delta that has to be
  /// decoded — and with no search on, nothing is decoded at all.
  bool _found(DiaryEntry entry) {
    if (terms.isEmpty) return true;
    if (matchesTerms(entry.title, terms)) return true;
    return matchesTerms(_DiaryCard.plainBody(entry.body), terms);
  }

  String get _emptyLabel => switch (filter) {
    _DiaryFilter.all => 'Пока нет заметок',
    _DiaryFilter.favorites => 'Нет избранных заметок',
    _DiaryFilter.drafts => 'Нет черновиков',
    _DiaryFilter.archive => 'В архиве пусто',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entriesAsync = ref.watch(diaryEntriesProvider);
    final mode = ref.watch(diaryViewModeProvider);
    // Two queries for the whole screen, not one per card — see
    // `moodsByEntryProvider`. An empty map while they are in flight, so a card
    // draws without its labels for a frame rather than not at all.
    final moods = ref.watch(moodsByEntryProvider).valueOrNull ?? const {};
    final tags = ref.watch(tagsByEntryProvider).valueOrNull ?? const {};
    // The pictures live in a directory that has to be asked for; until the
    // answer arrives a row simply draws without its cover.
    final imagesDirectory = ref.watch(noteImagesDirectoryProvider).valueOrNull;

    return entriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Ошибка: $error')),
      data: (entries) {
        final shown = entries.where(_keeps).where(_found).toList();
        if (shown.isEmpty) {
          return Center(
            child: Text(
              terms.isEmpty ? _emptyLabel : 'Ничего не найдено',
              style: theme.textTheme.bodyMedium?.copyWith(color: labelInk),
            ),
          );
        }

        void open(BuildContext context, DiaryEntry entry) =>
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NoteViewPage(entryId: entry.id),
              ),
            );

        // One inset for both views, so the notes stand in the same place
        // whichever way they are drawn. The 120 at the bottom clears the
        // floating nav bar.
        const padding = EdgeInsets.fromLTRB(20, 8, 20, 120);

        if (mode == DiaryViewMode.grid) {
          return GridView.builder(
            padding: padding,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              // Room for a cover and two lines under it. The picture takes
              // whatever the title and the date leave, so a tile is the same
              // height whatever it holds and the two columns stay level.
              childAspectRatio: 0.82,
            ),
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final entry = shown[index];
              return _DiaryTile(
                entry: entry,
                imagesDirectory: imagesDirectory,
                terms: terms,
                onOpen: () => open(context, entry),
              );
            },
          );
        }

        return ListView.separated(
          padding: padding,
          itemCount: shown.length,
          // Runs exactly the width of a card, since the cards fill the list and
          // the inset is the list's own.
          separatorBuilder: (_, _) => Divider(
            height: 21,
            thickness: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          itemBuilder: (context, index) {
            final entry = shown[index];
            return InkWell(
              onTap: () => open(context, entry),
              child: _DiaryCard(
                entry: entry,
                imagesDirectory: imagesDirectory,
                terms: terms,
                moods: moods[entry.id] ?? const [],
                tags: tags[entry.id] ?? const [],
              ),
            );
          },
        );
      },
    );
  }
}

/// One note in the list: the thumbnail, and beside it the title with the star,
/// then the date and the mood, then two lines of the text, then the tags.
///
/// No longer one fixed height — a note with tags is taller than one without, and
/// pinning the row would mean either cropping the tags or holding empty space
/// under every note that has none. What is capped is the *text*: two lines, so a
/// note of ten paragraphs cannot push its neighbours off the screen.
///
/// No fill and no shadow — the cards are told apart by the divider between them,
/// and a divider laid between two filled cards is invisible.
class _DiaryCard extends ConsumerWidget {
  const _DiaryCard({
    required this.entry,
    required this.imagesDirectory,
    this.terms = const [],
    this.moods = const [],
    this.tags = const [],
  });

  final DiaryEntry entry;
  final Directory? imagesDirectory;

  /// What the search is looking for: picked out of the title and the excerpt,
  /// and what the excerpt is wound forward to.
  final List<String> terms;

  /// The note's labels, handed down from the list — see `moodsByEntryProvider`.
  /// Normally one mood or none; the join table allows more and the row draws
  /// whatever it is given.
  final List<NoteMood> moods;
  final List<NoteTag> tags;

  static const double _thumb = 72;

  /// How many tags a card shows before it starts counting them instead. The same
  /// idea as the attachment strip on the note screen: the first few, then how
  /// many are left.
  static const int _tagsShown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Wound to the match, so a card found by its seventh paragraph does not
    // answer with its first.
    final excerpt = excerptAround(plainBody(entry.body), terms);
    final titled = entry.title.trim().isNotEmpty;
    final hidden = tags.length - _tagsShown;

    return Row(
      // Top, not centre: the thumbnail is one height and the text beside it is
      // not, and a picture floating in the middle of a tall card reads as a
      // mistake.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RowThumb(size: _thumb, path: noteThumbnail(entry, imagesDirectory)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Highlighted(
                      text: titled ? entry.title : 'Без названия',
                      terms: terms,
                      maxLines: 1,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: titled ? theme.colorScheme.onSurface : labelInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Its own gesture above the card's, so starring a note does
                  // not open it.
                  _FavouriteStar(
                    favourite: entry.isFavorite,
                    onTap: () => ref
                        .read(diaryDaoProvider)
                        .setFavorite(entry.id, !entry.isFavorite),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    formatTime(entry.updatedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: labelInk,
                    ),
                  ),
                  if (moods.isNotEmpty) ...[
                    // The separator only exists between two things.
                    Text(
                      '  ·  ',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: labelInk,
                      ),
                    ),
                    // Clipped rather than wrapped: the date line is one line,
                    // and a second mood is rare enough not to reshape the card.
                    Flexible(
                      child: ClipRect(
                        child: Row(
                          children: [
                            for (final mood in moods) ...[
                              MoodChip(
                                mood: mood,
                                // No fill on a row: the card already carries
                                // coloured tag chips a line below, and a filled
                                // mood next to the date makes the line a row of
                                // boxes.
                                filled: false,
                                surface: pageSurface(theme),
                              ),
                              if (mood != moods.last) const SizedBox(width: 10),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              _Highlighted(
                text: excerpt,
                terms: terms,
                maxLines: 2,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags.take(_tagsShown))
                      NoteTagChip(tag: tag, surface: pageSurface(theme)),
                    if (hidden > 0) _MoreTagsChip(count: hidden),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The body is a Delta; a card shows its text with the formatting dropped, and
  /// the search reads the same string. A note saved before anything was typed
  /// holds an empty string, which is not JSON — hence the guard rather than a
  /// try/catch.
  static String plainBody(String body) {
    if (body.trim().isEmpty) return '';
    final operations = jsonDecode(body) as List;
    return deltaPlainText(operations).trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Time for a note touched today, a date for anything older: a bare "08:30"
  /// on a note from last week says nothing. Read by the tile as well, so both
  /// views date a note the same way.
  static String formatTime(DateTime date) {
    final now = DateTime.now();
    final sameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;
    return sameDay
        ? DateFormat('HH:mm', 'ru_RU').format(date)
        : DateFormat('d MMM', 'ru_RU').format(date);
  }
}

/// The favourite toggle on a row.
///
/// On the page tone rather than on a picture, so no scrim disc — the star itself
/// carries the state, in the accent when the note is starred and in the label
/// tone when it is not. Lucide has no filled star to switch to, which is why
/// colour has to do the whole job.
class _FavouriteStar extends StatelessWidget {
  const _FavouriteStar({required this.favourite, required this.onTap});

  final bool favourite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      // Opaque and padded: a 16px star is not a tap target, and the padding is
      // what makes it one without moving the glyph.
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: favourite ? 'Убрать из избранного' : 'В избранное',
        child: Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Icon(
            LucideIcons.star,
            size: 18,
            color: favourite
                ? inkOn(pageSurface(theme), theme.colorScheme.primary)
                : labelInk,
          ),
        ),
      ),
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
  });

  final DiaryEntry entry;
  final Directory? imagesDirectory;
  final List<String> terms;
  final VoidCallback onOpen;

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
                      _DiaryCard.formatTime(entry.updatedAt),
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
          message: favourite ? 'Убрать из избранного' : 'В избранное',
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              LucideIcons.star,
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

/// The cover, or a stand-in when the note has none — or when its file is gone,
/// which a picture copied into the app's own directory should not be, but a row
/// is not the place to find out.
class _RowThumb extends StatelessWidget {
  const _RowThumb({required this.size, required this.path});

  final double size;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: insetSurface(theme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(LucideIcons.file_text, size: 22, color: labelInk),
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
