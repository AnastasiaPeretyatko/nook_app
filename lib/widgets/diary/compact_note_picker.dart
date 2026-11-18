import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/share_to_nook/editor_lock_bridge.dart';
import 'package:todo_app/utils/note_search.dart';
import 'package:todo_app/utils/shared_note_content.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/surfaces.dart';

/// A compact, non-mutating selector for a diary note.
///
/// The caller owns the next step. In particular, choosing a row here never
/// appends shared content or acknowledges a share event.
class CompactNotePicker extends ConsumerStatefulWidget {
  const CompactNotePicker({
    super.key,
    required this.onBack,
    required this.onClose,
    required this.eventId,
    required this.content,
    required this.appendForSharedEvent,
    required this.acknowledge,
    required this.onPersisted,
    required this.onAppendBusyChanged,
    required this.isPersisted,
    this.lockBridge = const MethodChannelEditorLockBridge(),
  });

  final VoidCallback onBack;
  final VoidCallback onClose;
  final String? eventId;
  final SharedNoteContent content;
  final Future<ShareEventResult> Function({
    required String eventId,
    required int noteId,
    required SharedNoteContent content,
  })
  appendForSharedEvent;
  final Future<void> Function(String eventId) acknowledge;
  final ValueChanged<String> onPersisted;
  final ValueChanged<bool> onAppendBusyChanged;
  final bool isPersisted;
  final EditorLockBridge lockBridge;

  @override
  ConsumerState<CompactNotePicker> createState() => _CompactNotePickerState();
}

