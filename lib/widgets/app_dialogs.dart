import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';

/// The dialogs and sheets of the "Иней" design (`DialogConfirm.dc.html`,
/// `DialogActions.dc.html`, `DialogRepeat.dc.html`), so that a screen asks for
/// one by what it says and not by how it looks:
///
/// * [showConfirmDialog] — a card in the middle, an icon, two big buttons;
/// * [showTextPromptDialog] — the same card around one line of text;
/// * [showActionsSheet] — a list of actions rising from the bottom;
/// * [showOptionsSheet] — a one-of-several list rising from the bottom.

/// Asks "are you sure". True only on the main button; closing it any other way
/// is a no.
///
/// [destructive] paints the icon and the main button in the danger tone — right
/// for a deletion, wrong for a question that merely has two answers.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required String action,
  String cancel = 'Отмена',
  bool destructive = true,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DialogCard(
        icon: icon,
        destructive: destructive,
        title: title,
        body: body,
        action: action,
        cancel: cancel,
        onAction: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    ) ??
    false;

/// One line of text in the dialog card, or null when cancelled or left empty.
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  required String hint,
  required String action,
  String initial = '',
  int maxLength = 100,
  bool obscure = false,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(
      title: title,
      hint: hint,
      action: action,
      initial: initial,
      maxLength: maxLength,
      obscure: obscure,
    ),
  );
  // A password is returned exactly as typed: trimming would change it.
  final trimmed = obscure ? result : result?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// An entry of [showActionsSheet].
class SheetAction<T> {
  const SheetAction({
    required this.icon,
    required this.label,
    required this.value,
    this.destructive = false,
    this.description,
  });

  final IconData icon;
  final String label;
  final T value;

  /// A grey second line under the label.
  final String? description;

  /// Written in the danger tone — "Удалить".
  final bool destructive;
}

/// The actions of a thing, as rows of a grey card in a sheet. Returns the value
/// of the one picked, or null when the sheet was dismissed.
Future<T?> showActionsSheet<T>(
  BuildContext context, {
  String? title,
  String? subtitle,
  required List<SheetAction<T>> actions,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => AppSheet(
    children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.of(Theme.of(sheetContext)).textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppPalette.of(Theme.of(sheetContext)).textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      GreyCard(
        children: [
          for (final action in actions)
            _ActionRow(
              action: action,
              onTap: () => Navigator.of(sheetContext).pop(action.value),
            ),
        ],
      ),
    ],
  ),
);

/// A one-of-several list in a sheet: [title], then each option with a radio
/// mark at its end, the [selected] one filled. Tapping an option answers at
/// once.
///
/// The answer is wrapped in a record so that picking the null option ("Личная
/// задача") is told apart from closing the sheet, which gives null itself.
Future<(T,)?> showOptionsSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) => showModalBottomSheet<(T,)>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) {
    final palette = AppPalette.of(Theme.of(sheetContext));
    return AppSheet(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: palette.textPrimary,
            ),
          ),
        ),
        GreyCard(
          children: [
            for (final (value, label) in options)
              InkWell(
                onTap: () => Navigator.of(sheetContext).pop((value,)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 58),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        _RadioMark(selected: value == selected),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  },
);

/// The frame every sheet shares: top corners 28, a handle, room at the bottom
/// for the system bar. [children] are laid out 12px apart.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Material(
        color: raisedSurface(theme),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.of(theme).outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                for (final child in children) ...[
                  const SizedBox(height: 12),
                  child,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A grey rounded card of rows with a hairline between them.
class GreyCard extends StatelessWidget {
  const GreyCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Material(
      color: palette.surfaceMuted,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: theme.brightness == Brightness.dark
            ? BorderSide(color: palette.border)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0)
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: palette.border,
                ),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionRow<T> extends StatelessWidget {
  const _ActionRow({required this.action, required this.onTap});

  final SheetAction<T> action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    final tone = action.destructive ? palette.danger : palette.textPrimary;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                action.icon,
                size: 20,
                color: action.destructive
                    ? palette.danger
                    : palette.textSecondary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: action.destructive
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: tone,
                      ),
                    ),
                    if (action.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        action.description!,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
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

class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? palette.textPrimary : palette.outline,
          width: selected ? 2 : 1.5,
        ),
      ),
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.textPrimary,
              ),
            )
          : null,
    );
  }
}

/// The card both dialogs sit in: corners 28, centred, padded 24/20/20.
class _DialogShell extends StatelessWidget {
  const _DialogShell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: raisedSurface(theme),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: const Color(0xFF1B2230).withValues(alpha: 0.22),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// A 52px button of a dialog: filled for the main answer, outlined for the
/// other.
class _DialogButton extends StatelessWidget {
  const _DialogButton({required this.label, required this.onTap, this.fill});

  final String label;
  final VoidCallback onTap;

  /// Null draws the outlined, plain button.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    final filled = fill != null;
    return SizedBox(
      height: 52,
      child: Material(
        color: filled ? fill : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: filled
              ? BorderSide.none
              : BorderSide(color: palette.borderStrong),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: filled ? onBrandFill(fill!) : palette.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogCard extends StatelessWidget {
  const _DialogCard({
    required this.icon,
    required this.destructive,
    required this.title,
    required this.body,
    required this.action,
    required this.cancel,
    required this.onAction,
    required this.onCancel,
  });

  final IconData icon;
  final bool destructive;
  final String title;
  final String body;
  final String action;
  final String cancel;
  final VoidCallback onAction;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return _DialogShell(
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: destructive ? palette.dangerSoft : palette.chip,
            ),
            child: Icon(
              icon,
              size: 24,
              color: destructive ? palette.danger : palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        _DialogButton(
          label: action,
          fill: destructive ? palette.danger : palette.textPrimary,
          onTap: onAction,
        ),
        const SizedBox(height: 8),
        _DialogButton(label: cancel, onTap: onCancel),
      ],
    );
  }
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.hint,
    required this.action,
    required this.initial,
    required this.maxLength,
    required this.obscure,
  });

  final String title;
  final String hint;
  final String action;
  final String initial;
  final int maxLength;
  final bool obscure;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return _DialogShell(
      children: [
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          obscureText: widget.obscure,
          textCapitalization: widget.obscure
              ? TextCapitalization.none
              : TextCapitalization.sentences,
          style: TextStyle(fontSize: 15, color: palette.textPrimary),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: widget.hint,
            counterText: '',
            filled: true,
            fillColor: insetSurface(theme),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            hintStyle: TextStyle(fontSize: 15, color: palette.textTertiary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _DialogButton(
          label: widget.action,
          fill: palette.textPrimary,
          onTap: _submit,
        ),
        const SizedBox(height: 8),
        _DialogButton(
          label: 'Отмена',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Icons the callers pick from, so the shared ones read the same everywhere.
abstract final class DialogIcons {
  static const delete = LucideIcons.trash_2;
  static const leave = LucideIcons.log_out;
  static const removeMember = LucideIcons.user_minus;
  static const warning = LucideIcons.triangle_alert;
}
