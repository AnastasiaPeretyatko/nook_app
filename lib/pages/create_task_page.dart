import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/widgets/form_header.dart';
import 'package:todo_app/widgets/icon_picker_sheet.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../utils/task_icons.dart';

/// How [CreateTaskPage] behaves: creating a brand new task, editing an
/// existing one, or duplicating one into a new task.
enum TaskFormMode { create, edit, clone }

/// One editable subtask line in the form. [id] is null while the row has no row
/// of its own in the database yet — a freshly added one, or a copy made by
/// duplicating a task.
class _SubtaskDraft {
  _SubtaskDraft({
    this.id,
    String title = '',
    this.done = false,
    this.isNew = false,
  }) : controller = TextEditingController(text: title);

  final int? id;
  final TextEditingController controller;
  bool done;

  /// Added by the button just now, so the field takes focus for typing.
  final bool isNew;

  void dispose() => controller.dispose();
}

class CreateTaskPage extends ConsumerStatefulWidget {
  const CreateTaskPage({super.key, this.mode = TaskFormMode.create, this.task})
    : assert(
        mode == TaskFormMode.create || task != null,
        'edit/clone modes require a source task',
      );

  final TaskFormMode mode;

  /// Source task for [TaskFormMode.edit] and [TaskFormMode.clone].
  final Task? task;

  @override
  ConsumerState<CreateTaskPage> createState() => _CreateTaskPageState();
}

