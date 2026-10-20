/// The options of a cycle day (`CycleDay.dc.html`).
///
/// **The index in each list is the stored value** — in the database and on the
/// server. Reordering or removing an entry rewrites what every saved day means;
/// new ones go at the end.
const cycleFlows = ['Нет', 'Мажущие', 'Лёгкие', 'Средние', 'Обильные'];

const cycleMoods = [
  'Спокойное',
  'Радостное',
  'Энергичное',
  'Раздражение',
  'Тревога',
  'Грусть',
];

const cycleSymptoms = [
  'Боль внизу живота',
  'Головная боль',
  'Боль в спине',
  'Вздутие',
  'Чувствительность груди',
  'Акне',
  'Усталость',
  'Тошнота',
  'Бессонница',
];

const cycleDischarges = [
  'Нет',
  'Сухо',
  'Липкие',
  'Кремовые',
  'Тягучие',
  'Водянистые',
  'Необычные',
];

const cycleSex = ['Не было', 'С защитой', 'Без защиты'];

/// `"0,3"` → `{0, 3}`. Anything that is not a number is dropped: the value also
/// comes from the server, which is free to hold what it likes.
Set<int> parseSymptoms(String stored) => {
  for (final part in stored.split(','))
    if (int.tryParse(part.trim()) case final i? when i >= 0) i,
};

/// `{3, 0}` → `"0,3"` — sorted, so the same choice is always the same string.
String encodeSymptoms(Iterable<int> symptoms) =>
    (symptoms.toSet().toList()..sort()).join(',');
