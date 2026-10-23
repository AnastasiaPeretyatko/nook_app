import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/pages/update_page.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/update/providers.dart';

/// "Доступно обновление" and an arrow: a thin strip over the bottom bar. A tap
/// anywhere on it opens [UpdatePage] with the release notes and the button.
/// While the APK comes down it shows the percentage and a progress line, so the
/// download is visible after the page is closed. Nothing at all when there is no
/// update.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateProvider);
    if (s.info == null) return const SizedBox.shrink();

    final p = AppPalette.of(Theme.of(context));
    final label = s.downloading
        ? 'Загрузка обновления…'
        : s.error != null
        ? 'Не удалось обновить'
        : 'Доступно обновление';
    return Material(
      color: p.surface,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const UpdatePage())),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(LucideIcons.download, size: 18, color: p.textPrimary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: s.downloading || s.error == null
                              ? p.textPrimary
                              : p.danger,
                        ),
                      ),
                    ),
                    if (s.downloading)
                      Text(
                        '${s.percent}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                        ),
                      )
                    else
                      Icon(
                        LucideIcons.chevron_right,
                        size: 20,
                        color: p.iconMuted,
                      ),
                  ],
                ),
              ),
              if (s.downloading)
                LinearProgressIndicator(value: s.percent! / 100),
            ],
          ),
        ),
      ),
    );
  }
}
