import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/share_to_nook/editor_lock_bridge.dart';
import 'package:todo_app/utils/shared_note_content.dart';
import 'package:todo_app/main.dart' show buildAppTheme;
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/widgets/diary/compact_note_picker.dart';

const _bridge = MethodChannel('com.yourname.todo_app/compact_share');

@pragma('vm:entry-point')
Future<void> shareMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    runApp(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const CompactShareApp(),
      ),
    );
  } on Object {
    runApp(const MaterialApp(home: _Failure()));
  }
}

class CompactShareApp extends ConsumerStatefulWidget {
  const CompactShareApp({
    super.key,
    this.bridge = _bridge,
    this.createForSharedEvent,
    this.appendForSharedEvent,
    this.editorLockBridge = const MethodChannelEditorLockBridge(),
  });

  final MethodChannel bridge;
  final Future<ShareEventResult> Function({
    required String eventId,
    required String title,
    required SharedNoteContent content,
  })?
  createForSharedEvent;
  final Future<ShareEventResult> Function({
    required String eventId,
    required int noteId,
    required SharedNoteContent content,
  })?
  appendForSharedEvent;
  final EditorLockBridge editorLockBridge;
  @override
  ConsumerState<CompactShareApp> createState() => _CompactShareAppState();
}

class _CompactShareAppState extends ConsumerState<CompactShareApp> {
  final _received = <String, String>{};
  final _persisted = <String>{};
  _Destination? _destination;
  _Destination? _selectedDestination;
  bool _appendBusy = false;
  @override
  void initState() {
    super.initState();
    // This engine owns its own Drift connection. The provider disposes it with
    // this compact tree; it never shares MainActivity's Flutter engine.
    ref.read(databaseProvider);
    widget.bridge.setMethodCallHandler((call) async {
      if (call.method == 'eventsAvailable') {
        await _drain();
      }
    });
    _drain();
  }

