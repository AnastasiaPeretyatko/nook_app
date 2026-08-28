import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/home_widget/providers.dart';
import 'package:todo_app/home_widget/widget_actions.dart';

/// Keeps the home-screen widget in step with the app, and reports its taps.
///
/// A widget in the tree rather than a provider, for the same reason [SyncScope]
/// is one: two of the three things it does are only visible from here — the app
/// coming back to the foreground, and the disposal that takes the subscriptions
/// down with it. It draws nothing.
///
/// ## The one thing that is not obvious
///
/// A checkbox pressed on the home screen is answered by a **second isolate**
/// with a **second connection** to the same database file. Drift dispatches its
/// stream updates in memory, per connection, so that write is invisible to the
/// app's own streams: come back to the app and the timeline would still show the
/// task unticked, while the widget behind it showed the opposite, until something
/// else happened to touch the table.
///
/// Coming back to the foreground is exactly when that has to be repaired, and
/// [GeneratedDatabase.markTablesUpdated] is drift's own answer for a table
/// written from outside — it re-reads every open query on the two tables and
/// nothing else. Unconditional, because there is no cheap way to ask whether the
/// widget was touched, and re-reading two tables is cheaper than finding out.
class HomeWidgetScope extends ConsumerStatefulWidget {
  const HomeWidgetScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HomeWidgetScope> createState() => _HomeWidgetScopeState();
}

class _HomeWidgetScopeState extends ConsumerState<HomeWidgetScope>
    with WidgetsBindingObserver {
  StreamSubscription<Uri?>? _taps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final bridge = ref.read(homeWidgetBridgeProvider);

    // The entry point Android calls when a checkbox on the widget is pressed.
    // Registered on every launch and not once ever: what is stored is a handle
    // to a Dart function, and a handle from a previous build of the app points
    // into code that is no longer there.
    unawaited(bridge.registerTapHandler(onHomeWidgetTap));

    // `listenManual` with `fireImmediately`, not `ref.listen`: a launch is the
    // most likely moment for the widget to be holding something stale — a week
    // of days that has run out, or a theme changed on another screen — and the
    // first state is the one that has to be pushed. The same reasoning as the
    // notification subscriptions in `main.dart`.
    ref.listenManual<String>(
      todayWidgetPayloadProvider,
      (_, payload) => unawaited(bridge.push(payload)),
      fireImmediately: true,
    );

    // A tap that reaches an app already running. With an error handler, or a
    // platform channel that fails would surface as an unhandled async error and
    // take the app down over a tap it could not read.
    _taps = bridge.taps.listen(
      _report,
      onError: (Object error) => debugPrint('Home widget tap stream: $error'),
    );
    // ...and one that started it. A stream cannot report what happened before
    // anybody listened, so the two halves are asked for separately.
    unawaited(bridge.launchUri().then(_report));
  }

  void _report(Uri? uri) {
    if (!mounted) return;
    ref.read(widgetTapProvider.notifier).report(widgetTapActionOf(uri));
  }

  @override
  void dispose() {
    _taps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // See the class comment: a tick made on the home screen was written by
    // another connection, and this is what tells the app's streams about it.
    final database = ref.read(databaseProvider);
    database.markTablesUpdated([database.tasks, database.taskLogs]);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
