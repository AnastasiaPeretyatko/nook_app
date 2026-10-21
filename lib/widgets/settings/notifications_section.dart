import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/settings/notification_settings.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/list_card.dart';

/// "Уведомления" of the settings list: whether reminders come, how far ahead,
/// and what is standing in their way.
///
/// The switch is never the whole story. It answers to the phone as much as to
/// the user, it can be on and refused, and two separate permissions can each be
/// missing in a way that changes what arrives — which is why the warnings sit
/// under the card.
///
/// **Exact alarms get no row.** They are a permission of the phone's, which an
/// app can neither grant nor revoke; a switch for it would look identical to
/// the one above and mean something else. Refused, the amber callout says so
/// where the consequence is and offers the one thing that can be done.
class NotificationsSection extends ConsumerStatefulWidget {
  const NotificationsSection({super.key});

  @override
  ConsumerState<NotificationsSection> createState() =>
      _NotificationsSectionState();
}

class _NotificationsSectionState extends ConsumerState<NotificationsSection>
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
    // Both permissions are granted on a system screen, outside the app, and
    // nothing reports it back — so both answers are re-read on every return.
    if (state == AppLifecycleState.resumed) {
      ref.read(notificationPermissionProvider.notifier).refresh();
      ref.read(exactAlarmPermissionProvider.notifier).refresh();
    }
  }

  Future<void> _setRemindersEnabled(bool enabled) async {
    await ref.read(taskRemindersEnabledProvider.notifier).setEnabled(enabled);
    // Turning the switch on is the user asking for notifications, which is the
    // one moment the permission can be asked for in context. Without this a
    // fresh install is never prompted at all: the lazy ask inside the reminder
    // sync waits for a task that carries a time, and until then there is
    // nothing to schedule and nothing to grant.
    //
    // Turning it off asks for nothing and revokes nothing. Neither platform
    // lets an app take away its own permission.
    if (!enabled) return;

    final permission = ref.read(notificationPermissionProvider.notifier);
    await permission.request();
    if (!mounted) return;
    // Still refused: Android answers a second request with a silent `false`,
    // so the system screen is the only place the tap can still be honoured.
    if (ref.read(notificationPermissionProvider).valueOrNull == false) {
      await permission.openSystemSettings();
    }
  }

  Future<void> _pickLead() async {
    final chosen = await showOptionsSheet<int>(
      context,
      title: 'Напоминать заранее',
      options: [for (final m in reminderLeadOptions) (m, reminderLeadLabel(m))],
      selected: ref.read(reminderLeadMinutesProvider),
    );
    if (chosen == null) return;
    await ref.read(reminderLeadMinutesProvider.notifier).setMinutes(chosen.$1);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    final remindersEnabled = ref.watch(taskRemindersEnabledProvider);
    final permission = ref.watch(notificationPermissionProvider).valueOrNull;
    final lead = ref.watch(reminderLeadMinutesProvider);
    final exactAlarms = ref.watch(exactAlarmPermissionProvider).valueOrNull;

    // What the switch shows: the wish *and* the system's answer. One that reads
    // "on" while the phone lets nothing through is a lie, and a fresh install is
    // exactly that — the wish defaults to on and the permission starts refused.
    // The two stay separate underneath, so that granting the permission later
    // has a wish to restore.
    final remindersOn = remindersEnabled && permission != false;
    // Only a definite "no" is worth a warning: null means the platform has
    // nothing to ask (desktop, tests) and loading is not yet an answer.
    final blocked = remindersEnabled && permission == false;
    // Minus the case already covered: a device that will not post anything has
    // a louder problem than a reminder arriving late.
    final inexact = remindersOn && exactAlarms == false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(title: 'Уведомления'),
        RowsCard(
          dividerIndent: 16,
          children: [
            // Says what the switch covers: a task with no time never reminds
            // anyone, and a running timer's shade entry does not answer to it.
            ToggleRow(
              label: 'Напоминания',
              sub: 'Для задач, у которых указано время',
              value: remindersOn,
              onChanged: _setRemindersEnabled,
            ),
            // Nothing to set while nothing can arrive.
            if (remindersOn)
              InkWell(
                onTap: _pickLead,
                child: SizedBox(
                  height: 54,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Напоминать заранее',
                            style: TextStyle(
                              fontSize: 15,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          reminderLeadLabel(lead),
                          style: TextStyle(
                            fontSize: 15,
                            color: palette.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
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
          ],
        ),
        if (blocked)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _NotificationWarning(
              icon: LucideIcons.bell_off,
              title: 'Уведомления выключены в настройках телефона',
              message:
                  'Переключатель не включится, пока разрешение не выдано, '
                  'а выдать его само приложение не может',
              actionLabel: 'Открыть настройки системы',
              onAction: () => ref
                  .read(notificationPermissionProvider.notifier)
                  .openSystemSettings(),
            ),
          ),
        if (inexact)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _NotificationWarning(
              icon: LucideIcons.alarm_clock,
              title: 'Напоминания приходят с опозданием',
              message:
                  'Система откладывает неточные будильники, чтобы экономить '
                  'заряд. Разрешите точное время, чтобы они приходили минута '
                  'в минуту',
              actionLabel: 'Разрешить точное время',
              onAction: () =>
                  ref.read(exactAlarmPermissionProvider.notifier).request(),
            ),
          ),
        // What earns a reminder and what does not — the rules live in
        // `taskRemindersFor` and are otherwise invisible.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Text(
            'Напоминание приходит для каждой задачи и привычки, у которой '
            'указано время, и планируется на неделю вперёд. Отмеченный день '
            'о себе не напомнит, как и задача в архиве.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// A reminder setting that is on and going nowhere, or arriving late.
///
/// One widget for both, because they are the same shape and the same amber, and
/// they say the same kind of thing: the app asked the system for something and
/// was refused, and the way out is on a system screen rather than in here.
class _NotificationWarning extends StatelessWidget {
  const _NotificationWarning({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

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
          Icon(icon, size: 20, color: warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: warning,
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
