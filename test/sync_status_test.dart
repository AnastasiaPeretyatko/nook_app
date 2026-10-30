import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/sync/sync_service.dart';
import 'package:todo_app/sync/sync_status.dart';

/// The one line the settings screen says about syncing.
///
/// Worth testing because it is the only window onto a feature that otherwise
/// runs entirely out of sight — and because a status line that reads
/// "1 минут назад" makes the whole thing look broken even when it is working.
void main() {
  setUpAll(() => initializeDateFormatting('ru_RU', null));
  offlineErrorTests();

  final now = DateTime.utc(2026, 8, 26, 12, 0);
  String label(SyncStatus status) => syncStatusLabel(status, now: now);

  SyncStatus at(Duration ago) => SyncStatus(lastSuccessAt: now.subtract(ago));

  group('what it says', () {
    test('before anything has ever worked', () {
      expect(label(const SyncStatus()), 'Ещё не синхронизировалось');
    });

    test('while a run is going', () {
      expect(
        label(const SyncStatus(phase: SyncPhase.running)),
        'Синхронизация…',
      );
    });

    test('with no connection — a state, not a fault', () {
      expect(
        label(const SyncStatus(phase: SyncPhase.offline)),
        'Нет связи — повторим позже',
      );
    });

    test('when the server refused', () {
      expect(
        label(const SyncStatus(phase: SyncPhase.failed)),
        'Не удалось синхронизировать',
      );
    });

    test('a failure does not erase when it last worked', () {
      // The old answer is still true. Replacing it with nothing would say the
      // sync has never worked, which is a different and worse claim.
      final status = at(
        const Duration(hours: 2),
      ).copyWith(phase: SyncPhase.failed);
      expect(status.lastSuccessAt, isNotNull);
    });
  });

  group('how long ago', () {
    test('seconds read as "только что"', () {
      expect(
        label(at(const Duration(seconds: 20))),
        'Синхронизировано только что',
      );
    });

    test('counts minutes three ways, as Russian does', () {
      expect(label(at(const Duration(minutes: 1))), endsWith('1 минуту назад'));
      expect(label(at(const Duration(minutes: 3))), endsWith('3 минуты назад'));
      expect(label(at(const Duration(minutes: 5))), endsWith('5 минут назад'));
      expect(
        label(at(const Duration(minutes: 21))),
        endsWith('21 минуту назад'),
      );
      expect(
        label(at(const Duration(minutes: 11))),
        endsWith('11 минут назад'),
      );
    });

    test('counts hours the same way', () {
      expect(label(at(const Duration(hours: 1))), endsWith('1 час назад'));
      expect(label(at(const Duration(hours: 2))), endsWith('2 часа назад'));
      expect(label(at(const Duration(hours: 9))), endsWith('9 часов назад'));
    });

    test('yesterday is named, not counted', () {
      expect(label(at(const Duration(days: 1))), 'Синхронизировано вчера');
    });

    test('anything older becomes a date', () {
      // "137 часов назад" is arithmetic, not an answer.
      expect(label(at(const Duration(days: 12))), contains('августа'));
    });

    test('a clock that went backwards does not read as the future', () {
      // Phones adjust their clocks. A negative gap must not produce
      // "-3 минуты назад".
      expect(
        label(SyncStatus(lastSuccessAt: now.add(const Duration(minutes: 5)))),
        'Синхронизировано только что',
      );
    });
  });

  group('as a value', () {
    test(
      'two identical statuses are equal, so nothing repaints for nothing',
      () {
        expect(at(const Duration(minutes: 5)), at(const Duration(minutes: 5)));
        expect(
          at(const Duration(minutes: 5)).hashCode,
          at(const Duration(minutes: 5)).hashCode,
        );
      },
    );

    test('a changed phase is a changed status', () {
      expect(
        at(Duration.zero),
        isNot(at(Duration.zero).copyWith(phase: SyncPhase.running)),
      );
    });
  });
}

void offlineErrorTests() {
  group('which failures count as "no connection"', () {
    test('a connection reset halfway is one', () {
      expect(
        SyncService.isOfflineError(http.ClientException('reset by peer')),
        isTrue,
      );
    });

    test('a broken TLS handshake is one', () {
      expect(
        SyncService.isOfflineError(const HandshakeException('tls')),
        isTrue,
      );
    });

    test('the own server being unreachable is one, its refusal is not', () {
      expect(SyncService.isOfflineError(const ApiException.offline()), isTrue);
      expect(
        SyncService.isOfflineError(
          const ApiException(ApiFailure.server, status: 409, code: 'x'),
        ),
        isFalse,
      );
      expect(
        SyncService.isOfflineError(const ApiException.signInRequired()),
        isFalse,
      );
    });

    test('a refusal by the server is not', () {
      expect(SyncService.isOfflineError(StateError('duplicate key')), isFalse);
    });
  });
}
