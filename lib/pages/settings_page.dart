import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/user_profile.dart';
import 'package:todo_app/pages/account_page.dart';
import 'package:todo_app/pages/groups_page.dart';
import 'package:todo_app/settings/app_version.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/widgets/page_header.dart';
import 'package:todo_app/widgets/settings/about_section.dart';
import 'package:todo_app/widgets/settings/analytics_section.dart';
import 'package:todo_app/widgets/settings/appearance_section.dart';
import 'package:todo_app/widgets/settings/notifications_section.dart';
import 'package:todo_app/widgets/user_avatar.dart';

/// Settings (`Settings.dc.html`): a pushed screen, opened from the profile
/// button on the habits tab, so it carries its own way back. Each block is a
/// section widget that watches what it needs; the page only stacks them.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Null when nobody is signed in — and also when Supabase never came up, so
    // the card reads the same on a device that has no account and on one that
    // could not reach the server.
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: pageSurface(theme),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const BackHeader(title: 'Настройки'),
            _ProfileCard(
              user: user,
              // Syncing lives on the account screen, so the card is its way in.
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AccountPage()),
              ),
            ),
            const AboutSection(),
            const AppearanceSection(),
            const AnalyticsSection(),
            const NotificationsSection(),
            // The block draws its own caption and card, and carries the margin
            // of a list: 16 + its own 8 makes the caption's 24.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: GroupsSection(),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                '$appName · Версия $appVersionLabel',
                style: TextStyle(
                  fontSize: 12,
                  color: AppPalette.of(theme).textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card at the top: who is signed in, or the way to sign in. A tap opens
/// the account screen either way.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.onTap});

  final User? user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final user = this.user;
    // Signed in, the card names the user rather than the setting — the avatar
    // already says what it is. A sign-up by email carries no name, so the
    // address is the fallback, and then there is nothing for the second line
    // to add.
    final title = user == null
        ? 'Аккаунт'
        : (user.displayName ?? user.email ?? 'Аккаунт');
    final subtitle = user == null
        ? 'Войти, чтобы синхронизировать'
        : (user.displayName != null && user.email != null
              ? user.email!
              : 'Вы вошли');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Material(
        color: palette.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                user == null
                    ? CircleAvatar(
                        radius: 26,
                        backgroundColor: palette.chip,
                        child: Icon(
                          LucideIcons.user_round,
                          color: palette.textSecondary,
                        ),
                      )
                    : UserAvatar(
                        user: user,
                        surface: theme.colorScheme.surface,
                        size: 52,
                      ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevron_right,
                  size: 16,
                  color: palette.iconMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
