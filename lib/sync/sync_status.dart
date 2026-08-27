import 'package:intl/intl.dart';

/// Where syncing stands, as far as the user is concerned.
///
/// Not the same list as `SyncOutcome`: that one says how the last *run* ended,
/// this one says what to tell somebody looking at the settings screen. The
/// difference is `running`, which is not an outcome at all, and `skipped`,
/// which is not worth mentioning.
enum SyncPhase {
  /// Nothing happening. What was last managed is in [SyncStatus.lastSuccessAt].
  idle,

  /// A run is in flight.
  running,

  /// The last attempt found no network. Not a fault — it will be retried.
  offline,

  /// The last attempt reached the server and was refused.
  failed,
}

/// The phase, plus when it last worked.
///
/// [lastSuccessAt] outlives the phase and the app: it is the answer to the
/// question people actually ask of a sync, which is not "what are you doing"
/// but "when did you last manage".
class SyncStatus {
  const SyncStatus({this.phase = SyncPhase.idle, this.lastSuccessAt});

  final SyncPhase phase;
  final DateTime? lastSuccessAt;

  SyncStatus copyWith({SyncPhase? phase, DateTime? lastSuccessAt}) =>
      SyncStatus(
        phase: phase ?? this.phase,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      );

  // Value equality so a rebuild that changes nothing does not repaint.
  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.lastSuccessAt == lastSuccessAt;

  @override
  int get hashCode => Object.hash(phase, lastSuccessAt);
}

/// The one line under "Синхронизация": on the settings row that leads to the
/// sync screen, and under the switch on the screen itself.
///
/// Shared so the two cannot disagree — a row saying "Синхронизировано 5 минут
/// назад" over a screen saying "Войдите в аккаунт" is the kind of thing that
/// makes a user stop trusting either.
///
/// The order is the order the obstacles come in. Why the switch is where it is
/// wins over what it would do, because a greyed-out control with no explanation
/// says no without saying why; a pending question wins over the status, since
/// nothing is being synced until it is answered; and once it is actually
/// running, what matters is not what the switch does — that is obvious from the
/// switch — but whether it is working.
String syncSummaryLabel({
  required bool ready,
  required bool signedIn,
  required bool needsDecision,
  required bool active,
  required SyncStatus status,
  required DateTime now,
}) {
  if (!ready) return 'Сервер недоступен';
  if (!signedIn) return 'Войдите в аккаунт, чтобы включить';
  if (needsDecision) return 'Ответьте на вопрос о данных на устройстве';
  if (active) return syncStatusLabel(status, now: now);
  return 'Заметки будут доступны на других устройствах';
}

/// One line for the settings screen.
///
/// [now] is passed in rather than read, so this stays a pure function — the
/// alternative is a test that only passes while the clock cooperates.
String syncStatusLabel(SyncStatus status, {required DateTime now}) {
  switch (status.phase) {
    case SyncPhase.running:
      return 'Синхронизация…';
    case SyncPhase.offline:
      return 'Нет связи — повторим позже';
    case SyncPhase.failed:
      return 'Не удалось синхронизировать';
    case SyncPhase.idle:
      final at = status.lastSuccessAt;
      if (at == null) return 'Ещё не синхронизировалось';
      return 'Синхронизировано ${_ago(at, now)}';
  }
}

/// "5 минут назад", "2 часа назад", or a date once that stops being useful.
///
/// Russian counts three ways, and a status line reading "1 минут назад" looks
/// like a bug in the app rather than a fact about the time.
String _ago(DateTime at, DateTime now) {
  final gap = now.difference(at);
  if (gap.isNegative || gap.inMinutes < 1) return 'только что';
  if (gap.inMinutes < 60) return '${_plural(gap.inMinutes, _minutes)} назад';
  if (gap.inHours < 24) return '${_plural(gap.inHours, _hours)} назад';
  if (gap.inDays == 1) return 'вчера';
  return DateFormat('d MMMM', 'ru_RU').format(at.toLocal());
}

const _minutes = ('минуту', 'минуты', 'минут');
const _hours = ('час', 'часа', 'часов');

String _plural(int count, (String, String, String) forms) {
  final hundred = count % 100;
  final ten = count % 10;
  final form = (hundred >= 11 && hundred <= 14)
      ? forms.$3
      : ten == 1
      ? forms.$1
      : (ten >= 2 && ten <= 4)
      ? forms.$2
      : forms.$3;
  return '$count $form';
}
