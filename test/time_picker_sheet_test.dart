import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/create_task_page.dart';
import 'package:todo_app/widgets/time_picker_sheet.dart';

/// Opens the sheet from a button and records what it returned.
Widget _host(int initial, void Function(int?) onResult) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => onResult(
          await showTimePickerSheet(context, initialMinutes: initial),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

Finder _wheel(String key) => find.byKey(ValueKey(key));

/// Scrolls a wheel by whole rows (48 px each; a drag up moves to later values).
Future<void> _scroll(WidgetTester tester, String key, int rows) async {
  await tester.drag(_wheel(key), Offset(0, -48.0 * rows));
  await tester.pumpAndSettle();
}

void main() {
  group('the time sheet', () {
    testWidgets('opens on the time it was given and hands it back', (
      tester,
    ) async {
      int? result = -1;
      await tester.pumpWidget(_host(14 * 60 + 30, (v) => result = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Время'), findsOneWidget);
      expect(find.text('Готово'), findsOneWidget);

      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(result, 14 * 60 + 30);
    });

    testWidgets('the hours and the minutes scroll on their own', (
      tester,
    ) async {
      int? result;
      await tester.pumpWidget(_host(8 * 60, (v) => result = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await _scroll(tester, 'hours', 3);
      await _scroll(tester, 'minutes', 25);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      expect(result, 11 * 60 + 25);
    });

    testWidgets('dismissing it returns nothing', (tester) async {
      int? result = -1;
      await tester.pumpWidget(_host(9 * 60, (v) => result = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // A tap on the scrim, above the sheet.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('the picked time is exact, not snapped to a grid', (
      tester,
    ) async {
      int? result;
      await tester.pumpWidget(_host(15 * 60 + 31, (v) => result = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      expect(result, 15 * 60 + 31);
    });
  });

  group('in the task form', () {
    late AppDatabase db;

    setUpAll(() async {
      await initializeDateFormatting('ru_RU', null);
    });

    setUp(() {
      db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first;
      view.physicalSize = const Size(1000, 2600);
      view.devicePixelRatio = 1.0;
      addTearDown(view.resetPhysicalSize);
      addTearDown(view.resetDevicePixelRatio);
    });

    Widget form({Task? task}) => ProviderScope(
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
          mode: task == null ? TaskFormMode.create : TaskFormMode.edit,
          task: task,
        ),
      ),
    );

    Future<Task> insertTimed(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          final id = await db.tasksDao.insertTask(
            TasksCompanion.insert(
              title: 'Встреча',
              scheduledTimeMinutes: const Value(14 * 60 + 30),
              endTimeMinutes: const Value(15 * 60 + 30),
              startDate: Value(DateTime(2026, 5, 20)),
            ),
          );
          return (await db.tasksDao.getTaskById(id))!;
        }))!;

    testWidgets('has no wheel on the page, just a line with the time', (
      tester,
    ) async {
      await tester.pumpWidget(form(task: await insertTimed(tester)));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListWheelScrollView), findsNothing);
      // Start and end are two blocks, not a line.
      expect(find.text('14:30'), findsOneWidget);
      expect(find.text('15:30'), findsOneWidget);
    });

    testWidgets('the line opens the sheet and takes the new time', (
      tester,
    ) async {
      await tester.pumpWidget(form(task: await insertTimed(tester)));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('14:30'));
      await tester.pumpAndSettle();
      expect(find.text('Время'), findsOneWidget);

      await _scroll(tester, 'hours', 2);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      // The duration rides along with the start.
      expect(find.text('16:30'), findsOneWidget);
      expect(find.text('17:30'), findsOneWidget);
      expect(find.byType(ListWheelScrollView), findsNothing);
    });

    testWidgets('an end past midnight is marked', (tester) async {
      final task = (await tester.runAsync(() async {
        final id = await db.tasksDao.insertTask(
          TasksCompanion.insert(
            title: 'Ночная смена',
            scheduledTimeMinutes: const Value(23 * 60),
            endTimeMinutes: const Value(24 * 60),
            startDate: Value(DateTime(2026, 5, 20)),
          ),
        );
        return (await db.tasksDao.getTaskById(id))!;
      }))!;
      await tester.pumpWidget(form(task: task));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.text('23:00'), findsOneWidget);
      expect(find.text('00:00 +1'), findsOneWidget);
    });
  });
}
