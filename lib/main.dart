import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/groups/group_events_provider.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_note_page.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/pages/cycle_page.dart';
import 'package:todo_app/pages/diary_page.dart';
import 'package:todo_app/pages/groups_page.dart';
import 'package:todo_app/pages/habits_page.dart';
import 'package:todo_app/pages/home_page.dart';
import 'package:todo_app/pages/tasks_page.dart';
import 'package:todo_app/home_widget/home_widget_scope.dart';
import 'package:todo_app/home_widget/providers.dart';
import 'package:todo_app/home_widget/widget_actions.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/notifications/task_reminder.dart';
import 'package:todo_app/notifications/timer_notification.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/settings/app_version.dart';
import 'package:todo_app/settings/notification_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/sync/sync_controller.dart';
import 'package:todo_app/sync/sync_status.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/group_events.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/app_bottom_nav_bar.dart';
import 'package:todo_app/update/providers.dart';
import 'package:todo_app/widgets/app_toast.dart';
import 'package:todo_app/widgets/member_avatar.dart';
import 'package:todo_app/widgets/update_banner.dart';
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
  /// The tasks tab's slot — and so the one that carries the overdue badge.
  /// Named, like the two constants after it, because the tabs have been
  /// reordered twice already.
  static const int _tasksIndex = 1;

  /// The timeline's slot in the pages list — where the app opens, and where a tap on
  /// the home-screen widget lands, that being the screen the widget is a small
  /// copy of.
  ///
  /// Both the launch tab and the widget's target are named through it rather
  /// than written out: a literal left behind by a reorder is what once opened
  /// the app on the wrong screen.
  static const int _timelineIndex = 2;

  /// The diary's slot. The "+" button reads it to decide what it creates.
  static const int _diaryIndex = 3;

  /// The cycle tab's slot — last, and present only while the cycle is tracked.
  /// It has no "+": nothing there is a task.
  static const int _cycleIndex = 4;

  /// One tab change, start to finish — the same 300ms the nav bar's indicator
  /// takes to slide, so the bar and the page it points at arrive together.
  static const Duration _tabMotion = Duration(milliseconds: 300);

  int _currentIndex = _timelineIndex;

  /// The tab being left behind, kept only for as long as it is still painted.
  int _leavingIndex = _timelineIndex;

  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: _tabMotion,
    // Settled: the first frame is a page already in place, not one arriving.
    value: 1,
  );

  /// The "Иней" tabs (DESIGN.md §6, "Навигация"). Settings are not one: they
  /// open from the profile button on the habits tab.
  static List<Widget> _pagesFor({required bool cycle}) => [
    const HabitsPage(),
    const TasksPage(),
    const HomePage(),
    const DiaryPage(),
    // Last, so that turning it on or off never moves another tab.
    if (cycle) const CyclePage(),
  ];

  static List<AppNavItem> _navItemsFor({required bool cycle}) => [
    const AppNavItem(icon: LucideIcons.circle_check, label: 'Привычки'),
    const AppNavItem(icon: LucideIcons.list, label: 'Задачи'),
    const AppNavItem(icon: LucideIcons.git_commit_vertical, label: 'Таймлайн'),
    const AppNavItem(icon: LucideIcons.file_text, label: 'Дневник'),
    if (cycle) const AppNavItem(icon: LucideIcons.flower_2, label: 'Цикл'),
  ];

  /// The bar's buttons for this frame: the nav items with the overdue count put on
  /// the tasks tab, the screen those tasks are listed on.
  ///
  /// The number is read here and handed over. `AppBottomNavBar` draws what it is
  /// given and knows nothing about tasks — it is on every screen, including the
  /// two that have no tasks on them at all.
  static List<AppNavItem> _navItemsWithBadge(
    int overdueTasks, {
    required bool cycle,
  }) {
    final items = _navItemsFor(cycle: cycle);
    return [
      for (var i = 0; i < items.length; i++)
        i == _tasksIndex ? items[i].withBadge(overdueTasks) : items[i],
    ];
  }

  @override
  void initState() {
    super.initState();
    // Once per launch; the banner appears only if GitHub has a newer build.
    ref.read(updateProvider.notifier).check();
    // Taps on the home-screen widget that mean "open the app somewhere". They
    // are reported by `HomeWidgetScope` above this screen, because a launch has
    // to be caught before any screen is on it; acting on one needs a tab and a
    // navigator, which only this screen has.
    ref.listenManual<WidgetTapRequest?>(widgetTapProvider, (_, request) {
      switch (request?.action) {
        case WidgetTapAction.open:
          _selectTab(_timelineIndex);
        case WidgetTapAction.create:
          _openTaskForm();
        case _:
          break;
      }
    });

    // A run that ends badly says so on whatever screen is up — the account page
    // is not where anyone is looking when a background sync fails. Only the
    // step from `running`, so the same failure is not announced twice.
    ref.listenManual<SyncStatus>(syncStatusProvider, (previous, next) {
      final failed =
          next.phase == SyncPhase.failed || next.phase == SyncPhase.offline;
      if (!mounted || !failed || previous?.phase != SyncPhase.running) return;
      showAppToast(
        Overlay.of(context, rootOverlay: true),
        isError: true,
        message: 'Не удалось синхронизировать',
        detail: next.phase == SyncPhase.offline
            ? 'Нет подключения к интернету'
            : 'Что-то пошло не так',
        actionLabel: 'Повторить',
        onAction: () => ref.read(syncControllerProvider).syncNow(),
        duration: const Duration(seconds: 8),
      );
    });

    // Other members' news from the groups: a task handed to me or to everyone, a
    // task done. A Realtime event starts a sync, the sync changes the mirror,
    // and the provider says what is new in it.
    ref.listenManual<List<GroupEvent>>(groupEventsProvider, (_, events) {
      if (!mounted || events.isEmpty) return;
      final first = events.first;
      final one = events.length == 1;
      showAppToast(
        Overlay.of(context, rootOverlay: true),
        leading: MemberAvatar(
          name: first.actorName,
          size: 36,
          accent: memberAccent(first.actorUid),
        ),
        message: one ? first.headline : 'Новое в группах: ${events.length}',
        detail: one
            ? first.subline
            : '${first.taskTitle} и ещё ${events.length - 1}',
        actionLabel: one ? 'Открыть' : null,
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GroupPage(groupUid: first.groupUid),
          ),
        ),
      );
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
    // The one-off tasks whose day has gone by unticked. Watched here, on the
    // screen that owns the bar, so the badge is up to date on whichever tab the
    // user is looking at — the tasks tab does not have to have been opened for
    // the count to appear.
    final overdueTasks = ref.watch(overdueTasksProvider).length;
    final cycle = ref.watch(aboutSettingsProvider.select((a) => a.cycleOn));
    final pages = _pagesFor(cycle: cycle);
    // The cycle tab can vanish under a visit (settings switched off elsewhere).
    if (_currentIndex >= pages.length) _currentIndex = _timelineIndex;
    if (_leavingIndex >= pages.length) _leavingIndex = _currentIndex;

    return Scaffold(
      extendBody: true,
      // Rebuilt every frame of the motion, and that costs nothing: the four
      // pages are `const`, so the framework skips their subtrees and only these
      // wrappers are built again.
      body: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) => Stack(
          children: [for (var i = 0; i < pages.length; i++) _tabPage(pages, i)],
        ),
      ),
      floatingActionButton: _currentIndex == _cycleIndex
          ? null
          : _AddButton(
              tooltip: _currentIndex == _diaryIndex
                  ? 'Новая запись'
                  : 'Новая задача',
              onPressed: _onAddTap,
            ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const UpdateBanner(),
          AppBottomNavBar(
            items: _navItemsWithBadge(overdueTasks, cycle: cycle),
            currentIndex: _currentIndex,
            onTap: _selectTab,
          ),
        ],
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
  Widget _tabPage(List<Widget> pages, int index) {
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
        child: _tabTransition(pages[index], index, t: t),
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
  Widget _tabTransition(Widget page, int index, {required double t}) {
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

  /// The "+" button is contextual: on the diary it opens the note editor,
  /// everywhere else the task form. Both are pushed routes, so the button
  /// behaves the same way wherever it is pressed — only what it creates
  /// changes.
  void _onAddTap() {
    if (_currentIndex == _diaryIndex) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CreateNotePage()));
      return;
    }
    // On the day screen the form opens on the day being looked at: swipe the
    // schedule to the 1st of September, press the button, and the task is the
    // 1st of September's. No other tab has a day on it, so there the form keeps
    // its own default of today.
    _openTaskForm(
      initialDate: _currentIndex == _timelineIndex
          ? ref.read(selectedDayProvider)
          : null,
    );
  }

  /// The task form, as a bottom sheet. Two callers: the "+" button, and
  /// "Добавить задачу" on the home-screen widget — which passes no day, the
  /// widget only ever showing today.
  void _openTaskForm({DateTime? initialDate}) =>
      showCreateTaskSheet(context, initialDate: initialDate);
}

