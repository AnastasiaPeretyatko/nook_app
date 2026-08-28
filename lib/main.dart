import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/pages/create_note_page.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/pages/diary_page.dart';
import 'package:todo_app/pages/habits_page.dart';
import 'package:todo_app/pages/home_page.dart';
import 'package:todo_app/pages/settings_page.dart';
import 'package:todo_app/home_widget/home_widget_scope.dart';
import 'package:todo_app/home_widget/providers.dart';
import 'package:todo_app/home_widget/widget_actions.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/notifications/task_reminder.dart';
import 'package:todo_app/notifications/timer_notification.dart';
import 'package:todo_app/settings/app_version.dart';
import 'package:todo_app/settings/notification_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/sync_controller.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/app_bottom_nav_bar.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  final prefs = await SharedPreferences.getInstance();
  // Awaited, but it never throws and never waits on the network: an account is
  // an extra, and a launch with no connection has to reach the same screens it
  // always does.
  final supabaseReady = await initSupabase();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseReadyProvider.overrideWithValue(supabaseReady),
      ],
      child: const MyApp(),
    ),
  );
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with SingleTickerProviderStateMixin {
  /// The diary's slot in [_pages]. The centre button reads it to decide what it
  /// creates, so the two lists and this constant have to stay in step.
  static const int _diaryIndex = 2;

  /// The schedule's slot in [_pages] — where a tap on the home-screen widget
  /// lands, that being the screen the widget is a small copy of.
  static const int _homeIndex = 0;

  /// One tab change, start to finish — the same 300ms the nav bar's indicator
  /// takes to slide, so the bar and the page it points at arrive together.
  static const Duration _tabMotion = Duration(milliseconds: 300);

  int _currentIndex = 1;

  /// The tab being left behind, kept only for as long as it is still painted.
  int _leavingIndex = 1;

  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: _tabMotion,
    // Settled: the first frame is a page already in place, not one arriving.
    value: 1,
  );

  static const List<Widget> _pages = [
    HomePage(),
    HabitsPage(),
    DiaryPage(),
    SettingsPage(),
  ];

  static const List<AppNavItem> _navItems = [
    AppNavItem(icon: LucideIcons.house, label: 'Home'),
    AppNavItem(icon: LucideIcons.repeat, label: 'Привычки'),
    AppNavItem(icon: LucideIcons.book_open, label: 'Дневник'),
    AppNavItem(icon: LucideIcons.settings, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    // Taps on the home-screen widget that mean "open the app somewhere". They
    // are reported by `HomeWidgetScope` above this screen, because a launch has
    // to be caught before any screen is on it; acting on one needs a tab and a
    // navigator, which only this screen has.
    ref.listenManual<WidgetTapRequest?>(widgetTapProvider, (_, request) {
      switch (request?.action) {
        case WidgetTapAction.open:
          _selectTab(_homeIndex);
        case WidgetTapAction.create:
          _openTaskForm();
        case _:
          break;
      }
    });
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _leavingIndex = _currentIndex;
      _currentIndex = index;
    });
    _motion.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      // Rebuilt every frame of the motion, and that costs nothing: the four
      // pages are `const`, so the framework skips their subtrees and only these
      // wrappers are built again.
      body: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) => Stack(
          children: [for (var i = 0; i < _pages.length; i++) _tabPage(i)],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        items: _navItems,
        currentIndex: _currentIndex,
        onTap: _selectTab,
        onCenterTap: _onCenterTap,
      ),
    );
  }

  /// One page of the stack, taking whatever part in the motion it has.
  ///
  /// Every page stays mounted and laid out, which is the whole constraint here:
  /// an `AnimatedSwitcher` would have been three lines and throws the outgoing
  /// subtree away, so the day the schedule is scrolled to, the diary's open tab
  /// and whatever is typed in its search would be rebuilt from nothing on every
  /// tap.
  ///
  /// So the three `maintain` flags that matter are on and the rest are not,
  /// which is `IndexedStack`'s own bargain spelled out: state, tickers and
  /// layout kept, painting withheld, and a hidden page left out of hit-testing,
  /// semantics and focus. Not `Visibility.maintain` — that one maintains all
  /// six, so a screen reader would read four screens at once and a focus
  /// traversal could land in the search field of a diary nobody is looking at.
  Widget _tabPage(int index) {
    final t = _motion.value;
    final isCurrent = index == _currentIndex;
    final isLeaving = index == _leavingIndex && t < 1;

    return Visibility(
      visible: isCurrent || isLeaving,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      // Only the page being arrived at answers a finger. The one on its way out
      // is still on screen for another moment and must not.
      child: IgnorePointer(
        ignoring: !isCurrent,
        child: _tabTransition(index, t: t),
      ),
    );
  }

  /// The page's place in the slide, as one of two screens lying side by side on
  /// a single sheet that is pulled across the window.
  ///
  /// **Both** move, by the same amount and in the same direction, so neither is
  /// ever laid over the other: going right the arriving page waits off the right
  /// edge and the one being left runs out to the left, going back the pair
  /// travels the other way. Nothing overlaps at any point of the motion, which
  /// is why there is no shadow here — the only seam is the join between the two,
  /// and it is off-screen the moment the sheet comes to rest.
  Widget _tabTransition(int index, {required double t}) {
    final page = _pages[index];
    // Settled: handed over bare, so no transform stands between the compositor
    // and a screen that is simply being looked at.
    if (t >= 1) return page;
    if (index != _currentIndex && index != _leavingIndex) return page;

    final forward = _currentIndex > _leavingIndex;
    final travelled = Curves.easeInOutCubic.transform(t);
    // How far the sheet has been pulled, and where this page sat on it before
    // the pull began — the page being left is the one under the window, so it
    // starts at zero.
    final pulled = forward ? -travelled : travelled;
    final start = index == _currentIndex ? (forward ? 1.0 : -1.0) : 0.0;

    return FractionalTranslation(
      // A fraction of the page's own width, so nothing here has to ask how wide
      // the screen is or watch for it changing.
      translation: Offset(start + pulled, 0),
      child: page,
    );
  }

  /// The centre button is contextual: on the diary it opens the note editor,
  /// everywhere else the task form. Both are pushed routes, so the button
  /// behaves the same way wherever it is pressed — only what it creates
  /// changes. The nav bar stays unaware of pages: it only reports the tap.
  void _onCenterTap() {
    if (_currentIndex == _diaryIndex) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CreateNotePage()));
      return;
    }
    _openTaskForm();
  }

  /// The task form, pushed. Two callers: the centre button, and
  /// "Добавить задачу" on the home-screen widget.
  void _openTaskForm() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateTaskPage()));
  }
}

