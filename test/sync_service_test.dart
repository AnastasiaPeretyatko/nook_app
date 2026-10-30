import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/api/api_exception.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/sync/sync_service.dart';

import 'support/fake_sync_api.dart';

const me = 'me-uid';
final day = DateTime(2026, 10, 30);

Map<String, dynamic> taskRow(
  String id, {
  String title = 'Зарядка',
  bool deleted = false,
}) => {
  'id': id,
  'user_id': me,
  'parent_id': null,
  'title': title,
  'description': null,
  'status': 'active',
  'tracking_mode': 'checkbox',
  'start_date': '2026-10-01',
  'created_at': '2026-10-01T08:00:00.000000Z',
  'client_updated_at': '2026-10-02T08:00:00.000000Z',
  'updated_at': '2026-10-02T08:00:01.000000Z',
  'deleted_at': deleted ? '2026-10-03T08:00:00.000000Z' : null,
  'group_id': null,
  'assignee_id': null,
};

Map<String, dynamic> logRow(String taskId, {bool completed = true}) => {
  'task_id': taskId,
  'user_id': me,
  'date': '2026-10-30',
  'completed': completed,
  'value': null,
  'completed_at': null,
  'client_updated_at': '2026-10-30T08:00:00.000000Z',
  'updated_at': '2026-10-30T08:00:01.000000Z',
};

Map<String, dynamic> moodRow(String id) => {
  'id': id,
  'name': 'Радость',
  'emoji': '😀',
  'created_at': '2026-10-01T08:00:00.000000Z',
  'client_updated_at': '2026-10-01T08:00:00.000000Z',
  'updated_at': '2026-10-01T08:00:01.000000Z',
  'deleted_at': null,
};

Map<String, dynamic> tagRow(String id) => {
  'id': id,
  'name': 'Работа',
  'color_key': 'blue',
  'created_at': '2026-10-01T08:00:00.000000Z',
  'client_updated_at': '2026-10-01T08:00:00.000000Z',
  'updated_at': '2026-10-01T08:00:01.000000Z',
  'deleted_at': null,
};

Map<String, dynamic> entryRow(
  String id, {
  String title = 'Заметка',
  List<String> moods = const [],
  List<String> tags = const [],
}) => {
  'id': id,
  'title': title,
  'body': '[]',
  'cover_image': null,
  'images': '[]',
  'is_favorite': false,
  'status': 'normal',
  'created_at': '2026-10-01T08:00:00.000000Z',
  'client_updated_at': '2026-10-02T08:00:00.000000Z',
  'updated_at': '2026-10-02T08:00:01.000000Z',
  'deleted_at': null,
  'mood_ids': moods,
  'tag_ids': tags,
};

Map<String, dynamic> cycleRow({
  String date = '2026-10-30',
  int flow = 3,
  List<int> symptoms = const [1, 4],
  String updated = '2026-10-30T08:00:00.000000Z',
}) => {
  'date': date,
  'flow': flow,
  'mood': 2,
  'symptoms': symptoms,
  'discharge': null,
  'sex': 1,
  'pill': false,
  'note': null,
  'client_updated_at': updated,
  'updated_at': '2026-10-30T08:00:01.000000Z',
};

Map<String, dynamic> page({
  List<Map<String, dynamic>> tasks = const [],
  List<Map<String, dynamic>> logs = const [],
  List<Map<String, dynamic>> moods = const [],
  List<Map<String, dynamic>> tags = const [],
  List<Map<String, dynamic>> entries = const [],
  List<Map<String, dynamic>> cycleDays = const [],
  Map<String, dynamic>? groups,
  String? next,
  bool more = false,
}) => {
  'next': next,
  'has_more': more,
  'tasks': tasks,
  'logs': logs,
  'moods': moods,
  'tags': tags,
  'entries': entries,
  'cycle_days': cycleDays,
  'groups': groups ?? {'groups': [], 'members': []},
};

