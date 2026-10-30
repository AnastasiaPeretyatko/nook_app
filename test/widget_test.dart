import 'package:flutter/widgets.dart' show Scrollable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/pages/settings_page.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/settings/app_version.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/widgets/app_bottom_nav_bar.dart';

/// Does the app boot?
///
/// This file used to be the untouched `flutter create` template — a counter that
/// has never existed in this app, tapping a "+" that opens the task form, and
/// `MyApp` pumped bare. It failed from the first commit and told nobody
/// anything.
///
/// What it is now is the one thing no other test covers: the real root widget,
/// with the real theme and the real navigation, wired the way `main()` wires it.
/// Every other widget test mounts a screen directly, so a `MyApp` that throws on
/// startup — a provider nobody overrode, a subscription set up in the wrong
/// order — would otherwise be found only by running the app.
///
/// The one override is exactly what `main()` passes: `sharedPreferencesProvider`
/// throws if it is not given one.
void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('the app boots on the day screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MyApp(),
      ),
    );
    // Not `pumpAndSettle`: the day timeline drives a ticker for its "now"
    // marker, so nothing ever settles.
    await tester.pump(const Duration(milliseconds: 500));

    // `MainScreen` starts on the timeline — `_timelineIndex` — and
    // the calendar above the schedule is what says so. The month name comes from
    // the `ru_RU` data loaded above, so this also pins that the locale really is
    // wired — read from `intl` rather than written out, or the test would start
    // failing on the first of next month.
    // Case-insensitive: `intl` yields "август" and the calendar's header
    // capitalises it.
    final month = DateFormat('LLLL', 'ru_RU').format(DateTime.now());
    expect(
      find.textContaining(RegExp(month, caseSensitive: false)),
      findsWidgets,
      reason: 'the calendar does not name the current month ($month)',
    );

    // Which tab that is, asked of the bar rather than of the screens: every
    // page stays mounted and laid out behind the one on top, so a finder cannot
    // tell the tab being looked at from the three that are not.
    //
    // Read through the item the bar points at, so the assertion survives the
    // tabs being reordered — which is exactly what once left the app opening on
    // the habits screen while this line still passed on the date heading there
    // naming the same month.
    final bar = tester.widget<AppBottomNavBar>(find.byType(AppBottomNavBar));
    expect(
      bar.items[bar.currentIndex].label,
      'Таймлайн',
      reason: 'the app does not open on the timeline',
    );

    // All four tabs are on the bottom bar, in the order of the design.
    expect(bar.items.map((item) => item.label), [
      'Привычки',
      'Задачи',
      'Таймлайн',
      'Дневник',
    ]);
    for (final item in bar.items) {
      expect(
        find.descendant(
          of: find.byType(AppBottomNavBar),
          matching: find.text(item.label),
        ),
        findsOneWidget,
        reason: 'no tab drawn for ${item.label}',
      );
    }
  });

  testWidgets('an overdue task puts a count on the tasks tab', (tester) async {
    // The badge, wired the way the app wires it: the count is read by
    // `MainScreen` from `overdueTasksProvider` and travels to the bar as an
    // `AppNavItem.badgeCount`. What is overdue is `overdue_test.dart`'s job; this
    // is the one test that the number reaches the screen at all — and that it
    // lands on the tasks tab rather than on whichever one happens to be first.
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final task = Task(
      dirty: false,
      id: 1,
      title: 'Забытая задача',
      status: TaskStatus.active,
      trackingMode: TrackingMode.checkbox,
      startDate: yesterday,
      createdAt: yesterday,
      updatedAt: yesterday,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          allTasksProvider.overrideWith((ref) => Stream.value([task])),
          allLogsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final bar = tester.widget<AppBottomNavBar>(find.byType(AppBottomNavBar));
    final badged = bar.items.where((item) => item.badgeCount > 0);
    expect(badged.map((item) => item.label), ['Задачи']);
    expect(badged.single.badgeCount, 1);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('a failed sync says so at the bottom, with a retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MyApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final status = ProviderScope.containerOf(
      tester.element(find.byType(MainScreen)),
    ).read(syncStatusProvider.notifier);
    status.reportRunning();
    status.reportFailure(offline: true);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Не удалось синхронизировать'), findsOneWidget);
    expect(find.text('Нет подключения к интернету'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);

    // The toast goes by itself; no timer may be left behind.
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Не удалось синхронизировать'), findsNothing);
  });

  testWidgets('every tab opens', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MyApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    for (final label in const ['Привычки', 'Задачи', 'Дневник', 'Таймлайн']) {
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNavBar),
          matching: find.text(label),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Settings are no tab now: they open from the profile button on the
    // habits tab. They read the version and the account, so they are the
    // screen most likely to throw on a provider nobody set up.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNavBar),
        matching: find.text('Привычки'),
      ),
    );
    // Two frames: the slide starts on the first, and only the second sees the
    // page come to rest under the finger.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Профиль и настройки'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // The version sits at the foot of a list now taller than the test window,
    // and a ListView builds only what is on screen.
    final settings = find.byType(SettingsPage);
    final version = find.descendant(
      of: settings,
      matching: find.textContaining(appName),
    );
    await tester.scrollUntilVisible(
      version,
      200,
      scrollable: find.descendant(
        of: settings,
        matching: find.byType(Scrollable),
      ),
    );
    expect(version, findsOneWidget);
  });

  testWidgets('the cycle tab is last, moves no other, and has no "+"', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'about_gender': 'female'});
    final womans = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(womans)],
        child: const MyApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final bar = tester.widget<AppBottomNavBar>(find.byType(AppBottomNavBar));
    expect(bar.items.map((item) => item.label), [
      'Привычки',
      'Задачи',
      'Таймлайн',
      'Дневник',
      'Цикл',
    ]);
    // Everywhere else the "+" is there…
    expect(find.byTooltip('Новая задача'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNavBar),
        matching: find.text('Цикл'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    // …and on the cycle tab nothing in it is a task.
    expect(find.byTooltip('Новая задача'), findsNothing);
    expect(find.byTooltip('Новая запись'), findsNothing);
  });
}
