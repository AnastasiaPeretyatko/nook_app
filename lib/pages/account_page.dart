import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/auth/auth_errors.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/auth_user.dart';
import 'package:todo_app/auth/google_id_token.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/push/push_registration.dart';
import 'package:todo_app/push/push_service.dart';
import 'package:todo_app/sync/first_sync.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/sync_controller.dart';
import 'package:todo_app/sync/sync_service.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/sync/sync_status.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/list_card.dart';
import 'package:todo_app/widgets/app_toast.dart';
import 'package:todo_app/widgets/page_header.dart';
import 'package:todo_app/widgets/user_avatar.dart';

/// The account: signing in, signing up, and signing out.
///
/// One pushed route for all three, the way [CreateNotePage] is one screen for
/// writing a note and for editing one — the form and the account card differ in
/// what they show, not in how they are reached.
///
/// Deliberately **not** a gate in front of the app. The whole point of the local
/// database is that it needs nobody's permission, so signing in is something
/// found in settings, not something the first launch demands.
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

enum _Mode { signIn, signUp }

/// How the user proves it is them before the account is deleted.
enum _ConfirmWith { password, google }

/// What "выйти" was asked to do with what is on the phone.
enum _SignOutChoice { keep, wipe }

class _AccountPageState extends ConsumerState<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _isBusy = false;

  /// What the full-screen spinner says while [_isBusy].
  String _busyLabel = '';

  /// Signed in and on the way out of this screen. The session has already
  /// landed, so the screen would redraw itself as the account card for the few
  /// frames the closing animation takes — a flash of a page nobody asked for.
  /// While this is set it keeps showing the form (under the spinner) instead.
  bool _leaving = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == _Mode.signUp;

  void _switchMode() {
    setState(() {
      _mode = _isSignUp ? _Mode.signIn : _Mode.signUp;
      _error = null;
    });
    // The fields keep what was typed: someone who mistyped their way into
    // "already registered" is one tap from signing in with the same pair.
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;

    setState(() {
      _isBusy = true;
      _busyLabel = _isSignUp ? 'Создаём аккаунт…' : 'Входим…';
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final password = _password.text;
      if (_isSignUp) {
        await repo.signUp(email: email, password: password);
      } else {
        await repo.signInWithPassword(email: email, password: password);
      }
      _password.clear();
      _leaveToApp();
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted && !_leaving) setState(() => _isBusy = false);
    }
  }

  /// Signed in: back to the app itself (the settings and this screen are pushed
  /// on top of it), rather than leaving the user looking at the form they just
  /// filled in. Syncing is switched on from the account screen, one tap away.
  void _leaveToApp() {
    if (!mounted) return;
    setState(() => _leaving = true);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _google() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;

    setState(() {
      _isBusy = true;
      _busyLabel = 'Входим через Google…';
      _error = null;
    });
    try {
      final idToken = await ref.read(googleIdTokenProvider)();
      // Null: the user closed the sheet. Not an error, so nothing is shown.
      if (idToken != null) {
        await repo.signInWithGoogle(idToken);
        _leaveToApp();
      }
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted && !_leaving) setState(() => _isBusy = false);
    }
  }

  /// Signing out, with or without leaving the data behind.
  ///
  /// Two answers rather than one, and the default is still the old behaviour:
  /// this app works without an account, so somebody who signed in to look
  /// around and signed out again must not lose what they wrote. Clearing is
  /// offered, never assumed.
  ///
  /// The other half of the protection is not here at all — it is on the way
  /// **in**, in [askAboutExistingData]: a device whose data belongs to another
  /// account cannot be left as it is when somebody else signs in. That is the
  /// moment the leak would happen, so that is where the choice is forced.
  Future<void> _signOut() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;
    final overlay = Overlay.of(context, rootOverlay: true);

    final choice = await _askHowToLeave();
    if (choice == null) return;

    setState(() => _error = null);
    try {
      if (choice == _SignOutChoice.wipe && !await _clearDevice()) return;
      _setBusy('Выходим…');
      // While the session still authorises it: afterwards the phone would keep
      // getting this account's pushes.
      await unregisterDevice(
        ref.read(syncApiProvider),
        ref.read(pushServiceProvider),
      );
      await repo.signOut();
      showAppToast(
        overlay,
        message: 'Вы вышли из аккаунта',
        icon: LucideIcons.log_out,
        duration: const Duration(seconds: 3),
      );
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      _setBusy(null);
    }
  }

  /// Shows (or hides) the full-screen spinner. Only around work that is being
  /// done — never while a dialog waits for the user, who would be looking at a
  /// spinner that is not spinning for anything.
  void _setBusy(String? label) {
    if (!mounted) return;
    setState(() {
      _isBusy = label != null;
      _busyLabel = label ?? '';
    });
  }

  /// Deleting the account for good: a warning, then the password.
  ///
  /// The server is asked first and the phone wiped only once it has agreed —
  /// the other order would leave a signed-in account with an empty phone if the
  /// request failed. The data goes from the phone as well, or the next sign-in
  /// would offer "another account's data" that no account owns any more.
  Future<void> _deleteAccount() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;
    final overlay = Overlay.of(context, rootOverlay: true);

    final sure = await showConfirmDialog(
      context,
      icon: DialogIcons.delete,
      title: 'Удалить аккаунт?',
      body:
          'Аккаунт, его данные на сервере и данные на этом телефоне будут '
          'стёрты без возможности вернуть.\n\nГруппы, которые вы вели, '
          'удалятся; в остальных группах ваши задачи останутся без имени.',
      action: 'Продолжить',
      cancel: 'Не удалять',
    );
    if (!sure || !mounted) return;

    // The app does not know whether this account has a password or is Google's,
    // so the user says how to prove it.
    final how = await showActionsSheet<_ConfirmWith>(
      context,
      title: 'Подтвердите удаление',
      actions: const [
        SheetAction(
          icon: LucideIcons.lock,
          label: 'Ввести пароль',
          description: 'Если вы входили по почте',
          value: _ConfirmWith.password,
        ),
        SheetAction(
          icon: LucideIcons.user,
          label: 'Войти через Google',
          description: 'Если вы входили через Google',
          value: _ConfirmWith.google,
        ),
      ],
    );
    if (how == null || !mounted) return;

    String? password;
    if (how == _ConfirmWith.password) {
      password = await showTextPromptDialog(
        context,
        title: 'Введите пароль',
        hint: 'Пароль',
        action: 'Удалить аккаунт',
        maxLength: 128,
        obscure: true,
      );
      if (password == null) return;
    }

    setState(() {
      _isBusy = true;
      _busyLabel = 'Удаляем аккаунт…';
      _error = null;
    });
    try {
      String? idToken;
      if (how == _ConfirmWith.google) {
        // Fresh from Google: the server will not take an old one for this.
        idToken = await ref.read(googleIdTokenProvider)();
        if (idToken == null) return; // closed the sheet
      }
      await repo.deleteAccount(password: password, idToken: idToken);
      await forgetAccountData(ref);
      showAppToast(
        overlay,
        message: 'Аккаунт удалён',
        duration: const Duration(seconds: 4),
      );
    } catch (error) {
      if (mounted) setState(() => _error = deleteAccountErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Two rows rather than two buttons: "выйти" and "выйти и стереть" are not a
  /// yes and a stronger yes, they are different actions, and each needs its
  /// sentence under it.
  Future<_SignOutChoice?> _askHowToLeave() => showActionsSheet<_SignOutChoice>(
    context,
    title: 'Выйти из аккаунта?',
    actions: const [
      SheetAction(
        icon: LucideIcons.log_out,
        label: 'Просто выйти',
        description: 'Заметки и задачи останутся на этом устройстве',
        value: _SignOutChoice.keep,
      ),
      SheetAction(
        icon: LucideIcons.trash_2,
        label: 'Выйти и стереть',
        description: 'Отправить последние изменения и удалить всё с телефона',
        value: _SignOutChoice.wipe,
        destructive: true,
      ),
    ],
  );

  /// Sends what is waiting, then removes it. Returns whether to go on and sign
  /// out.
  ///
  /// **Sync first, and wipe only if it worked.** The device is about to stop
  /// being a copy of anything, so a run that failed means the last edits exist
  /// here and nowhere else — deleting them then is not "clearing the device",
  /// it is losing data. The user is told which of the two happened and decides.
  ///
  /// A device where syncing was never on has no server copy at all, and no
  /// amount of syncing now would make one: the switch is off, so
  /// [SyncController.syncNow] returns `skipped` without attempting anything.
  /// That case gets the plain "this cannot be undone" confirmation instead of a
  /// false reassurance.
  Future<bool> _clearDevice() async {
    if (ref.read(syncActiveProvider)) {
      _setBusy('Отправляем изменения…');
      final outcome = await ref.read(syncControllerProvider).syncNow();
      _setBusy(null);
      if (outcome != SyncOutcome.done) {
        if (!mounted) return false;
        if (!await _confirmWipeAfterFailure(outcome)) return false;
      }
    } else {
      if (!mounted) return false;
      final notes = await ref.read(diaryDaoProvider).entryCount();
      final tasks = await ref.read(tasksDaoProvider).taskCount();
      if (notes == 0 && tasks == 0) return true;
      if (!mounted) return false;
      if (!await confirmWipe(context, notes: notes, tasks: tasks)) return false;
    }

    if (!mounted) return false;
    _setBusy('Стираем данные…');
    await forgetAccountData(ref);
    return true;
  }

  /// The last send did not land. Says so plainly and asks again.
  Future<bool> _confirmWipeAfterFailure(SyncOutcome outcome) async {
    return showConfirmDialog(
      context,
      icon: DialogIcons.warning,
      title: 'Последние изменения не отправлены',
      body: outcome == SyncOutcome.offline
          ? 'Нет связи с сервером, поэтому часть данных есть только на этом '
                'телефоне.\n\nЕсли стереть сейчас, они пропадут совсем.'
          : 'Сервер не принял последние изменения, поэтому часть данных есть '
                'только на этом телефоне.\n\nЕсли стереть сейчас, они '
                'пропадут совсем.',
      action: 'Всё равно стереть',
      cancel: 'Не стирать',
    );
  }

  /// Turns syncing on, asking about the data already here the first time this
  /// account is involved.
  ///
  /// The question comes **before** the setting is stored: a user who backs out
  /// of the dialog has not decided anything, and leaving it on would start a sync
  /// they never agreed to.
  Future<void> _enableSync() async {
    final choice = await askAboutExistingData(context, ref);
    if (choice == null) return;
    await applyFirstSyncChoice(ref, choice);
    await ref.read(syncEnabledProvider.notifier).setEnabled(true);
  }

  /// The same question, reached from the card that appears when the account has
  /// changed under a switch that was already on. True when it was answered —
  /// answering is what lets syncing start, so the card shows it working.
  ///
  /// A failure is shown rather than swallowed: this button used to do nothing
  /// at all when the question could not be asked.
  Future<bool> _decideAgain() async {
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      final choice = await askAboutExistingData(context, ref);
      if (choice == null) return false;
      await applyFirstSyncChoice(ref, choice);
      return true;
    } catch (error) {
      showAppToast(
        overlay,
        message: 'Не удалось начать синхронизацию',
        detail: error.toString(),
        isError: true,
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _leaving ? null : ref.watch(currentUserProvider);

    final title = user != null
        ? 'Аккаунт'
        : (_isSignUp ? 'Регистрация' : 'Вход');

    // A pushed route with its own header, like the group screen: a round back
    // button, the title in the middle. Deliberately **not** a gate in front of
    // the app, so the way back is always there.
    return PopScope(
      // Mid-request the way back is shut: leaving would not stop the request,
      // only hide what it did.
      canPop: !_isBusy,
      child: Scaffold(
        backgroundColor: pageSurface(theme),
        body: Stack(
          children: [
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  BackHeader(title: title),
                  if (user != null) ...[
                    _Profile(user: user),
                    _SyncCard(onEnable: _enableSync, onDecide: _decideAgain),
                    const _SyncToggles(),
                    _SignOutBlock(
                      onSignOut: _isBusy ? null : _signOut,
                      onDelete: _isBusy ? null : _deleteAccount,
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _buildForm(theme),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _Callout(
                        icon: LucideIcons.triangle_alert,
                        tone: const Color(0xFFE05252),
                        title: _error!,
                      ),
                    ),
                ],
              ),
            ),
            if (_isBusy && _busyLabel.isNotEmpty) _BusyOverlay(_busyLabel),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final accent = inkOn(theme.colorScheme.surface, theme.colorScheme.primary);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _email,
            enabled: !_isBusy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: _fieldDecoration(
              theme,
              label: 'Почта',
              icon: LucideIcons.mail,
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Введите почту';
              // Deliberately loose: the server is the authority on what an
              // address is, and a strict pattern here only ever turns away
              // addresses that in fact work.
              if (!text.contains('@') || !text.contains('.')) {
                return 'Проверьте адрес почты';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            enabled: !_isBusy,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            autofillHints: [
              _isSignUp ? AutofillHints.newPassword : AutofillHints.password,
            ],
            onFieldSubmitted: (_) => _submit(),
            decoration: _fieldDecoration(
              theme,
              label: 'Пароль',
              icon: LucideIcons.lock,
              suffix: IconButton(
                icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eye_off),
                iconSize: 20,
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (value) {
              final text = value ?? '';
              if (text.isEmpty) return 'Введите пароль';
              if (_isSignUp && text.length < 6) {
                return 'Пароль не короче 6 символов';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isBusy ? null : _submit,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              // The label gives way to a spinner, which is also what puts the
              // action out of reach of a second tap — the same bargain
              // FormHeader.isBusy strikes on the two full-screen forms.
              child: _isBusy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: onBrandFill(theme.colorScheme.primary),
                      ),
                    )
                  : Text(_isSignUp ? 'Создать аккаунт' : 'Войти'),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'или',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _isBusy ? null : _google,
              // Lucide is a stroke set with no brand marks, so there is no
              // Google glyph to reach for. A globe is at least honest about
              // what the button does: it opens a browser.
              icon: const Icon(LucideIcons.globe, size: 20),
              label: const Text('Войти через Google'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isBusy ? null : _switchMode,
            style: TextButton.styleFrom(foregroundColor: accent),
            child: Text(
              _isSignUp
                  ? 'Уже есть аккаунт? Войти'
                  : 'Нет аккаунта? Зарегистрироваться',
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(
    ThemeData theme, {
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: insetSurface(theme),
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}

/// Who you are: the picture, the name, the address.
class _Profile extends StatelessWidget {
  const _Profile({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        children: [
          UserAvatar(user: user, surface: pageSurface(theme), size: 80),
          const SizedBox(height: 10),
          // The name when the provider gave one, the address when it did not —
          // a sign-up with an email carries no name at all.
          Text(
            user.displayName ?? user.email,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          // Only worth a second line when the first one is not already it.
          if (user.displayName != null) ...[
            const SizedBox(height: 2),
            Text(
              user.email,
              style: TextStyle(fontSize: 14, color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// A dimmed screen with a spinner and one line, over everything while a request
/// is in flight. A server that was asleep takes seconds to answer, and the small
/// spinner on a button is easy to miss — this one says plainly that the tap
/// worked and something is happening.
class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Stack(
      children: [
        const ModalBarrier(color: Color(0x66000000), dismissible: false),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: raisedSurface(theme),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Where syncing stands, and the button for the next step: turn it on, answer
/// the question, or sync now.
class _SyncCard extends ConsumerStatefulWidget {
  const _SyncCard({required this.onEnable, required this.onDecide});

  final VoidCallback onEnable;
  final Future<bool> Function() onDecide;

  @override
  ConsumerState<_SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends ConsumerState<_SyncCard> {
  /// A press shows the spinner for at least this long. A run with nothing to
  /// send ends in a fraction of a second, and a button that flickers once looks
  /// like a button that did nothing.
  static const _minSpinner = Duration(seconds: 2);

  bool _pressed = false;

  /// Keeps the spinner up until [work] is done *and* [_minSpinner] has passed.
  Future<void> _hold(Future<Object?> work) async {
    setState(() => _pressed = true);
    await Future.wait([work, Future<void>.delayed(_minSpinner)]);
    if (mounted) setState(() => _pressed = false);
  }

  Future<void> _decide() async {
    if (await widget.onDecide()) await _hold(Future.value());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final user = ref.watch(currentUserProvider);
    final enabled = ref.watch(syncEnabledProvider);
    final needsDecision = ref.watch(syncNeedsDecisionProvider);
    final status = ref.watch(syncStatusProvider);
    final claim = ref.watch(syncClaimProvider);
    final info = syncCardInfo(
      enabled: enabled,
      needsDecision: needsDecision,
      // A claim naming somebody else means the data here was written under
      // another account: a warning, not a question.
      changingHands: claim != null && claim != user?.id,
      auto: ref.watch(syncAutoProvider),
      status: status,
      now: DateTime.now(),
    );

    // The tone as a tile: a light fill and a stronger glyph, from the palette
    // families so both themes read.
    final surface = raisedSurface(theme);
    final (Color fill, Color ink, IconData icon) = switch (info.tone) {
      SyncCardTone.ok => _tile(
        theme,
        surface,
        'green',
        LucideIcons.cloud_check,
      ),
      SyncCardTone.attention => _tile(
        theme,
        surface,
        'blue',
        LucideIcons.circle_question_mark,
      ),
      SyncCardTone.error => (
        palette.dangerSoft,
        palette.danger,
        LucideIcons.cloud_alert,
      ),
      SyncCardTone.neutral => (
        palette.chip,
        palette.textSecondary,
        enabled ? LucideIcons.cloud : LucideIcons.cloud_off,
      ),
    };

    final running = _pressed || status.phase == SyncPhase.running;
    final String label;
    final VoidCallback? action;
    if (!enabled) {
      label = 'Включить синхронизацию';
      action = widget.onEnable;
    } else if (needsDecision) {
      label = 'Синхронизировать';
      action = running ? null : _decide;
    } else {
      label = 'Синхронизировать сейчас';
      action = running
          ? null
          : () => _hold(ref.read(syncControllerProvider).syncNow());
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 20, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Selectable: when the server refuses, the point of its
                    // words is to be sent to somebody.
                    SelectableText(
                      info.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: palette.borderStrong),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onTap: action,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (running)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          enabled && !needsDecision
                              ? LucideIcons.refresh_cw
                              : LucideIcons.cloud,
                          size: 16,
                          color: action == null
                              ? palette.textTertiary
                              : palette.textPrimary,
                        ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: action == null
                                ? palette.textTertiary
                                : palette.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A palette family's light tone and glyph tone for the status tile.
  static (Color, Color, IconData) _tile(
    ThemeData theme,
    Color surface,
    String family,
    IconData icon,
  ) {
    final accent = taskColorForKey(family);
    final fill = taskBadgeSurface(theme, accent, surface);
    return (fill, taskBadgeInk(theme, accent, fill), icon);
  }
}

/// The three switches of how syncing behaves. Shown once syncing is on: before
/// that there is nothing to configure.
class _SyncToggles extends ConsumerWidget {
  const _SyncToggles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(syncEnabledProvider)) return const SizedBox.shrink();
    final auto = ref.watch(syncAutoProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(title: 'Синхронизация'),
        RowsCard(
          dividerIndent: 16,
          children: [
            ToggleRow(
              label: 'Автоматически',
              sub: 'Сохранять изменения в облако сразу',
              value: auto,
              onChanged: (v) async {
                await ref.read(syncAutoProvider.notifier).setValue(v);
                // Switched on, the changes made meanwhile should not wait for
                // the next timer.
                if (v) await ref.read(syncControllerProvider).syncNow();
              },
            ),
            ToggleRow(
              label: 'Только по Wi-Fi',
              sub: 'Не тратить мобильный интернет',
              value: ref.watch(syncWifiOnlyProvider),
              // It only holds back the automatic runs, so with those off there
              // is nothing for it to hold back.
              onChanged: auto
                  ? (v) => ref.read(syncWifiOnlyProvider.notifier).setValue(v)
                  : null,
            ),
            ToggleRow(
              label: 'Синхронизировать Дневник',
              sub: 'Заметки тоже будут на всех устройствах',
              value: ref.watch(syncDiaryProvider),
              onChanged: (v) => ref.read(syncDiarySetterProvider)(v),
            ),
            // Only for someone who tracks a cycle: for everybody else there is
            // nothing to send and the row would be noise. Off by default — it is
            // health data, and it is the user's call when it leaves the phone.
            if (ref.watch(aboutSettingsProvider).cycleOn)
              ToggleRow(
                label: 'Синхронизировать цикл',
                sub:
                    'Отметки цикла будут на всех устройствах. Видны только вам',
                value: ref.watch(syncCycleProvider),
                onChanged: (v) => ref.read(syncCycleSetterProvider)(v),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Выйти из аккаунта" and what it does to the data.
class _SignOutBlock extends StatelessWidget {
  const _SignOutBlock({required this.onSignOut, required this.onDelete});

  final VoidCallback? onSignOut;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: palette.border),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: onSignOut,
                child: Center(
                  child: Text(
                    'Выйти из аккаунта',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: onSignOut == null
                          ? palette.textTertiary
                          : palette.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Данные на телефоне останутся. Новые изменения перестанут '
            'сохраняться в облако.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onDelete,
            child: Text(
              'Удалить аккаунт',
              style: TextStyle(
                fontSize: 14,
                color: inkOn(
                  palette.surface,
                  Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration(ThemeData theme) => BoxDecoration(
  color: raisedSurface(theme),
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: AppPalette.of(theme).border),
);

/// The shape `_PermissionWarning` on the settings screen uses: an inset block
/// with a coloured icon and two lines. Repeated rather than shared because that
/// one is private to its own screen and carries a button this one has no use
/// for.
class _Callout extends StatelessWidget {
  const _Callout({required this.icon, required this.tone, required this.title});

  final IconData icon;
  final Color tone;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = insetSurface(theme);
    // The colour as ink on the surface, never as the surface: inkOn walks it
    // until it is legible in either theme.
    final ink = inkOn(surface, tone, minContrast: 3);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: ink),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