  Future<void> _drain() async {
    final events =
        await widget.bridge.invokeMethod<List<dynamic>>('takePending') ??
        const [];
    for (final event in events) {
      if (event is! Map || event['id'] is! String || event['text'] is! String) {
        continue;
      }
      final id = event['id'] as String;
      _received[id] = event['text'] as String;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.bridge.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = ref.watch(appColorProvider);
    final mode = ref.watch(themeModeProvider);
    final event = _received.entries.isEmpty ? null : _received.entries.first;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(color, Brightness.light),
      darkTheme: buildAppTheme(color, Brightness.dark),
      themeMode: mode,
      locale: const Locale('ru', 'RU'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU')],
      home: PopScope<void>(
        canPop: _destination == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _destination != null && !_appendBusy) {
            setState(() => _destination = null);
          }
        },
        child: _destination == _Destination.append
            ? CompactNotePicker(
                onClose: SystemNavigator.pop,
                eventId: event?.key,
                content: SharedNoteContent(event?.value ?? ''),
                isPersisted: event != null && _persisted.contains(event.key),
                appendForSharedEvent:
                    widget.appendForSharedEvent ??
                    ref.read(diaryDaoProvider).appendForSharedEvent,
                acknowledge: (id) =>
                    widget.bridge.invokeMethod<void>('acknowledge', {'id': id}),
                onPersisted: (id) {
                  if (mounted) setState(() => _persisted.add(id));
                },
                onAppendBusyChanged: (busy) {
                  if (mounted) setState(() => _appendBusy = busy);
                },
                onBack: () => setState(() {
                  _appendBusy = false;
                  _destination = null;
                }),
                lockBridge: widget.editorLockBridge,
              )
            : Scaffold(
                backgroundColor: Colors.transparent,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onTap: SystemNavigator.pop,
                      behavior: HitTestBehavior.opaque,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.18),
                      ),
                    ),
                    _CompactShareSheet(
                      child: _destination == null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Сохранить в Nook',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _ShareDestinationTile(
                                  icon: LucideIcons.clipboard_minus,
                                  title: 'Создать новую заметку',
                                  subtitle: 'Сохранить текст отдельно',
                                  selected:
                                      _selectedDestination ==
                                      _Destination.create,
                                  onTap: () => setState(
                                    () => _selectedDestination =
                                        _Destination.create,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _ShareDestinationTile(
                                  icon: LucideIcons.clipboard_plus,
                                  title: 'Добавить к существующей',
                                  subtitle:
                                      'Текст будет добавлен в конце заметки',
                                  selected:
                                      _selectedDestination ==
                                      _Destination.append,
                                  onTap: () => setState(
                                    () => _selectedDestination =
                                        _Destination.append,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 52,
                                  child: FilledButton(
                                    onPressed: _selectedDestination == null
                                        ? null
                                        : () => setState(
                                            () => _destination =
                                                _selectedDestination,
                                          ),
                                    child: const Text('Продолжить'),
                                  ),
                                ),
                              ],
                            )
                          : _destination == _Destination.create
                          ? _CreateForm(
                              eventId: event?.key,
                              initialBody: event?.value ?? '',
                              isPersisted:
                                  event != null &&
                                  _persisted.contains(event.key),
                              createForSharedEvent:
                                  widget.createForSharedEvent ??
                                  ref
                                      .read(diaryDaoProvider)
                                      .createForSharedEvent,
                              acknowledge: (id) =>
                                  widget.bridge.invokeMethod<void>(
                                    'acknowledge',
                                    {'id': id},
                                  ),
                              onPersisted: (id) {
                                if (mounted) {
                                  setState(() => _persisted.add(id));
                                }
                              },
                              onBack: () => setState(() => _destination = null),
                              onClose: SystemNavigator.pop,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CompactShareSheet extends StatelessWidget {
  const _CompactShareSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: Material(
            color: raisedSurface(theme),
            elevation: 16,
            shadowColor: surfaceShadow(theme, light: 0.16),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    child,
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

class _ShareDestinationTile extends StatelessWidget {
  const _ShareDestinationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : palette.borderStrong,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 22, color: palette.textPrimary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                selected: selected,
                child: _ChoiceRadio(selected: selected),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceRadio extends StatelessWidget {
  const _ChoiceRadio({required this.selected});

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

class _CreateForm extends StatefulWidget {
  const _CreateForm({
    required this.eventId,
    required this.initialBody,
    required this.isPersisted,
    required this.createForSharedEvent,
    required this.acknowledge,
    required this.onPersisted,
    required this.onBack,
    required this.onClose,
  });

  final String? eventId;
  final String initialBody;
  final bool isPersisted;
  final Future<ShareEventResult> Function({
    required String eventId,
    required String title,
    required SharedNoteContent content,
  })
  createForSharedEvent;
  final Future<void> Function(String eventId) acknowledge;
  final ValueChanged<String> onPersisted;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  State<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends State<_CreateForm> {
  static const _completionDelay = Duration(milliseconds: 800);

  late final title = TextEditingController();
  late final body = TextEditingController(text: widget.initialBody);
  Timer? _completionTimer;
  bool _isSaving = false;
  bool _didPersist = false;
  bool _isComplete = false;
  bool _hasConflict = false;
  String? _error;

  bool get _canSave =>
      !_isSaving &&
      !_didPersist &&
      !_hasConflict &&
      !widget.isPersisted &&
      widget.eventId != null &&
      body.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _didPersist = widget.isPersisted;
    body.addListener(_onBodyChanged);
  }

  void _onBodyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.createForSharedEvent(
        eventId: widget.eventId!,
        title: title.text.trim(),
        content: SharedNoteContent(body.text),
      );
    } on ShareEventConflict {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _hasConflict = true;
          _error = 'Это событие уже обработано другим действием';
        });
      }
      return;
    } on Object {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'Не удалось сохранить заметку';
        });
      }
      return;
    }

    _didPersist = true;
    widget.onPersisted(widget.eventId!);
    await _acknowledgeAndComplete();
  }

  Future<void> _retryAcknowledgement() async {
    if (_isSaving || !_didPersist || widget.eventId == null) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    await _acknowledgeAndComplete();
  }

  Future<void> _acknowledgeAndComplete() async {
    try {
      await widget.acknowledge(widget.eventId!);
    } on Object {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'Заметка сохранена, но не подтверждена';
        });
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
    _completionTimer?.cancel();
    body.removeListener(_onBodyChanged);
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isComplete) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 40),
          SizedBox(height: 12),
          Text('Заметка сохранена', style: TextStyle(fontSize: 20)),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Новая заметка',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isSaving ? null : widget.onBack,
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          child: const Text('Выбрать другое действие'),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: title,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Заголовок'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: body,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Текст заметки'),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        if (_didPersist && _error != null)
          TextButton(
            onPressed: _isSaving ? null : _retryAcknowledgement,
            child: const Text('Повторить подтверждение'),
          ),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _canSave ? _save : null,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить'),
          ),
        ),
      ],
    );
  }
}

enum _Destination { create, append }

class _Failure extends StatelessWidget {
  const _Failure();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Не удалось открыть Share')));
}
