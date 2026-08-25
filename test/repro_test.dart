import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

Task _task({
  required int id,
  required String title,
  RepeatType? repeatType,
  TrackingMode trackingMode = TrackingMode.checkbox,
  int? targetDurationMinutes,
  double? targetValue,
  int? scheduledTimeMinutes,
  int? endTimeMinutes,
  int? colorValue = 0xFFFFC1CC,
  String? iconKey,
}) {
  return Task(
    id: id,
    title: title,
    status: TaskStatus.active,
    repeatType: repeatType,
    trackingMode: trackingMode,
    targetDurationMinutes: targetDurationMinutes,
    targetValue: targetValue,
    scheduledTimeMinutes: scheduledTimeMinutes,
    endTimeMinutes: endTimeMinutes,
    colorValue: colorValue,
    iconKey: iconKey,
    startDate: _today.subtract(const Duration(days: 30)),
    createdAt: _today,
    updatedAt: _today,
  );
}

final _tasks = <Task>[
  // Habits (repeat != null) -> HabitsGrid
  _task(id: 1, title: 'Зарядка', repeatType: RepeatType.daily),
  _task(
    id: 2,
    title: 'Медитация 10 минут каждое утро подряд',
    repeatType: RepeatType.daily,
    trackingMode: TrackingMode.timer,
    targetDurationMinutes: 10,
  ),
  _task(
    id: 3,
    title: 'Вода',
    repeatType: RepeatType.daily,
    trackingMode: TrackingMode.counter,
    targetValue: 8,
  ),
  _task(id: 4, title: 'Чтение', repeatType: RepeatType.weekly),
  // Timed tasks -> TaskTimeline
  _task(
    id: 10,
    title: 'Подъём',
    repeatType: RepeatType.daily,
    scheduledTimeMinutes: 7 * 60,
  ),
  _task(
    id: 11,
    title: 'Работа',
    repeatType: RepeatType.daily,
    scheduledTimeMinutes: 9 * 60,
    endTimeMinutes: 18 * 60,
  ),
  _task(
    id: 12,
    title: 'Спортзал',
    repeatType: RepeatType.daily,
    scheduledTimeMinutes: 19 * 60,
    endTimeMinutes: 20 * 60,
  ),
  _task(
    id: 13,
    title: 'Ночная смена',
    repeatType: RepeatType.daily,
    scheduledTimeMinutes: 23 * 60,
    endTimeMinutes: 25 * 60,
  ),
  // Same start/end (zero-length) and back-to-back (zero gap)
  _task(
    id: 14,
    title: 'Ноль',
    repeatType: RepeatType.daily,
    scheduledTimeMinutes: 20 * 60,
    endTimeMinutes: 20 * 60,
  ),
  _task(
    id: 15,
    title: 'Сразу после',
    repeatType: RepeatType.daily,
    scheduledTimeMinutes: 20 * 60,
  ),
];

final _logs = <TaskLog>[
  TaskLog(id: 1, taskId: 1, date: _today, completed: true),
  TaskLog(id: 2, taskId: 3, date: _today, completed: false, value: 3),
  TaskLog(id: 3, taskId: 2, date: _today, completed: false, value: 120),
  TaskLog(
    id: 4,
    taskId: 1,
    date: _today.subtract(const Duration(days: 3)),
    completed: true,
  ),
];

/// Settings reads its own preferences, and [MainScreen] builds every tab at
/// once — so the real store has to stand in even for a layout test.
late SharedPreferences _prefs;

Widget _app() => ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(_prefs),
    rootTasksProvider.overrideWith((ref) => Stream.value(_tasks)),
    allTasksProvider.overrideWith((ref) => Stream.value(_tasks)),
    allLogsProvider.overrideWith((ref) => Stream.value(_logs)),
    logsForDateProvider.overrideWith((ref, date) => Stream.value(_logs)),
    logsBetweenProvider.overrideWith((ref, range) => Stream.value(_logs)),
  ],
  child: const MaterialApp(
    locale: Locale('ru', 'RU'),
    localizationsDelegates: [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: [Locale('ru', 'RU')],
    home: MainScreen(),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU', null);
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  for (final size in const [
    Size(1080, 2400),
    Size(1080, 1920),
    Size(720, 1280),
    Size(1440, 3120),
  ]) {
    testWidgets('MainScreen with data lays out at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Sanity: seeded data really did render.
      debugPrint(
        'TEXTS@$size: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
      );

      // Now visit every tab.
      for (final label in const ['Привычки', 'Дневник', 'Settings']) {
        final icon = {
          'Привычки': LucideIcons.repeat,
          'Дневник': LucideIcons.book_open,
          'Settings': LucideIcons.settings,
        }[label]!;
        await tester.tap(find.byIcon(icon).last);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      }
    });
  }
}