/// The server's list of my groups: [owner] owns `g-1`, with [members] in it.
Map<String, dynamic> teamSnapshot({
  String name = 'Семья',
  String owner = 'boss-uid',
  List<Map<String, dynamic>>? members,
}) => {
  'groups': [
    {'id': 'g-1', 'name': name, 'owner_id': owner},
  ],
  'members':
      members ??
      [
        {
          'group_id': 'g-1',
          'user_id': owner,
          'display_name': 'Аня',
          'avatar_url': null,
        },
        {
          'group_id': 'g-1',
          'user_id': me,
          'display_name': null,
          'avatar_url': 'https://x.test/a.png',
        },
      ],
};

void main() {
  late AppDatabase db;
  late FakeSyncApi api;
  late SyncService service;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    api = FakeSyncApi();
    service = SyncService(
      dao: db.diaryDao,
      tasksDao: db.tasksDao,
      cycleDao: db.cycleDao,
      api: api,
      userId: () => me,
    );
  });

  Future<Task> localTask(String title) async {
    final id = await db.tasksDao.insertTask(
      TasksCompanion.insert(title: title),
    );
    return (await db.tasksDao.getTaskById(id))!;
  }

  group('the order and the clock', () {
    test('pulls first, pushes after', () async {
      await localTask('Моя');
      expect(await service.sync(), SyncOutcome.done);
      expect(api.calls.first, startsWith('pull('));
      expect(api.calls.last, 'push');
    });

    test(
      'asks for tasks and the diary, from the beginning the first time',
      () async {
        await service.sync();
        expect(
          api.calls.single,
          'pull(since: null, include: diary, limit: 500)',
        );
      },
    );

    test('reads from 5 s before the watermark, once', () async {
      service.watermark = DateTime.utc(2026, 10, 30, 10);
      api.pullAnswers
        ..clear()
        ..addAll([
          page(next: '2026-10-30T10:00:10.123456Z', more: true),
          page(next: '2026-10-30T10:00:20.000000Z'),
        ]);
      await service.sync();
      expect(api.calls[0], contains('since: 2026-10-30T09:59:55.000Z'));
      // The second page starts exactly where the first said, no overlap again.
      expect(api.calls[1], contains('since: 2026-10-30T10:00:10.123456Z'));
      expect(service.watermark, DateTime.utc(2026, 10, 30, 10, 0, 20));
    });

    test(
      'an idle answer (next = since) never moves the watermark back',
      () async {
        service.watermark = DateTime.utc(2026, 10, 30, 10);
        api.pullAnswers
          ..clear()
          ..add(page(next: '2026-10-30T09:59:55.000000Z'));
        await service.sync();
        expect(service.watermark, DateTime.utc(2026, 10, 30, 10));
      },
    );

    test('a null next leaves the watermark alone', () async {
      await service.sync();
      expect(service.watermark, isNull);
    });
  });

  group('what comes down', () {
    test('a new task and its mark are stored, clean', () async {
      api.pullAnswers
        ..clear()
        ..add(
          page(
            tasks: [taskRow('t-1')],
            logs: [logRow('t-1')],
            next: '2026-10-30T10:00:00.000000Z',
          ),
        );
      await service.sync();

      final task = (await db.tasksDao.taskByUid('t-1'))!;
      expect(task.title, 'Зарядка');
      expect(task.dirty, isFalse);
      final log = await db.tasksDao.getLogForDate(task.id, day);
      expect(log?.completed, isTrue);
      expect(await db.tasksDao.pendingLogs(), isEmpty);
    });

    test('a deleted task disappears', () async {
      api.pullAnswers
        ..clear()
        ..addAll([
          page(tasks: [taskRow('t-1')], next: '2026-10-30T10:00:00.000000Z'),
          page(
            tasks: [taskRow('t-1', deleted: true)],
            next: '2026-10-30T10:01:00.000000Z',
          ),
        ]);
      await service.sync();
      await service.sync(force: true);
      expect(await db.tasksDao.taskByUid('t-1'), isNull);
    });

    test(
      'a mark that came before its task is kept once the task arrives',
      () async {
        api.pullAnswers
          ..clear()
          ..addAll([
            page(
              logs: [logRow('t-1')],
              next: '2026-10-30T10:00:00.000000Z',
              more: true,
            ),
            page(tasks: [taskRow('t-1')], next: '2026-10-30T10:00:05.000000Z'),
          ]);
        await service.sync();
        final task = (await db.tasksDao.taskByUid('t-1'))!;
        expect(
          (await db.tasksDao.getLogForDate(task.id, day))?.completed,
          isTrue,
        );
      },
    );

    test('a mark with no task at all is dropped, not an error', () async {
      api.pullAnswers
        ..clear()
        ..add(
          page(logs: [logRow('nobody')], next: '2026-10-30T10:00:00.000000Z'),
        );
      expect(await service.sync(), SyncOutcome.done);
      expect(await db.select(db.taskLogs).get(), isEmpty);
    });

    test(
      'a task deleted here but not yet reported is not raised again',
      () async {
        final task = await localTask('Выброшена');
        await db.tasksDao.deleteTaskCascade(task.id);
        api.pullAnswers
          ..clear()
          ..add(
            page(
              tasks: [taskRow(task.uid!)],
              logs: [logRow(task.uid!)],
              next: '2026-10-30T10:00:00.000000Z',
            ),
          );

        await service.sync();

        expect(await db.tasksDao.taskByUid(task.uid!), isNull);
        expect(await db.select(db.taskLogs).get(), isEmpty);
        // ...and the deletion goes up.
        expect(api.pushed.single['deleted'], [
          {'table': 'tasks', 'id': task.uid},
        ]);
      },
    );

    test('our unsent edit survives an older server copy', () async {
      final task = await localTask('Новое название');
      final old = taskRow(task.uid!, title: 'Старое')
        ..['client_updated_at'] = '2000-01-01T00:00:00.000000Z';
      api.pullAnswers
        ..clear()
        ..add(page(tasks: [old], next: '2026-10-30T10:00:00.000000Z'));

      await service.sync();

      expect((await db.tasksDao.taskByUid(task.uid!))?.title, 'Новое название');
      expect(api.pushed.single['tasks'], hasLength(1));
    });
  });

  group('what goes up', () {
    test('tasks and marks in one request, and the marks are cleared', () async {
      final task = await localTask('Моя');
      await db.tasksDao.setLog(task.id, day, completed: true);

      await service.sync();

      final body = api.pushed.single;
      expect((body['tasks'] as List).single['id'], task.uid);
      expect((body['logs'] as List).single['task_id'], task.uid);
      expect(await db.tasksDao.pendingTasks(), isEmpty);
      expect(await db.tasksDao.pendingLogs(), isEmpty);
      expect(await service.hasPending(), isFalse);
    });

    test('nothing to send, nothing sent', () async {
      await service.sync();
      expect(api.pushed, isEmpty);
    });

    test(
      'a refused row is cleared too, so it is not offered for ever',
      () async {
        await localTask('Плохая');
        api.rejected = [
          {'table': 'tasks', 'id': 'x', 'reason': 'invalid_row'},
        ];
        expect(await service.sync(), SyncOutcome.done);
        expect(await db.tasksDao.pendingTasks(), isEmpty);
      },
    );

    group('group tasks', () {
      Future<Task> groupTask({
        String? author = me,
        String? assignee,
        String title = 'Общая',
      }) async {
        final id = await db.tasksDao.insertTask(
          TasksCompanion.insert(
            title: title,
            groupUid: const Value('g-1'),
            assigneeUid: Value(assignee),
            authorUid: Value(author),
          ),
        );
        return (await db.tasksDao.getTaskById(id))!;
      }

      test('one I wrote goes up with its group and assignee', () async {
        // A pull that lists the group comes first, as in a real run.
        api.pullAnswers
          ..clear()
          ..add(page(groups: teamSnapshot()));
        await groupTask(assignee: 'boss-uid');

        await service.sync();

        final sent = (api.pushed.single['tasks'] as List).single as Map;
        expect(sent['group_id'], 'g-1');
        expect(sent['assignee_id'], 'boss-uid');
        expect(await db.tasksDao.pendingTasks(), isEmpty);
      });

      test('the owner may send another member\'s task', () async {
        api.pullAnswers
          ..clear()
          ..add(
            page(
              groups: teamSnapshot(
                owner: me,
                members: [
                  {
                    'group_id': 'g-1',
                    'user_id': me,
                    'display_name': null,
                    'avatar_url': null,
                  },
                ],
              ),
            ),
          );
        await groupTask(author: 'other-uid');

        await service.sync();

        expect(api.pushed.single['tasks'], hasLength(1));
      });

      test('someone else\'s task is not sent, and stays as it is', () async {
        api.pullAnswers
          ..clear()
          ..add(page(groups: teamSnapshot()));
        final task = await groupTask(author: 'other-uid');

        await service.sync();

        expect(api.pushed, isEmpty);
        expect((await db.tasksDao.pendingTasks()).single.id, task.id);
      });

      test('deleting one I wrote is reported', () async {
        api.pullAnswers
          ..clear()
          ..add(page(groups: teamSnapshot()));
        final task = await groupTask();
        await service.sync();
        api.pushed.clear();

        await db.tasksDao.deleteTaskCascade(task.id);
        await service.sync();

        expect(api.pushed.single['deleted'], [
          {'table': 'tasks', 'id': task.uid},
        ]);
      });

      for (final reason in ['unknown_group', 'not_allowed', 'id_taken']) {
        test(
          '$reason is final: the mark is cleared, nothing retried',
          () async {
            api.pullAnswers
              ..clear()
              ..add(page(groups: teamSnapshot()));
            final task = await groupTask();
            api.rejected = [
              {'table': 'tasks', 'id': task.uid, 'reason': reason},
            ];

            await service.sync();
            expect(await db.tasksDao.pendingTasks(), isEmpty);

            api.pushed.clear();
            await service.sync();
            expect(api.pushed, isEmpty);
          },
        );
      }

      test('a mark refused as not_allowed is taken back here too', () async {
        api.pullAnswers
          ..clear()
          ..add(page(groups: teamSnapshot()));
        final task = await groupTask(assignee: 'boss-uid');
        await db.tasksDao.clearTaskDirty({task.uid!: task.updatedAt});
        await db.tasksDao.setLog(task.id, day, completed: true);
        api.rejected = [
          {'table': 'task_logs', 'id': task.uid, 'reason': 'not_allowed'},
        ];

        await service.sync();

        expect(await db.tasksDao.getLogForDate(task.id, day), isNull);
        expect(await db.tasksDao.pendingLogs(), isEmpty);
      });

      test('a mark refused for another reason stays', () async {
        api.pullAnswers
          ..clear()
          ..add(page(groups: teamSnapshot()));
        final task = await groupTask();
        await db.tasksDao.clearTaskDirty({task.uid!: task.updatedAt});
        await db.tasksDao.setLog(task.id, day, completed: true);
        api.rejected = [
          {'table': 'task_logs', 'id': task.uid, 'reason': 'unknown_task'},
        ];

        await service.sync();

        expect(await db.tasksDao.getLogForDate(task.id, day), isNotNull);
      });

      test('a task from the group arrives with its author and the '
          'other member\'s mark, which is not mine', () async {
        final row = {
          ...taskRow('t-1', title: 'Купить хлеб'),
          'user_id': 'boss-uid',
          'group_id': 'g-1',
          'assignee_id': null,
        };
        api.pullAnswers
          ..clear()
          ..add(
            page(
              groups: teamSnapshot(),
              tasks: [row],
              logs: [
                {...logRow('t-1'), 'user_id': 'boss-uid'},
              ],
            ),
          );

        await service.sync();

        final task = (await db.tasksDao.taskByUid('t-1'))!;
        expect([task.groupUid, task.authorUid], ['g-1', 'boss-uid']);
        expect(await db.tasksDao.getLogForDate(task.id, day), isNull);
        final marks = await db.select(db.groupMarks).get();
        expect(
          [marks.single.userUid, marks.single.completed],
          ['boss-uid', true],
        );
      });
    });

    test(
      'more than 500 tasks go in several requests, tasks before marks',
      () async {
        for (var i = 0; i < 501; i++) {
          await db.tasksDao.insertTask(TasksCompanion.insert(title: 'T$i'));
        }
        final first = (await db.tasksDao.pendingTasks()).first;
        await db.tasksDao.setLog(first.id, day, completed: true);

        await service.sync();

        expect(api.pushed.map((b) => b.keys.single).toList(), [
          'tasks',
          'tasks',
          'logs',
        ]);
        expect((api.pushed[0]['tasks'] as List), hasLength(500));
        expect((api.pushed[1]['tasks'] as List), hasLength(1));
        expect(await db.tasksDao.pendingTasks(), isEmpty);
      },
    );
  });

  group('the diary', () {
    Future<List<String>> moodsOf(String entryUid) async {
      final entry = (await db.diaryDao.entryByUid(entryUid))!;
      return db.diaryDao.moodUidsForEntry(entry.id);
    }

    test('a note comes down with its mood and its tag, clean', () async {
      api.pullAnswers
        ..clear()
        ..add(
          page(
            moods: [moodRow('m-1')],
            tags: [tagRow('t-1')],
            entries: [
              entryRow('e-1', moods: ['m-1'], tags: ['t-1']),
            ],
            next: '2026-10-30T10:00:00.000000Z',
          ),
        );
      await service.sync();

      final entry = (await db.diaryDao.entryByUid('e-1'))!;
      expect(entry.title, 'Заметка');
      expect(entry.dirty, isFalse);
      expect(await moodsOf('e-1'), ['m-1']);
      expect(await db.diaryDao.tagUidsForEntry(entry.id), ['t-1']);
    });

    test('a note that names a mood from a later page still gets it', () async {
      api.pullAnswers
        ..clear()
        ..addAll([
          page(
            entries: [
              entryRow('e-1', moods: ['m-1']),
            ],
            next: '2026-10-30T10:00:00.000000Z',
            more: true,
          ),
          page(moods: [moodRow('m-1')], next: '2026-10-30T10:00:05.000000Z'),
        ]);
      await service.sync();
      expect(await moodsOf('e-1'), ['m-1']);
    });

    test('a label this phone has never heard of is dropped, quietly', () async {
      api.pullAnswers
        ..clear()
        ..add(
          page(
            entries: [
              entryRow('e-1', moods: ['ghost']),
            ],
            next: '2026-10-30T10:00:00.000000Z',
          ),
        );
      await service.sync();

      expect(await moodsOf('e-1'), isEmpty);
      expect((await db.diaryDao.entryByUid('e-1'))!.dirty, isFalse);
      expect(api.pushed, isEmpty);
    });

    test(
      'a note deleted here but not yet reported is not raised again',
      () async {
        final id = await db.diaryDao.insertEntry(
          DiaryEntriesCompanion.insert(title: const Value('Выброшена')),
        );
        final uid = (await db.diaryDao.getEntry(id))!.uid!;
        await db.diaryDao.deleteEntry(id);
        api.pullAnswers
          ..clear()
          ..add(
            page(entries: [entryRow(uid)], next: '2026-10-30T10:00:00.000000Z'),
          );

        await service.sync();

        expect(await db.diaryDao.entryByUid(uid), isNull);
        expect(api.pushed.single['deleted'], [
          {'table': 'diary_entries', 'id': uid},
        ]);
        expect(await db.diaryDao.pendingTombstones(), isEmpty);
      },
    );

    test('a note goes up with its labels, after the labels', () async {
      final mood = await db.diaryDao.insertMood(name: 'Грусть', emoji: '😢');
      final tag = await db.diaryDao.insertTag(name: 'Дом', colorKey: 'red');
      final id = await db.diaryDao.insertEntry(
        DiaryEntriesCompanion.insert(title: const Value('Моя')),
      );
      await db.diaryDao.setEntryMoods(id, [mood]);
      await db.diaryDao.setEntryTags(id, [tag]);

      await service.sync();

      final body = api.pushed.single;
      expect(body.keys.toList(), ['moods', 'tags', 'entries']);
      final moodUid = (body['moods'] as List).single['id'];
      expect((body['entries'] as List).single['mood_ids'], [moodUid]);
      expect((body['entries'] as List).single['tag_ids'], [
        (body['tags'] as List).single['id'],
      ]);
      expect(await db.diaryDao.pendingEntries(), isEmpty);
      expect(await db.diaryDao.pendingMoods(), isEmpty);
      expect(await db.diaryDao.pendingTags(), isEmpty);
    });

    test('a note refused for a label is still cleared', () async {
      await db.diaryDao.insertEntry(
        DiaryEntriesCompanion.insert(title: const Value('Моя')),
      );
      api.rejected = [
        {'table': 'diary_entries', 'id': 'x', 'reason': 'unknown_label'},
      ];
      await service.sync();
      expect(await db.diaryDao.pendingEntries(), isEmpty);
    });

    test(
      'the switch off: no diary asked for, none sent, the mark stays',
      () async {
        var on = false;
        final s = SyncService(
          dao: db.diaryDao,
          tasksDao: db.tasksDao,
          cycleDao: db.cycleDao,
          api: api,
          userId: () => me,
          syncDiary: () => on,
        );
        await db.diaryDao.insertEntry(
          DiaryEntriesCompanion.insert(title: const Value('Личная')),
        );

        expect(await s.hasPending(), isFalse);
        await s.sync();
        expect(api.calls.single, 'pull(since: null, include: , limit: 500)');
        expect(api.pushed, isEmpty);
        expect(await db.diaryDao.pendingEntries(), hasLength(1));

        on = true;
        expect(await s.hasPending(), isTrue);
        await s.sync(force: true);
        expect((api.pushed.single['entries'] as List), hasLength(1));
      },
    );

    test(
      'a queue too big for one request is cut by size, labels first',
      () async {
        final big = 'я' * 1500000; // about 3 MB of UTF-8 each
        final tag = await db.diaryDao.insertTag(name: 'Тег', colorKey: 'red');
        for (var i = 0; i < 3; i++) {
          final id = await db.diaryDao.insertEntry(
            DiaryEntriesCompanion.insert(title: Value('N$i'), body: Value(big)),
          );
          await db.diaryDao.setEntryTags(id, [tag]);
        }

        await service.sync();

        expect(api.pushed.map((b) => b.keys.single).toList(), [
          'tags',
          'entries',
          'entries',
          'entries',
        ]);
        expect(await db.diaryDao.pendingEntries(), isEmpty);
      },
    );
  });

  group('the cycle', () {
    var on = true;

    SyncService cycleService() => SyncService(
      dao: db.diaryDao,
      tasksDao: db.tasksDao,
      cycleDao: db.cycleDao,
      api: api,
      userId: () => me,
      syncCycle: () => on,
    );

    setUp(() => on = true);

    test('switched on, it is asked for; off by default, it is not', () async {
      await cycleService().sync();
      expect(api.calls.single, contains('include: cycle,diary'));

      api.calls.clear();
      await service.sync(force: true);
      expect(api.calls.single, isNot(contains('cycle')));
    });

    test('a day comes down with its marks, clean', () async {
      api.pullAnswers
        ..clear()
        ..add(
          page(cycleDays: [cycleRow()], next: '2026-10-30T10:00:00.000000Z'),
        );
      await cycleService().sync();

      final stored = (await db.cycleDao.getDay(day))!;
      expect(stored.flow, 3);
      expect(stored.mood, 2);
      expect(stored.symptoms, '1,4');
      expect(stored.dirty, isFalse);
    });

    test('a day taken back arrives empty and clears the mark here', () async {
      await db.cycleDao.saveDay(day, flow: 3, mood: 2);
      await db.cycleDao.clearDirty(await db.cycleDao.pending());
      api.pullAnswers
        ..clear()
        ..add(
          page(
            cycleDays: [
              cycleRow(
                  flow: 0,
                  symptoms: const [],
                  updated: '2999-01-01T00:00:00.000000Z',
                )
                ..['mood'] = null
                ..['sex'] = null,
            ],
            next: '2026-10-30T10:00:00.000000Z',
          ),
        );
      await cycleService().sync();

      final stored = (await db.cycleDao.getDay(day))!;
      expect(stored.flow, 0);
      expect(stored.mood, isNull);
      expect(stored.symptoms, '');
    });

    test('our unsent edit survives an older server copy', () async {
      await db.cycleDao.saveDay(day, flow: 4);
      api.pullAnswers
        ..clear()
        ..add(
          page(
            cycleDays: [
              cycleRow(flow: 1, updated: '2000-01-01T00:00:00.000000Z'),
            ],
            next: '2026-10-30T10:00:00.000000Z',
          ),
        );

      await cycleService().sync();

      expect((await db.cycleDao.getDay(day))!.flow, 4);
      expect((api.pushed.single['cycle_days'] as List).single['flow'], 4);
    });

    test(
      'a marked day goes up without a user id, sorted, and is cleared',
      () async {
        await db.cycleDao.saveDay(day, flow: 2, symptoms: {4, 1});

        await cycleService().sync();

        final sent = (api.pushed.single['cycle_days'] as List).single as Map;
        expect(sent['date'], '2026-10-30');
        expect(sent['symptoms'], [1, 4]);
        expect(sent.containsKey('user_id'), isFalse);
        expect(await db.cycleDao.pending(), isEmpty);
      },
    );

    test('a mark taken back is sent as an empty day, not a deletion', () async {
      await db.cycleDao.saveDay(day, flow: 2);
      await db.cycleDao.clearDirty(await db.cycleDao.pending());
      await db.cycleDao.clearDay(day);

      await cycleService().sync();

      final body = api.pushed.single;
      expect(body.containsKey('deleted'), isFalse);
      final sent = (body['cycle_days'] as List).single as Map;
      expect(sent['flow'], 0);
      expect(sent['symptoms'], isEmpty);
    });

    test('a refused day is cleared too', () async {
      await db.cycleDao.saveDay(day, flow: 2);
      api.rejected = [
        {'table': 'cycle_days', 'id': '2026-10-30', 'reason': 'invalid_row'},
      ];
      await cycleService().sync();
      expect(await db.cycleDao.pending(), isEmpty);
    });

    test(
      'off: nothing sent, the mark stays, and nothing pending is reported',
      () async {
        await db.cycleDao.saveDay(day, flow: 2);
        on = false;
        final s = cycleService();

        expect(await s.hasPending(), isFalse);
        await s.sync();
        expect(api.pushed, isEmpty);
        expect(await db.cycleDao.pending(), hasLength(1));

        on = true;
        expect(await s.hasPending(), isTrue);
      },
    );

    test('600 days go in two requests', () async {
      for (var i = 0; i < 600; i++) {
        await db.cycleDao.saveDay(
          DateTime(2024, 1, 1).add(Duration(days: i)),
          flow: 1,
        );
      }
      await cycleService().sync();
      expect(api.pushed.map((b) => (b['cycle_days'] as List).length).toList(), [
        500,
        100,
      ]);
      expect(await db.cycleDao.pending(), isEmpty);
    });
  });

  group('the groups', () {
    test('the list in the answer becomes the groups on the phone', () async {
      api.pullAnswers
        ..clear()
        ..add(page(groups: teamSnapshot()));
      await service.sync();

      final groups = await db.tasksDao.getGroups();
      expect([groups.single.uid, groups.single.name], ['g-1', 'Семья']);
      expect(groups.single.ownerUid, 'boss-uid');
      final members = await db.tasksDao.getGroupMembers();
      expect(members, hasLength(2));
      expect(
        members.firstWhere((m) => m.userUid == 'boss-uid').displayName,
        'Аня',
      );
      expect(
        members.firstWhere((m) => m.userUid == me).avatarUrl,
        'https://x.test/a.png',
      );
    });

    test('a group that left the list takes its tasks with it', () async {
      api.pullAnswers
        ..clear()
        ..add(page(groups: teamSnapshot()));
      await service.sync();
      final id = await db.tasksDao.insertTask(
        TasksCompanion.insert(title: 'Общая', groupUid: const Value('g-1')),
      );
      await db.tasksDao.clearTaskDirty({
        for (final t in await db.tasksDao.pendingTasks()) t.uid!: t.updatedAt,
      });

      api.pullAnswers
        ..clear()
        ..add(page());
      await service.sync();

      expect(await db.tasksDao.getGroups(), isEmpty);
      expect(await db.tasksDao.getGroupMembers(), isEmpty);
      expect(await db.tasksDao.getTaskById(id), isNull);
      // Learning about it is not news to send back.
      expect(await db.diaryDao.pendingTombstones(), isEmpty);
    });

    test('a renamed group and a new member are picked up', () async {
      api.pullAnswers
        ..clear()
        ..add(page(groups: teamSnapshot()));
      await service.sync();

      api.pullAnswers
        ..clear()
        ..add(
          page(
            groups: teamSnapshot(
              name: 'Семья 2',
              members: [
                {
                  'group_id': 'g-1',
                  'user_id': 'boss-uid',
                  'display_name': 'Аня',
                  'avatar_url': null,
                },
                {
                  'group_id': 'g-1',
                  'user_id': 'new-uid',
                  'display_name': 'Миша',
                  'avatar_url': null,
                },
              ],
            ),
          ),
        );
      await service.sync();

      expect((await db.tasksDao.getGroups()).single.name, 'Семья 2');
      expect(
        {for (final m in await db.tasksDao.getGroupMembers()) m.userUid},
        {'boss-uid', 'new-uid'},
      );
    });

    test('an answer without the list leaves the groups alone', () async {
      api.pullAnswers
        ..clear()
        ..add(page(groups: teamSnapshot()));
      await service.sync();

      api.pullAnswers
        ..clear()
        ..add({...page()}..remove('groups'));
      await service.sync();

      expect(await db.tasksDao.getGroups(), hasLength(1));
    });

    test('the same list again does not rewrite the tables', () async {
      api.pullAnswers
        ..clear()
        ..add(page(groups: teamSnapshot()));
      await service.sync();

      var changes = 0;
      final sub = db.select(db.taskGroups).watch().skip(1).listen((_) {
        changes++;
      });
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await service.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(changes, 0);
    });
  });

  group('when it goes wrong', () {
    test('no connection: offline, and everything stays marked', () async {
      await localTask('Моя');
      api.error = const ApiException.offline();

      expect(await service.sync(), SyncOutcome.offline);
      expect(await db.tasksDao.pendingTasks(), hasLength(1));
    });

    test(
      'the server refusing the request is a failure with its words',
      () async {
        api.error = const ApiException(
          ApiFailure.server,
          status: 400,
          code: 'validation_failed',
          message: 'bad since',
        );
        expect(await service.sync(), SyncOutcome.failed);
        expect(service.lastError, 'bad since');
      },
    );

    test(
      'a first request that times out is tried again before giving up',
      () async {
        var calls = 0;
        final flaky = FakeSyncApi();
        final s = SyncService(
          dao: db.diaryDao,
          tasksDao: db.tasksDao,
          cycleDao: db.cycleDao,
          api: _Flaky(flaky, () => ++calls < 3),
          userId: () => me,
        );
        expect(await s.sync(), SyncOutcome.done);
        expect(calls, 3);
      },
    );

    test('nobody signed in: skipped, with a reason', () async {
      final s = SyncService(
        dao: db.diaryDao,
        tasksDao: db.tasksDao,
        cycleDao: db.cycleDao,
        api: api,
        userId: () => null,
      );
      expect(await s.sync(), SyncOutcome.skipped);
      expect(s.lastError, contains('войдите'));
      expect(api.calls, isEmpty);
    });
  });
}

/// Throws "offline" while [failing] says so, then behaves as the fake.
class _Flaky extends FakeSyncApi {
  _Flaky(this._inner, this._failing);

  final FakeSyncApi _inner;
  final bool Function() _failing;

  @override
  Future<Map<String, dynamic>> pull({
    String? since,
    Set<String> include = const {},
    int limit = 500,
  }) async {
    if (_failing()) throw const ApiException.offline();
    return _inner.pull(since: since, include: include, limit: limit);
  }
}
