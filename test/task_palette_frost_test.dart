import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/sync/payload.dart';
import 'package:todo_app/utils/task_palette.dart';

/// The "Иней" task palette: six families on offer, the old warm keys painted as
/// the rose (PLAN.md, decision A), and the v18 migration moving stored task
/// colours onto the new tones without sending anything.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  int ink(String key) => taskSwatchForKey(key)!.accent.toARGB32();

  test(
    'six families are offered; the warm keys still resolve, as the rose',
    () {
      expect(pickableTaskPalette.map((s) => s.key), [
        'violet',
        'sky',
        'blue',
        'green',
        'teal',
        'pink',
      ]);
      for (final warm in ['red', 'orange', 'yellow']) {
        expect(ink(warm), ink('pink'));
      }
      // A colour shared by several keys goes up as the pickable one.
      expect(taskColorKeyOf(taskColorForKey('orange')), 'pink');
    },
  );

  test('a v17 device moves its task colours onto the new tones', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('nook_v18').path}/db.sqlite',
    );
    final current = AppDatabase.forExecutor(NativeDatabase(file));
    Future<int> task(String title, int? argb) => current.tasksDao.insertTask(
      TasksCompanion.insert(title: title, colorValue: Value(argb)),
    );
    final violet = await task('фиолетовая', legacyTaskAccents['violet']);
    final orange = await task('оранжевая', legacyTaskAccents['orange']);
    final oldLight = await task('светлая', legacyTaskLightTones['green']);
    final stranger = await task('чужой цвет', 0xFF123456);
    final none = await task('без цвета', null);
    // As v17 left them: already sent.
    await current.customStatement('UPDATE tasks SET dirty = 0');
    await current.customStatement('PRAGMA user_version = 17');
    await current.close();

    final upgraded = AppDatabase.forExecutor(NativeDatabase(file));
    addTearDown(upgraded.close);
    Future<Task> get(int id) => (upgraded.select(
      upgraded.tasks,
    )..where((t) => t.id.equals(id))).getSingle();

    expect((await get(violet)).colorValue, ink('violet'));
    expect((await get(orange)).colorValue, ink('pink'));
    expect((await get(oldLight)).colorValue, ink('green'));
    expect((await get(stranger)).colorValue, 0xFF123456);
    expect((await get(none)).colorValue, isNull);

    // A repaint, not an edit: nothing is queued for the server, and the key
    // the server holds for it is the one it already had.
    final all = await upgraded.select(upgraded.tasks).get();
    expect(all.where((t) => t.dirty), isEmpty);
    expect(taskToRow(await get(violet))['color_key'], 'violet');
  });
}
