import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// The one place that talks to the home-screen widget.
///
/// Everything above it deals in payloads; this deals in the platform: writing
/// the payload where the launcher can read it, and asking Android to redraw.
/// Split the way [AppNotifications] is split from the reminders it posts — the
/// derivation is pure and testable, the platform call is wrapped and allowed to
/// fail.
///
/// Every call is a no-op off Android. Widgets are the only consumer, the desktop
/// and web builds have no such thing, and a test must not need a plugin.
class HomeWidgetBridge {
  /// [skipIfStored]: do not redraw for a payload that is already stored. For the
  /// background isolate that answers a tap — it starts with nothing remembered, so
  /// it would otherwise redraw every widget on the screen, changed or not.
  HomeWidgetBridge({this.skipIfStored = false});

  final bool skipIfStored;

  /// The class name of the `AppWidgetProvider`, which the plugin resolves
  /// against the application id. It has to stay the same as the Kotlin class in
  /// `android/app/src/main/kotlin/.../TodayWidgetProvider.kt` and as the
  /// `receiver` declared in the manifest — three spellings of one name, and
  /// nothing checks them against each other at build time.
  static const providerName = 'TodayWidgetProvider';

  /// The key the payload is stored under. Read by `TodayWidgetProvider`.
  static const payloadKey = 'today_payload';

  /// The habit widgets — the week of one habit, the row of circles and the 2×2
  /// streak — share one payload, since they draw the same data. Spelled like [providerName]:
  /// the Kotlin classes and the manifest receivers carry the same names.
  static const habitsPayloadKey = 'habits_payload';
  static const habitProviderNames = [
    'HabitWeekWidgetProvider',
    'HabitStripWidgetProvider',
    'HabitStreakWidgetProvider',
  ];

  /// What was last handed to the platform, per key. A widget redraw is a
  /// broadcast and a re-inflate in the launcher, so an unchanged payload is
  /// worth not sending — and the app pushes on every task edit, every tick and
  /// every theme change.
  final _pushed = <String, String>{};

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Stores [payload] and asks the "Сегодня" widget to redraw.
  ///
  /// Safe to call as often as anything changes: an identical payload returns
  /// immediately, and a platform that has no widgets does nothing at all.
  Future<void> push(String payload) =>
      _push(payloadKey, payload, const [providerName]);

  /// The same for the habit widgets.
  Future<void> pushHabits(String payload) =>
      _push(habitsPayloadKey, payload, habitProviderNames);

  Future<void> _push(String key, String payload, List<String> providers) async {
    if (!_supported || _pushed[key] == payload) return;
    try {
      if (skipIfStored &&
          await HomeWidget.getWidgetData<String>(key) == payload) {
        _pushed[key] = payload;
        return;
      }
      await HomeWidget.saveWidgetData<String>(key, payload);
      for (final name in providers) {
        await HomeWidget.updateWidget(androidName: name);
      }
      _pushed[key] = payload;
    } catch (error, stack) {
      // A widget that could not be redrawn is not a reason to take a task edit
      // down with it. Reported, not thrown.
      debugPrint('Home widget update failed: $error\n$stack');
    }
  }

  /// Registers the entry point Android calls when a row on the widget is
  /// tapped. Once per launch, before anything can be tapped.
  ///
  /// [callback] must be a top-level or static function marked
  /// `@pragma('vm:entry-point')`: what is stored is a handle to it, and the
  /// isolate that later looks the handle up is not this one.
  Future<void> registerTapHandler(Future<void> Function(Uri?) callback) async {
    if (!_supported) return;
    try {
      await HomeWidget.registerInteractivityCallback(callback);
    } catch (error, stack) {
      debugPrint('Home widget callback registration failed: $error\n$stack');
    }
  }

  /// The URI the app was launched with by a tap on the widget, or null when it
  /// was opened the ordinary way. Cold start only — see [taps].
  Future<Uri?> launchUri() async {
    if (!_supported) return null;
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (error) {
      debugPrint('Home widget launch uri failed: $error');
      return null;
    }
  }

  /// Taps that reach an app which was already running. [launchUri] covers the
  /// other half — a stream cannot report an event that happened before anything
  /// was listening.
  Stream<Uri?> get taps =>
      _supported ? HomeWidget.widgetClicked : const Stream.empty();
}
