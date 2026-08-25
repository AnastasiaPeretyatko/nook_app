import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// A note's pictures, full screen.
///
/// Opens at [initialIndex] and swipes between the rest, so tapping the third
/// thumbnail of a note lands on the third picture rather than on the first.
///
/// A route of its own rather than a dialog: it takes the whole screen, it is
/// dismissed by the system back gesture like any other page, and it must not
/// leave the note showing around its edges.
Future<void> showNoteGallery(
  BuildContext context, {
  required List<String> paths,
  int initialIndex = 0,
}) {
  if (paths.isEmpty) return Future.value();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _NoteGallery(paths: paths, initialIndex: initialIndex),
    ),
  );
}

class _NoteGallery extends StatefulWidget {
  const _NoteGallery({required this.paths, required this.initialIndex});

  final List<String> paths;
  final int initialIndex;

  @override
  State<_NoteGallery> createState() => _NoteGalleryState();
}

class _NoteGalleryState extends State<_NoteGallery> {
  /// Where a double tap takes the picture, and back again.
  static const double _zoom = 2.5;

  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );

  /// One transform for the whole carousel, shared by every page. Only the page
  /// on screen can be pinched, and the zoom is reset the moment another one
  /// arrives, so there is never a second picture holding a transform of its own.
  final _view = TransformationController();

  late int _index = widget.initialIndex;

  /// Whether the picture is scaled up right now. It decides who gets a
  /// horizontal drag: see [_onViewChanged].
  bool _zoomedIn = false;

  /// Where the last double tap landed, so the zoom grows around the point that
  /// was tapped instead of the middle of the screen.
  Offset _tapped = Offset.zero;

  @override
  void initState() {
    super.initState();
    _view.addListener(_onViewChanged);
  }

  @override
  void dispose() {
    _view.removeListener(_onViewChanged);
    _view.dispose();
    _pages.dispose();
    super.dispose();
  }

  /// A zoomed picture is panned, not swiped: while it is scaled up the page view
  /// has to stop taking horizontal drags, or moving the picture sideways brings
  /// the next one in instead.
  void _onViewChanged() {
    // Not `> 1`: floating-point scale settles a hair off after a reset.
    final zoomedIn = _view.value.getMaxScaleOnAxis() > 1.01;
    if (zoomedIn != _zoomedIn) setState(() => _zoomedIn = zoomedIn);
  }

  void _onPageChanged(int index) {
    _view.value = Matrix4.identity();
    setState(() => _index = index);
  }

  void _onDoubleTap() {
    if (_zoomedIn) {
      _view.value = Matrix4.identity();
      return;
    }
    // Scale about the tapped point: the point stays where the finger is, which
    // is what makes the zoom feel like it grew out of that spot. Written by
    // entry rather than through `translate`/`scale`, which are being deprecated
    // out of `Matrix4` in favour of typed variants.
    _view.value = Matrix4.identity()
      ..setEntry(0, 0, _zoom)
      ..setEntry(1, 1, _zoom)
      ..setEntry(0, 3, -_tapped.dx * (_zoom - 1))
      ..setEntry(1, 3, -_tapped.dy * (_zoom - 1));
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.paths.length > 1;

    // Black, not the page tone: a picture is shown against nothing, and the
    // theme has no business here.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            onPageChanged: _onPageChanged,
            physics: _zoomedIn
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.paths.length,
            itemBuilder: (context, index) => GestureDetector(
              // The position comes with the *down* of the second tap; the work
              // is done on the tap itself, once it is certain it was a double.
              onDoubleTapDown: (details) => _tapped = details.localPosition,
              onDoubleTap: _onDoubleTap,
              child: InteractiveViewer(
                transformationController: _view,
                minScale: 1,
                maxScale: 4,
                child: _Picture(path: widget.paths[index]),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  _GalleryButton(
                    icon: LucideIcons.x,
                    tooltip: 'Закрыть',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (many) _Counter(index: _index, total: widget.paths.length),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One picture, whole: [BoxFit.contain], so nothing is cropped away — the note's
/// own screens are where a picture is fitted to a shape.
class _Picture extends StatelessWidget {
  const _Picture({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (context, _, _) => const Center(
          child: Icon(LucideIcons.image_off, size: 44, color: Colors.white54),
        ),
      ),
    );
  }
}

/// "2 / 5". Only shown when there is more than one picture: a lone "1 / 1" says
/// nothing.
class _Counter extends StatelessWidget {
  const _Counter({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${index + 1} / $total',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The same scrim disc the note view screen puts on its cover: a button here
/// sits on an arbitrary photograph too.
class _GalleryButton extends StatelessWidget {
  const _GalleryButton({
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
