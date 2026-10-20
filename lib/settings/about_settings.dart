import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/settings/theme_provider.dart';
import 'package:todo_app/utils/cycle.dart';

enum Gender {
  female('Женский'),
  male('Мужской'),
  unspecified('Не указывать');

  const Gender(this.label);
  final String label;
}

/// The settings block "О себе": the gender and, for a woman, the cycle.
///
/// Kept in [sharedPreferencesProvider] and nowhere else, on purpose — it is
/// private health data, and the sync engine only ever reads the database, so
/// none of it leaves the phone (the screen promises as much).
class AboutSettings {
  const AboutSettings({
    this.gender = Gender.unspecified,
    this.trackCycle = true,
    this.lastStart,
    this.cycleLength = 27,
    this.periodLength = 5,
  });

  final Gender gender;

  /// The switch "Отслеживать цикл". On by default: picking "Женский" is already
  /// the choice, and the tab appears at once.
  final bool trackCycle;

  /// First day of the last period; null until the user says.
  final DateTime? lastStart;
  final int cycleLength;
  final int periodLength;

  /// The "Цикл" tab exists only for this.
  bool get cycleOn => gender == Gender.female && trackCycle;

  /// Null until the start of the last period is known — no forecast without it.
  CycleModel? get model => lastStart == null
      ? null
      : CycleModel(
          lastStart: lastStart!,
          length: cycleLength,
          periodLength: periodLength,
        );

  AboutSettings copyWith({
    Gender? gender,
    bool? trackCycle,
    DateTime? lastStart,
    int? cycleLength,
    int? periodLength,
  }) => AboutSettings(
    gender: gender ?? this.gender,
    trackCycle: trackCycle ?? this.trackCycle,
    lastStart: lastStart ?? this.lastStart,
    cycleLength: cycleLength ?? this.cycleLength,
    periodLength: periodLength ?? this.periodLength,
  );
}

const cycleLengthRange = (min: 21, max: 45);
const periodLengthRange = (min: 2, max: 10);

final aboutSettingsProvider =
    NotifierProvider<AboutSettingsNotifier, AboutSettings>(
      AboutSettingsNotifier.new,
    );

class AboutSettingsNotifier extends Notifier<AboutSettings> {
  static const _gender = 'about_gender';
  static const _track = 'cycle_track';
  static const _start = 'cycle_last_start';
  static const _length = 'cycle_length';
  static const _period = 'cycle_period_length';

  @override
  AboutSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final start = prefs.getString(_start);
    return AboutSettings(
      gender:
          Gender.values.asNameMap()[prefs.getString(_gender)] ??
          Gender.unspecified,
      trackCycle: prefs.getBool(_track) ?? true,
      lastStart: start == null ? null : DateTime.tryParse(start),
      cycleLength: (prefs.getInt(_length) ?? 27).clamp(
        cycleLengthRange.min,
        cycleLengthRange.max,
      ),
      periodLength: (prefs.getInt(_period) ?? 5).clamp(
        periodLengthRange.min,
        periodLengthRange.max,
      ),
    );
  }

  Future<void> setGender(Gender gender) async {
    state = state.copyWith(gender: gender);
    await ref.read(sharedPreferencesProvider).setString(_gender, gender.name);
  }

  Future<void> setTrackCycle(bool on) async {
    state = state.copyWith(trackCycle: on);
    await ref.read(sharedPreferencesProvider).setBool(_track, on);
  }

  Future<void> setLastStart(DateTime day) async {
    final d = DateTime(day.year, day.month, day.day);
    state = state.copyWith(lastStart: d);
    // `yyyy-MM-dd`, so it reads back as the same local day.
    await ref
        .read(sharedPreferencesProvider)
        .setString(_start, d.toIso8601String().substring(0, 10));
  }

  Future<void> setCycleLength(int days) async {
    final v = days.clamp(cycleLengthRange.min, cycleLengthRange.max);
    state = state.copyWith(cycleLength: v);
    await ref.read(sharedPreferencesProvider).setInt(_length, v);
  }

  Future<void> setPeriodLength(int days) async {
    final v = days.clamp(periodLengthRange.min, periodLengthRange.max);
    state = state.copyWith(periodLength: v);
    await ref.read(sharedPreferencesProvider).setInt(_period, v);
  }
}
