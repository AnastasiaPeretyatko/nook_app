import 'dart:async';
import 'dart:convert';

import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:todo_app/utils/task_colors.dart';

/// How a note's text is styled, in the editor and on the view screen alike.
///
/// Paragraph and list spacing is halved off Fleather's fallback, and the two
/// headings the toolbar can reach are redefined; everything else — quotes, code,
/// inline styles — stays as Fleather derives it from the app theme.
///
/// The defaults are what make this necessary: Fleather draws H1 at 34px in
/// weight 300 with the text colour at 70% alpha — thin and washed out, and
/// larger than the note's own title. Ours step down from that title (22 / w700)
/// instead, so a heading inside a note can never outshout the note's name, and
/// they are full-strength [ColorScheme.onSurface].
FleatherThemeData noteEditorTheme(BuildContext context) {
  final theme = Theme.of(context);
  final ink = theme.colorScheme.onSurface;
  final fallback = FleatherThemeData.fallback(context);

  return fallback.copyWith(
    // Every Enter starts a new paragraph, so what reads as the gap between two
    // lines is the paragraph spacing: Fleather's 6 above and 10 below make 16px
    // between neighbours. Halved.
    paragraph: TextBlockTheme(
      style: fallback.paragraph.style,
      spacing: const VerticalSpacing(top: 3, bottom: 5),
    ),
    lists: TextBlockTheme(
      style: fallback.lists.style,
      spacing: const VerticalSpacing(top: 3, bottom: 5),
      lineSpacing: fallback.lists.lineSpacing,
    ),
    // Built off the fallback paragraph rather than from scratch: Fleather
    // merges a block style onto an empty `TextStyle`, so a heading written out
    // by hand carries no font family and would come out in the platform's
    // default face while the rest of the note is the app's.
    heading1: TextBlockTheme(
      style: fallback.paragraph.style.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: ink,
      ),
      spacing: const VerticalSpacing(top: 16, bottom: 4),
    ),
    heading2: TextBlockTheme(
      style: fallback.paragraph.style.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: ink,
      ),
      spacing: const VerticalSpacing(top: 12, bottom: 4),
    ),
  );
}

/// How a note's check-list boxes look.
///
/// Fleather draws them with its own copy of the Material checkbox
/// (`FleatherCheckbox`), which reads `CheckboxTheme.of(context)` — so the box is
/// restyled by wrapping the editor rather than by patching the package. Its M3
/// default is a 1px-radius square with a 2px border: a hard little square next
/// to soft text. This rounds it and thins the outline.
///
/// Two things here are **not** reachable: the box is a fixed 18px
/// (`_kEdgeSize`) and the tick inside it is stroked at a fixed 2.0
/// (`_kStrokeWidth`) — both private consts in the package. Only the outline of
/// the empty box thins out; the tick keeps its weight.
///
/// The border is deliberately given as a plain [BorderSide]: Fleather drops it
/// for the ticked state on its own, so the accent fill is not outlined.
///
/// A ticked box is the app accent with a white tick. The fill is pinned rather
/// than left to the package, which happens to default to the same thing — a
/// version bump must not be able to repaint it. The tick is [onBrandFill], not
/// `onPrimary`: a box filled with the user's colour is a **brand fill**, and the
/// app writes one recognisable white on every one of those instead of flipping
/// to black on the pale families. `onPrimary` would do exactly that flip, and a
/// black tick in a yellow box is not what the rest of the app looks like.
/// [onBrandFill] still steps aside for an all-but-white accent, where white on
/// white would be nothing at all.
///
/// Only the ticked-and-enabled state is pinned; everything else resolves to null
/// and keeps the package's own M3 default — the same rule `switchTheme` follows
/// in `buildAppTheme`, and it is what leaves a read-only note's boxes looking
/// properly disabled.
CheckboxThemeData noteCheckboxTheme(BuildContext context) {
  final theme = Theme.of(context);
  final accent = theme.colorScheme.primary;

  bool ticked(Set<WidgetState> states) =>
      states.contains(WidgetState.selected) &&
      !states.contains(WidgetState.disabled);

  return CheckboxThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    side: BorderSide(width: 1.2, color: theme.colorScheme.outline),
    fillColor: WidgetStateProperty.resolveWith<Color?>(
      (states) => ticked(states) ? accent : null,
    ),
    checkColor: WidgetStateProperty.resolveWith<Color?>(
      (states) => ticked(states) ? onBrandFill(accent) : null,
    ),
  );
}

