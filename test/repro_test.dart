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

/// Any moment at all: these tests never read a log's edit time. It exists
/// because the sync needs one and the column is therefore not nullable.
final _fixtureStamp = DateTime(2026, 1, 1);

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
  return Task(dirty: false, 
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
  TaskLog(dirty: false, updatedAt: _fixtureStamp, id: 1, taskId: 1, date: _today, completed: true),
  TaskLog(dirty: false, updatedAt: _fixtureStamp, id: 2, taskId: 3, date: _today, completed: false, value: 3),
  TaskLog(dirty: false, updatedAt: _fixtureStamp, id: 3, taskId: 2, date: _today, completed: false, value: 120),
  TaskLog(dirty: false, updatedAt: _fixtureStamp, 
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

  // Physical size **and** its density, because layout depends on neither alone:
  // what a widget is given is `physicalSize / devicePixelRatio`, and a pair that
  // no device ships is a viewport nothing has to survive.
  //
  // 720x1280 used to sit here at 3.0, which is 240pt wide — narrower than any
  // Android phone ever made, and the only size in the list that overflowed.
  // A 720p phone runs at 2.0. Swept afterwards: everything from 320pt up lays
  // out clean, and 320pt is the narrowest width that ships, so it is in the list
  // now rather than being assumed.
  for (final device in const [
    (name: 'small 480p', size: Size(640, 960), dpr: 2.0), //     320 x 480
    (name: '720p', size: Size(720, 1280), dpr: 2.0), //          360 x 640
    (name: '1080p short', size: Size(1080, 1920), dpr: 3.0), //  360 x 640
    (name: '1080p tall', size: Size(1080, 2400), dpr: 3.0), //   360 x 800
    (name: '1440p', size: Size(1440, 3120), dpr: 3.0), //        480 x 1040
  ]) {
    final size = device.size;
    testWidgets('MainScreen with data lays out on a ${device.name}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = device.dpr;
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
