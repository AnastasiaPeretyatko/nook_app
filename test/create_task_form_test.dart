import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
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

/// A "Значение" task as it sits in the database: a name and the day the
/// watching began, nothing else. [targetValue] is what a row saved while the mode
/// was still a number with a target may carry.
Task _valueTask({double? targetValue}) {
  final now = DateTime(2026, 5, 20);
  return Task(
    dirty: false,
    id: 1,
    title: 'Смена белья',
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

/// Saves the form and waits for the database. `pumpAndSettle` cannot be used: the
/// save button shows a spinner while it works, and that animation never ends.
Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Сохранить'));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pump(const Duration(milliseconds: 20));
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

  testWidgets('the form opens full screen, with no handle to drag', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('ru', 'RU'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru', 'RU')],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCreateTaskSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.getSize(find.byType(CreateTaskPage)), const Size(1000, 2600));
    // The only 40x4 bar on the old sheet was its grab handle.
    expect(
      find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 40,
      ),
      findsNothing,
    );
  });

  testWidgets(
    'after the title come the colour and the subtasks, then the rest',
    (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      double top(Finder f) => tester.getTopLeft(f).dy;
      final description = top(find.text('Описание'));
      final colour = top(find.byType(ColorPickerRow));
      final subtasks = top(find.text('ПОДЗАДАЧИ'));
      final when = top(find.text('КОГДА'));
      expect(description < colour, isTrue);
      expect(colour < subtasks, isTrue);
      expect(subtasks < when, isTrue);
    },
  );

  group('keyboard on open', () {
    bool titleFocused(WidgetTester tester) => tester
        .widget<EditableText>(find.byType(EditableText).first)
        .focusNode
        .hasFocus;

    testWidgets('a new task puts the cursor in the title', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      expect(titleFocused(tester), isTrue);
    });

    testWidgets('editing a task does not open the keyboard', (tester) async {
      await _openValueForm(tester);
      expect(titleFocused(tester), isFalse);
    });
  });

  group('repeat block', () {
    testWidgets('is collapsed to a toggle by default', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      expect(find.text('ПОВТОРЯТЬ'), findsOneWidget);
      // None of the repeat controls are on screen yet.
      expect(find.text('День'), findsNothing);
      expect(find.text('Каждый день'), findsNothing);
      expect(find.text('Повторять каждые'), findsNothing);
    });

    testWidgets('opens on daily with no interval control', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'ПОВТОРЯТЬ');

      expect(find.text('День'), findsOneWidget);
      expect(find.text('N дней'), findsOneWidget);
      // Daily is "every day", so there is deliberately no interval stepper.
      expect(find.text('Повторять каждые'), findsNothing);
      expect(find.text('Каждый день'), findsOneWidget);
    });

    testWidgets('weekly shows seven day circles', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'ПОВТОРЯТЬ');
      await tester.tap(find.text('Неделя'));
      await tester.pumpAndSettle();

      for (final day in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']) {
        expect(find.text(day), findsOneWidget, reason: 'circle for $day');
      }
      expect(find.text('Повторять каждые'), findsOneWidget);
    });

    testWidgets('picking extra weekdays updates the summary', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'ПОВТОРЯТЬ');
      await tester.tap(find.text('Неделя'));
      await tester.pumpAndSettle();

      // Seeded with today's weekday, so tapping that one would *remove* it —
      // this used to fail every Monday, Wednesday and Friday.
      const shortNames = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
      final seeded = shortNames[DateTime.now().weekday - 1];
      for (final day in ['пн', 'ср', 'пт']) {
        if (day == seeded) continue;
        await tester.tap(
          find.text('${day[0].toUpperCase()}${day.substring(1)}'),
        );
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
      await _toggle(tester, 'ПОВТОРЯТЬ');
      await tester.tap(find.text('Месяц'));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
    });

    testWidgets('selecting the 31st warns about short months', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'ПОВТОРЯТЬ');
      await tester.tap(find.text('Месяц'));
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
      await _toggle(tester, 'ПОВТОРЯТЬ');
      await tester.tap(find.text('Неделя'));
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

  group('the "Значение" mode', () {
    testWidgets('is picked like any other mode', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Значение'));
      await tester.pumpAndSettle();

      // Nothing to reach for it: no target, no duration.
      expect(find.text('Целевое значение'), findsNothing);
      expect(find.textContaining('Цель:'), findsNothing);
    });

    testWidgets('leaves only the day the watching starts', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      expect(find.text('КОГДА'), findsOneWidget);
      expect(find.text('ПОВТОРЯТЬ'), findsOneWidget);

      await tester.tap(find.text('Значение'));
      await tester.pumpAndSettle();

      expect(find.text('ОТСЛЕЖИВАТЬ С'), findsOneWidget);
      // No time, no switch for the date, no repeat rule, no subtasks.
      expect(find.text('КОГДА'), findsNothing);
      expect(find.text('Указать время'), findsNothing);
      expect(find.text('Указать дату'), findsNothing);
      expect(find.text('ПОВТОРЯТЬ'), findsNothing);
      expect(find.text('Добавить подзадачу'), findsNothing);

      // And the rest come back when the user thinks better of it.
      await tester.tap(find.text('Чекбокс'));
      await tester.pumpAndSettle();
      expect(find.text('КОГДА'), findsOneWidget);
      expect(find.text('ПОВТОРЯТЬ'), findsOneWidget);
    });

    testWidgets('a task opened from a future day starts today', (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            locale: const Locale('ru', 'RU'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ru', 'RU')],
            home: CreateTaskPage(
              mode: TaskFormMode.create,
              initialDate: tomorrow,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Значение'));
      await tester.pumpAndSettle();

      // "Days since" counted from tomorrow would run backwards.
      final now = DateTime.now();
      final today = DateFormat('d MMMM yyyy', 'ru_RU').format(now);
      expect(find.text(today), findsOneWidget);
    });

    testWidgets('is saved with a start date and nothing else', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Смена белья');
      // Set up the other modes' state first, to prove it is not saved.
      await _toggle(tester, 'Указать время');
      await _toggle(tester, 'ПОВТОРЯТЬ');
      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Значение'));
      await tester.pumpAndSettle();

      await _save(tester);

      final saved = (await tester.runAsync(
        () => db.select(db.tasks).get(),
      ))!.single;
      expect(saved.title, 'Смена белья');
      expect(saved.trackingMode, TrackingMode.value);
      expect(saved.repeatType, isNull);
      expect(saved.repeatInterval, isNull);
      expect(saved.repeatDaysMask, isNull);
      expect(saved.scheduledTimeMinutes, isNull);
      expect(saved.endTimeMinutes, isNull);
      expect(saved.targetValue, isNull);
      expect(saved.targetDurationMinutes, isNull);
      final now = DateTime.now();
      expect(saved.startDate, DateTime(now.year, now.month, now.day));
    });

    testWidgets('turning a habit into one drops its schedule', (tester) async {
      final habit = await tester.runAsync(() async {
        final id = await db.tasksDao.insertTask(
          TasksCompanion.insert(
            title: 'Зарядка',
            repeatType: const Value(RepeatType.weekly),
            repeatDaysMask: const Value(0x15),
            scheduledTimeMinutes: const Value(8 * 60),
            endTimeMinutes: const Value(9 * 60),
            startDate: Value(DateTime(2026, 5, 20)),
          ),
        );
        return (await db.tasksDao.getTaskById(id))!;
      });
      await tester.pumpWidget(_form(mode: TaskFormMode.edit, task: habit));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Значение'));
      await tester.pumpAndSettle();
      await _save(tester);

      final saved = (await tester.runAsync(
        () => db.tasksDao.getTaskById(habit!.id),
      ))!;
      expect(saved.trackingMode, TrackingMode.value);
      expect(saved.repeatType, isNull);
      expect(saved.repeatDaysMask, isNull);
      expect(saved.scheduledTimeMinutes, isNull);
      expect(saved.endTimeMinutes, isNull);
      // The start date it had is the day the watching begins.
      expect(saved.startDate, DateTime(2026, 5, 20));
    });

    testWidgets('a saved one opens with its mode and date intact', (
      tester,
    ) async {
      await _openValueForm(tester);

      expect(find.text('ОТСЛЕЖИВАТЬ С'), findsOneWidget);
      expect(find.text('20 мая 2026'), findsOneWidget);
      expect(find.text('Целевое значение'), findsNothing);
    });

    testWidgets('the other three modes still work', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();
      expect(find.text('Цель: 1 раз'), findsOneWidget);

      await tester.tap(find.text('Таймер'));
      await tester.pumpAndSettle();
      expect(find.text('Цель: без цели'), findsOneWidget);
      expect(find.text('Цель: 1 раз'), findsNothing);

      await tester.tap(find.text('Чекбокс'));
      await tester.pumpAndSettle();
      expect(find.text('Цель: без цели'), findsNothing);
    });
  });

  group('tracking targets', () {
    testWidgets('a counter always counts at least once', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();

      // "без цели" is the checkbox.
      expect(find.text('Цель: 1 раз'), findsOneWidget);
      expect(find.textContaining('без цели'), findsNothing);
    });

    testWidgets('a fractional target becomes whole when switching to counter', (
      tester,
    ) async {
      await _openValueForm(tester, targetValue: 2.5);

      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();

      // 2.5 cannot stay 2.5 taps.
      expect(find.text('Цель: 3 раза'), findsOneWidget);
    });

    testWidgets(
      'a timer starts without a target and takes one from the sheet',
      (tester) async {
        await tester.pumpWidget(_form());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Таймер'));
        await tester.pumpAndSettle();
        expect(find.text('Цель: без цели'), findsOneWidget);

        await tester.tap(find.text('Цель: без цели'));
        await tester.pumpAndSettle();
        expect(find.text('Своя длительность'), findsOneWidget);

        // Two hours and five minutes via the sheet's own steppers. A stepper
        // reports `value + step` rather than a delta, so each tap needs a frame
        // before the next one.
        Finder plusIn(String label) => find.descendant(
          of: find
              .ancestor(of: find.text(label), matching: find.byType(Column))
              .first,
          matching: find.byIcon(LucideIcons.plus),
        );
        await tester.tap(plusIn('Часы'));
        await tester.pumpAndSettle();
        await tester.tap(plusIn('Часы'));
        await tester.pumpAndSettle();
        await tester.tap(plusIn('Минуты'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Готово'));
        await tester.pumpAndSettle();

        expect(find.text('Цель: 2 ч 5 мин'), findsOneWidget);
      },
    );

    testWidgets('the counter target can be typed in', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Счётчик'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Цель: 1 раз'));
      await tester.pumpAndSettle();

      expect(find.text('Своя цель'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '10000');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Готово'));
      await tester.pumpAndSettle();

      expect(find.text('Цель: 10000 раз'), findsOneWidget);
    });
  });

  group('when', () {
    testWidgets('date and time are switches, both on the card', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      expect(find.text('Указать дату'), findsOneWidget);
      expect(find.text('Указать время'), findsOneWidget);
      // The date is on from the start and shows in the card's caption.
      expect(find.textContaining('Сегодня'), findsOneWidget);
    });

    testWidgets('switching the date off switches the time off with it', (
      tester,
    ) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'Указать время');
      expect(find.text('С'), findsOneWidget);

      await _toggle(tester, 'Указать дату');

      expect(find.text('С'), findsNothing);
      expect(find.textContaining('Сегодня'), findsNothing);
      // And without a date the time switch cannot be turned back on.
      final timeSwitch = tester.widget<Switch>(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('Указать время'),
                matching: find.byType(Row),
              )
              .first,
          matching: find.byType(Switch),
        ),
      );
      expect(timeSwitch.value, isFalse);
      expect(timeSwitch.onChanged, isNull);
    });

    testWidgets('the time comes back off when the date does', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'Указать время');
      await _toggle(tester, 'Указать дату');
      await _toggle(tester, 'Указать дату');

      expect(find.text('С'), findsNothing);
      await _toggle(tester, 'Указать время');
      expect(find.text('С'), findsOneWidget);
    });

    testWidgets('a duration chip sets the end of the range', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await _toggle(tester, 'Указать время');
      expect(find.text('ДО'), findsOneWidget);

      await tester.tap(find.text('30 мин'));
      await tester.pumpAndSettle();

      expect(find.text('ДО · 30 МИН'), findsOneWidget);
    });

    testWidgets('a time without a date is not saved', (tester) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Задача');
      await _toggle(tester, 'Указать время');
      await _toggle(tester, 'Указать дату');
      await _save(tester);

      final saved = (await tester.runAsync(
        () => db.select(db.tasks).get(),
      ))!.single;
      expect(saved.startDate, isNull);
      expect(saved.scheduledTimeMinutes, isNull);
    });
  });

  group('who', () {
    testWidgets('the card is absent while the user has no group', (
      tester,
    ) async {
      await tester.pumpWidget(_form());
      await tester.pumpAndSettle();

      expect(find.text('КОМУ'), findsNothing);
    });
  });
}