class _CompactNotePickerState extends ConsumerState<CompactNotePicker>
    with WidgetsBindingObserver {
  static const _completionDelay = Duration(milliseconds: 800);

  final _search = TextEditingController();
  List<String> _terms = const [];
  int? _selectedId;
  Set<int> _lockedIds = const {};
  bool _loadingLocks = true;
  bool _lockLoadFailed = false;
  bool _isSaving = false;
  bool _didPersist = false;
  bool _isComplete = false;
  bool _hasConflict = false;
  bool _releasePending = false;
  String? _releaseOwnerId;
  int? _releaseNoteId;
  String? _error;
  Timer? _completionTimer;

  bool get _canAppend =>
      !_isSaving &&
      !_didPersist &&
      !_hasConflict &&
      !widget.isPersisted &&
      widget.eventId != null &&
      _selectedId != null &&
      !_loadingLocks &&
      !_lockLoadFailed &&
      !_lockedIds.contains(_selectedId);

  @override
  void initState() {
    super.initState();
    _didPersist = widget.isPersisted;
    WidgetsBinding.instance.addObserver(this);
    _refreshLocks();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLocks();
    }
  }

  Future<void> _refreshLocks() async {
    if (mounted) {
      setState(() {
        _loadingLocks = true;
        _lockLoadFailed = false;
      });
    }
    try {
      final lockedIds = (await widget.lockBridge.getLockedIds()).toSet();
      if (!mounted) return;
      setState(() {
        _lockedIds = lockedIds;
        _loadingLocks = false;
        if (_selectedId != null && lockedIds.contains(_selectedId)) {
          _selectedId = null;
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _lockedIds = const {};
        _selectedId = null;
        _loadingLocks = false;
        _lockLoadFailed = true;
      });
    }
  }

  Future<void> _append() async {
    if (!_canAppend) return;

    final noteId = _selectedId!;
    final eventId = widget.eventId!;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    widget.onAppendBusyChanged(true);

    var acquired = false;
    var lockDenied = false;
    var eventConflict = false;
    var didPersist = false;
    var releaseFailed = false;
    String? ownerId;
    String? error;
    try {
      ownerId = await widget.lockBridge.newOwner();
      acquired = await widget.lockBridge.tryAcquire(
        noteId: noteId,
        ownerId: ownerId,
      );
      if (!acquired) {
        lockDenied = true;
        error = 'Заметка открыта в редакторе';
      } else {
        await widget.appendForSharedEvent(
          eventId: eventId,
          noteId: noteId,
          content: widget.content,
        );
        didPersist = true;
      }
    } on ShareEventConflict {
      eventConflict = true;
      error = 'Это событие уже обработано для другой заметки';
    } on Object {
      error = acquired
          ? 'Не удалось добавить текст в заметку'
          : 'Не удалось проверить доступ к заметке';
    } finally {
      if (acquired && ownerId != null) {
        try {
          releaseFailed = !await widget.lockBridge.release(
            noteId: noteId,
            ownerId: ownerId,
          );
        } on Object {
          releaseFailed = true;
        }
      }
    }

    if (!mounted) return;
    if (!didPersist) {
      setState(() {
        _isSaving = false;
        _error = error;
        _hasConflict = eventConflict;
        if (lockDenied) _selectedId = null;
      });
      widget.onAppendBusyChanged(false);
      return;
    }

    _didPersist = true;
    widget.onPersisted(eventId);
    if (releaseFailed) {
      setState(() {
        _isSaving = false;
        _releasePending = true;
        _releaseOwnerId = ownerId;
        _releaseNoteId = noteId;
        _error = 'Не удалось освободить заметку';
      });
      widget.onAppendBusyChanged(false);
      return;
    }
    await _acknowledgeAndComplete();
  }

  Future<void> _retryRelease() async {
    final ownerId = _releaseOwnerId;
    final noteId = _releaseNoteId;
    if (_isSaving || ownerId == null || noteId == null) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });
    widget.onAppendBusyChanged(true);
    try {
      final released = await widget.lockBridge.release(
        noteId: noteId,
        ownerId: ownerId,
      );
      if (!released) throw StateError('lock release rejected');
    } on Object {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'Не удалось освободить заметку';
        });
        widget.onAppendBusyChanged(false);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _releasePending = false;
      _releaseOwnerId = null;
      _releaseNoteId = null;
    });
    await _acknowledgeAndComplete();
  }

  Future<void> _retryAcknowledgement() async {
    if (_isSaving || !_didPersist || _releasePending) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    widget.onAppendBusyChanged(true);
    await _acknowledgeAndComplete();
  }

  Future<void> _acknowledgeAndComplete() async {
    try {
      await widget.acknowledge(widget.eventId!);
    } on Object {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'Текст добавлен, но не подтверждён';
        });
        widget.onAppendBusyChanged(false);
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _isComplete = true;
    });
    _completionTimer = Timer(_completionDelay, () {
      if (mounted) widget.onClose();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _completionTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    if (_isComplete) {
      return Scaffold(
        backgroundColor: pageSurface(theme),
        body: const SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 40),
                SizedBox(height: 12),
                Text('Добавлено в заметку', style: TextStyle(fontSize: 20)),
              ],
            ),
          ),
        ),
      );
    }

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

    return Scaffold(
      backgroundColor: pageSurface(theme),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isSaving ? null : widget.onBack,
                    icon: const Icon(LucideIcons.chevron_left),
                    tooltip: 'Назад',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Выбрать заметку',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('compact-note-lock-refresh'),
                    onPressed: _loadingLocks ? null : _refreshLocks,
                    icon: const Icon(LucideIcons.refresh_cw),
                    tooltip: 'Обновить доступность заметок',
                  ),
                ],
              ),
            ),
            _PickerSearchBar(
              controller: _search,
              onChanged: (query) => setState(() => _terms = searchTerms(query)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                searching ? 'Результаты поиска' : 'Последние заметки',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (_lockLoadFailed) ...[
              Text(
                'Не удалось проверить открытые заметки',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                key: const Key('compact-note-lock-retry'),
                onPressed: _refreshLocks,
                child: const Text('Повторить'),
              ),
            ] else if (_loadingLocks)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Проверяем доступность заметок…'),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        searching ? 'Ничего не найдено' : 'Заметок пока нет',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = shown[index];
                        final selected = entry.id == _selectedId;
                        final locked = _lockedIds.contains(entry.id);
                        final selectable =
                            !_loadingLocks && !_lockLoadFailed && !locked;
                        final title = entry.title.trim().isEmpty
                            ? 'Без названия'
                            : entry.title;
                        return Material(
                          color: selected
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.08,
                                )
                              : raisedSurface(theme),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            key: ValueKey('compact-note-${entry.id}'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: selectable
                                ? () => setState(() => _selectedId = entry.id)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.file_text,
                                    size: 22,
                                    color: palette.textSecondary,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: palette.textPrimary,
                                          ),
                                        ),
                                        if (locked) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Открыта в редакторе',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: theme.colorScheme.error,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (locked)
                                    const Icon(Icons.lock_outline)
                                  else
                                    Semantics(
                                      selected: selected,
                                      child: _PickerRadio(selected: selected),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            if (_releasePending)
              TextButton(
                onPressed: _isSaving ? null : _retryRelease,
                child: const Text('Повторить освобождение'),
              )
            else if (_didPersist && _error != null)
              TextButton(
                onPressed: _isSaving ? null : _retryAcknowledgement,
                child: const Text('Повторить подтверждение'),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _canAppend ? _append : null,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Добавить в заметку'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerSearchBar extends StatelessWidget {
  const _PickerSearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
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
              key: const Key('compact-note-search'),
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

class _PickerRadio extends StatelessWidget {
  const _PickerRadio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? color : AppPalette.of(theme).outline,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: selected
          ? DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            )
          : null,
    );
  }
}
