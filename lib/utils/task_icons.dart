import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// One selectable task icon: the key `tasks.iconKey` stores, the glyph drawn
/// for it and the label the picker shows.
///
/// The key is what lives in the database — never the glyph's code point. A code
/// point only means something inside one particular font file, and Lucide
/// renumbers its glyphs whenever icons are added, so a stored code point would
/// silently start pointing at a different picture on a package bump. A key
/// survives that, and survives swapping the icon set again later.
class TaskIcon {
  const TaskIcon(this.key, this.icon, this.label);

  final String key;
  final IconData icon;
  final String label;
}

/// Every icon a task can carry, in the order the picker lays them out.
///
/// Each glyph sits in a `const` expression, which is what lets the icon
/// tree-shaker see the whole set and subset the font down to it.
const taskIcons = <TaskIcon>[
  TaskIcon('alarm', LucideIcons.alarm_clock, 'Будильник'),
  TaskIcon('coffee', LucideIcons.coffee, 'Кофе'),
  TaskIcon('meditation', LucideIcons.flower_2, 'Медитация'),
  TaskIcon('gym', LucideIcons.dumbbell, 'Зал'),
  TaskIcon('run', LucideIcons.footprints, 'Бег'),
  TaskIcon('bike', LucideIcons.bike, 'Велосипед'),
  TaskIcon('swim', LucideIcons.waves_ladder, 'Плавание'),
  TaskIcon('shower', LucideIcons.shower_head, 'Душ'),
  TaskIcon('sleep', LucideIcons.bed, 'Сон'),
  TaskIcon('food', LucideIcons.utensils, 'Еда'),
  TaskIcon('drink', LucideIcons.cup_soda, 'Напиток'),
  TaskIcon('water', LucideIcons.droplet, 'Вода'),
  TaskIcon('reading', LucideIcons.book_open, 'Чтение'),
  TaskIcon('study', LucideIcons.graduation_cap, 'Учёба'),
  TaskIcon('computer', LucideIcons.laptop, 'Компьютер'),
  TaskIcon('work', LucideIcons.briefcase, 'Работа'),
  TaskIcon('meeting', LucideIcons.handshake, 'Встреча'),
  TaskIcon('call', LucideIcons.phone, 'Звонок'),
  TaskIcon('message', LucideIcons.message_circle, 'Сообщение'),
  TaskIcon('mail', LucideIcons.mail, 'Почта'),
  TaskIcon('shopping', LucideIcons.shopping_cart, 'Покупки'),
  TaskIcon('finance', LucideIcons.wallet, 'Финансы'),
  TaskIcon('home', LucideIcons.house, 'Дом'),
  TaskIcon('cleaning', LucideIcons.spray_can, 'Уборка'),
  TaskIcon('health', LucideIcons.hospital, 'Здоровье'),
  TaskIcon('medication', LucideIcons.pill, 'Лекарство'),
  TaskIcon('heart', LucideIcons.heart, 'Самочувствие'),
  TaskIcon('music', LucideIcons.music, 'Музыка'),
  TaskIcon('movie', LucideIcons.film, 'Кино'),
  TaskIcon('games', LucideIcons.gamepad_2, 'Игры'),
  TaskIcon('art', LucideIcons.brush, 'Творчество'),
  TaskIcon('photo', LucideIcons.camera, 'Фото'),
  TaskIcon('pet', LucideIcons.paw_print, 'Питомец'),
  TaskIcon('nature', LucideIcons.leaf, 'Природа'),
  TaskIcon('walk', LucideIcons.trees, 'Прогулка'),
  TaskIcon('travel', LucideIcons.plane, 'Путешествие'),
  TaskIcon('car', LucideIcons.car, 'Авто'),
  TaskIcon('important', LucideIcons.star, 'Важное'),
  TaskIcon('goal', LucideIcons.trophy, 'Цель'),
  TaskIcon('idea', LucideIcons.lightbulb, 'Идея'),
  TaskIcon('thinking', LucideIcons.brain, 'Размышление'),
  TaskIcon('help', LucideIcons.heart_handshake, 'Помощь'),
  TaskIcon('social', LucideIcons.users, 'Общение'),
  TaskIcon('kids', LucideIcons.baby, 'Дети'),
  TaskIcon('rest', LucideIcons.armchair, 'Отдых'),
  TaskIcon('vacation', LucideIcons.umbrella, 'Отпуск'),
  TaskIcon('timer', LucideIcons.timer, 'Таймер'),
  TaskIcon('habit', LucideIcons.repeat, 'Привычка'),
];

