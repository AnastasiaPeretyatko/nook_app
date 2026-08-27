import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/sync/first_sync.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/sync_controller.dart';
import 'package:todo_app/sync/sync_status.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';

/// Syncing, on a screen of its own: the switch, the question that gates it, and
/// the way to make a run happen now.
///
/// A pushed route with an `AppBar`, like `AccountPage` and `AppearancePage`, and
/// worth a screen rather than a settings row because the switch is never the
/// whole story. It can be out of reach for two different reasons, it can be on
/// and blocked by a question about what is already on the device, and once it
/// runs the thing people look for is not the switch at all but when it last
/// managed. The settings list keeps one row leading here and no logic of its
/// own; the line under that row and the line under this switch are the same
/// [syncSummaryLabel], so the two can never disagree.
class SyncPage extends ConsumerWidget {
  const SyncPage({super.key});

  /// Turns syncing on or off, asking about the data already here the first time
  /// this account is involved.
  ///
  /// The question comes **before** the setting is stored: a user who backs out
  /// of the dialog has not decided anything, and leaving the switch on would
  /// start a sync they never agreed to. Turning it off asks nothing.
  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    if (!enabled) {
      await ref.read(syncEnabledProvider.notifier).setEnabled(false);
      return;
    }

    final choice = await askAboutExistingData(context, ref);
    if (choice == null) return;

    await applyFirstSyncChoice(ref, choice);
    await ref.read(syncEnabledProvider.notifier).setEnabled(true);
  }

  /// The same question, reached from the callout that appears when the account
  /// has changed under a switch that was already on.
  Future<void> _decideAgain(BuildContext context, WidgetRef ref) async {
    final choice = await askAboutExistingData(context, ref);
    if (choice == null) return;
    await applyFirstSyncChoice(ref, choice);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Null when nobody is signed in — and also when Supabase never came up, so
    // the screen reads the same on a device that has no account and on one that
    // could not reach the server.
    final user = ref.watch(currentUserProvider);
    final ready = ref.watch(supabaseReadyProvider);
    final syncEnabled = ref.watch(syncEnabledProvider);
    // The stored setting is only a wish. Syncing also needs somewhere to sync
    // to, and the two are kept apart deliberately: signing out must not rewrite
    // the switch, so that it is still on when the user signs back in.
    final canSync = ready && user != null;
    final needsDecision = ref.watch(syncNeedsDecisionProvider);
    final syncActive = ref.watch(syncActiveProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Синхронизация')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                syncEnabled && canSync
                    ? LucideIcons.refresh_cw
                    : LucideIcons.cloud_off,
              ),
              title: const Text('Включить синхронизацию'),
              subtitle: Text(
                syncSummaryLabel(
                  ready: ready,
                  signedIn: user != null,
                  needsDecision: needsDecision,
                  active: syncActive,
                  status: syncStatus,
                  now: DateTime.now(),
                ),
              ),
              value: syncEnabled && canSync,
              // Null greys the row out and makes it untouchable, which is the
              // honest state: without an account there is nowhere to sync to,
              // and offering the switch would promise something it cannot do.
              onChanged: canSync
                  ? (enabled) => _setEnabled(context, ref, enabled)
                  : null,
            ),
            // Sync is wanted and possible, but what is already here was settled
            // with a different account — or with none. Nothing is sent or
            // fetched until this is answered, so the callout is not advice, it
            // is the thing standing in the way.
            if (needsDecision) ...[
              const SizedBox(height: 8),
              _SyncDecisionNeeded(onDecide: () => _decideAgain(context, ref)),
            ],
            // Worth having beyond impatience: it is the only way to find out
            // whether syncing works *now* rather than at the heartbeat's
            // convenience, which is exactly what somebody setting up a second
            // device needs.
            if (syncActive)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: syncStatus.phase == SyncPhase.running
                      ? null
                      : () => ref.read(syncControllerProvider).syncNow(),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: inkOn(
                      theme.colorScheme.surface,
                      theme.colorScheme.primary,
                    ),
                  ),
                  child: const Text('Синхронизировать сейчас'),
                ),
              ),
            const SizedBox(height: 20),
            // What travels and what does not, said plainly: a backup against
            // losing the phone, not a shared desk. A running timer is momentary
            // state and stays where it is running.
            Text(
              'Заметки, задачи и отметки дней хранятся в аккаунте и '
              'появляются на других устройствах, где выполнен вход. '
              'Запущенные таймеры остаются на этом устройстве.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when syncing is switched on but what is already on this device has not
/// been settled with the account that is signed in.
///
/// The same shape as the settings screen's permission warning, and the same
/// reason for existing: something the user asked for is not happening, and only
/// they can unblock it. Blue rather than amber — nothing is wrong, there is
/// simply a question waiting.
class _SyncDecisionNeeded extends StatelessWidget {
  const _SyncDecisionNeeded({required this.onDecide});

  final VoidCallback onDecide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = insetSurface(theme);
    final ink = inkOn(surface, const Color(0xFF4C8DF6), minContrast: 3);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.circle_question_mark, size: 20, color: ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Что делать с заметками на устройстве?',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Синхронизация не начнётся, пока вы не ответите',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onDecide,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: ink,
                  ),
                  child: const Text('Ответить'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
