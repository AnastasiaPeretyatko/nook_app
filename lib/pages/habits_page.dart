import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/habits/habits_grid.dart';
import 'package:todo_app/widgets/habits/tasks_list.dart';

class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key});

  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: _HabitsDateHeader(date: DateTime.now()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: _HabitsTabBar(
                tabs: const [
                  _HabitsTab(icon: Icons.repeat, label: 'Привычки'),
                  _HabitsTab(icon: Icons.check_circle_outline, label: 'Задачи'),
                ],
                selectedIndex: _selectedTab,
                onChanged: (index) => setState(() => _selectedTab = index),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: const [HabitsGrid(), TasksList()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitsDateHeader extends StatelessWidget {
  const _HabitsDateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayMonth = DateFormat('d MMMM', 'ru_RU').format(date);
    final weekday = DateFormat('EEE', 'ru_RU').format(date).toUpperCase();

    final baseStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );

    return RichText(
      text: TextSpan(
        style: baseStyle?.copyWith(color: theme.colorScheme.onSurface),
        children: [
          TextSpan(text: dayMonth),
          const TextSpan(text: ' '),
          TextSpan(
            text: weekday,
            style: baseStyle?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitsTab {
  const _HabitsTab({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _HabitsTabBar extends StatelessWidget {
  const _HabitsTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<_HabitsTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The track and the thumb are neutral in both themes; what sits on the
    // thumb is asked for against the thumb, not assumed to be black.
    final thumb = neutralChip(theme);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: insetSurface(theme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / tabs.length;
          return Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                alignment: Alignment(
                  tabs.length == 1
                      ? 0
                      : -1 + 2 * selectedIndex / (tabs.length - 1),
                  0,
                ),
                child: Container(
                  width: tabWidth,
                  height: 36,
                  decoration: BoxDecoration(
                    color: thumb,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: SizedBox(
                          height: 36,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tabs[i].icon,
                                  size: 16,
                                  color: i == selectedIndex
                                      ? onTaskColor(thumb)
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  tabs[i].label,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: i == selectedIndex
                                        ? onTaskColor(thumb)
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
