import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo_app/auth/providers.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/settings/sync_settings.dart';
import 'package:todo_app/sync/providers.dart';

/// The one question syncing has to ask before it starts: what happens to what
/// is already here?
///
/// It is asked per **account**, not per device. Answering once and never again
/// would mean that signing a second account into the same phone quietly hands
/// it whatever the first person had written — which is the failure worth
/// spending a dialog on, and the reason nothing syncs until this is settled.
///
/// Both answers are recorded the same way: by claiming the device for the
/// account that answered. What differs is only whether the rows keep their
/// unsent marks.
enum FirstSyncChoice {
  /// Send what is here. The rows keep their marks and go up on the next run,
  /// which is what would have happened anyway — this answer simply lets it.
  upload,

  /// Leave what is here alone. Marks cleared without anything being sent.
  keepLocal,
}

/// Records the answer and lets syncing begin.
///
/// The watermark is reset in both cases. It measures how far through *an
/// account's* history this device has read, so carrying one account's position
/// into another would make the new account's pull start in the middle and skip
/// everything written before — silently, and with nothing that would ever go
/// back for it.
Future<void> applyFirstSyncChoice(WidgetRef ref, FirstSyncChoice choice) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return;

  if (choice == FirstSyncChoice.keepLocal) {
    // Both halves, or the answer is only half honoured: every task and every
    // day mark on the device is unsent too, and clearing the diary alone would
    // let them all go up on the next run while the dialog said they would not.
    await ref.read(diaryDaoProvider).keepExistingEntriesLocal();
    await ref.read(tasksDaoProvider).keepExistingTasksLocal();
  }

  await ref.read(syncWatermarkProvider.notifier).set(null);
  await ref.read(syncClaimProvider.notifier).claimFor(user.id);
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
Future<FirstSyncChoice?> askAboutExistingData(
  BuildContext context,
  WidgetRef ref,
) async {
  final notes = await ref.read(diaryDaoProvider).unsentEntryCount();
  final tasks = await ref.read(tasksDaoProvider).unsentTaskCount();
  if (notes == 0 && tasks == 0) return FirstSyncChoice.upload;
  if (!context.mounted) return null;

  final email = ref.read(currentUserProvider)?.email;

  return showDialog<FirstSyncChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('На устройстве ${_whatIsHere(notes, tasks)}'),
      content: Text(
        email == null
            ? 'Загрузить их в аккаунт?\n\n'
                  'Если не загружать, они останутся только здесь — до тех пор, '
                  'пока вы их не измените.'
            : 'Загрузить их в аккаунт $email?\n\n'
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
