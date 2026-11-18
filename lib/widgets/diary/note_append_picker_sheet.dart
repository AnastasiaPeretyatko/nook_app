import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/share_to_nook/open_note_editor.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/note_search.dart';
import 'package:todo_app/utils/shared_note_content.dart';
import 'package:todo_app/widgets/app_dialogs.dart';

/// Lets a shared-text flow choose the note that receives [content].
///
/// The returned row is the one the DAO updated; null means that the sheet was
/// dismissed or that the target disappeared before its append could finish.
Future<DiaryEntry?> showNoteAppendPickerSheet(
  BuildContext context, {
  required SharedNoteContent content,
}) => showModalBottomSheet<DiaryEntry>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _NoteAppendPickerSheet(content: content),
);

class _NoteAppendPickerSheet extends ConsumerStatefulWidget {
  const _NoteAppendPickerSheet({required this.content});

  final SharedNoteContent content;

  @override
  ConsumerState<_NoteAppendPickerSheet> createState() =>
      _NoteAppendPickerSheetState();
}

class _NoteAppendPickerSheetState
    extends ConsumerState<_NoteAppendPickerSheet> {
  final _search = TextEditingController();
  List<String> _terms = const [];
  bool _isAppending = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _select(DiaryEntry entry) async {
    if (_isAppending || ref.read(openNoteEditorsProvider).contains(entry.id)) {
      return;
    }
    setState(() => _isAppending = true);
    final updated = await ref
        .read(diaryDaoProvider)
        .appendSharedContent(entry.id, widget.content);
    if (!mounted) return;
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    // `diaryEntriesProvider` is the app's one view of `watchEntries()`, whose
    // DAO ordering is newest-modified first. Filtering does not re-sort it.
    final entries = (ref.watch(diaryEntriesProvider).valueOrNull ?? const [])
        .where((entry) => entry.status != DiaryEntryStatus.archived)
        .toList();
    final searching = _terms.isNotEmpty;
    final shown = searching
        ? entries
              .where(
                (entry) =>
                    matchesTerms(entry.title, _terms) ||
                    matchesTerms(plainNoteBody(entry.body), _terms),
              )
              .toList()
        : entries;

    return AppSheet(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Text(
            'Добавить в заметку',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ),
        TextField(
          key: const Key('note-append-search'),
          controller: _search,
          onChanged: (query) => setState(() => _terms = searchTerms(query)),
          decoration: InputDecoration(
            hintText: 'Поиск заметок',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: palette.surfaceMuted,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Text(
                searching ? 'Результаты поиска' : 'Последние заметки',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Text(
                    searching ? 'Ничего не найдено' : 'Заметок пока нет',
                    style: TextStyle(color: palette.textSecondary),
                  ),
                )
              else
                GreyCard(
                  children: [
                    for (final entry in shown)
                      _NoteOption(
                        entry: entry,
                        enabled:
                            !_isAppending &&
                            !ref
                                .read(openNoteEditorsProvider)
                                .contains(entry.id),
                        onTap: () => _select(entry),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoteOption extends StatelessWidget {
  const _NoteOption({
    required this.entry,
    required this.enabled,
    required this.onTap,
  });

  final DiaryEntry entry;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    final title = entry.title.trim().isEmpty ? 'Без названия' : entry.title;
    return InkWell(
      key: ValueKey('note-append-${entry.id}'),
      onTap: enabled ? onTap : null,
      child: Padding(
        key: const Key('note-append-row'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.note_outlined, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat(
                      'd MMM yyyy, HH:mm',
                      'ru_RU',
                    ).format(entry.updatedAt.toLocal()),
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
