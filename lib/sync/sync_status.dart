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
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastSuccessAt,
    this.lastError,
  });

  final SyncPhase phase;
  final DateTime? lastSuccessAt;

  /// What the server said, when it said no. Null when the last run worked or
  /// never happened.
  ///
  /// Kept because the alternative is what this app shipped with: a screen that
  /// says "не удалось" and nothing else. A refusal is the one failure a user
  /// cannot wait out and cannot diagnose, and the message Postgres sends back
  /// names the table and the constraint — which is the difference between
  /// "синхронизация сломалась" and a bug that can be found.
  ///
  /// Not stored. It describes the attempt, not the device, and a message
  /// surviving a restart would go on accusing a server that has since been
  /// fixed.
  final String? lastError;

  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastSuccessAt,
    String? lastError,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
    lastError: lastError ?? this.lastError,
  );

  // Value equality so a rebuild that changes nothing does not repaint.
  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.lastSuccessAt == lastSuccessAt &&
      other.lastError == lastError;

  @override
  int get hashCode => Object.hash(phase, lastSuccessAt, lastError);
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

/// How the status card on the account screen should be painted.
enum SyncCardTone {
  /// Everything is where it should be.
  ok,

  /// Nothing is wrong, nothing is happening: off, manual, or waiting.
  neutral,

  /// A question the user has to answer before anything moves.
  attention,

  /// The last run was refused.
  error,
}

/// The title and the line under it on the account screen's status card
/// (`Account.dc.html`), with the tone to paint them in.
///
/// Pure, like [syncStatusLabel], so every state can be pinned without a screen.
/// The order is the order the obstacles come in: off, then a pending question,
/// then what the last run did, then the resting state.
({String title, String subtitle, SyncCardTone tone}) syncCardInfo({
  required bool enabled,
  required bool needsDecision,
  required bool changingHands,
  required bool auto,
  required SyncStatus status,
  required DateTime now,
}) {
  if (!enabled) {
    return (
      title: 'Синхронизация выключена',
      subtitle: 'Заметки и задачи остаются только на этом телефоне',
      tone: SyncCardTone.neutral,
    );
  }
  if (needsDecision) {
    return changingHands
        ? (
            title: 'На устройстве данные другого аккаунта',
            subtitle:
                'Их нужно перенести в ваш аккаунт или стереть — до этого '
                'синхронизация не работает',
            tone: SyncCardTone.attention,
          )
        : (
            title: 'Что делать с данными на устройстве?',
            subtitle: 'Синхронизация не начнётся, пока вы не ответите',
            tone: SyncCardTone.attention,
          );
  }

  final last = _lastTime(status.lastSuccessAt, now);
  switch (status.phase) {
    case SyncPhase.running:
      return (
        title: 'Синхронизация…',
        subtitle: last,
        tone: SyncCardTone.neutral,
      );
    case SyncPhase.failed:
      return (
        title: 'Не удалось синхронизировать',
        // The server's own words when it gave any: they name what was refused.
        subtitle: status.lastError ?? last,
        tone: SyncCardTone.error,
      );
    case SyncPhase.offline:
      return (
        title: 'Нет связи с сервером',
        subtitle: 'Повторим позже. $last',
        tone: SyncCardTone.neutral,
      );
    case SyncPhase.idle:
      if (status.lastSuccessAt == null) {
        return (
          title: auto ? 'Ещё не синхронизировалось' : 'Синхронизация вручную',
          subtitle: auto
              ? 'Начнётся само, как только появятся изменения'
              : 'Нажмите «Синхронизировать сейчас»',
          tone: SyncCardTone.neutral,
        );
      }
      return auto
          ? (
              title: 'Всё синхронизировано',
              subtitle: last,
              tone: SyncCardTone.ok,
            )
          : (
              title: 'Синхронизация вручную',
              subtitle: last,
              tone: SyncCardTone.neutral,
            );
  }
}

/// "Последний раз сегодня в 09:12", "…вчера в 21:40", "…12 октября в 09:12".
String _lastTime(DateTime? at, DateTime now) {
  if (at == null) return 'Ещё не синхронизировалось';
  final local = at.toLocal();
  final clock = DateFormat('HH:mm').format(local);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  final when = switch (days) {
    0 => 'сегодня',
    1 => 'вчера',
    _ => DateFormat('d MMMM', 'ru_RU').format(local),
  };
  return 'Последний раз $when в $clock';
}
