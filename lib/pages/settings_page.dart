import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/auth/user_profile.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/pages/account_page.dart';
import 'package:todo_app/pages/appearance_page.dart';
import 'package:todo_app/pages/sync_page.dart';
import 'package:todo_app/settings/app_version.dart';
import 'package:todo_app/settings/notification_settings.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/sync_status.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/user_avatar.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Granting the permission happens in system settings, outside the app, and
    // nothing reports it back — so the answer is re-read on every return.
    if (state == AppLifecycleState.resumed) {
      ref.read(notificationPermissionProvider.notifier).refresh();
    }
  }

  Future<void> _setRemindersEnabled(bool enabled) async {
    await ref.read(taskRemindersEnabledProvider.notifier).setEnabled(enabled);
    // Turning the switch on is the user asking for notifications, which is the
    // one moment the permission can be asked for in context. Without this a
    // fresh install is never prompted at all: the lazy ask inside the reminder
    // sync waits for a task that carries a time, and until then there is
    // nothing to schedule and nothing to grant.
    if (enabled) {
      await ref.read(notificationPermissionProvider.notifier).request();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remindersEnabled = ref.watch(taskRemindersEnabledProvider);
    final permission = ref.watch(notificationPermissionProvider).valueOrNull;
    // Null when nobody is signed in — and also when Supabase never came up, so
    // the row reads the same on a device that has no account and on one that
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
    // Only a definite "no" is worth a warning: null means the platform has
    // nothing to ask (desktop, tests) and loading is not yet an answer.
    final blocked = remindersEnabled && permission == false;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Text(
              'Настройки',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              // The picture stands in for the row's icon once there is someone
              // to show: it is what makes the row read as "you" at a glance.
              leading: user == null
                  ? const Icon(LucideIcons.user_round)
                  : UserAvatar(
                      user: user,
                      surface: theme.colorScheme.surface,
                      size: 40,
                    ),
              // Signed in, the row names the user rather than the setting —
              // the avatar already says which row this is. A sign-up by email
              // carries no name, so the address is the fallback, and then
              // there is nothing left for the second line to add.
              title: Text(
                user == null
                    ? 'Аккаунт'
                    : (user.displayName ?? user.email ?? 'Аккаунт'),
              ),
              subtitle: Text(
                user == null
                    ? 'Войти, чтобы синхронизировать'
                    : (user.displayName != null && user.email != null
                          ? user.email!
                          : 'Вы вошли'),
              ),
              trailing: const Icon(LucideIcons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AccountPage())),
            ),
            // The switch itself lives on its own screen: it is out of reach for
            // two different reasons, it can be on and blocked by a question,
            // and once it runs there is a state worth reporting — none of which
            // fits under a row in a list.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                syncEnabled && canSync
                    ? LucideIcons.refresh_cw
                    : LucideIcons.cloud_off,
              ),
              title: const Text('Синхронизация'),
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
              trailing: const Icon(LucideIcons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SyncPage())),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.palette),
              title: const Text('Внешний вид'),
              subtitle: const Text('Тема оформления'),
              trailing: const Icon(LucideIcons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AppearancePage())),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(LucideIcons.bell),
              title: const Text('Уведомления задач'),
              subtitle: const Text('Напоминать в назначенное задаче время'),
              value: remindersEnabled,
              onChanged: _setRemindersEnabled,
            ),
            if (blocked) ...[
              const SizedBox(height: 8),
              _PermissionWarning(
                onOpenSettings: () => ref
                    .read(notificationPermissionProvider.notifier)
                    .openSystemSettings(),
              ),
            ],
            const SizedBox(height: 32),
            Center(
              child: Text(
                '$appName · Версия $appVersionLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when reminders are on but the system will not let anything through.
/// The app cannot ask a second time — Android answers a refused request with a
/// silent `false` — so the only way out is the system settings screen.
class _PermissionWarning extends StatelessWidget {
  const _PermissionWarning({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = insetSurface(theme);
    // Amber as ink on the surface, not as the surface: inkOn darkens or lightens
    // it until it is legible in either theme.
    final warning = inkOn(surface, const Color(0xFFF59E0B), minContrast: 3);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.bell_off, size: 20, color: warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Уведомления запрещены в настройках системы',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Напоминания не придут, пока разрешение не выдано',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onOpenSettings,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: warning,
                  ),
                  child: const Text('Открыть настройки системы'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
