import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/pages/archive_page.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/habits/habits_grid.dart';
import 'package:todo_app/widgets/habits/tasks_list.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key});

  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  /// The tab bar's thumb and the page transition move together, so they share
  /// one duration and curve.
  static const _tabSwitch = Duration(milliseconds: 250);
  static const _tabCurve = Curves.easeInOutCubic;

  int _selectedTab = 0;
  final _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// A tap on the tab bar. The swipe reports itself through [_onPageChanged]
  /// instead — animating there would fight the finger.
  void _onTabTapped(int index) {
    if (index == _selectedTab) return;
    setState(() => _selectedTab = index);
    _pages.animateToPage(index, duration: _tabSwitch, curve: _tabCurve);
  }

  /// The archive opens as a full route on top of the nav bar: the only way
  /// back is its own arrow, which is what keeps it out of the tab strip.
  void _onArchiveTapped() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ArchivePage()));
  }

  void _onPageChanged(int index) {
    // Also fires at the end of [_onTabTapped]'s animation, where the state is
    // already there.
    if (index == _selectedTab) return;
    setState(() => _selectedTab = index);
  }

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
              child: Row(
                children: [
                  Expanded(child: _HabitsDateHeader(date: DateTime.now())),
                  const SizedBox(width: 8),
                  _ArchiveButton(onPressed: _onArchiveTapped),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: _HabitsTabBar(
                tabs: const [
                  _HabitsTab(icon: LucideIcons.repeat, label: 'Привычки'),
                  _HabitsTab(icon: LucideIcons.circle_check, label: 'Задачи'),
                ],
                selectedIndex: _selectedTab,
                onChanged: _onTabTapped,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: _onPageChanged,
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

    // `Text.rich` and not `RichText`: the bare one defaults to
    // `TextScaler.noScaling`, so this heading stayed at its 24px while the
    // calendar's month on the day screen — a plain `Text`, which reads
    // `MediaQuery.textScalerOf` — grew with the system font size. Two headings
    // written in the same style came out different sizes on every device whose
    // font scale is not 1.0.
    return Text.rich(
      TextSpan(
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
      style: baseStyle?.copyWith(color: theme.colorScheme.onSurface),
    );
  }
}

/// The header's trailing button: everything archived lives behind it.
class _ArchiveButton extends StatelessWidget {
  const _ArchiveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      tooltip: 'Архив',
      onPressed: onPressed,
      icon: Icon(
        LucideIcons.archive,
        color: theme.colorScheme.onSurfaceVariant,
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
    // The track stays neutral; the thumb is the app accent, so the selected tab
    // reads as a brand fill and takes [onBrandFill] for its icon and label.
    final thumb = theme.colorScheme.primary;
    final selectedInk = onBrandFill(thumb);

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
                duration: _HabitsPageState._tabSwitch,
                curve: _HabitsPageState._tabCurve,
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
                                      ? selectedInk
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  tabs[i].label,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: i == selectedIndex
                                        ? selectedInk
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
