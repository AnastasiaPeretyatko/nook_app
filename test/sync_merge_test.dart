import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/sync/merge.dart';

/// The rule that decides whose version of a note survives.
///
/// Pure, so it is tested the way `taskRemindersFor` and `timerNotificationsFor`
/// are: hand-built values in, an answer out, no database and no network. Worth
/// the attention because it is the quietest failure in the whole feature — a
/// wrong answer throws nothing and logs nothing, it just loses what somebody
/// wrote.
void main() {
  pullDecisions();

  const local = 'aaaa-1111';
  const remote = 'bbbb-2222';

  DateTime at(int second) => DateTime.utc(2026, 8, 26, 12, 0, second);

  group('last write wins', () {
    test('the later remote edit is taken', () {
      expect(
        remoteWins(
          localUpdatedAt: at(10),
          remoteUpdatedAt: at(20),
          localUid: local,
          remoteUid: remote,
        ),
        isTrue,
      );
    });

    test('an older remote edit is refused', () {
      expect(
        remoteWins(
          localUpdatedAt: at(20),
          remoteUpdatedAt: at(10),
          localUid: local,
          remoteUid: remote,
        ),
        isFalse,
      );
    });

    test('a difference under a second does not count', () {
      // Drift keeps whole seconds, so this pair is stored identically. Reading
      // the milliseconds would decide by something the database did not keep.
      expect(
        remoteWins(
          localUpdatedAt: DateTime.utc(2026, 8, 26, 12, 0, 5, 100),
          remoteUpdatedAt: DateTime.utc(2026, 8, 26, 12, 0, 5, 900),
          localUid: 'zzzz',
          remoteUid: 'aaaa',
        ),
        isFalse,
        reason: 'both are second 5; the uid decides, and "aaaa" < "zzzz"',
      );
    });
  });

  group('a tie in the same second', () {
    test('is broken by the uid, not by who is asking', () {
      expect(
        remoteWins(
          localUpdatedAt: at(7),
          remoteUpdatedAt: at(7),
          localUid: 'aaaa',
          remoteUid: 'bbbb',
        ),
        isTrue,
      );
      expect(
        remoteWins(
          localUpdatedAt: at(7),
          remoteUpdatedAt: at(7),
          localUid: 'bbbb',
          remoteUid: 'aaaa',
        ),
        isFalse,
      );
    });

    test('gives both devices the same winner', () {
      // The property that actually matters. Phone and tablet ask the question
      // from opposite sides — each one's "local" is the other's "remote" — and
      // they must not both decide they are already up to date, or the row never
      // converges again.
      final phoneKeepsItsOwn = !remoteWins(
        localUpdatedAt: at(7),
        remoteUpdatedAt: at(7),
        localUid: local,
        remoteUid: remote,
      );
      final tabletKeepsItsOwn = !remoteWins(
        localUpdatedAt: at(7),
        remoteUpdatedAt: at(7),
        localUid: remote,
        remoteUid: local,
      );

      expect(
        phoneKeepsItsOwn,
        isNot(tabletKeepsItsOwn),
        reason: 'exactly one side may keep its copy',
      );
    });

    test('the same row against itself changes nothing', () {
      expect(
        remoteWins(
          localUpdatedAt: at(7),
          remoteUpdatedAt: at(7),
          localUid: local,
          remoteUid: local,
        ),
        isFalse,
      );
    });
  });
}

/// What to do with one row that arrived from the server.
///
/// Enumerated here rather than discovered against a live server: it is four
/// branches deciding whether somebody's writing survives, and every wrong
/// answer is silent.
void pullDecisions() {
  DateTime at(int second) => DateTime.utc(2026, 8, 26, 12, 0, second);

  PullAction decide({
    bool deleted = false,
    DateTime? localAt,
    bool dirty = false,
    required DateTime remoteAt,
    String localUid = 'aaaa',
    String remoteUid = 'aaaa',
  }) => pullAction(
    remoteDeleted: deleted,
    localUpdatedAt: localAt,
    localDirty: dirty,
    remoteUpdatedAt: remoteAt,
    localUid: localUid,
    remoteUid: remoteUid,
  );

  group('a note this device has never seen', () {
    test('is taken', () {
      expect(decide(remoteAt: at(10)), PullAction.insert);
    });

    test('unless it only arrived to say it was deleted', () {
      // Nothing to delete, and inserting it would resurrect it on this device
      // alone — the one place it had never existed.
      expect(decide(deleted: true, remoteAt: at(10)), PullAction.skip);
    });
  });

  group('a note this device already has', () {
    test('is overwritten when nothing was changed here', () {
      // Not dirty means this copy *is* the last thing agreed with the server,
      // so whatever arrived is newer by construction. No clock is consulted,
      // which also means no skewed clock can refuse an update.
      expect(
        decide(localAt: at(30), remoteAt: at(10)),
        PullAction.overwrite,
        reason: 'even an older-looking stamp wins over a copy we did not touch',
      );
    });

    test('keeps the local edit when ours is newer', () {
      expect(
        decide(localAt: at(30), dirty: true, remoteAt: at(10)),
        PullAction.keepLocal,
      );
    });

    test('yields when theirs is newer', () {
      expect(
        decide(localAt: at(10), dirty: true, remoteAt: at(30)),
        PullAction.overwrite,
      );
    });

    test('is deleted when it was deleted elsewhere', () {
      expect(
        decide(deleted: true, localAt: at(10), remoteAt: at(30)),
        PullAction.delete,
      );
    });

    test('is deleted even when this device has an unsent edit', () {
      // The deliberate loss. A deletion is a destructive act the user meant;
      // the opposite rule brings a thrown-away note back on a device they are
      // not looking at, and there is no gesture that would mean "delete it,
      // really".
      expect(
        decide(deleted: true, localAt: at(99), dirty: true, remoteAt: at(1)),
        PullAction.delete,
      );
    });
  });
}
