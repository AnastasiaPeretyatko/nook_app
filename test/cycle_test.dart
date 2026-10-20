import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/cycle_page.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/utils/cycle.dart';
import 'package:todo_app/widgets/settings/about_section.dart';

void main() {
  // The numbers of Cycle.dc.html: a period began on 5 October, 27-day cycle.
  final model = CycleModel(lastStart: DateTime(2026, 10, 5));

  group('CycleModel', () {
    test('cycle day counts from the first day of the period', () {
      expect(model.cycleDay(DateTime(2026, 10, 5)), 1);
      expect(model.cycleDay(DateTime(2026, 10, 16)), 12);
      // The 28th day is day 1 of the next cycle.
      expect(model.cycleDay(DateTime(2026, 11, 1)), 1);
      expect(model.cycleDay(DateTime(2026, 10, 4)), isNull);
    });

    test('phases: period 1-5, fertile 9-15, ovulation 14', () {
      CyclePhase on(int d) => model.phaseOfCycleDay(d);
      expect(on(5), CyclePhase.period);
      expect(on(6), CyclePhase.other);
      expect(on(9), CyclePhase.fertile);
      expect(on(14), CyclePhase.ovulation);
      expect(on(15), CyclePhase.fertile);
      expect(on(16), CyclePhase.other);
      expect(model.phaseOn(DateTime(2026, 10, 18)), CyclePhase.ovulation);
    });

    test('the cycles after the entered one are a forecast', () {
      expect(model.isForecast(DateTime(2026, 10, 31)), isFalse);
      expect(model.isForecast(DateTime(2026, 11, 1)), isTrue);
    });

    test('the fertile window is the current one through its last day', () {
      // Ovulation is the 18th: the window is the 13th to the 19th.
      final w = model.fertileWindow(DateTime(2026, 10, 16));
      expect(w.start, DateTime(2026, 10, 13));
      expect(w.end, DateTime(2026, 10, 19));
      // Still that one on its last day…
      expect(
        model.fertileWindow(DateTime(2026, 10, 19)).end,
        DateTime(2026, 10, 19),
      );
      // …and the next cycle's after it.
      final next = model.fertileWindow(DateTime(2026, 10, 20));
      expect(next.start, DateTime(2026, 11, 9));
      expect(next.end, DateTime(2026, 11, 15));
    });

    test('next period and ovulation', () {
      final today = DateTime(2026, 10, 16);
      expect(model.nextPeriodStart(today), DateTime(2026, 11, 1));
      expect(model.nextOvulation(today), DateTime(2026, 10, 18));
      // Ovulation already gone: the next cycle's.
      expect(
        model.nextOvulation(DateTime(2026, 10, 25)),
        DateTime(2026, 11, 14),
      );
      // On the day itself it is still "today".
      expect(
        model.nextOvulation(DateTime(2026, 10, 18)),
        DateTime(2026, 10, 18),
      );
    });

    test('a clock change does not shift a day', () {
      // Europe leaves summer time on 25 October 2026; a start before it must
      // still land the next period on a whole day.
      final m = CycleModel(lastStart: DateTime(2026, 10, 20));
      expect(m.nextPeriodStart(DateTime(2026, 10, 30)), DateTime(2026, 11, 16));
    });
  });

  group('the "О себе" block', () {
    Future<ProviderContainer> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await initializeDateFormatting('ru_RU');
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: AboutSection())),
          ),
        ),
      );
      return container;
    }

    testWidgets('cycle rows appear only for «Женский», and the pick is kept', (
      tester,
    ) async {
      final container = await pump(tester);
      expect(find.text('Отслеживать цикл'), findsNothing);

      await tester.tap(find.text('Женский'));
      await tester.pump();
      expect(find.text('Отслеживать цикл'), findsOneWidget);
      expect(find.text('Начало последних месячных'), findsOneWidget);
      expect(container.read(aboutSettingsProvider).cycleOn, isTrue);

      await tester.tap(find.text('Мужской'));
      await tester.pump();
      expect(find.text('Отслеживать цикл'), findsNothing);
      expect(container.read(aboutSettingsProvider).cycleOn, isFalse);
      expect(
        container.read(sharedPreferencesProvider).getString('about_gender'),
        'male',
      );
    });

    testWidgets('the start date reads back as the same day', (tester) async {
      final container = await pump(tester);
      await container
          .read(aboutSettingsProvider.notifier)
          .setLastStart(DateTime(2026, 10, 5, 23, 59));
      expect(
        container.read(aboutSettingsProvider).lastStart,
        DateTime(2026, 10, 5),
      );
      // A fresh notifier over the same prefs sees the day, not the clock.
      final again = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            container.read(sharedPreferencesProvider),
          ),
        ],
      );
      addTearDown(again.dispose);
      expect(
        again.read(aboutSettingsProvider).lastStart,
        DateTime(2026, 10, 5),
      );
    });
  });

  testWidgets('the cycle page draws the forecast, and asks for a date first', (
    tester,
  ) async {
    // A tall screen: the forecast is far down the list, which builds only what
    // is on it.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ru_RU');
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CyclePage()),
      ),
    );
    expect(find.textContaining('Укажите, когда начались'), findsOneWidget);
    expect(find.text('Овуляция'), findsNothing);

    await container
        .read(aboutSettingsProvider.notifier)
        .setLastStart(DateTime.now());
    await tester.pump();
    expect(find.text('День цикла'), findsOneWidget);
    expect(find.text('Овуляция'), findsWidgets);
    expect(find.textContaining('через'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
