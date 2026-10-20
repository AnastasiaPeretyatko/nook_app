import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/pages/archive_page.dart';
import 'package:todo_app/pages/settings_page.dart';
import 'package:todo_app/widgets/habits/habits_today.dart';
import 'package:todo_app/widgets/habits/habits_week.dart';
import 'package:todo_app/widgets/segmented_switch.dart';
import 'package:todo_app/widgets/page_header.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The "Привычки" tab. Settings live behind the profile button here rather than
/// on a tab of their own (DESIGN.md §6, "Навигация").
///
/// Two views under a switch: "Сегодня" (the week's strip and today's list) and
/// "Неделя" (how the week went). The choice is the page's own state, and the
/// page stays mounted behind the bottom bar, so it survives a visit elsewhere.
class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key});

  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              caption: todayCaption(DateTime.now()),
              title: 'Привычки',
              actions: [
                RoundIconButton(
                  icon: LucideIcons.archive,
                  tooltip: 'Архив',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ArchivePage(),
                    ),
                  ),
                ),
                RoundIconButton(
                  icon: LucideIcons.user_round,
                  tooltip: 'Профиль и настройки',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: SegmentedSwitch(
                labels: const ['Сегодня', 'Неделя'],
                selected: _view,
                onChanged: (i) => setState(() => _view = i),
              ),
            ),
            Expanded(
              child: _view == 0 ? const HabitsToday() : const HabitsWeek(),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Пятница, 16 октября" — the caption over a tab's title.
String todayCaption(DateTime date) {
  final text = DateFormat('EEEE, d MMMM', 'ru_RU').format(date);
  return text[0].toUpperCase() + text.substring(1);
}
