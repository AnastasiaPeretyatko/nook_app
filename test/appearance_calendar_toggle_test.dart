import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/settings/calendar_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/widgets/settings/appearance_section.dart';

/// The switch that keeps habits out of the month calendar.
///
/// It lives in the settings list's "Внешний вид" block and is the only
/// setting the calendar reads.
/// Two things are worth pinning: the tap survives a restart (it is written to
/// [SharedPreferences], not held in the widget), and the row says which of the
/// two states it is in — a switch labelled only "Привычки в календаре" does not
/// tell the user what the dots then mean.
void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  setUp(() async {
    await prefs.clear();
  });

  Widget app() => ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: Scaffold(body: ListView(children: const [AppearanceSection()])),
    ),
  );

  testWidgets('habits in the calendar are on by default', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final tile = tester.widget<Switch>(find.byType(Switch));
    expect(tile.value, isTrue);
    expect(find.text('Точками отмечены задачи и привычки'), findsOneWidget);
  });

  testWidgets('turning it off is stored and reported', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('Точками отмечены только задачи'), findsOneWidget);

    // A fresh scope over the same store is what the next launch looks like.
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(showHabitsInCalendarProvider), isFalse);
  });

  testWidgets('the theme and the accent are picked inline and stored', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Тёмная'));
    await tester.tap(find.bySemanticsLabel('Шалфей'));
    await tester.pumpAndSettle();

    expect(prefs.getString('theme_mode'), 'dark');
    expect(prefs.getInt('app_color'), appAccents[4].light.toARGB32());
  });
}