/// Builds a theme whose accent (primary) comes from [seed], while surfaces and
/// backgrounds stay neutral so selecting a color only recolors elements, not
/// the whole screen.
///
/// Public so tests can render a screen in the theme the app actually ships,
/// rather than in `ThemeData.dark()`.
ThemeData buildAppTheme(Color seed, Brightness brightness) {
  final isLight = brightness == Brightness.light;

  // In dark theme a near-black accent is invisible, so apply it as white.
  final accent = (!isLight && seed.computeLuminance() < 0.1)
      ? Colors.white
      : seed;

  final base = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
  // Whichever of black/white contrasts better with the accent. Not
  // estimateBrightnessForColor: its 0.15 threshold puts a deep red such as
  // #D33243 (luminance 0.165) on the black side, where white in fact reads
  // better. The two contrast ratios cross over at luminance sqrt(0.0525)-0.05.
  final onAccent = accent.computeLuminance() > 0.179
      ? Colors.black
      : Colors.white;

  final scheme = base.copyWith(
    primary: accent,
    onPrimary: onAccent,
    surfaceTint: Colors.transparent,
    surface: isLight ? Colors.white : const Color(0xFF121212),
    onSurface: isLight ? const Color(0xFF1A1A1A) : const Color(0xFFECECEC),
    onSurfaceVariant: isLight
        ? const Color(0xFF6B6B6B)
        : const Color(0xFFB0B0B0),
    surfaceContainerLowest: isLight ? Colors.white : const Color(0xFF0D0D0D),
    surfaceContainerLow: isLight
        ? const Color(0xFFF7F7F7)
        : const Color(0xFF1A1A1A),
    surfaceContainer: isLight
        ? const Color(0xFFF2F2F2)
        : const Color(0xFF1E1E1E),
    surfaceContainerHigh: isLight
        ? const Color(0xFFECECEC)
        : const Color(0xFF282828),
    surfaceContainerHighest: isLight
        ? const Color(0xFFE6E6E6)
        : const Color(0xFF333333),
    outlineVariant: isLight ? const Color(0xFFDADADA) : const Color(0xFF3A3A3A),
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    // The whole app is Nunito. Set on the theme rather than per style, so every
    // widget that reads a text style off the theme — including the ones inside
    // the framework and the note editor — gets it without being told. The
    // family is bundled in `assets/fonts`; see the `fonts:` block in
    // pubspec.yaml for which weights exist. A weight that is not there resolves
    // to the nearest one that is, so nothing is ever left without a face.
    fontFamily: 'Nunito',
    // One switch look for the whole app: an accent thumb on a half-strength
    // accent track. That is what a bare `activeThumbColor` used to produce in
    // the task form — Flutter derives the track from the thumb with alpha 0x80
    // when only the thumb is given — while a switch with no override at all
    // took the M3 default of a solid accent track and an `onPrimary` thumb.
    // Only the selected state is spelled out; returning null anywhere else
    // keeps the M3 default, so the off and disabled states stay neutral.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => _switchIsOn(states) ? accent : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => _switchIsOn(states) ? accent.withValues(alpha: 0.5) : null,
      ),
    ),
    // A `FilledButton` is an accent-filled control, so its label is the brand
    // ink — one recognisable white on every accent — and not the scheme's
    // `onPrimary`, which flips to black the moment the accent is light enough
    // (the default violet is, at luminance 0.27). The task form already spelled
    // that out on each of its buttons; pinning it here is what stops the next
    // button from being born black, the same way `switchTheme` above settled an
    // argument between two screens.
    //
    // Only the foreground, and only for the enabled state: no
    // `disabledForegroundColor` is given, so a disabled button falls through to
    // the M3 default and still reads as disabled rather than as white on grey.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(foregroundColor: onBrandFill(accent)),
    ),
    useMaterial3: true,
  );
}

