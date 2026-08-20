import 'package:drift/drift.dart';
import 'enums.dart';

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get parentId => integer().nullable().references(Tasks, #id)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status =>
      textEnum<TaskStatus>().withDefault(const Constant('active'))();

  TextColumn get repeatType => textEnum<RepeatType>().nullable()();
  IntColumn get repeatInterval => integer().nullable()();

  /// Bitmask of the days a repeating task lands on, where day `d` sets bit
  /// `d - 1`. What a day means depends on [repeatType]: for
  /// [RepeatType.weekly] it is [DateTime.weekday] (Monday = bit 0 … Sunday =
  /// bit 6), for [RepeatType.monthly] it is the day of the month (1 … 31).
  /// Null means "not specified" — such tasks fall back to the weekday or day of
  /// month of their anchor date, as they did before this column existed.
  /// [RepeatType.daily] and [RepeatType.custom] ignore it.
  IntColumn get repeatDaysMask => integer().nullable()();

  TextColumn get trackingMode =>
      textEnum<TrackingMode>().withDefault(const Constant('checkbox'))();
  IntColumn get targetDurationMinutes => integer().nullable()();
  RealColumn get targetValue => real().nullable()();

  IntColumn get iconCodePoint => integer().nullable()();
  IntColumn get colorValue => integer().nullable()();

  IntColumn get scheduledTimeMinutes => integer().nullable()();
  IntColumn get endTimeMinutes => integer().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class TaskLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId => integer().references(Tasks, #id)();
  DateTimeColumn get date => dateTime()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  RealColumn get value => real().nullable()();
}

class TaskSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId => integer().references(Tasks, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
}

class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get type =>
      textEnum<EventType>().withDefault(const Constant('personal'))();
}