/// A saved note's text, as it is read.
///
/// The same Fleather editor the note was written in rather than a `Text`: the
/// body is a Delta, and only the editor knows how to draw its headings, lists
/// and check-boxes.
///
/// Everything on it is inert **except its check-boxes**, which can be ticked
/// where [onChanged] is given — a to-do list nobody can tick is a picture of a
/// to-do list.
class NoteBodyView extends StatefulWidget {
  const NoteBodyView({super.key, required this.body, this.onChanged});

  /// The stored Delta, JSON-encoded.
  final String body;

  /// Called with the note's new Delta each time one of its boxes is ticked.
  /// Null makes the text a picture: the boxes are drawn but cannot be touched.
  final ValueChanged<String>? onChanged;

  @override
  State<NoteBodyView> createState() => _NoteBodyViewState();
}

class _NoteBodyViewState extends State<NoteBodyView> {
  late FleatherController _controller;
  StreamSubscription<ParchmentChange>? _changes;

  /// A focus node that will not take focus. It is what keeps an editor that is
  /// technically writable from behaving like one — see [build].
  final _focus = FocusNode(canRequestFocus: false);

  /// The body as this widget last knew it: what it was handed, or what it last
  /// reported upwards. A tick travels to the database and comes back through
  /// the stream, and this is what tells that echo apart from a real edit made
  /// somewhere else.
  late String _known;

  @override
  void initState() {
    super.initState();
    _known = widget.body;
    _controller = _controllerFor(widget.body);
    _listen();
  }

  /// Ticking a box formats the line with `notify: false` — Fleather keeps the
  /// controller deliberately quiet, so that a check-box does not rebuild the
  /// whole editor. The **document** still announces the change, and that stream
  /// is the only place a tick can be heard from.
  void _listen() {
    if (widget.onChanged == null) return;
    _changes = _controller.document.changes.listen((_) => _report());
  }

  void _report() {
    final encoded = jsonEncode(_controller.document.toDelta());
    if (encoded == _known) return;
    _known = encoded;
    widget.onChanged?.call(encoded);
  }

  @override
  void didUpdateWidget(NoteBodyView old) {
    super.didUpdateWidget(old);
    // The note is streamed, so an edit arrives as a new body string — including
    // the tick this screen has just written, which the document it is rebuilt
    // from already holds. Rebuilding on that would throw the editor away under
    // the finger that ticked it.
    if (widget.body != _known) {
      _known = widget.body;
      _changes?.cancel();
      _controller.dispose();
      _controller = _controllerFor(widget.body);
      _listen();
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A body that is empty, or somehow not the JSON it should be, still has to
  /// render: a broken document must not take the screen down with it.
  FleatherController _controllerFor(String body) {
    if (body.trim().isEmpty) return FleatherController();
    try {
      return FleatherController(
        document: ParchmentDocument.fromJson(jsonDecode(body) as List),
      );
    } on Object {
      return FleatherController();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CheckboxTheme(
      data: noteCheckboxTheme(context),
      child: FleatherTheme(
        data: noteEditorTheme(context),
        child: FleatherEditor(
          controller: _controller,
          focusNode: _focus,
          // Not read-only, and that is the whole trick: Fleather ties a
          // check-box to the editor (`enabled: !readOnly`), so a note whose
          // boxes must work cannot be a read-only editor. What an editor
          // otherwise *is* gets taken away one piece at a time instead — the
          // focus node refuses focus, so a tap raises no keyboard and places no
          // cursor and no text can be typed; selection is off, so there is no
          // long-press toolbar to paste through; the caret is hidden. What is
          // left is a page that can only be ticked.
          readOnly: widget.onChanged == null,
          showCursor: false,
          enableInteractiveSelection: false,
          // The screen scrolls; an editor with its own scroll would fight it.
          scrollable: false,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
