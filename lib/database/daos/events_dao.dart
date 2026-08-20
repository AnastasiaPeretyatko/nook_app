import 'package:drift/drift.dart';
import '../app_database.dart';

part 'events_dao.g.dart';

@DriftAccessor(tables: [Events])
class EventsDao extends DatabaseAccessor<AppDatabase> with _$EventsDaoMixin {
  EventsDao(super.db);

  Stream<List<Event>> watchAllEvents() => select(events).watch();

  Stream<List<Event>> watchEventsForRange(DateTime from, DateTime to) =>
      (select(
        events,
      )..where((e) => e.startDate.isBetweenValues(from, to))).watch();

  Future<int> insertEvent(EventsCompanion event) => into(events).insert(event);

  Future<bool> updateEvent(EventsCompanion event) =>
      update(events).replace(event);

  Future<int> deleteEvent(int id) =>
      (delete(events)..where((e) => e.id.equals(id))).go();
}
