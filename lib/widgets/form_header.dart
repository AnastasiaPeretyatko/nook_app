import 'package:flutter/material.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';

/// The header of a full-screen form: cancel on the left, what is being made in
/// the middle, save on the right.
///
/// Shared by the task form and the note form so the two screens the centre
/// button opens are dismissed and committed the same way. Both actions are the
/// app accent, read through [inkOn] against the page tone — the palette holds
/// pale accents (the yellow family) that would be unreadable as bare text.
///
/// The title is centred against the screen, not against what is left over
/// between the two labels: a `Stack` keeps it put when one label is wider than
/// the other.
class FormHeader extends StatelessWidget {
  const FormHeader({
    super.key,
    required this.title,
    required this.onCancel,
    required this.onSave,
    this.isBusy = false,
    this.cancelLabel = 'Отмена',
    this.saveLabel = 'Сохранить',
  });

  final String title;
  final VoidCallback onCancel;

  /// Null disables the action — the form is not in a state it can commit.
  final VoidCallback? onSave;

  /// A save in flight: the label gives way to a spinner, which is also what
  /// takes the action out of reach for a second tap.
  final bool isBusy;

  final String cancelLabel;
  final String saveLabel;

  static const double _height = 56;

  /// Keeps the title clear of the two labels. Wider than either of them, so a
  /// long title ellipsises rather than running under a button.
  static const double _sideInset = 104;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = inkOn(pageSurface(theme), theme.colorScheme.primary);

    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _sideInset),
              child: Center(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _Action(
              label: cancelLabel,
              color: accent,
              weight: FontWeight.w400,
              onPressed: onCancel,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: isBusy
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                  )
                : _Action(
                    label: saveLabel,
                    color: accent,
                    // The primary action of the two, so it reads a step
                    // heavier than "cancel".
                    weight: FontWeight.w600,
                    onPressed: onSave,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.color,
    required this.weight,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final FontWeight weight;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        // A step under the title: the actions frame it, they do not compete
        // with it.
        style: TextStyle(fontSize: 15, fontWeight: weight),
      ),
    );
  }
}
