import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/auth_errors.dart';
import 'package:todo_app/auth/auth_repository.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/auth/user_profile.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
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

class _AccountPageState extends ConsumerState<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _isBusy = false;
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
      // Nothing to pop to a result: the screen watches currentUserProvider and
      // redraws itself as the account card the moment the session lands.
      _password.clear();
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _google() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;

    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final opened = await repo.signInWithGoogle();
      if (!opened && mounted) {
        setState(() => _error = 'Не удалось открыть браузер');
      }
      // A successful launch says nothing about the sign-in: the session comes
      // back over the deep link and arrives through currentUserProvider.
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _signOut() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Заметки и задачи останутся на этом устройстве'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await repo.signOut();
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = ref.watch(supabaseReadyProvider);
    final user = ref.watch(currentUserProvider);

    final title = user != null
        ? 'Аккаунт'
        : (_isSignUp ? 'Регистрация' : 'Вход');

    // A pushed route with an AppBar, like ArchivePage and AppearancePage: the
    // back arrow is the only way out. Not a FormHeader — that one is the
    // cancel/save strip of a form that *creates* something, and it put the
    // commit action in the top-right corner, far from the fields it commits.
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (!ready)
              const _Callout(
                icon: LucideIcons.cloud_off,
                tone: Color(0xFFF59E0B),
                title: 'Сервер недоступен',
                subtitle:
                    'Не удалось связаться с Supabase. Всё остальное '
                    'работает как обычно',
              )
            else if (user != null)
              _AccountCard(user: user, onSignOut: _isBusy ? null : _signOut)
            else
              _buildForm(theme),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _Callout(
                icon: LucideIcons.triangle_alert,
                tone: const Color(0xFFE05252),
                title: _error!,
              ),
            ],
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Синхронизация заметок появится позже',
                textAlign: TextAlign.center,
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

/// The signed-in half: who you are, and the way out.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user, required this.onSignOut});

  final User user;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created = DateTime.tryParse(user.createdAt)?.toLocal();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: insetSurface(theme),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(user: user, surface: insetSurface(theme), size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The name when the provider gave one, the address when it
                    // did not — a sign-up with an email carries no name at all.
                    Text(
                      user.displayName ?? user.email ?? 'Вы вошли',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    // Only worth a second line when the first one is not
                    // already the address.
                    if (user.displayName != null && user.email != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.email!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (created != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'С ${DateFormat('d MMMM y', 'ru_RU').format(created)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onSignOut,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: inkOn(
                insetSurface(theme),
                const Color(0xFFE05252),
                minContrast: 3,
              ),
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

/// The shape `_PermissionWarning` on the settings screen uses: an inset block
/// with a coloured icon and two lines. Repeated rather than shared because that
/// one is private to its own screen and carries a button this one has no use
/// for.
class _Callout extends StatelessWidget {
  const _Callout({
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String? subtitle;

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
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
