import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/settings/about_settings.dart';
import 'package:todo_app/sync/providers.dart';
import 'package:todo_app/utils/note_images.dart';

/// The one question syncing has to ask before it starts: what happens to what
/// is already here?
///
/// It is asked per **account**, not per device. Answering once and never again
/// would mean that signing a second account into the same phone quietly hands
/// it whatever the first person had written — which is the failure worth
/// spending a dialog on, and the reason nothing syncs until this is settled.
///
/// ## Two questions, not one
///
/// The answers split by whether this device has ever been claimed, because the
/// data on it means two different things.
///
/// With **no previous claim** the rows are this same person's, written before
/// they had an account: the only question is whether they want them in it.
/// [upload] and [keepLocal] are both reasonable and neither is dangerous.
///
/// With a **previous claim by somebody else** the rows belong to another
/// account. Leaving them where they are is the failure this whole mechanism
/// exists to prevent — the new user would read, edit and be unable to sync
/// another person's tasks — so that answer is not offered at all. What is
/// offered is [adopt] and [wipe]: take them over properly, or remove them.
enum FirstSyncChoice {
  /// Send what is here. The rows keep their marks and go up on the next run,
  /// which is what would have happened anyway — this answer simply lets it.
  upload,

  /// Leave what is here alone. Marks cleared without anything being sent.
  keepLocal,

  /// Take over what the previous account left, as this account's own.
  ///
  /// Every note, task and invented label is given a **new identity** and marked
  /// to be sent. Both halves are needed and for different reasons: a row that
  /// already went up under the other account carries no mark, so nothing would
  /// ever offer it; and its uid is the primary key of a row that account owns
  /// on the server, so an upsert under this one is refused outright.
  adopt,

  /// Remove what the previous account left. The device keeps nothing of theirs.
  wipe,
}

/// Records the answer and lets syncing begin.
///
/// The watermark is reset in every case. It measures how far through *an
/// account's* history this device has read, so carrying one account's position
/// into another would make the new account's pull start in the middle and skip
/// everything written before — silently, and with nothing that would ever go
/// back for it.
Future<void> applyFirstSyncChoice(WidgetRef ref, FirstSyncChoice choice) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return;

  switch (choice) {
    case FirstSyncChoice.upload:
      // Nothing to do: the marks are already on, which is what "send it" means.
      break;

    case FirstSyncChoice.keepLocal:
      // Both halves, or the answer is only half honoured: every task and every
      // day mark on the device is unsent too, and clearing the diary alone would
      // let them all go up on the next run while the dialog said they would not.
      await ref.read(diaryDaoProvider).keepExistingEntriesLocal();
      await ref.read(tasksDaoProvider).keepExistingTasksLocal();
      await ref.read(cycleDaoProvider).keepLocal();

    case FirstSyncChoice.adopt:
      await ref.read(diaryDaoProvider).remintEntryUids();
      await ref.read(tasksDaoProvider).remintTaskUids();
      // A day is its own identity, so unlike a task it needs no new uid — only
      // to be offered again, under this account.
      await ref.read(cycleDaoProvider).markAllDirty();

    case FirstSyncChoice.wipe:
      await wipeAccountData(ref);
  }

  await ref.read(syncWatermarkProvider.notifier).set(null);
  await ref.read(syncClaimProvider.notifier).claimFor(user.id);
}

/// Everything one account left on this device, removed.
///
/// The database has no notion of who owns a row — there is no `user_id` column
/// anywhere in it and there never was — so this is the only thing that makes
/// the app tell the truth about whose data it is showing.
///
/// The pictures go with the rows. They live on disk rather than in the
/// database, so nothing else would ever reach them, and a photograph left
/// behind would be the most private part of what the previous person had.
///
/// The eight seeded moods stay: they are a constant of the app, shared by every
/// account, and removing them would leave the next person with an empty mood
/// picker. See [DiaryDao.wipeAllEntries].
Future<void> wipeAccountData(WidgetRef ref) async {
  await ref.read(tasksDaoProvider).wipeAllTasks();
  await ref.read(diaryDaoProvider).wipeAllEntries();
  await ref.read(cycleDaoProvider).wipeAll();
  await deleteAllNoteImages();
  await ref.read(aboutSettingsProvider.notifier).clear();
}

/// The same, plus forgetting everything stored *about* the sync.
///
/// What signing out and clearing the device leaves behind: no claim, no
/// watermark, no "last synced" — three answers that would otherwise describe
/// data which is no longer here, and which the next account to sign in would
/// read as being about theirs.
Future<void> forgetAccountData(WidgetRef ref) async {
  await wipeAccountData(ref);
  await ref.read(syncWatermarkProvider.notifier).set(null);
  await ref.read(syncStatusProvider.notifier).forget();
  await ref.read(syncClaimProvider.notifier).clear();
}

