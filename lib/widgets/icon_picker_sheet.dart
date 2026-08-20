import 'package:flutter/material.dart';
import 'package:todo_app/utils/surfaces.dart';

class IconPickerSheet extends StatefulWidget {
  const IconPickerSheet({super.key, this.selected});

  final IconData? selected;

  static Future<IconData?> show(BuildContext context, {IconData? selected}) {
    return showModalBottomSheet<IconData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IconPickerSheet(selected: selected),
    );
  }

  @override
  State<IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<IconPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  static const _allIcons = [
    (Icons.alarm_outlined, 'Будильник'),
    (Icons.coffee_outlined, 'Кофе'),
    (Icons.self_improvement_outlined, 'Медитация'),
    (Icons.fitness_center, 'Зал'),
    (Icons.directions_run, 'Бег'),
    (Icons.directions_bike_outlined, 'Велосипед'),
    (Icons.pool_outlined, 'Плавание'),
    (Icons.shower_outlined, 'Душ'),
    (Icons.bed_outlined, 'Сон'),
    (Icons.restaurant_outlined, 'Еда'),
    (Icons.local_cafe_outlined, 'Напиток'),
    (Icons.water_drop_outlined, 'Вода'),
    (Icons.book_outlined, 'Чтение'),
    (Icons.school_outlined, 'Учёба'),
    (Icons.laptop_outlined, 'Компьютер'),
    (Icons.work_outline, 'Работа'),
    (Icons.meeting_room_outlined, 'Встреча'),
    (Icons.phone_outlined, 'Звонок'),
    (Icons.message_outlined, 'Сообщение'),
    (Icons.email_outlined, 'Почта'),
    (Icons.shopping_cart_outlined, 'Покупки'),
    (Icons.attach_money, 'Финансы'),
    (Icons.home_outlined, 'Дом'),
    (Icons.cleaning_services_outlined, 'Уборка'),
    (Icons.local_hospital_outlined, 'Здоровье'),
    (Icons.medication_outlined, 'Лекарство'),
    (Icons.favorite_outline, 'Здоровье'),
    (Icons.music_note_outlined, 'Музыка'),
    (Icons.movie_outlined, 'Кино'),
    (Icons.sports_esports_outlined, 'Игры'),
    (Icons.brush_outlined, 'Творчество'),
    (Icons.photo_camera_outlined, 'Фото'),
    (Icons.pets, 'Питомец'),
    (Icons.eco_outlined, 'Природа'),
    (Icons.park_outlined, 'Прогулка'),
    (Icons.flight_outlined, 'Путешествие'),
    (Icons.directions_car_outlined, 'Авто'),
    (Icons.star_outline, 'Важное'),
    (Icons.emoji_events_outlined, 'Цель'),
    (Icons.lightbulb_outline, 'Идея'),
    (Icons.psychology_outlined, 'Размышление'),
    (Icons.volunteer_activism_outlined, 'Помощь'),
    (Icons.groups_outlined, 'Общение'),
    (Icons.child_care, 'Дети'),
    (Icons.spa_outlined, 'Отдых'),
    (Icons.beach_access_outlined, 'Отпуск'),
    (Icons.timer_outlined, 'Таймер'),
    (Icons.repeat, 'Привычка'),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _query.isEmpty
        ? _allIcons
        : _allIcons
              .where((e) => e.$2.toLowerCase().contains(_query.toLowerCase()))
              .toList();

    return Container(
      decoration: BoxDecoration(
        color: raisedSurface(theme),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Выберите иконку',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: insetSurface(theme),
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Поиск...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: insetSurface(theme),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Ничего не найдено',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.85,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final (icon, label) = filtered[i];
                      final isSelected =
                          widget.selected?.codePoint == icon.codePoint;
                      return _IconCell(
                        icon: icon,
                        label: label,
                        isSelected: isSelected,
                        onTap: () => Navigator.of(context).pop(icon),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _IconCell extends StatelessWidget {
  const _IconCell({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected ? theme.colorScheme.primary : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : insetSurface(theme),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.4)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 26,
              color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: isSelected
                    ? color
                    : theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.75,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
