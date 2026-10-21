import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/update/providers.dart';

/// "Доступно обновление X.Y.Z": a strip over the bottom bar with the release's
/// changelog and one button. The changelog shows three lines; when there is more,
/// "Подробнее" opens all of it (scrolling inside the strip if it is very long). While the APK comes down the button gives way to
/// a percentage and a progress line; a failure shows its reason and turns the
/// button into "Повторить". Nothing at all when there is no update.
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  static const _collapsedLines = 3;
  static const _style = TextStyle(fontSize: 12);

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(updateProvider);
    final info = s.info;
    if (info == null) return const SizedBox.shrink();

    final p = AppPalette.of(Theme.of(context));
    final notifier = ref.read(updateProvider.notifier);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(LucideIcons.download, size: 20, color: p.textPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Доступно обновление ${info.versionName}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                        ),
                      ),
                      if (s.error != null)
                        Text(
                          s.error!,
                          style: TextStyle(fontSize: 12, color: p.danger),
                        )
                      else if (info.changelog.isNotEmpty)
                        _Changelog(
                          text: info.changelog,
                          style: _style.copyWith(color: p.textSecondary),
                          linkColor: p.textPrimary,
                          collapsedLines: _collapsedLines,
                          expanded: _expanded,
                          onToggle: () =>
                              setState(() => _expanded = !_expanded),
                        ),
                    ],
                  ),
                ),
                if (s.downloading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${s.percent}%',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                  )
                else ...[
                  TextButton(
                    onPressed: notifier.install,
                    child: Text(s.error != null ? 'Повторить' : 'Обновить'),
                  ),
                  IconButton(
                    tooltip: 'Скрыть',
                    onPressed: notifier.dismiss,
                    icon: Icon(LucideIcons.x, size: 18, color: p.iconMuted),
                  ),
                ],
              ],
            ),
            if (s.downloading)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 8, 0),
                child: LinearProgressIndicator(
                  value: s.percent! / 100,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The release notes: [collapsedLines] lines, or all of them when [expanded].
/// "Подробнее" / "Свернуть" appears only when the text really is longer than
/// that, which is measured, not guessed from the length.
class _Changelog extends StatelessWidget {
  const _Changelog({
    required this.text,
    required this.style,
    required this.linkColor,
    required this.collapsedLines,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;
  final int collapsedLines;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final longer = painter.didExceedMaxLines;
        painter.dispose();

        final body = Text(
          text,
          maxLines: expanded ? null : collapsedLines,
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: style,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Very long notes scroll inside the strip rather than cover the app.
            if (expanded)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: SingleChildScrollView(child: body),
              )
            else
              body,
            if (longer)
              InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    expanded ? 'Свернуть' : 'Подробнее',
                    style: style.copyWith(
                      color: linkColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
