import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';

/// A heading and the notes under it.
typedef DiaryGroup = ({String title, List<DiaryEntry> notes});

/// Cuts [notes] — newest first, as the diary hands them out — into the sections
/// of `Journal.dc.html`: "Эта неделя" for what was touched since Monday, then one
/// section per month ("Сентябрь"), with the year added for any other than this
/// one ("Сентябрь 2025").
///
/// The date is [DiaryEntry.updatedAt]: the one the list already shows and sorts
/// by. A note dated later than [now] — a clock that moved — counts as this week
/// rather than getting a section from the future.
///
/// Pure, so the cut can be pinned without a screen. Needs `ru_RU` date symbols.
List<DiaryGroup> groupDiaryByDate(List<DiaryEntry> notes, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));

  final groups = <String, List<DiaryEntry>>{};
  for (final note in notes) {
    final at = note.updatedAt.toLocal();
    final day = DateTime(at.year, at.month, at.day);
    final String title;
    if (!day.isBefore(monday)) {
      title = 'Эта неделя';
    } else {
      final month = DateFormat('LLLL', 'ru_RU').format(at);
      final name = '${month[0].toUpperCase()}${month.substring(1)}';
      title = at.year == now.year ? name : '$name ${at.year}';
    }
    groups.putIfAbsent(title, () => []).add(note);
  }
  return [for (final e in groups.entries) (title: e.key, notes: e.value)];
}

/// "24 записи", "1 запись", "5 записей".
String diaryCountLabel(int count) {
  final hundred = count % 100;
  final ten = count % 10;
  final word = (hundred >= 11 && hundred <= 14)
      ? 'записей'
      : switch (ten) {
          1 => 'запись',
          2 || 3 || 4 => 'записи',
          _ => 'записей',
        };
  return '$count $word';
}
