/// Which of two versions of the same row wins.
///
/// Pure: no database, no network, nothing to mock. The same shape as
/// `taskRemindersFor` and `timerNotificationsFor` — the decision is separated
/// from the machinery that acts on it precisely because this is the part worth
/// testing, and the part that fails quietly. A wrong answer here does not throw
/// and does not log; it silently drops somebody's writing.
library;

/// The winner when the same row was edited in two places.
///
/// **Last write wins.** The local database stays the working copy — everything
/// the app does is written there first and nothing waits for a server — but a
/// later edit beats an earlier one whichever device made it. Anything else and
/// the second device is pointless: a note written on the tablet would never be
/// allowed to reach the phone.
///
/// Only whole **seconds** are comparable. Drift stores a `DateTime` as
/// `millisecondsSinceEpoch ~/ 1000`, so two edits inside the same second arrive
/// indistinguishable, and this is common enough to matter: a save writes the
/// note and its labels one after another.
///
/// The tie is broken on [uid], which sounds arbitrary and is the point. What
/// matters is not *which* version wins a tie but that **both devices pick the
/// same one** without conferring — the alternative is each keeping its own,
/// each believing it is up to date, and the two never converging again. A uid
/// is stable, opaque and identical on both sides, so comparing it as a string
/// gives the same answer everywhere.
bool remoteWins({
  required DateTime localUpdatedAt,
  required DateTime remoteUpdatedAt,
  required String localUid,
  required String remoteUid,
}) {
  final local = storedSeconds(localUpdatedAt);
  final remote = storedSeconds(remoteUpdatedAt);
  if (remote != local) return remote > local;

  // Same second. Deterministic, and deliberately not "local wins": a rule that
  // favours whoever is asking is not a rule, it is two rules, and the devices
  // would each keep their own copy forever.
  return remoteUid.compareTo(localUid) > 0;
}

/// What to do with one row that came down from the server.
enum PullAction {
  /// This device has never seen it. Insert, clean.
  insert,

  /// The server's version is the one to keep. Overwrite, clean.
  overwrite,

  /// Ours is newer. Leave it alone — it is still marked unsent, so the next
  /// push carries it up and settles the disagreement there.
  keepLocal,

  /// It was deleted on another device. Delete it here too.
  delete,

  /// Nothing to do: the server's copy is the one we already have.
  skip,
}

/// Decides [PullAction] for a single row.
///
/// Pure, and the reason it is separated from the engine at all: this is four
/// lines of branching that decide whether somebody's writing survives, and it
/// is far cheaper to enumerate the cases here than to reproduce them against a
/// live server.
///
/// [localUpdatedAt] and [localDirty] are null when the row is unknown here.
///
/// **A deletion wins outright**, without consulting the clocks. That is a
/// choice, and the losing case is real: delete a note on the phone, edit it on
/// the tablet, and the edit goes with it. It is still the better of the two —
/// the opposite rule resurrects a note the user deliberately threw away, on a
/// device they are not looking at, and there is no gesture in the app that
/// means "no, really, delete it". Losing an edit is a mistake the user can see
/// and redo; a note that will not stay deleted is one they cannot fix.
PullAction pullAction({
  required bool remoteDeleted,
  required DateTime? localUpdatedAt,
  required bool localDirty,
  required DateTime remoteUpdatedAt,
  required String localUid,
  required String remoteUid,
}) {
  final known = localUpdatedAt != null;

  if (remoteDeleted) return known ? PullAction.delete : PullAction.skip;
  if (!known) return PullAction.insert;

  // Not dirty means this copy *is* what was last agreed with the server, so
  // anything that arrives is by definition newer. No clocks needed, which also
  // means no way for a skewed one to refuse an update.
  if (!localDirty) return PullAction.overwrite;

  return remoteWins(
        localUpdatedAt: localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
        localUid: localUid,
        remoteUid: remoteUid,
      )
      ? PullAction.overwrite
      : PullAction.keepLocal;
}

/// A moment at the resolution the database actually keeps.
///
/// Drift stores a `DateTime` as `millisecondsSinceEpoch ~/ 1000` and reads it
/// back with the milliseconds gone. Anything comparing two timestamps has to
/// compare them *as stored*, or it decides by a difference the database threw
/// away — which is a bug that looks like nothing at all, right up until two
/// versions of a note are declared identical and one of them is dropped.
///
/// The single definition of that fact: `DiaryDao.updateEntryById` uses it to
/// keep a note's stamps strictly increasing, and [remoteWins] to decide when
/// two edits are genuinely simultaneous.
int storedSeconds(DateTime moment) => moment.millisecondsSinceEpoch ~/ 1000;
