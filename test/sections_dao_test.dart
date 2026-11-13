import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/app_database.dart';

void main() {
  late AppDatabase db;
  late SectionsDao dao;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    dao = SectionsDao(db);
  });

  tearDown(() => db.close());

  Future<void> insertProject(String id) => db
      .into(db.localProjects)
      .insert(
        LocalProjectsCompanion.insert(
          id: id,
          name: id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

  group('SectionsDao', () {
    test(
      'creates and orders sections within their exact project scope',
      () async {
        await insertProject('home');
        await insertProject('work');

        final regular = await dao.createSection(
          userId: 'user-1',
          name: 'Inbox',
          position: 2,
        );
        final homeLater = await dao.createSection(
          userId: 'user-1',
          projectId: 'home',
          name: 'Later',
          position: 2,
        );
        final homeFirst = await dao.createSection(
          userId: 'user-1',
          projectId: 'home',
          name: 'First',
          position: 1,
        );
        await dao.createSection(
          userId: 'user-1',
          projectId: 'work',
          name: 'Work',
          position: 0,
        );
        await dao.createSection(
          userId: 'user-2',
          name: 'Other user',
          position: 0,
        );

        expect(
          (await dao.getSections(
            userId: 'user-1',
          )).map((section) => section.id),
          [regular.id],
        );
        expect(
          (await dao.getSections(
            userId: 'user-1',
            projectId: 'home',
          )).map((section) => section.id),
          [homeFirst.id, homeLater.id],
        );
      },
    );

    test(
      'rejects a project section when the project is not stored locally',
      () {
        expect(
          dao.createSection(
            userId: 'user-1',
            projectId: 'missing',
            name: 'Invalid',
            position: 0,
          ),
          throwsStateError,
        );
      },
    );

    test('watches changes within one user and project scope', () async {
      final changes = StreamIterator(dao.watchSections(userId: 'user-1'));
      addTearDown(changes.cancel);

      expect(await changes.moveNext(), isTrue);
      expect(changes.current, isEmpty);

      await dao.createSection(userId: 'user-1', name: 'Inbox', position: 0);

      expect(await changes.moveNext(), isTrue);
      expect(changes.current.single.name, 'Inbox');
    });

    test(
      'updates only a section owned by the requested user and scope',
      () async {
        await insertProject('home');
        final section = await dao.createSection(
          userId: 'user-1',
          projectId: 'home',
          name: 'Before',
          position: 0,
        );

        final updated = await dao.updateSection(
          id: section.id,
          userId: 'user-1',
          projectId: 'home',
          name: 'After',
          position: 3,
        );

        expect(updated.name, 'After');
        expect(updated.position, 3);
        await expectLater(
          dao.updateSection(
            id: section.id,
            userId: 'user-2',
            projectId: 'home',
            name: 'No access',
          ),
          throwsStateError,
        );
        expect(
          (await dao.getSection(
            section.id,
            userId: 'user-1',
            projectId: 'home',
          ))!.name,
          'After',
        );
      },
    );

    test(
      'deletes a section and clears its tasks without deleting them',
      () async {
        await insertProject('home');
        final section = await dao.createSection(
          userId: 'user-1',
          projectId: 'home',
          name: 'Today',
          position: 0,
        );
        final assignedTaskId = await db.tasksDao.insertTask(
          TasksCompanion.insert(
            title: 'Assigned',
            projectUid: const Value('home'),
            sectionId: Value(section.id),
          ),
        );
        final unrelatedTaskId = await db.tasksDao.insertTask(
          TasksCompanion.insert(title: 'Unrelated'),
        );

        await dao.deleteSection(
          id: section.id,
          userId: 'user-1',
          projectId: 'home',
        );

        expect(
          await dao.getSection(section.id, userId: 'user-1', projectId: 'home'),
          isNull,
        );
        expect(
          (await db.tasksDao.getTaskById(assignedTaskId))!.sectionId,
          isNull,
        );
        expect(
          (await db.tasksDao.getTaskById(assignedTaskId))!.sectionDirty,
          isTrue,
        );
        expect(
          (await db.tasksDao.getTaskById(unrelatedTaskId))!.sectionId,
          isNull,
        );
      },
    );

    test(
      'reorders every section in a project and marks changed rows dirty',
      () async {
        await insertProject('home');
        final first = await dao.createSection(
          userId: 'user-1',
          projectId: 'home',
          name: 'First',
          position: 0,
        );
        final second = await dao.createSection(
          userId: 'user-1',
          projectId: 'home',
          name: 'Second',
          position: 1,
        );
        final third = await dao.createSection(
          userId: 'user-1',
          projectId: 'home',
          name: 'Third',
          position: 2,
        );
        await dao.clearSectionDirty({
          first.id: first.updatedAt,
          second.id: second.updatedAt,
          third.id: third.updatedAt,
        });

        await dao.reorderSections(
          userId: 'user-1',
          projectId: 'home',
          orderedIds: [third.id, first.id, second.id],
        );

        final reordered = await dao.getSections(
          userId: 'user-1',
          projectId: 'home',
        );
        expect(reordered.map((section) => section.id), [
          third.id,
          first.id,
          second.id,
        ]);
        expect(reordered.map((section) => section.position), [0, 1, 2]);
        expect(reordered.every((section) => section.dirty), isTrue);
      },
    );

    test(
      'rejects an incomplete reorder so project scopes cannot mix',
      () async {
        await insertProject('home');
        final first = await dao.createSection(
          userId: 'user-1',
          projectId: 'home',
          name: 'First',
          position: 0,
        );
        await dao.createSection(
          userId: 'user-1',
          projectId: 'home',
          name: 'Second',
          position: 1,
        );

        await expectLater(
          dao.reorderSections(
            userId: 'user-1',
            projectId: 'home',
            orderedIds: [first.id],
          ),
          throwsStateError,
        );
      },
    );
  });
}
