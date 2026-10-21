import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';

/// Opens the time sheet and returns the picked time as minutes from midnight, or
/// null when the sheet was dismissed without pressing "Готово".
///
/// Minutes and not a `TimeOfDay` because that is what a task stores
/// (`scheduledTimeMinutes`) and what the form holds.
Future<int?> showTimePickerSheet(
  BuildContext context, {
  required int initialMinutes,
  String title = 'Время',
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        TimePickerSheet(initialMinutes: initialMinutes, title: title),
  );
}

/// A bottom sheet with two wheels — hours and minutes — in place of the system
/// clock dialog. Minutes step by one, so any time can be reached by scrolling.
class TimePickerSheet extends StatefulWidget {
  const TimePickerSheet({
    super.key,
    required this.initialMinutes,
    this.title = 'Время',
  });

  final int initialMinutes;
  final String title;

  @override
  State<TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<TimePickerSheet> {
  late int _hour = (widget.initialMinutes % (24 * 60)) ~/ 60;
  late int _minute = widget.initialMinutes % 60;
  late final FixedExtentScrollController _hourController =
      FixedExtentScrollController(initialItem: _hour);
  late final FixedExtentScrollController _minuteController =
      FixedExtentScrollController(initialItem: _minute);

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: raisedSurface(theme),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    LucideIcons.clock,
                    size: 20,
                    // The accent as ink on the sheet, not as a fill.
                    color: inkOn(raisedSurface(theme), accent, minContrast: 3),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Wheel(
                      key: const ValueKey('hours'),
                      controller: _hourController,
                      count: 24,
                      selected: _hour,
                      onChanged: (v) => setState(() => _hour = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        ':',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _Wheel(
                      key: const ValueKey('minutes'),
                      controller: _minuteController,
                      count: 60,
                      selected: _minute,
                      onChanged: (v) => setState(() => _minute = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_hour * 60 + _minute),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: onBrandFill(accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Готово',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One wheel of two-digit numbers, the chosen one on a neutral plate.
class _Wheel extends StatelessWidget {
  const _Wheel({
    super.key,
    required this.controller,
    required this.count,
    required this.selected,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int count;
  final int selected;
  final ValueChanged<int> onChanged;

  static const _extent = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 80,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                height: _extent,
                decoration: BoxDecoration(
                  color: insetSurface(theme),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: _extent,
            perspective: 0.003,
            diameterRatio: 1.5,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: count,
              builder: (context, index) {
                final isSelected = index == selected;
                return Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
