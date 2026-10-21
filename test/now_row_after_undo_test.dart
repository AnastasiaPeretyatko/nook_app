import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/widgets/home/task_timeline.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU', null));

  testWidgets('"Сейчас" takes its place at once when a task comes back', (
    tester,
  ) async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final minutes = now.hour * 60 + now.minute;
    // One task an hour behind the clock, one an hour ahead.
    final before = (minutes - 60).clamp(0, 1439);
    final after = (minutes + 60).clamp(0, 1439);
    if (before >= minutes || after <= minutes) return; // too close to midnight

    final ids = await tester.runAsync(() async {
      final a = await db.tasksDao.insertTask(
        TasksCompanion.insert(
          title: 'Первая',
          startDate: Value(today),
          scheduledTimeMinutes: Value(before),
        ),
      );
      final b = await db.tasksDao.insertTask(
        TasksCompanion.insert(
          title: 'Вторая',
          startDate: Value(today),
          scheduledTimeMinutes: Value(after),
        ),
      );
      return (a, b);
    });

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
          home: Scaffold(body: TaskTimeline(selectedDay: today)),
        ),
      ),
    );

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump();
    }

    double y(String text) => tester
        .getTopLeft(
          text == 'Сейчас' ? find.textContaining(text) : find.text(text),
        )
        .dy;

    await settle();
    expect(y('Первая') < y('Сейчас'), isTrue, reason: 'before delete');
    expect(y('Сейчас') < y('Вторая'), isTrue);

    final deleted = await tester.runAsync(
      () => db.tasksDao.deleteTaskCascade(ids!.$1),
    );
    await settle();
    expect(find.text('Первая'), findsNothing);
    expect(y('Сейчас') < y('Вторая'), isTrue);

    await tester.runAsync(() => db.tasksDao.restoreDeleted(deleted!));
    await settle();
    expect(y('Первая') < y('Сейчас'), isTrue, reason: 'after undo');
    expect(y('Сейчас') < y('Вторая'), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
