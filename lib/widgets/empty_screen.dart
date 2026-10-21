import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/task_palette.dart';

/// What a tab shows when it has nothing yet (`EmptyHabits`, `EmptyTasks`,
/// `EmptyJournal` .dc.html): a tinted tile with an icon, a title, a line of
/// help, optionally a few ready-made starts as chips, and a dark button.
///
/// [family] is the key of a task-palette family (`green`, `blue`, `violet`) that
/// tints the tile, so each tab keeps its own colour in both themes.
class EmptyScreen extends StatelessWidget {
  const EmptyScreen({
    super.key,
    required this.family,
    required this.icon,
    required this.title,
    required this.body,
    this.presets = const [],
    this.onPreset,
    this.actionLabel,
    this.onAction,
  });

  final String family;
  final IconData icon;
  final String title;
  final String body;

  /// "Или выберите готовую": short names offered as chips; [onPreset] gets the
  /// one that was tapped.
  final List<String> presets;
  final ValueChanged<String>? onPreset;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final swatch = taskPalette.firstWhere((s) => s.key == family);
    final dark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: dark ? swatch.darkFill : swatch.light,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(
                icon,
                size: 40,
                color: dark ? swatch.darkInk : swatch.strong,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: p.textSecondary,
              ),
            ),
            if (presets.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Или выберите готовую',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in presets)
                    Material(
                      color: p.surface,
                      shape: StadiumBorder(side: BorderSide(color: p.border)),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: onPreset == null ? null : () => onPreset!(name),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              Material(
                color: p.textPrimary,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onAction,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: 17, color: p.background),
                        const SizedBox(width: 8),
                        // Flexible: a big system font must wrap, not overflow.
                        Flexible(
                          child: Text(
                            actionLabel!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: p.background,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