class _CreateTaskPageState extends ConsumerState<CreateTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  TrackingMode _trackingMode = TrackingMode.checkbox;

  /// Only meaningful while [_repeatEnabled] is true; keeps the last picked type
  /// so toggling repetition off and on again restores the previous choice.
  RepeatType _repeatType = RepeatType.daily;

  /// "Every N weeks/months/days". Unused by [RepeatType.daily], which always
  /// means every single day.
  int _repeatInterval = 1;

  /// Weekdays a [RepeatType.weekly] task lands on, as [DateTime.weekday]
  /// numbers. Never empty while the weekly picker is on screen.
  Set<int> _repeatWeekdays = {};

  /// Days of the month a [RepeatType.monthly] task lands on (1 … 31). Never
  /// empty while the monthly picker is on screen.
  Set<int> _repeatMonthDays = {};

  /// Target for the counter and value tracking modes, both of which live in the
  /// same `targetValue` column. Zero means "no target": such a task shows a
  /// plain checkbox instead of a counter, so it stays null in the database.
  double _targetValue = 0;

  /// Target for the timer tracking mode, in minutes. Zero means "no target" and
  /// stays null in the database, same as [_targetValue].
  int _targetDurationMinutes = 0;

  /// Subtask lines shown inside the description card, in display order.
  final List<_SubtaskDraft> _subtasks = [];

  /// Ids the form started with, so rows the user deleted can be removed on save.
  Set<int> _loadedSubtaskIds = const {};

  /// True until the existing subtasks have been read. Saving before that would
  /// drop a duplicate's subtasks, so the save button waits.
  bool _loadingSubtasks = false;
  /// Key of the chosen task icon — see `taskIcons`.
  String? _selectedIconKey;
  Color? _selectedColor;
  int _startMinutes = 0;
  int? _durationMinutes;
  DateTime _selectedDate = DateTime.now();
  bool _timeEnabled = false;
  bool _dateEnabled = true;
  bool _repeatEnabled = false;
  bool _isSaving = false;

  late final FixedExtentScrollController _timeWheelController;

  static const _cardRadius = BorderRadius.all(Radius.circular(18));
  static const _timeStep = 15;
  static const _maxInterval = 99;

  /// Counters are whole repetitions, so they step by one; free-form values step
  /// by a half to make targets like 2.5 reachable.
  static const _counterStep = 1.0;
  static const _minCounterTarget = 1.0;
  static const _valueStep = 0.5;
  static const _maxTargetValue = 100000.0;

  /// Timer targets step in five-minute chunks and stop at a full day.
  static const _timerStep = 5;
  static const _maxTargetMinutes = 24 * 60;

  @override
  void initState() {
    super.initState();
    final now = TimeOfDay.now();
    final roundedNow =
        ((now.hour * 60 + now.minute) / _timeStep).round() *
        _timeStep %
        (24 * 60);

    final source = widget.task;
    if (source != null) {
      _titleController.text = source.title;
      _descController.text = source.description ?? '';
      _trackingMode = source.trackingMode;
      _repeatEnabled = source.repeatType != null;
      _repeatType = source.repeatType ?? RepeatType.daily;
      _repeatInterval = (source.repeatInterval ?? 1).clamp(1, _maxInterval);
      // Tasks saved before the pickers existed carry no mask: they repeated on
      // the weekday / day of month of their anchor, so preselect exactly that.
      final anchor = source.startDate ?? source.createdAt;
      if (_repeatType == RepeatType.weekly) {
        _repeatWeekdays = daysFromMask(source.repeatDaysMask, maxDay: 7);
        if (_repeatWeekdays.isEmpty) _repeatWeekdays = {anchor.weekday};
      }
      if (_repeatType == RepeatType.monthly) {
        _repeatMonthDays = daysFromMask(source.repeatDaysMask, maxDay: 31);
        if (_repeatMonthDays.isEmpty) _repeatMonthDays = {anchor.day};
      }
      _targetDurationMinutes = (source.targetDurationMinutes ?? 0).clamp(
        0,
        _maxTargetMinutes,
      );
      _targetValue = (source.targetValue ?? 0).clamp(0, _maxTargetValue);
      if (_trackingMode == TrackingMode.counter) {
        _targetValue = _counterTargetOf(_targetValue);
      }
      _selectedIconKey = source.iconKey;
      _selectedColor = source.colorValue != null
          ? Color(source.colorValue!)
          : null;
      _timeEnabled = source.scheduledTimeMinutes != null;
      _startMinutes = source.scheduledTimeMinutes ?? roundedNow;
      if (source.scheduledTimeMinutes != null &&
          source.endTimeMinutes != null) {
        final diff = source.endTimeMinutes! - source.scheduledTimeMinutes!;
        _durationMinutes = diff > 0 ? diff : null;
      }
      _dateEnabled = source.startDate != null;
      _selectedDate = source.startDate ?? DateTime.now();
    } else {
      _startMinutes = roundedNow;
    }

    _timeWheelController = FixedExtentScrollController(
      initialItem: _startMinutes ~/ _timeStep,
    );

    if (source != null) {
      _loadingSubtasks = true;
      unawaited(_loadSubtasks(source));
    }
  }

  /// Seeds the subtask rows from the task being edited or duplicated. A duplicate
  /// keeps the titles but drops the ids, so saving inserts fresh rows under the
  /// new task instead of moving the originals.
  Future<void> _loadSubtasks(Task source) async {
    final keepIds = widget.mode == TaskFormMode.edit;
    final dao = ref.read(tasksDaoProvider);
    final existing = await dao.getSubtasks(source.id);
    if (existing.isEmpty) {
      if (mounted) setState(() => _loadingSubtasks = false);
      return;
    }

    final refDate = _subtaskLogDate(source.startDate);
    final drafts = <_SubtaskDraft>[];
    for (final subtask in existing) {
      final log = await dao.getLogForDate(subtask.id, refDate);
      drafts.add(
        _SubtaskDraft(
          id: keepIds ? subtask.id : null,
          title: subtask.title,
          done: log?.completed ?? false,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _subtasks.addAll(drafts);
      _loadedSubtaskIds = keepIds
          ? existing.map((t) => t.id).toSet()
          : const {};
      _loadingSubtasks = false;
    });
  }

  /// Subtask completion lives in `TaskLogs` like any other task's, so it needs a
  /// date: the task's own start date, or today when it has none.
  DateTime _subtaskLogDate(DateTime? startDate) {
    final date = startDate ?? DateTime.now();
    return DateTime(date.year, date.month, date.day);
  }

  void _addSubtask() =>
      setState(() => _subtasks.add(_SubtaskDraft(isNew: true)));

  void _removeSubtask(int index) => setState(() {
    _subtasks.removeAt(index).dispose();
  });

  String get _screenTitle => switch (widget.mode) {
    TaskFormMode.create => 'Новая задача',
    TaskFormMode.edit => 'Редактирование',
    TaskFormMode.clone => 'Дублирование',
  };

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    for (final subtask in _subtasks) {
      subtask.dispose();
    }
    _timeWheelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final startMin = _startMinutes;
    final endMin =
        (_timeEnabled && _durationMinutes != null && _durationMinutes! > 0)
        ? startMin + _durationMinutes!
        : null;

    final title = _titleController.text.trim();
    final description = _descController.text.trim();
    final repeatType = _repeatEnabled ? _repeatType : null;
    // Daily means literally every day, so it carries no interval. For the other
    // types an interval of 1 is the default and stays null in the database.
    final repeatInterval =
        repeatType == null ||
            repeatType == RepeatType.daily ||
            _repeatInterval <= 1
        ? null
        : _repeatInterval;
    final repeatDaysMask = switch (repeatType) {
      RepeatType.weekly => daysToMask(_repeatWeekdays),
      RepeatType.monthly => daysToMask(_repeatMonthDays),
      RepeatType.daily || RepeatType.custom || null => null,
    };
    final targetDuration =
        _trackingMode == TrackingMode.timer && _targetDurationMinutes > 0
        ? _targetDurationMinutes
        : null;
    final targetValue = switch (_trackingMode) {
      // A counter is defined by how many times, so it always carries one.
      TrackingMode.counter => _counterTargetOf(_targetValue),
      TrackingMode.value => _targetValue > 0 ? _targetValue : null,
      TrackingMode.checkbox || TrackingMode.timer => null,
    };
    final startDate = _dateEnabled
        ? DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)
        : null;

    setState(() => _isSaving = true);
    final dao = ref.read(tasksDaoProvider);
    final source = widget.task;

    final subtaskLogDate = _subtaskLogDate(startDate);

    if (widget.mode == TaskFormMode.edit && source != null) {
      await dao.updateTaskById(
        source.id,
        TasksCompanion(
          title: Value(title),
          description: Value(description.isEmpty ? null : description),
          trackingMode: Value(_trackingMode),
          repeatType: Value(repeatType),
          repeatInterval: Value(repeatInterval),
          repeatDaysMask: Value(repeatDaysMask),
          targetDurationMinutes: Value(targetDuration),
          targetValue: Value(targetValue),
          iconKey: Value(_selectedIconKey),
          colorValue: Value(_selectedColor?.toARGB32()),
          scheduledTimeMinutes: Value(_timeEnabled ? startMin : null),
          endTimeMinutes: Value(endMin),
          startDate: Value(startDate),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _saveSubtasks(dao, source.id, subtaskLogDate);
    } else {
      final companion = TasksCompanion.insert(
        title: title,
        description: description.isEmpty
            ? const Value.absent()
            : Value(description),
        trackingMode: Value(_trackingMode),
        repeatType: repeatType != null
            ? Value(repeatType)
            : const Value.absent(),
        repeatInterval: repeatInterval != null
            ? Value(repeatInterval)
            : const Value.absent(),
        repeatDaysMask: repeatDaysMask != null
            ? Value(repeatDaysMask)
            : const Value.absent(),
        targetDurationMinutes: targetDuration != null
            ? Value(targetDuration)
            : const Value.absent(),
        targetValue: targetValue != null
            ? Value(targetValue)
            : const Value.absent(),
        iconKey: _selectedIconKey != null
            ? Value(_selectedIconKey!)
            : const Value.absent(),
        colorValue: _selectedColor != null
            ? Value(_selectedColor!.toARGB32())
            : const Value.absent(),
        scheduledTimeMinutes: _timeEnabled
            ? Value(startMin)
            : const Value.absent(),
        endTimeMinutes: endMin != null ? Value(endMin) : const Value.absent(),
        startDate: startDate != null ? Value(startDate) : const Value.absent(),
      );

      final newId = await dao.insertTask(companion);
      // A duplicate's subtasks come through the form's own rows, seeded from the
      // source in [_loadSubtasks] — copying them again here would double them up.
      await _saveSubtasks(dao, newId, subtaskLogDate);
    }

    if (mounted) Navigator.of(context).pop();
  }

  /// Writes the subtask rows under [parentId]: inserts the new ones, updates the
  /// titles of the kept ones, and deletes the rows the user cleared or removed.
  /// An empty title counts as removal — there is nothing to save in a blank line.
  Future<void> _saveSubtasks(
    TasksDao dao,
    int parentId,
    DateTime logDate,
  ) async {
    final keptIds = <int>{};

    for (final draft in _subtasks) {
      final title = draft.controller.text.trim();
      final id = draft.id;

      if (title.isEmpty) continue;

      if (id == null) {
        final newId = await dao.insertTask(
          TasksCompanion.insert(parentId: Value(parentId), title: title),
        );
        // Only tick a brand-new subtask, so unchecked ones leave no empty log.
        if (draft.done) await dao.setLog(newId, logDate, completed: true);
        continue;
      }

      keptIds.add(id);
      await dao.updateTaskById(
        id,
        TasksCompanion(title: Value(title), updatedAt: Value(DateTime.now())),
      );
      await dao.setLog(id, logDate, completed: draft.done);
    }

    for (final id in _loadedSubtaskIds) {
      if (!keptIds.contains(id)) await dao.deleteTaskCascade(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageSurface(Theme.of(context)),
      body: SafeArea(
        child: Column(
          children: [
            FormHeader(
              title: _screenTitle,
              onCancel: () => Navigator.of(context).pop(),
              onSave: _save,
              isBusy: _isSaving || _loadingSubtasks,
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _AppearanceCard(
                      selectedIconKey: _selectedIconKey,
                      selectedColor: _selectedColor,
                      onPickIcon: () async {
                        final key = await IconPickerSheet.show(
                          context,
                          selected: _selectedIconKey,
                        );
                        if (key != null) {
                          setState(() => _selectedIconKey = key);
                        }
                      },
                      onColorChanged: (c) => setState(() => _selectedColor = c),
                      titleField: _Field(
                        controller: _titleController,
                        label: 'Название',
                        hint: 'Что нужно сделать?',
                        autofocus: true,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Обязательное поле'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // A card of its own: the title is what the task *is*, the
                    // description is the detail behind it, and a divider inside
                    // one card read as if the two belonged together.
                    _Card(
                      child: Column(
                        children: [
                          // One block: the label heads it, then the subtasks,
                          // then the description text itself — no divider
                          // between them, or they read as two sections. The
                          // button closes the block, below the content it adds
                          // to, so the reading order is what the task holds
                          // before how to add more of it.
                          const _CardLabel('Описание'),
                          for (var i = 0; i < _subtasks.length; i++)
                            _SubtaskRow(
                              key: ObjectKey(_subtasks[i]),
                              draft: _subtasks[i],
                              onToggle: () => setState(() {
                                _subtasks[i].done = !_subtasks[i].done;
                              }),
                              onRemove: () => _removeSubtask(i),
                            ),
                          _Field(
                            controller: _descController,
                            hint: 'Дополнительные детали',
                            maxLines: 3,
                          ),
                          _AddSubtaskButton(onTap: _addSubtask),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionLabel('Дата и время'),
                    const SizedBox(height: 8),
                    _Card(
                      child: Column(
                        children: [
                          _ToggleRow(
                            icon: LucideIcons.clock,
                            label: 'Указать время',
                            value: _timeEnabled,
                            onChanged: (v) => setState(() => _timeEnabled = v),
                          ),
                          if (_timeEnabled) ...[
                            const _Divider(),
                            const SizedBox(height: 8),
                            _TimeWheel(
                              controller: _timeWheelController,
                              startMinutes: _startMinutes,
                              durationMinutes: _durationMinutes,
                              step: _timeStep,
                              onChanged: (m) =>
                                  setState(() => _startMinutes = m),
                            ),
                          ],
                          const _Divider(),
                          _ToggleRow(
                            icon: LucideIcons.calendar,
                            label: 'Указать дату',
                            value: _dateEnabled,
                            onChanged: (v) => setState(() => _dateEnabled = v),
                          ),
                          if (_dateEnabled) ...[
                            const _Divider(),
                            _DateRow(date: _selectedDate, onTap: _pickDate),
                          ],
                        ],
                      ),
                    ),
                    if (_timeEnabled) ...[
                      const SizedBox(height: 12),
                      _SectionHeader(
                        title: 'Как долго?',
                        actionLabel: 'Настроить',
                        onAction: _showCustomDuration,
                      ),
                      const SizedBox(height: 8),
                      _Card(
                        child: _DurationSelector(
                          value: _durationMinutes,
                          onChanged: (v) =>
                              setState(() => _durationMinutes = v),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _SectionLabel('Режим отслеживания'),
                    const SizedBox(height: 8),
                    _Card(
                      child: _ModeSelector(
                        value: _trackingMode,
                        onChanged: _changeTrackingMode,
                      ),
                    ),
                    if (_trackingMode == TrackingMode.timer) ...[
                      const SizedBox(height: 12),
                      _Card(
                        child: _StepperRow(
                          label: 'Целевая длительность',
                          valueText: _targetDurationLabel,
                          onMinus: _targetDurationMinutes > 0
                              ? () => _changeTargetDuration(-_timerStep)
                              : null,
                          onPlus: _targetDurationMinutes < _maxTargetMinutes
                              ? () => _changeTargetDuration(_timerStep)
                              : null,
                          onValueTap: _enterTargetDuration,
                        ),
                      ),
                    ],
                    if (_trackingMode == TrackingMode.counter) ...[
                      const SizedBox(height: 12),
                      _Card(
                        child: _StepperRow(
                          label: 'Целевое количество',
                          valueText: _targetValueLabel,
                          // A counter stops at one: "no target" is what the
                          // checkbox mode is for.
                          onMinus: _targetValue > _minCounterTarget
                              ? () => _changeTarget(-_counterStep)
                              : null,
                          onPlus: _targetValue < _maxTargetValue
                              ? () => _changeTarget(_counterStep)
                              : null,
                          onValueTap: () => _enterTarget(allowDecimal: false),
                        ),
                      ),
                    ],
                    if (_trackingMode == TrackingMode.value) ...[
                      const SizedBox(height: 12),
                      _Card(
                        child: _StepperRow(
                          label: 'Целевое значение',
                          valueText: _targetValueLabel,
                          onMinus: _targetValue > 0
                              ? () => _changeTarget(-_valueStep)
                              : null,
                          onPlus: _targetValue < _maxTargetValue
                              ? () => _changeTarget(_valueStep)
                              : null,
                          onValueTap: () => _enterTarget(allowDecimal: true),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        children: [
                          _ToggleRow(
                            icon: LucideIcons.repeat,
                            label: 'Повторение',
                            value: _repeatEnabled,
                            onChanged: (v) =>
                                setState(() => _repeatEnabled = v),
                          ),
                          if (_repeatEnabled) ...[
                            const _Divider(),
                            _RepeatTypeSelector(
                              value: _repeatType,
                              onChanged: _onRepeatTypeChanged,
                            ),
                            // Daily needs no interval at all — "every day" is
                            // the whole rule. The rest get one control each.
                            if (_repeatType == RepeatType.weekly) ...[
                              const _Divider(),
                              _WeekdayPicker(
                                selected: _repeatWeekdays,
                                onToggle: (d) => _toggleDay(_repeatWeekdays, d),
                              ),
                            ],
                            if (_repeatType == RepeatType.monthly) ...[
                              const _Divider(),
                              _MonthDayPicker(
                                selected: _repeatMonthDays,
                                onToggle: (d) =>
                                    _toggleDay(_repeatMonthDays, d),
                              ),
                            ],
                            if (_repeatType != RepeatType.daily) ...[
                              const _Divider(),
                              _StepperRow(
                                label: 'Повторять каждые',
                                valueText:
                                    '$_repeatInterval $_intervalUnitLabel',
                                onMinus: _repeatInterval > 1
                                    ? () => setState(() => _repeatInterval--)
                                    : null,
                                onPlus: _repeatInterval < _maxInterval
                                    ? () => setState(() => _repeatInterval++)
                                    : null,
                              ),
                            ],
                            const _Divider(),
                            _RepeatSummary(text: _repeatSummary),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030, 12, 31),
      locale: const Locale('ru', 'RU'),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _showCustomDuration() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomDurationSheet(initialMinutes: _durationMinutes),
    );
    if (result != null) {
      setState(() => _durationMinutes = result <= 0 ? null : result);
    }
  }

  void _onRepeatTypeChanged(RepeatType type) => setState(() {
    _repeatType = type;
    _repeatInterval = 1;
    // Seed the pickers from the task's own date so they never open empty.
    if (type == RepeatType.weekly && _repeatWeekdays.isEmpty) {
      _repeatWeekdays = {_selectedDate.weekday};
    }
    if (type == RepeatType.monthly && _repeatMonthDays.isEmpty) {
      _repeatMonthDays = {_selectedDate.day};
    }
  });

  /// Toggles a day in [selection], refusing to clear the last remaining one — a
  /// repeating task has to land somewhere.
  void _toggleDay(Set<int> selection, int day) => setState(() {
    if (selection.contains(day)) {
      if (selection.length > 1) selection.remove(day);
    } else {
      selection.add(day);
    }
  });

  void _changeTarget(double delta) => setState(() {
    _targetValue = (_targetValue + delta).clamp(
      _trackingMode == TrackingMode.counter ? _minCounterTarget : 0,
      _maxTargetValue,
    );
  });

  /// Switching the mode carries the target over, so it has to be brought into
  /// the new mode's shape: a counter counts whole times and at least once, while
  /// "Значение" is free to be fractional or absent.
  void _changeTrackingMode(TrackingMode mode) => setState(() {
    _trackingMode = mode;
    if (mode == TrackingMode.counter) {
      _targetValue = _counterTargetOf(_targetValue);
    }
  });

  /// [value] as a counter target: whole, and never below one.
  static double _counterTargetOf(double value) {
    final rounded = value.round().toDouble();
    return rounded < _minCounterTarget ? _minCounterTarget : rounded;
  }

  void _changeTargetDuration(int delta) => setState(() {
    _targetDurationMinutes = (_targetDurationMinutes + delta).clamp(
      0,
      _maxTargetMinutes,
    );
  });

  /// Reuses the hours-and-minutes sheet, so long targets take two taps instead
  /// of climbing there five minutes at a time.
  Future<void> _enterTargetDuration() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CustomDurationSheet(initialMinutes: _targetDurationMinutes),
    );
    if (result != null) {
      setState(
        () => _targetDurationMinutes = result.clamp(0, _maxTargetMinutes),
      );
    }
  }

  /// "без цели" at zero, otherwise a human duration like "1 ч 30 мин".
  String get _targetDurationLabel => _targetDurationMinutes > 0
      ? _formatDurationLabel(_targetDurationMinutes)
      : 'без цели';

  /// Lets a large target be typed instead of tapped up half a unit at a time.
  Future<void> _enterTarget({required bool allowDecimal}) async {
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TargetValueSheet(
        initial: _targetValue,
        allowDecimal: allowDecimal,
        max: _maxTargetValue,
      ),
    );
    if (result != null) setState(() => _targetValue = result);
  }

  /// What the target stepper shows: "без цели" at zero, "10 раз" for counters
  /// and a bare number for free-form values.
  String get _targetValueLabel {
    if (_targetValue <= 0) return 'без цели';
    final number = _formatNumber(_targetValue);
    if (_trackingMode != TrackingMode.counter) return number;
    final whole = _targetValue.round();
    return '$number ${_plural(whole, 'раз', 'раза', 'раз')}';
  }

  /// Short unit shown inside the stepper, e.g. "3 недели".
  String get _intervalUnitLabel => switch (_repeatType) {
    RepeatType.weekly => _plural(_repeatInterval, 'неделя', 'недели', 'недель'),
    RepeatType.monthly => _plural(
      _repeatInterval,
      'месяц',
      'месяца',
      'месяцев',
    ),
    RepeatType.daily ||
    RepeatType.custom => _plural(_repeatInterval, 'день', 'дня', 'дней'),
  };

  /// Plain-language restatement of the whole rule, so the number in the stepper
  /// never has to be interpreted on its own.
  String get _repeatSummary {
    final n = _repeatInterval;
    switch (_repeatType) {
      case RepeatType.daily:
        return 'Каждый день';

      case RepeatType.weekly:
        final days = _weekdayNames(_repeatWeekdays);
        final every = n == 1
            ? 'Каждую неделю'
            : 'Каждые $n ${_plural(n, 'неделю', 'недели', 'недель')}';
        return _repeatWeekdays.length == 7
            ? '$every, все дни'
            : '$every: $days';

      case RepeatType.monthly:
        final every = n == 1
            ? 'Каждый месяц'
            : 'Каждые $n ${_plural(n, 'месяц', 'месяца', 'месяцев')}';
        final days = _repeatMonthDays.toList()..sort();
        final which = days.length == 1
            ? '${days.single}-го числа'
            : 'по числам: ${days.join(', ')}';
        // 29–31 do not exist in every month, so spell out where they land.
        final note = days.any((d) => d > 28)
            ? ' · в коротких месяцах — последний день'
            : '';
        return '$every, $which$note';

      case RepeatType.custom:
        return n == 1
            ? 'Каждый день'
            : 'Каждые $n ${_plural(n, 'день', 'дня', 'дней')}';
    }
  }
}

/// Drops a trailing ".0" so that whole targets read as "10", not "10.0".
String _formatNumber(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();

/// Russian plural form for [n]: 1 день, 2 дня, 5 дней.
String _plural(int n, String one, String few, String many) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  final mod10 = n % 10;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}

const _weekdayShortNames = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

/// Selected weekdays as "пн, ср, пт", always in calendar order.
String _weekdayNames(Set<int> weekdays) {
  final sorted = weekdays.toList()..sort();
  return sorted.map((d) => _weekdayShortNames[d - 1]).join(', ');
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: raisedSurface(theme),
        borderRadius: _CreateTaskPageState._cardRadius,
        boxShadow: [
          BoxShadow(
            color: surfaceShadow(theme),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: child,
      ),
    );
  }
}

/// A field label on its own, for a block whose heading has to sit above other
/// controls rather than float inside the input.
class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      // Aligned explicitly: a bare [Text] takes only the width of its glyphs,
      // so it would sit wherever the surrounding column happens to align its
      // children — centred, in a plain [Column].
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.label,
    this.maxLines = 1,
    this.autofocus = false,
    this.validator,
  });

  final TextEditingController controller;

  /// Floating label. Null for a field whose heading is drawn above it instead.
  final String? label;
  final String hint;
  final int maxLines;
  final bool autofocus;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      validator: validator,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: InputBorder.none,
        labelStyle: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        hintStyle: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

/// The "add a subtask" plate. Closes the description card: the subtasks it
/// creates read as part of that block rather than as a separate section, and it
/// sits below them so the block reads content first, action last.
class _AddSubtaskButton extends StatelessWidget {
  const _AddSubtaskButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: insetSurface(theme),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.plus, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                'Добавить подзадачу',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A checkbox and a text field for one subtask, with a way back out: a blank or
/// removed line simply is not saved.
class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({
    super.key,
    required this.draft,
    required this.onToggle,
    required this.onRemove,
  });

  final _SubtaskDraft draft;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: draft.done ? primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: draft.done ? primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                    width: 1.6,
                  ),
                ),
                child: draft.done
                    ? Icon(
                        LucideIcons.check,
                        size: 14,
                        color: onBrandFill(theme.colorScheme.primary),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: draft.controller,
              autofocus: draft.isNew,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: draft.done ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75) : theme.colorScheme.onSurface,
                decoration: draft.done ? TextDecoration.lineThrough : null,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Подзадача',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(LucideIcons.x, size: 16),
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            visualDensity: VisualDensity.compact,
            tooltip: 'Убрать подзадачу',
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
          // Colours come from `switchTheme` in `buildAppTheme`, so this row and
          // the switch in the settings screen look the same.
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDurationLabel(int minutes) {
  if (minutes < 60) return '$minutes мин';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '$h ч';
  return '$h ч $m мин';
}

class _DurationSelector extends StatelessWidget {
  const _DurationSelector({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  static const _presets = [15, 30, 45, 60, 90, 120];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presets = [..._presets];
    // Show a custom value as its own selected chip if not among presets.
    if (value != null && value! > 0 && !presets.contains(value)) {
      presets.add(value!);
      presets.sort();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip(context, theme, null, 'Без длительности'),
            for (final m in presets) ...[
              const SizedBox(width: 8),
              _chip(context, theme, m, _formatDurationLabel(m)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    ThemeData theme,
    int? minutes,
    String label,
  ) {
    final selected = value == minutes;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onChanged(minutes),
      selectedColor: theme.colorScheme.primary,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: selected ? onBrandFill(theme.colorScheme.primary) : theme.colorScheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: insetSurface(theme),
      side: BorderSide.none,
      showCheckmark: false,
    );
  }
}

class _CustomDurationSheet extends StatefulWidget {
  const _CustomDurationSheet({required this.initialMinutes});

  final int? initialMinutes;

  @override
  State<_CustomDurationSheet> createState() => _CustomDurationSheetState();
}

class _CustomDurationSheetState extends State<_CustomDurationSheet> {
  late int _hours = (widget.initialMinutes ?? 0) ~/ 60;
  late int _minutes = (widget.initialMinutes ?? 0) % 60;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _hours * 60 + _minutes;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: raisedSurface(theme),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
            Text(
              'Своя длительность',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Stepper(
                    label: 'Часы',
                    value: _hours,
                    max: 23,
                    onChanged: (v) => setState(() => _hours = v),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Stepper(
                    label: 'Минуты',
                    value: _minutes,
                    max: 59,
                    step: 5,
                    onChanged: (v) => setState(() => _minutes = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(total),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: onBrandFill(theme.colorScheme.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  total > 0
                      ? 'Готово · ${_formatDurationLabel(total)}'
                      : 'Без длительности',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Types an exact target, for the amounts that would take too many taps.
/// An empty field means "no target" and comes back as zero.
class _TargetValueSheet extends StatefulWidget {
  const _TargetValueSheet({
    required this.initial,
    required this.allowDecimal,
    required this.max,
  });

  final double initial;
  final bool allowDecimal;
  final double max;

  @override
  State<_TargetValueSheet> createState() => _TargetValueSheetState();
}

class _TargetValueSheetState extends State<_TargetValueSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial > 0 ? _formatNumber(widget.initial) : '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _parsed {
    final raw = _controller.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return 0;
    final parsed = double.tryParse(raw) ?? 0;
    return parsed.clamp(0, widget.max);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: raisedSurface(theme),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
            Text(
              'Своя цель',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: widget.allowDecimal
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.number,
              inputFormatters: [
                if (widget.allowDecimal)
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                else
                  FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => Navigator.of(context).pop(_parsed),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'Без цели',
                filled: true,
                fillColor: insetSurface(theme),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_parsed),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: onBrandFill(theme.colorScheme.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _parsed > 0
                      ? 'Готово · ${_formatNumber(_parsed)}'
                      : 'Без цели',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: insetSurface(theme),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: value > 0
                    ? () => onChanged((value - step).clamp(0, max))
                    : null,
                icon: const Icon(LucideIcons.minus),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                '$value',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                onPressed: value < max
                    ? () => onChanged((value + step).clamp(0, max))
                    : null,
                icon: const Icon(LucideIcons.plus),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.value, required this.onChanged});
  final TrackingMode value;
  final ValueChanged<TrackingMode> onChanged;

  static const _modes = [
    (TrackingMode.checkbox, LucideIcons.circle_check, 'Чекбокс'),
    (TrackingMode.counter, LucideIcons.circle_plus, 'Счётчик'),
    (TrackingMode.timer, LucideIcons.timer, 'Таймер'),
    (TrackingMode.value, LucideIcons.sliders_horizontal, 'Значение'),
  ];

  /// Modes the form will not let the user pick.
  ///
  /// [TrackingMode.value] is parked: nothing in the app reads a free-form value
  /// yet, so saving a task with it produces something that behaves like a plain
  /// checkbox while quietly remembering a number. It stays on screen, greyed
  /// out, rather than being taken away — and a task that already uses it still
  /// shows it as its mode, so opening such a task to edit cannot silently
  /// rewrite what it tracks. Emptying this set is all it takes to bring the mode
  /// back; nothing in the database or the enum changes meanwhile.
  static const _blocked = {TrackingMode.value};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: _modes.map((entry) {
          final (mode, icon, label) = entry;
          final selected = value == mode;
          final blocked = !selected && _blocked.contains(mode);

          final Color background;
          final Color iconColor;
          final Color labelColor;
          if (selected) {
            // A selected tile is painted with the accent — a brand fill, so its
            // icon and label take the brand ink instead of the scheme's
            // luminance-flipped onPrimary. Every accent-filled control on this
            // form does the same.
            background = theme.colorScheme.primary;
            iconColor = onBrandFill(background);
            labelColor = onBrandFill(background);
          } else if (blocked) {
            background = disabledInsetSurface(theme);
            iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55);
            labelColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55);
          } else {
            background = insetSurface(theme);
            iconColor = theme.colorScheme.onSurfaceVariant;
            labelColor = theme.colorScheme.onSurfaceVariant;
          }

          return Expanded(
            child: GestureDetector(
              onTap: blocked ? null : () => onChanged(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(icon, size: 22, color: iconColor),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: labelColor,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Two-by-two grid of repeat types. There is no "no repeat" cell — repetition
/// is switched off by the toggle above the grid, not by a selection here.
class _RepeatTypeSelector extends StatelessWidget {
  const _RepeatTypeSelector({required this.value, required this.onChanged});
  final RepeatType value;
  final ValueChanged<RepeatType> onChanged;

  static const _types = [
    (RepeatType.daily, LucideIcons.calendar_check, 'Ежедневно'),
    (RepeatType.weekly, LucideIcons.calendar_range, 'Еженедельно'),
    (RepeatType.monthly, LucideIcons.calendar_days, 'Ежемесячно'),
    (RepeatType.custom, LucideIcons.sliders_horizontal, 'Другое'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(children: [_cell(theme, _types[0]), _cell(theme, _types[1])]),
          const SizedBox(height: 6),
          Row(children: [_cell(theme, _types[2]), _cell(theme, _types[3])]),
        ],
      ),
    );
  }

  Widget _cell(ThemeData theme, (RepeatType, IconData, String) entry) {
    final (type, icon, label) = entry;
    final selected = value == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary
                : insetSurface(theme),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? onBrandFill(theme.colorScheme.primary) : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected
                      ? onBrandFill(theme.colorScheme.primary)
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seven circles, Monday through Sunday, any number of them selectable.
class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onToggle});

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var weekday = 1; weekday <= 7; weekday++)
            _circle(theme, weekday, selected.contains(weekday)),
        ],
      ),
    );
  }

  Widget _circle(ThemeData theme, int weekday, bool isSelected) {
    // Weekends read a touch dimmer when off, matching the calendar elsewhere.
    final isWeekend = weekday >= 6;
    return GestureDetector(
      onTap: () => onToggle(weekday),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : insetSurface(theme),
          shape: BoxShape.circle,
        ),
        child: Text(
          _weekdayShortNames[weekday - 1],
          style: theme.textTheme.labelMedium?.copyWith(
            color: isSelected
                ? onBrandFill(theme.colorScheme.primary)
                : (isWeekend ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55) : theme.colorScheme.onSurfaceVariant),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Calendar-style grid of the days of a month, any number of them selectable.
/// Days 29–31 are kept in the grid even though short months lack them: the
/// schedule pulls them back to the last day of such a month.
class _MonthDayPicker extends StatelessWidget {
  const _MonthDayPicker({required this.selected, required this.onToggle});

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  static const _columns = 7;
  static const _lastDay = 31;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = (_lastDay / _columns).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          for (var row = 0; row < rows; row++) ...[
            if (row > 0) const SizedBox(height: 6),
            Row(
              children: [
                for (var col = 0; col < _columns; col++)
                  Expanded(child: _slot(theme, row * _columns + col + 1)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// A day cell, or empty space for the slots past the 31st in the last row.
  Widget _slot(ThemeData theme, int day) {
    if (day > _lastDay) return const SizedBox(height: 34);

    final isSelected = selected.contains(day);
    return GestureDetector(
      onTap: () => onToggle(day),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary
                : insetSurface(theme),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$day',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isSelected ? onBrandFill(theme.colorScheme.primary) : theme.colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled row with a [−] value [+] control, e.g.
/// "Повторять каждые  [−] 2 недели [+]". [valueText] always carries the unit, so
/// the number never has to be interpreted on its own. Passing null for [onMinus]
/// or [onPlus] greys out that button; [onValueTap] makes the number itself
/// tappable for entering a large amount directly.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.valueText,
    required this.onMinus,
    required this.onPlus,
    this.onValueTap,
  });

  final String label;
  final String valueText;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final VoidCallback? onValueTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: insetSurface(theme),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                IconButton(
                  onPressed: onMinus,
                  icon: const Icon(LucideIcons.minus, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                GestureDetector(
                  onTap: onValueTap,
                  behavior: HitTestBehavior.opaque,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 92),
                    child: Text(
                      valueText,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onPlus,
                  icon: const Icon(LucideIcons.plus, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RepeatSummary extends StatelessWidget {
  const _RepeatSummary({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            LucideIcons.calendar_sync,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtWheelTime(int minutes) {
  final normalized = minutes % (24 * 60);
  final h = (normalized ~/ 60).toString().padLeft(2, '0');
  final m = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

class _TimeWheel extends StatelessWidget {
  const _TimeWheel({
    required this.controller,
    required this.startMinutes,
    required this.durationMinutes,
    required this.step,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int startMinutes;
  final int? durationMinutes;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemCount = (24 * 60) ~/ step;

    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 46,
            perspective: 0.002,
            diameterRatio: 1.7,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (i) => onChanged(i * step),
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: itemCount,
              builder: (context, index) {
                final start = index * step;
                final selected = start == startMinutes;
                return _TimeWheelItem(
                  start: start,
                  selected: selected,
                  durationMinutes: durationMinutes,
                );
              },
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                height: 46,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeWheelItem extends StatelessWidget {
  const _TimeWheelItem({
    required this.start,
    required this.selected,
    required this.durationMinutes,
  });

  final int start;
  final bool selected;
  final int? durationMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!selected) {
      return Center(
        child: Text(
          _fmtWheelTime(start),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }

    final hasDuration = durationMinutes != null && durationMinutes! > 0;
    final end = hasDuration ? start + durationMinutes! : null;

    final spans = <InlineSpan>[TextSpan(text: _fmtWheelTime(start))];
    if (end != null) {
      spans.add(const TextSpan(text: ' – '));
      spans.add(TextSpan(text: _fmtWheelTime(end)));
      if (end >= 24 * 60) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Text(
                '+1',
                style: TextStyle(
                  color: onBrandFill(theme.colorScheme.primary),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      }
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text.rich(
          TextSpan(children: spans),
          style: theme.textTheme.titleMedium?.copyWith(
            color: onBrandFill(theme.colorScheme.primary),
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = DateFormat('d MMMM yyyy', 'ru_RU').format(date);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.calendar,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.selectedIconKey,
    required this.selectedColor,
    required this.onPickIcon,
    required this.onColorChanged,
    required this.titleField,
  });

  /// The task's title input, sat beside the icon square. The two belong on one
  /// line: the square is what the task looks like, the field is what it is.
  final Widget titleField;

  final String? selectedIconKey;
  final Color? selectedColor;
  final VoidCallback onPickIcon;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewColor = selectedColor ?? ColorPickerRow.colors.first;
    final previewIcon = taskIconFor(selectedIconKey) ?? LucideIcons.star;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: onPickIcon,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: previewColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: previewColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(previewIcon, size: 28, color: previewColor),
                ),
              ),
              const SizedBox(width: 16),
              // The square itself is the way into the icon picker now, so
              // there is no "choose an icon" line to make room for.
              Expanded(child: titleField),
            ],
          ),
          const SizedBox(height: 4),
          Divider(height: 1, thickness: 0.5, color: theme.colorScheme.outlineVariant),
          ColorPickerRow(selected: selectedColor, onChanged: onColorChanged),
        ],
      ),
    );
  }
}