/// The floating "+" of every tab: a dark rounded square, light in the dark
/// theme — the main action is drawn in the text colour, not the accent
/// (DESIGN.md §1, §4: 56px, radius 20, 24 from the edge, 20 above the bar).
class _AddButton extends StatelessWidget {
  const _AddButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(Theme.of(context));
    final shape = BorderRadius.circular(20);
    return Padding(
      // On top of the 16 the scaffold's endFloat already leaves.
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E1B2230),
              offset: Offset(0, 8),
              blurRadius: 24,
            ),
          ],
        ),
        child: Material(
          color: p.textPrimary,
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Tooltip(
              message: tooltip,
              child: SizedBox.square(
                dimension: 56,
                child: Icon(LucideIcons.plus, size: 24, color: p.background),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds a theme whose accent (primary) comes from [seed], while surfaces and
/// backgrounds stay neutral so selecting a color only recolors elements, not
/// the whole screen. The neutrals are the "Иней" tokens, [AppPalette].
///
/// Public so tests can render a screen in the theme the app actually ships,
/// rather than in `ThemeData.dark()`.
ThemeData buildAppTheme(Color seed, Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final p = isLight ? AppPalette.light : AppPalette.dark;

  // One of the six accents takes its own dark tone. Any other colour (a test's)
  // is used as given, except that a near-black one is invisible on the dark
  // page and is applied as white.
  final known = appAccents
      .where((a) => a.light.toARGB32() == seed.toARGB32())
      .firstOrNull;
  final accent = isLight
      ? seed
      : known?.dark ?? (seed.computeLuminance() < 0.1 ? Colors.white : seed);

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
    // A card is `surface`; the page under it is `p.background`. The container
    // ladder climbs from the card through the chip tones, lightest = most
    // raised in the dark theme, where a shadow shows nothing.
    surface: p.surface,
    onSurface: p.textPrimary,
    onSurfaceVariant: p.textSecondary,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surfaceMuted,
    surfaceContainerHigh: p.chip,
    surfaceContainerHighest: isLight ? p.segmentTrack : p.segmentSelected,
    outline: p.outline,
    outlineVariant: p.border,
    error: p.danger,
    onError: isLight ? Colors.white : AppPalette.dark.background,
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    extensions: [p],
    // The whole app is Onest. Set on the theme rather than per style, so every
    // widget that reads a text style off the theme — including the ones inside
    // the framework and the note editor — gets it without being told. The
    // family is bundled in `assets/fonts`; see the `fonts:` block in
    // pubspec.yaml for which weights exist. A weight that is not there resolves
    // to the nearest one that is, so nothing is ever left without a face.
    fontFamily: 'Onest',
    // One switch look for the whole app. On: an accent thumb on a half-strength
    // accent track. Off: a white thumb (a soft white in the dark theme) on the
    // palette's off track, with no outline — the M3 default draws an outlined
    // grey ring there, which read as a disabled control. Disabled stays dim.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        final disabled = states.contains(WidgetState.disabled);
        final colour = states.contains(WidgetState.selected)
            ? accent
            : (isLight ? Colors.white : p.textPrimary);
        return disabled ? colour.withValues(alpha: 0.5) : colour;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        final disabled = states.contains(WidgetState.disabled);
        final colour = states.contains(WidgetState.selected)
            ? accent.withValues(alpha: 0.5)
            : p.switchOff;
        return disabled ? colour.withValues(alpha: 0.5) : colour;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
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
      home: const SyncScope(child: HomeWidgetScope(child: MainScreen())),
    );
  }
}
