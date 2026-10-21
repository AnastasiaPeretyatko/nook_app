import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/pages/archive_page.dart';

/// The archive is a shelf for habits put away by hand — nothing else.
void main() {
  final day = DateTime(2026, 10, 1);

  Task task(
    int id,
    String title, {
    TaskStatus status = TaskStatus.archived,
    RepeatType? repeat,
    TrackingMode mode = TrackingMode.checkbox,
  }) => Task(
    id: id,
    dirty: false,
    title: title,
    status: status,
    repeatType: repeat,
    trackingMode: mode,
    startDate: day,
    createdAt: day,
    updatedAt: day,
  );

  Future<void> open(WidgetTester tester, List<Task> tasks) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
          allLogsProvider.overrideWith(
            (ref) => Stream.value(const <TaskLog>[]),
          ),
          myUidProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          locale: const Locale('ru', 'RU'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru', 'RU')],
          home: const ArchivePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUpAll(() => initializeDateFormatting('ru_RU', null));

  testWidgets(
    'lists habits and "Значение" tasks put away, and no one-off task',
    (tester) async {
      await open(tester, [
        task(1, 'Зарядка', repeat: RepeatType.daily),
        task(2, 'Смена белья', mode: TrackingMode.value),
        // A one-off task: archived by status, or ticked and active.
        task(3, 'Позвонить'),
        task(4, 'Купить хлеб', status: TaskStatus.active),
      ]);

      expect(find.text('Зарядка'), findsOneWidget);
      expect(find.text('Смена белья'), findsOneWidget);
      expect(find.text('Позвонить'), findsNothing);
      expect(find.text('Купить хлеб'), findsNothing);
      expect(find.text('Выполненные'), findsNothing);
    },
  );

  testWidgets('with only one-off tasks the archive reads as empty', (
    tester,
  ) async {
    await open(tester, [task(1, 'Позвонить')]);

    expect(find.text('Архив пуст'), findsOneWidget);
  });
}
