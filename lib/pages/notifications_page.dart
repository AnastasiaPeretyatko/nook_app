import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/settings/notification_settings.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';

/// Reminders, on a screen of its own: whether they come, how far ahead, and
/// what is standing in their way.
///
/// A pushed route with an `AppBar`, like `SyncPage` and `AppearancePage`, and
/// worth a screen for the same reason: the switch is never the whole story. It
/// answers to the phone as much as to the user, it can be on and refused, and
/// two separate permissions can each be missing in a way that changes what
/// arrives. The settings list keeps one row leading here and no logic of its
/// own — the line under that row is [reminderSummaryLabel], and the detail it
/// summarises lives in the rows below rather than being said twice.
///
/// **Only two rows, and both are settings of this app.** Exact alarms are a
/// permission of the phone's, and an app can neither grant nor revoke one — a
/// switch for it would look identical to the switch above and mean something
/// else entirely, which is exactly how it read. Granted, there is nothing to
/// decide and nothing worth a row; refused, the amber callout says so where the
/// consequence is and offers the one thing that can be done about it.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage>
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
    // This screen is where those trips start, which is why the observer is here
    // and not only on the settings list underneath.
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
    // lets an app take away its own permission — the system switch can only be
    // moved by hand, on the system's own screen.
    if (!enabled) return;

    final permission = ref.read(notificationPermissionProvider.notifier);
    await permission.request();
    if (!mounted) return;
    // Still refused, and the switch will not stay on until that changes.
    // Android answers a second request with a silent `false`, so there is
    // nothing left to ask and the system screen is the only place the tap can
    // still be honoured.
    if (ref.read(notificationPermissionProvider).valueOrNull == false) {
      await permission.openSystemSettings();
    }
  }

  Future<void> _pickLead() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _ReminderLeadSheet(current: ref.read(reminderLeadMinutesProvider)),
    );
    if (chosen == null) return;
    await ref.read(reminderLeadMinutesProvider.notifier).setMinutes(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remindersEnabled = ref.watch(taskRemindersEnabledProvider);
    final permission = ref.watch(notificationPermissionProvider).valueOrNull;
    final lead = ref.watch(reminderLeadMinutesProvider);
    final exactAlarms = ref.watch(exactAlarmPermissionProvider).valueOrNull;

    // What the switch shows: the wish *and* the system's answer. One that reads
    // "on" while the phone lets nothing through is a lie, and a fresh install is
    // exactly that — the wish defaults to on and the permission starts refused.
    //
    // The two stay separate underneath rather than being collapsed into one
    // stored value, because a refusal must not erase the wish: granting the
    // permission later would then have nothing to restore, and the switch would
    // have to be found and turned on a second time.
    final remindersOn = remindersEnabled && permission != false;
    // Only a definite "no" is worth a warning: null means the platform has
    // nothing to ask (desktop, tests) and loading is not yet an answer.
    final blocked = remindersEnabled && permission == false;
    // The same rule for exact alarms, and the only place they are mentioned at
    // all. Minus the case that is already covered: a device that will not post
    // anything has a louder problem than a reminder arriving late, and two
    // warnings stacked say less than one.
    final inexact = remindersOn && exactAlarms == false;

    return Scaffold(
      appBar: AppBar(title: const Text('Уведомления')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                remindersOn ? LucideIcons.bell : LucideIcons.bell_off,
              ),
              title: const Text('Включить уведомления'),
              // Says what the switch covers, since that is what makes turning
              // it off a real choice: a task with no time never reminds anyone
              // of anything, and a running timer's shade entry is not a reminder
              // and does not answer to this switch.
              subtitle: const Text('Для задач, у которых указано время'),
              value: remindersOn,
              onChanged: _setRemindersEnabled,
            ),
            // Nothing to set while nothing can arrive: a lead time under a
            // switch that is off describes a reminder that is not going to be
            // sent.
            if (remindersOn)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.clock),
                title: const Text('Напоминать за'),
                subtitle: Text(reminderLeadLabel(lead)),
                trailing: const Icon(LucideIcons.chevron_right),
                onTap: _pickLead,
              ),
            if (blocked) ...[
              const SizedBox(height: 8),
              _NotificationWarning(
                icon: LucideIcons.bell_off,
                // Says what the switch above is doing, now that it reads off
                // against the wish it still holds.
                title: 'Уведомления выключены в настройках телефона',
                message:
                    'Переключатель не включится, пока разрешение не выдано, '
                    'а выдать его само приложение не может',
                actionLabel: 'Открыть настройки системы',
                onAction: () => ref
                    .read(notificationPermissionProvider.notifier)
                    .openSystemSettings(),
              ),
            ],
            if (inexact) ...[
              const SizedBox(height: 8),
              _NotificationWarning(
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
            ],
            const SizedBox(height: 20),
            // What earns a reminder and what does not, said plainly — the rules
            // live in `taskRemindersFor` and are otherwise invisible.
            Text(
              'Напоминание приходит для каждой задачи и привычки, у которой '
              'указано время, и планируется на неделю вперёд. Отмеченный день '
              'о себе не напомнит, как и задача в архиве.',
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

/// How long before a task its reminder should come.
///
/// Pops the lead that was tapped and lets the screen store it; the sheet itself
/// knows nothing about preferences — the same split as the diary's view sheet.
class _ReminderLeadSheet extends StatelessWidget {
  const _ReminderLeadSheet({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        // A `Material` and not a painted `Container`: a `ListTile` puts its own
        // fill and its ink on the nearest `Material` above it.
        child: Material(
          color: raisedSurface(theme),
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final minutes in reminderLeadOptions)
                  _ReminderLeadTile(minutes: minutes, current: current),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderLeadTile extends StatelessWidget {
  const _ReminderLeadTile({required this.minutes, required this.current});

  final int minutes;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = minutes == current;
    // The accent read against the sheet, since the pale families are not
    // readable as their own colour.
    final accent = inkOn(raisedSurface(theme), theme.colorScheme.primary);

    return ListTile(
      onTap: () => Navigator.of(context).pop(minutes),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        reminderLeadLabel(minutes),
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          color: selected ? accent : theme.colorScheme.onSurface,
        ),
      ),
      trailing: selected
          ? Icon(LucideIcons.check, size: 20, color: accent)
          : null,
    );
  }
}
