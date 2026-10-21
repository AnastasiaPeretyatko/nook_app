import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/theme/app_palette.dart';

/// A dark pill at the very bottom of the screen (`Toasts.dc.html`): an icon, a
/// line of text and, if there is something to take back, one button. It goes by
/// itself after [duration] and can be swiped off to either side.
///
/// Not a `SnackBar`: a floating one is laid out by the `Scaffold` above the
/// bottom bar *and* above the floating "+", so it hung in the middle of the
/// screen. Here it is an entry of the root [Overlay] instead, which also keeps
/// it alive when the screen that asked for it has closed. Take the overlay with
/// `Overlay.of(context, rootOverlay: true)` before awaiting anything.
///
/// [detail] is a smaller line under the message. [isError] draws the light card
/// with a red mark instead of the dark pill — the "Не удалось синхронизировать"
/// variant of the design — and [icon] is not used for it. [leading] replaces the
/// icon with any widget, such as a member's avatar.
///
/// One at a time: a new toast replaces the one on screen.
void showAppToast(
  OverlayState overlay, {
  required String message,
  String? detail,
  bool isError = false,
  Widget? leading,
  IconData icon = LucideIcons.trash_2,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 5),
}) {
  _current?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Toast(
      message: message,
      detail: detail,
      isError: isError,
      leading: leading,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      onDone: () {
        if (_current == entry) _current = null;
        entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

OverlayEntry? _current;

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.detail,
    required this.isError,
    required this.leading,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final String? detail;
  final bool isError;
  final Widget? leading;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _leave);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slide.dispose();
    super.dispose();
  }

  /// Slides down and out, then takes the entry off.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    await _slide.reverse();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final error = widget.isError;
    // The dark pill is the same near-black in both themes: it is meant to stand
    // out from the page, light or dark. An error is the page's own card instead.
    final fill = error ? p.surface : const Color(0xFF1B2230);
    final button = error ? p.surface : const Color(0xFF2C3546);
    final muted = error ? p.textSecondary : const Color(0xFFC9CFDA);
    final ink = error ? p.textPrimary : Colors.white;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 12 + bottom,
      child: FadeTransition(
        opacity: _slide,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.6),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _slide, curve: Curves.easeOut)),
          child: Dismissible(
            key: const ValueKey('app-toast'),
            direction: DismissDirection.horizontal,
            onDismissed: (_) {
              _timer?.cancel();
              widget.onDone();
            },
            child: Material(
              color: fill,
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: error ? BorderSide(color: p.outline) : BorderSide.none,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Row(
                    children: [
                      if (error)
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: p.dangerSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            LucideIcons.info,
                            size: 14,
                            color: p.danger,
                          ),
                        )
                      else if (widget.leading != null)
                        widget.leading!
                      else
                        Icon(widget.icon, size: 20, color: muted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.message,
                              style: TextStyle(fontSize: 15, color: ink),
                            ),
                            if (widget.detail != null)
                              Text(
                                widget.detail!,
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                          ],
                        ),
                      ),
                      if (widget.actionLabel != null)
                        Material(
                          color: button,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: error
                                ? BorderSide(color: p.outline)
                                : BorderSide.none,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              widget.onAction?.call();
                              _leave();
                            },
                            child: SizedBox(
                              height: 40,
                              child: Center(
                                widthFactor: 1,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: Text(
                                    widget.actionLabel!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