final Map<String, IconData> _byKey = {
  for (final entry in taskIcons) entry.key: entry.icon,
};

/// The glyph for a stored key, or null when the task carries no icon — or one
/// whose key this build no longer knows. Callers supply their own fallback,
/// because it differs by screen (a habit falls back to the repeat glyph, a
/// one-off task to a check).
IconData? taskIconFor(String? key) => key == null ? null : _byKey[key];

/// Old `tasks.iconCodePoint` values mapped onto the new keys.
///
/// These are Material Icons code points — the only thing rows saved before this
/// table carry. Read by the schema v10 migration and by nothing else; once a
/// row has an `iconKey` its code point is dead weight.
const legacyTaskIconKeys = <int, String>{
  0xee66: 'alarm', // alarm_outlined
  0xef68: 'coffee', // coffee_outlined
  0xf352: 'meditation', // self_improvement_outlined
  0xe28d: 'gym', // fitness_center
  0xe1dc: 'run', // directions_run
  0xefc0: 'bike', // directions_bike_outlined
  0xf2bf: 'swim', // pool_outlined
  0xf383: 'shower', // shower_outlined
  0xeec7: 'sleep', // bed_outlined
  0xf316: 'food', // restaurant_outlined
  0xf175: 'drink', // local_cafe_outlined
  0xf0695: 'water', // water_drop_outlined
  0xeedf: 'reading', // book_outlined
  0xf33c: 'study', // school_outlined
  0xf152: 'computer', // laptop_outlined
  0xe6f4: 'work', // work_outline
  0xf1c0: 'meeting', // meeting_room_outlined
  0xf290: 'call', // phone_outlined
  0xf1c6: 'message', // message_outlined
  0xf018: 'mail', // email_outlined
  0xf37f: 'shopping', // shopping_cart_outlined
  0xe0b2: 'finance', // attach_money
  0xf107: 'home', // home_outlined
  0xef56: 'cleaning', // cleaning_services_outlined
  0xf17e: 'health', // local_hospital_outlined
  0xf1bf: 'medication', // medication_outlined
  0xe25c: 'heart', // favorite_outline
  0xf1fb: 'music', // music_note_outlined
  0xf1f5: 'movie', // movie_outlined
  0xf3ca: 'games', // sports_esports_outlined
  0xef02: 'art', // brush_outlined
  0xf29b: 'photo', // photo_camera_outlined
  0xe4a1: 'pet', // pets
  0xf005: 'nature', // eco_outlined
  0xf25c: 'walk', // park_outlined
  0xf085: 'travel', // flight_outlined
  0xefc6: 'car', // directions_car_outlined
  0xe5fd: 'important', // star_outline
  0xf01a: 'goal', // emoji_events_outlined
  0xe37c: 'idea', // lightbulb_outline
  0xf2d2: 'thinking', // psychology_outlined
  0xf4a9: 'help', // volunteer_activism_outlined
  0xf0db: 'social', // groups_outlined
  0xe160: 'kids', // child_care
  0xf3bb: 'rest', // spa_outlined
  0xeec6: 'vacation', // beach_access_outlined
  0xf44a: 'timer', // timer_outlined
  0xe51f: 'habit', // repeat
};