/// Asks, and returns null if the user backed out.
///
/// The counts are read first so the question can be concrete: "12 заметок и 30
/// задач" is something a person can weigh, "your data" is not. With nothing on
/// the device there is nothing to decide, and the answer is
/// [FirstSyncChoice.upload] without a dialog — sending an empty account is the
/// same as not sending one.
///
/// **Both** counts, and that is the whole reason this is not the notes-only
/// question it was. A device with no notes and thirty habits would otherwise
/// take the silent `upload` branch and hand them all over without asking, which
/// is exactly the moment the dialog exists for.
///
/// The counts are of **everything here**, not of what is waiting to be sent.
/// The two are the same number on a device nobody has claimed, and wildly
/// different on one changing hands: the previous account's rows went up under
/// that account and carry no mark at all, so counting the unsent would find
/// none of them and this dialog would never open over the data it exists for.
Future<FirstSyncChoice?> askAboutExistingData(
  BuildContext context,
  WidgetRef ref,
) async {
  final notes = await ref.read(diaryDaoProvider).entryCount();
  final tasks = await ref.read(tasksDaoProvider).taskCount();
  if (notes == 0 && tasks == 0) return FirstSyncChoice.upload;
  if (!context.mounted) return null;

  final email = ref.read(currentUserProvider)?.email;
  final claim = ref.read(syncClaimProvider);
  final user = ref.read(currentUserProvider);

  // Claimed by somebody else. Not "claimed by anybody": a device whose claim
  // names the account signing in does not reach this dialog at all, and one
  // with no claim is holding its own user's pre-account data.
  final changingHands = claim != null && claim != user?.id;

  return changingHands
      ? _askAboutAnotherAccount(context, notes: notes, tasks: tasks, to: email)
      : _askAboutOwnData(context, notes: notes, tasks: tasks, to: email);
}

/// The first sign-in on this device: the rows are the user's own, from before
/// they had an account.
Future<FirstSyncChoice?> _askAboutOwnData(
  BuildContext context, {
  required int notes,
  required int tasks,
  required String? to,
}) {
  return showDialog<FirstSyncChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('На устройстве ${_whatIsHere(notes, tasks)}'),
      content: Text(
        to == null
            ? 'Загрузить их в аккаунт?\n\n'
                  'Если не загружать, они останутся только здесь — до тех пор, '
                  'пока вы их не измените.'
            : 'Загрузить их в аккаунт $to?\n\n'
                  'Если не загружать, они останутся только здесь — до тех пор, '
                  'пока вы их не измените.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(FirstSyncChoice.keepLocal),
          child: const Text('Не загружать'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(FirstSyncChoice.upload),
          child: const Text('Загрузить'),
        ),
      ],
    ),
  );
}

/// The device is changing hands: what is here was written under another
/// account.
///
/// "Оставить только на устройстве" is deliberately **not** among the answers.
/// It is the state this whole mechanism exists to prevent — one person reading
/// and editing another's tasks, on a phone where those edits can never reach
/// any server — and offering it as one choice of three would make it look like
/// a matter of taste.
///
/// Wiping is confirmed once more before it happens. The rows may exist nowhere
/// else: the other account could itself have answered "не загружать", in which
/// case this device is the only copy there has ever been.
Future<FirstSyncChoice?> _askAboutAnotherAccount(
  BuildContext context, {
  required int notes,
  required int tasks,
  required String? to,
}) async {
  final choice = await showDialog<FirstSyncChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Здесь данные другого аккаунта'),
      content: Text(
        'На устройстве ${_whatIsHere(notes, tasks)}, созданные под другим '
        'аккаунтом.\n\n'
        'Их можно перенести — они станут вашими и загрузятся '
        '${to == null ? 'в ваш аккаунт' : 'в $to'} — или стереть с устройства.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(FirstSyncChoice.wipe),
          child: const Text('Стереть'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(FirstSyncChoice.adopt),
          child: const Text('Перенести'),
        ),
      ],
    ),
  );

  if (choice != FirstSyncChoice.wipe) return choice;
  if (!context.mounted) return null;
  final sure = await confirmWipe(context, notes: notes, tasks: tasks);
  return sure ? FirstSyncChoice.wipe : null;
}

/// "Точно стереть?" — the last step before data leaves the device for good.
///
/// Shared with the sign-out screen, which offers the same removal from the
/// other side. The count is repeated here rather than left to the first
/// dialog: this is the sentence somebody reads when they have already decided,
/// and it is the last place a wrong number would be noticed.
Future<bool> confirmWipe(
  BuildContext context, {
  required int notes,
  required int tasks,
}) async {
  return showConfirmDialog(
    context,
    icon: DialogIcons.delete,
    title: 'Стереть с устройства?',
    body:
        '${_whatIsHere(notes, tasks)} будут удалены с этого телефона вместе с '
        'вложенными фотографиями.\n\n'
        'Отменить это будет нельзя.',
    action: 'Стереть',
  );
}

/// "12 заметок и 30 задач", or whichever half there is.
///
/// A half that is zero is left out rather than written as "0 задач": the
/// sentence is there to tell the user what they are deciding about, and naming
/// something there is none of only makes it harder to read.
String _whatIsHere(int notes, int tasks) {
  final parts = [
    if (notes > 0) _plural(notes, _notesForms),
    if (tasks > 0) _plural(tasks, _tasksForms),
  ];
  return parts.join(' и ');
}

const _notesForms = ('заметка', 'заметки', 'заметок');
const _tasksForms = ('задача', 'задачи', 'задач');

/// "12 заметок" — Russian counts three ways, and a dialog that says
/// "1 заметок" reads as machinery rather than as a question.
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
