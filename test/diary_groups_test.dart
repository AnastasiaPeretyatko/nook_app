import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/utils/diary_groups.dart';

/// How the diary cuts its notes into sections, and says how many there are.
void main() {
  setUpAll(() => initializeDateFormatting('ru_RU', null));

  // A Friday, so "this week" starts on Monday the 12th.
  final now = DateTime(2026, 10, 16, 12);

  DiaryEntry note(int id, DateTime at) => DiaryEntry(
    id: id,
    title: 'n$id',
    body: '',
    images: '[]',
    isFavorite: false,
    status: DiaryEntryStatus.normal,
    createdAt: at,
    updatedAt: at,
    dirty: false,
  );

  test('this week, then a section per month, newest first', () {
    final groups = groupDiaryByDate([
      note(1, DateTime(2026, 10, 16)),
      note(2, DateTime(2026, 10, 14)),
      note(3, DateTime(2026, 10, 2)),
      note(4, DateTime(2026, 9, 28)),
      note(5, DateTime(2026, 9, 3)),
    ], now);

    expect(
      [for (final g in groups) g.title],
      ['Эта неделя', 'Октябрь', 'Сентябрь'],
    );
    expect([for (final n in groups[0].notes) n.id], [1, 2]);
    expect([for (final n in groups[2].notes) n.id], [4, 5]);
  });

  test('Monday counts as this week, the Sunday before it does not', () {
    final groups = groupDiaryByDate([
      note(1, DateTime(2026, 10, 12, 0, 1)),
      note(2, DateTime(2026, 10, 11, 23, 59)),
    ], now);

    expect(groups.first.title, 'Эта неделя');
    expect(groups.first.notes.single.id, 1);
    expect(groups.last.title, 'Октябрь');
  });

  test('another year is named, this one is not', () {
    final groups = groupDiaryByDate([note(1, DateTime(2025, 9, 28))], now);

    expect(groups.single.title, 'Сентябрь 2025');
  });

  test('a note dated in the future is this week, not a section of its own', () {
    final groups = groupDiaryByDate([note(1, DateTime(2027, 1, 5))], now);

    expect(groups.single.title, 'Эта неделя');
  });

  test('nothing in, nothing out', () {
    expect(groupDiaryByDate(const [], now), isEmpty);
  });

  group('the count', () {
    test('says it the Russian way', () {
      expect(diaryCountLabel(0), '0 записей');
      expect(diaryCountLabel(1), '1 запись');
      expect(diaryCountLabel(2), '2 записи');
      expect(diaryCountLabel(5), '5 записей');
      expect(diaryCountLabel(11), '11 записей');
      expect(diaryCountLabel(21), '21 запись');
      expect(diaryCountLabel(24), '24 записи');
      expect(diaryCountLabel(112), '112 записей');
    });
  });
}
