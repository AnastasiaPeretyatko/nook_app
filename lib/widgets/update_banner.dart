import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/update/providers.dart';

/// "Доступно обновление X.Y.Z": a strip over the bottom bar with the release's
/// changelog and one button. While the APK comes down the button gives way to
/// a percentage and a progress line; a failure shows its reason and turns the
/// button into "Повторить". Nothing at all when there is no update.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                        Text(
                          info.changelog,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: p.textSecondary,
                          ),
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
