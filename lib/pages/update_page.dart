import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/update/providers.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/widgets/page_header.dart';

/// The update in full: which version, what is new, and the button at the very
/// bottom. Pressing it, the button gives way to the download's progress; a
/// failure shows its reason and the button comes back as "Повторить".
class UpdatePage extends ConsumerWidget {
  const UpdatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = AppPalette.of(theme);
    final s = ref.watch(updateProvider);
    final info = s.info;

    return Scaffold(
      backgroundColor: pageSurface(theme),
      body: SafeArea(
        child: Column(
          children: [
            const BackHeader(title: 'Обновление'),
            Expanded(
              child: info == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      children: [
                        Text(
                          'Доступное обновление v${info.versionName}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: p.textPrimary,
                          ),
                        ),
                        if (info.changelog.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            'Что нового:',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            info.changelog,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.4,
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            if (info != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: s.downloading
                    ? _Progress(percent: s.percent!)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                s.error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: p.danger),
                              ),
                            ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: ref
                                .read(updateProvider.notifier)
                                .install,
                            child: Text(
                              s.error != null ? 'Повторить' : 'Обновить',
                            ),
                          ),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where the button was: what has come down so far.
class _Progress extends StatelessWidget {
  const _Progress({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    return SizedBox(
      height: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Загрузка $percent%',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: percent / 100,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }
}
