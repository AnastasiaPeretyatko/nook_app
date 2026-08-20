import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/pages/diary_page.dart';
import 'package:todo_app/pages/habits_page.dart';
import 'package:todo_app/pages/home_page.dart';
import 'package:todo_app/pages/settings_page.dart';
import 'package:todo_app/notifications/providers.dart';
import 'package:todo_app/notifications/task_reminder.dart';
import 'package:todo_app/notifications/timer_notification.dart';
import 'package:todo_app/settings/app_version.dart';
import 'package:todo_app/settings/notification_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/widgets/app_bottom_nav_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MyApp(),
    ),
  );
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 1;
  static const List<Widget> _pages = [
    HabitsPage(),
    HomePage(),
    DiaryPage(),
    SettingsPage(),
  ];

  static const List<AppNavItem> _navItems = [
    AppNavItem(icon: Icons.repeat, label: 'Привычки'),
    AppNavItem(icon: Icons.home_outlined, label: 'Home'),
    AppNavItem(icon: Icons.book_outlined, label: 'Дневник'),
    AppNavItem(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: AppBottomNavBar(
        items: _navItems,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
        },
        onCenterTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CreateTaskPage())),
      ),
    );
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
    useMaterial3: true,
  );
}

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
      home: const MainScreen(),
    );
  }
}
