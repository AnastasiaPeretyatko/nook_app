import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../utils/cycle_marks.dart';

part 'cycle_dao.g.dart';

/// The cycle's day marks: reads for the screen, and the surface the sync engine
/// works through. Shaped after the day-mark half of [TasksDao], and for the same
/// reasons — see `CycleDays` for why a day is its own identity and nothing here
/// ever deletes one.
@DriftAccessor(tables: [CycleDays])
class CycleDao extends DatabaseAccessor<AppDatabase> with _$CycleDaoMixin {
  CycleDao(super.db);

  static DateTime dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  Stream<List<CycleDay>> watchAll() => select(cycleDays).watch();

  Future<CycleDay?> getDay(DateTime day) => (select(
    cycleDays,
  )..where((d) => d.date.equals(dayOf(day)))).getSingleOrNull();

  /// Saves the whole of one day. An all-empty day is saved too, not deleted: that
  /// is how a mark taken back reaches the other devices.
  Future<void> saveDay(
    DateTime day, {
    int flow = 0,
    int? mood,
    Set<int> symptoms = const {},
    int? discharge,
    int? sex,
    bool pill = false,
    String? note,
  }) {
    return transaction(() async {
      final date = dayOf(day);
      final existing = await getDay(date);
      final trimmed = note?.trim();
      final row = CycleDaysCompanion(
        date: Value(date),
        flow: Value(flow),
        mood: Value(mood),
        symptoms: Value(encodeSymptoms(symptoms)),
        discharge: Value(discharge),
        sex: Value(sex),
        pill: Value(pill),
        note: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
        dirty: const Value(true),
        updatedAt: Value(TasksDao.stampAfter(existing?.updatedAt)),
      );
      await into(
        cycleDays,
      ).insert(row, onConflict: DoUpdate((_) => row, target: [cycleDays.date]));
    });
  }

  /// Takes every mark off [day]. The row stays, empty — that is how the other
  /// devices hear of it (see [saveDay]).
  Future<void> clearDay(DateTime day) => saveDay(day);

  /// What an ordinary period day is marked with when it is added from the
  /// calendar, where only "was it a period day" is asked: the middle of the
  /// flow list ("Средние").
  static const defaultFlow = 3;

  /// Marks [day] as a period day, or takes that back, **leaving everything else
  /// on the day as it was** — the mood, the symptoms, the note. A day that
  /// already has a flow keeps its strength when it is marked again.
  Future<void> setPeriodDay(DateTime day, {required bool on}) {
    return transaction(() async {
      final existing = await getDay(day);
      await saveDay(
        day,
        flow: on
            ? (existing != null && existing.flow > 0
                  ? existing.flow
                  : defaultFlow)
            : 0,
        mood: existing?.mood,
        symptoms: parseSymptoms(existing?.symptoms ?? ''),
        discharge: existing?.discharge,
        sex: existing?.sex,
        pill: existing?.pill ?? false,
        note: existing?.note,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // The surface the sync engine works through (see `TasksDao`'s twin of it).
  // ---------------------------------------------------------------------------

  Future<List<CycleDay>> pending() =>
      (select(cycleDays)..where((d) => d.dirty.equals(true))).get();

  /// Marks the sent days as settled — only where the row is still the one that
  /// was sent, so an edit made during the send keeps its mark.
  Future<void> clearDirty(Iterable<CycleDay> sent) async {
    for (final day in sent) {
      await (update(cycleDays)..where(
            (d) =>
                d.date.equals(day.date) &
                d.updatedAt.isSmallerOrEqualValue(day.updatedAt),
          ))
          .write(const CycleDaysCompanion(dirty: Value(false)));
    }
  }

  /// Takes the server's answer for a day, **without** marking it for sending.
  Future<void> applyRemote(CycleDaysCompanion day) async {
    final row = day.copyWith(
      date: Value(dayOf(day.date.value)),
      dirty: const Value(false),
    );
    await into(
      cycleDays,
    ).insert(row, onConflict: DoUpdate((_) => row, target: [cycleDays.date]));
  }

  /// "Leave what is here on this phone": nothing is offered to the server.
  Future<void> keepLocal() =>
      update(cycleDays).write(const CycleDaysCompanion(dirty: Value(false)));

  /// Everything here goes up again — an account that changed hands.
  Future<void> markAllDirty() =>
      update(cycleDays).write(const CycleDaysCompanion(dirty: Value(true)));

  Future<void> wipeAll() => delete(cycleDays).go();
}
