import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

late AppDatabase db;

Widget _form({TaskFormMode mode = TaskFormMode.create, Task? task}) =>
    ProviderScope(
      // Only edit mode reaches the database, to read the task's subtasks — but
      // the override is unconditional so a create-mode test can never open the
      // real on-device file by accident.
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        locale: const Locale('ru', 'RU'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru', 'RU')],
        home: CreateTaskPage(mode: mode, task: task),
      ),
    );

/// A task saved back when [TrackingMode.value] could still be picked. Editing
/// one is the only way left to reach the value controls, so it is how they are
/// tested.
Task _valueTask({double? targetValue}) {
  final now = DateTime(2026, 5, 20);
  return Task(
    dirty: false,
    id: 1,
    title: 'Вода',
    status: TaskStatus.active,
    trackingMode: TrackingMode.value,
    targetValue: targetValue,
    startDate: now,
    createdAt: now,
    updatedAt: now,
  );
}

/// Opens the form on a value-mode task and lets its subtask read finish, which
/// needs the real event loop: under fake time a drift future never completes.
Future<void> _openValueForm(WidgetTester tester, {double? targetValue}) async {
  await tester.pumpWidget(
    _form(
      mode: TaskFormMode.edit,
      task: _valueTask(targetValue: targetValue),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

/// Taps the plus of the stepper in the row labelled [label]. The search has to be
/// scoped: the "add a subtask" plate carries an [LucideIcons.plus] of its own.
Future<void> _plus(WidgetTester tester, String label) async {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  await tester.tap(
    find.descendant(of: row, matching: find.byIcon(LucideIcons.plus)),
  );
  await tester.pumpAndSettle();
}

/// Colour of a mode tile's caption — how a blocked mode is told from a pickable
/// one without reaching into the widget's private types.
Color? _modeLabelColour(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

/// Flips the switch sitting in the row labelled [label].
Future<void> _toggle(WidgetTester tester, String label) async {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
  });

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(() async => db.close());

    // Tall surface so the whole form is laid out without scrolling.
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1000, 2600);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  group('repeat block', () {
    testWidgets('is collapsed to a toggle by default', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      expect(find.text('Повторение'), findsOneWidget);
      // None of the repeat controls are on screen yet.
      expect(find.text('Ежедневно'), findsNothing);
      expect(find.text('Каждый день'), findsNothing);
      expect(find.text('Повторять каждые'), findsNothing);
    });

    testWidgets('opens on daily with no interval control', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'Повторение');

      expect(find.text('Ежедневно'), findsOneWidget);
      expect(find.text('Другое'), findsOneWidget);
      // Daily is "every day", so there is deliberately no interval stepper.
      expect(find.text('Повторять каждые'), findsNothing);
      expect(find.text('Каждый день'), findsOneWidget);
    });

    testWidgets('weekly shows seven day circles', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'Повторение');
      await tester.tap(find.text('Еженедельно'));
      await tester.pumpAndSettle();

      for (final day in ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс']) {
        expect(find.text(day), findsOneWidget, reason: 'circle for $day');
      }
      expect(find.text('Повторять каждые'), findsOneWidget);
    });

    testWidgets('picking extra weekdays updates the summary', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'Повторение');
      await tester.tap(find.text('Еженедельно'));
      await tester.pumpAndSettle();

      // Seeded with today's weekday, so tapping that one would *remove* it —
      // this used to fail every Monday, Wednesday and Friday.
      const shortNames = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
      final seeded = shortNames[DateTime.now().weekday - 1];
      for (final day in ['пн', 'ср', 'пт']) {
        if (day == seeded) continue;
        await tester.tap(find.text(day));
      }
      await tester.pumpAndSettle();

      final summary = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .firstWhere((s) => s.startsWith('Каждую неделю'));
      expect(summary, contains('пн'));
      expect(summary, contains('ср'));
      expect(summary, contains('пт'));
    });

    testWidgets('monthly shows the 1–31 grid', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'Повторение');
      await tester.tap(find.text('Ежемесячно'));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
    });

    testWidgets('selecting the 31st warns about short months', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'Повторение');
      await tester.tap(find.text('Ежемесячно'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('31'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('в коротких месяцах — последний день'),
        findsOneWidget,
      );
    });

    testWidgets('interval stepper counts weeks with a unit', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'Повторение');
      await tester.tap(find.text('Еженедельно'));
      await tester.pumpAndSettle();

      expect(find.text('1 неделя'), findsOneWidget);
      await _plus(tester, 'Повторять каждые');
      expect(find.text('2 недели'), findsOneWidget);
      expect(find.textContaining('Каждые 2 недели'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.minus));
      await tester.pumpAndSettle();
      expect(find.text('1 неделя'), findsOneWidget);
    });
  });

  group('the parked "Значение" mode', () {
    testWidgets('cannot be picked on a new task', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Значение'));
      await tester.pumpAndSettle();

      // Nothing happened: no value stepper, and the checkbox mode is still the
      // one selected — which is what "no target row at all" means here.
      expect(find.text('Целевое значение'), findsNothing);
      expect(find.text('Целевое количество'), findsNothing);
      expect(find.text('Целевая длительность'), findsNothing);
    });

    testWidgets('is still offered, just greyed out', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      // Left on screen on purpose, so the mode reads as "later" rather than as
      // something that never existed.
      expect(find.text('Значение'), findsOneWidget);
      // Dimmer than a pickable mode. Compared by opacity rather than against a
      // literal: both colours now come from the theme, so the dark theme gets
      // its own greys.
      final parked = _modeLabelColour(tester, 'Значение')!;
      final pickable = _modeLabelColour(tester, 'Счётчик')!;
      expect(
        parked.a,
        lessThan(pickable.a),
        reason: 'the pickable modes must not look blocked too',
      );
    });

    testWidgets('the other three modes still work', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();
      expect(find.text('Целевое количество'), findsOneWidget);

      await tester.tap(find.text('Таймер'));
      await tester.pumpAndSettle();
      expect(find.text('Целевая длительность'), findsOneWidget);

      await tester.tap(find.text('Чекбокс'));
      await tester.pumpAndSettle();
      expect(find.text('Целевая длительность'), findsNothing);
    });

    testWidgets('a task already using it opens with it intact', (tester) async {
      await _openValueForm(tester, targetValue: 3);

      // The mode is not rewritten behind the user's back just because it can no
      // longer be chosen.
      expect(find.text('Целевое значение'), findsOneWidget);
      expect(_modeLabelColour(tester, 'Значение'), isNot(Colors.black26));
    });

    testWidgets('switching away from it is a one-way door', (tester) async {
      await _openValueForm(tester, targetValue: 3);

      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();
      expect(find.text('Целевое количество'), findsOneWidget);

      await tester.tap(find.text('Значение'));
      await tester.pumpAndSettle();
      expect(find.text('Целевое значение'), findsNothing);
      expect(find.text('Целевое количество'), findsOneWidget);
    });
  });

  group('tracking targets', () {
    testWidgets('counter steps in whole repetitions', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();

      expect(find.text('Целевое количество'), findsOneWidget);
      // A counter always counts at least once — "без цели" is the checkbox.
      expect(find.text('без цели'), findsNothing);
      expect(find.text('1 раз'), findsOneWidget);

      await _plus(tester, 'Целевое количество');
      expect(find.text('2 раза'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.minus));
      await tester.tap(find.byIcon(LucideIcons.minus));
      await tester.pumpAndSettle();
      expect(find.text('1 раз'), findsOneWidget);
    });

    testWidgets('minus stops at a single repetition', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();

      final minus = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(LucideIcons.minus),
          matching: find.byType(IconButton),
        ),
      );
      expect(minus.onPressed, isNull);
    });

    testWidgets('a fractional target becomes whole when switching to counter', (
      tester,
    ) async {
      await _openValueForm(tester, targetValue: 2.5);
      expect(find.text('2.5'), findsOneWidget);

      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();

      // 2.5 cannot stay 2.5 taps.
      expect(find.text('3 раза'), findsOneWidget);
    });

    testWidgets('timer steps in five-minute chunks', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Таймер'));
      await tester.pumpAndSettle();

      expect(find.text('Целевая длительность'), findsOneWidget);
      expect(find.text('без цели'), findsOneWidget);

      await _plus(tester, 'Целевая длительность');
      expect(find.text('5 мин'), findsOneWidget);

      for (var i = 0; i < 11; i++) {
        await _plus(tester, 'Целевая длительность');
      }
      // 60 minutes reads as an hour, not as "60 мин".
      expect(find.text('1 ч'), findsOneWidget);

      await _plus(tester, 'Целевая длительность');
      expect(find.text('1 ч 5 мин'), findsOneWidget);
    });

    testWidgets('tapping the duration opens the hours sheet', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Таймер'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('без цели'));
      await tester.pumpAndSettle();

      expect(find.text('Своя длительность'), findsOneWidget);
      // Two hours via the sheet's own hour stepper. It reports `value + step`
      // rather than a delta, so each tap needs a frame before the next one.
      final hours = find
          .ancestor(of: find.text('Часы'), matching: find.byType(Column))
          .first;
      final plus = find.descendant(
        of: hours,
        matching: find.byIcon(LucideIcons.plus),
      );
      await tester.tap(plus);
      await tester.pumpAndSettle();
      await tester.tap(plus);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Готово'));
      await tester.pumpAndSettle();

      expect(find.text('2 ч'), findsOneWidget);
    });

    testWidgets('value steps by a half', (tester) async {
      await _openValueForm(tester);

      expect(find.text('Целевое значение'), findsOneWidget);

      await _plus(tester, 'Целевое значение');
      expect(find.text('0.5'), findsOneWidget);

      await _plus(tester, 'Целевое значение');
      // Whole results drop the ".0" tail.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('tapping the number types an exact target', (tester) async {
      await _openValueForm(tester);

      await tester.tap(find.text('без цели'));
      await tester.pumpAndSettle();

      expect(find.text('Своя цель'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '10000');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Готово'));
      await tester.pumpAndSettle();

      expect(find.text('10000'), findsOneWidget);
    });
  });
}
