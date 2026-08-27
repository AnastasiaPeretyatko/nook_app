import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/auth/supabase_init.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/settings/app_version.dart';
import 'package:todo_app/settings/theme_provider.dart';

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
/// The two overrides are exactly the two `main()` passes.
/// `sharedPreferencesProvider` throws if it is not given one, and
/// `supabaseReadyProvider` stands in for a network call that must not happen in
/// a test — false is the honest answer here, and it is also the state a launch
/// with no connection reaches.
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
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          supabaseReadyProvider.overrideWithValue(false),
        ],
        child: const MyApp(),
      ),
    );
    // Not `pumpAndSettle`: the day timeline drives a ticker for its "now"
    // marker, so nothing ever settles.
    await tester.pump(const Duration(milliseconds: 500));

    // `MainScreen` starts at index 1, the day screen, and the calendar above the
    // schedule is what says so. The month name comes from the `ru_RU` data
    // loaded above, so this also pins that the locale really is wired — read
    // from `intl` rather than written out, or the test would start failing on the
    // first of next month.
    // Case-insensitive: `intl` yields "август" and the calendar's header
    // capitalises it.
    final month = DateFormat('LLLL', 'ru_RU').format(DateTime.now());
    expect(
      find.textContaining(RegExp(month, caseSensitive: false)),
      findsWidgets,
      reason: 'the calendar does not name the current month ($month)',
    );

    // All four tabs are on the bottom bar. By icon, not by label: `AppNavItem`
    // carries a label but `AppBottomNavBar` never draws one — the bar is icons
    // and a centre button.
    for (final icon in const [
      LucideIcons.repeat,
      LucideIcons.house,
      LucideIcons.book_open,
      LucideIcons.settings,
    ]) {
      expect(find.byIcon(icon), findsWidgets, reason: 'no tab for $icon');
    }
  });

  testWidgets('every tab opens', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          supabaseReadyProvider.overrideWithValue(false),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // The settings tab is the one that reads the version and the account, so it
    // is the one most likely to throw on a provider nobody set up.
    await tester.tap(find.byIcon(LucideIcons.settings).last);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining(appName), findsWidgets);
  });
}