/// A switch that is on and touchable — the only state [buildAppTheme] repaints.
bool _switchIsOn(Set<WidgetState> states) =>
    states.contains(WidgetState.selected) &&
    !states.contains(WidgetState.disabled);

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // The shade follows the running timers for as long as the app is alive; the
    // entries it posts keep counting on their own once it is not. Subscribed
    // once here rather than in build: `ref.listen` cannot fire for the state
    // that is already there, and a timer left running from the last launch has
    // to be picked back up.
    ref.listenManual<List<TimerNotification>>(
      runningTimerNotificationsProvider,
      (_, running) => ref.read(appNotificationsProvider).sync(running),
      fireImmediately: true,
    );

    // Reminders are rescheduled whenever the tasks, the day's ticks or the
    // setting change. The setting is read here rather than inside the derived
    // provider so that turning it off still reaches the platform — with an
    // empty list there would be nothing to tell apart from having no tasks.
    ref.listenManual<List<TaskReminder>>(
      taskRemindersProvider,
      (_, reminders) => ref
          .read(appNotificationsProvider)
          .syncReminders(
            reminders,
            enabled: ref.read(taskRemindersEnabledProvider),
          ),
      fireImmediately: true,
    );
    ref.listenManual<bool>(taskRemindersEnabledProvider, (_, enabled) {
      ref
          .read(appNotificationsProvider)
          .syncReminders(ref.read(taskRemindersProvider), enabled: enabled);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final appColor = ref.watch(appColorProvider);
    return MaterialApp(
      title: appName,
      theme: buildAppTheme(appColor, Brightness.light),
      darkTheme: buildAppTheme(appColor, Brightness.dark),
      themeMode: themeMode,
      locale: const Locale('ru', 'RU'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU')],
      // Wrapped around the app rather than placed on a screen: syncing has to
      // keep up while the diary is nowhere in sight, and the lifecycle events
      // it listens for belong to the whole app. It draws nothing.
      home: const SyncScope(
        child: HomeWidgetScope(child: MainScreen()),
      ),
    );
  }
}
