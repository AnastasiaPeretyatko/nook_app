import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/database/app_database.dart';
import 'package:todo_app/database/providers.dart';
import 'package:todo_app/utils/recurrence.dart';
import 'package:todo_app/utils/surfaces.dart';
import 'package:todo_app/utils/task_audience.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/widgets/app_dialogs.dart';
import 'package:todo_app/widgets/color_picker_row.dart';
import 'package:todo_app/utils/task_palette.dart';
import 'package:todo_app/widgets/icon_picker_sheet.dart';
import 'package:todo_app/widgets/time_picker_sheet.dart';
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
  const CreateTaskPage({
    super.key,
    this.mode = TaskFormMode.create,
    this.task,
    this.initialDate,
    this.initialGroupUid,
  }) : assert(
         mode == TaskFormMode.create || task != null,
         'edit/clone modes require a source task',
       );

  final TaskFormMode mode;

  /// Source task for [TaskFormMode.edit] and [TaskFormMode.clone].
  final Task? task;

  /// Day a new task starts on, for [TaskFormMode.create]: the day the screen the
  /// form was opened from is showing. Null means today.
  ///
  /// Only the start date is seeded from it — the time of day still comes from the
  /// clock. Ignored by the other two modes, which take the date from [task].
  final DateTime? initialDate;

  /// Group a new task is made in, for [TaskFormMode.create]: the group screen's
  /// "+" opens the form already pointed at it. The user can still switch it.
  final String? initialGroupUid;

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

  /// Target for the counter tracking mode, in the `targetValue` column. A counter
  /// always carries one; the other modes ignore it and save null.
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

  /// The group the task is shared in, null for a personal one — and with it,
  /// the member it is handed to, null for everyone. A group task is a one-off
  /// with no subtasks and no "Значение" mode: the form hides those controls
  /// and [_save] drops whatever they held.
  String? _groupUid;
  String? _assigneeUid;

  /// The groups to offer and their members — read once, like the subtasks:
  /// the form is seeded, not live.
  List<TaskGroup> _groups = const [];
  List<GroupMember> _allMembers = const [];

  static const _cardRadius = BorderRadius.all(Radius.circular(20));

  /// A new task's start time is the current time rounded to this many minutes.
  static const _timeStep = 15;
  static const _maxInterval = 99;

  /// Counters are whole repetitions: never below one.
  static const _minCounterTarget = 1.0;
  static const _maxTargetValue = 100000.0;

  /// Timer targets stop at a full day.
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
      _groupUid = source.groupUid;
      _assigneeUid = source.assigneeUid;
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
      if (_trackingMode == TrackingMode.value) _clampDateToToday();
    } else {
      _startMinutes = roundedNow;
      _selectedDate = widget.initialDate ?? DateTime.now();
      _groupUid = widget.initialGroupUid;
    }

    if (source != null) {
      _loadingSubtasks = true;
      unawaited(_loadSubtasks(source));
    }
    unawaited(_loadGroups());
  }

  Future<void> _loadGroups() async {
    final dao = ref.read(tasksDaoProvider);
    final groups = await dao.getGroups();
    final members = await dao.getGroupMembers();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _allMembers = members;
    });
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
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // A "Значение" task is nothing but a name and the day the watching began: no
    // time to be reminded at, no rule to repeat on, no target to reach. The form
    // hides those controls, but they keep their state when the user flips the
    // mode back and forth, so they are dropped here rather than trusted.
    final isValue = _trackingMode == TrackingMode.value;
    final isGroup = _groupUid != null;
    final timeEnabled = _timeEnabled && !isValue;

    final startMin = _startMinutes;
    final endMin =
        (timeEnabled && _durationMinutes != null && _durationMinutes! > 0)
        ? startMin + _durationMinutes!
        : null;

    final title = _titleController.text.trim();
    final description = _descController.text.trim();
    final repeatType = _repeatEnabled && !isValue && !isGroup
        ? _repeatType
        : null;
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
      TrackingMode.checkbox || TrackingMode.timer || TrackingMode.value => null,
    };
    // A "Значение" task always has its start date: it is the one thing it says
    // about when, and "days since" has nothing to count from without it.
    final startDate = _dateEnabled || isValue
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
          scheduledTimeMinutes: Value(timeEnabled ? startMin : null),
          endTimeMinutes: Value(endMin),
          startDate: Value(startDate),
          // The group itself is fixed at creation; who it is for is not.
          assigneeUid: Value(isGroup ? _assigneeUid : null),
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
        scheduledTimeMinutes: timeEnabled
            ? Value(startMin)
            : const Value.absent(),
        endTimeMinutes: endMin != null ? Value(endMin) : const Value.absent(),
        startDate: startDate != null ? Value(startDate) : const Value.absent(),
        groupUid: isGroup ? Value(_groupUid) : const Value.absent(),
        assigneeUid: isGroup ? Value(_assigneeUid) : const Value.absent(),
        authorUid: isGroup
            ? Value(ref.read(myUidProvider))
            : const Value.absent(),
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

    // The form hides subtasks for a "Значение" task, so nothing it holds is
    // saved: a task switched to that mode sheds the ones it had.
    final drafts = _trackingMode == TrackingMode.value || _groupUid != null
        ? const <_SubtaskDraft>[]
        : _subtasks;

    for (final draft in drafts) {
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
    final isValue = _trackingMode == TrackingMode.value;
    final isGroup = _groupUid != null;
    final groups = _groups;
    final members = [
      for (final m in _allMembers)
        if (m.groupUid == _groupUid) m,
    ];
    final me = ref.watch(myUidProvider);
    // Fixed once the task exists — the server keeps the group it was made in.
    final canPickGroup = widget.mode != TaskFormMode.edit;
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final sheet = raisedSurface(theme);
    final ink = _selectedColor ?? ColorPickerRow.colors.first;
    final fill = taskBadgeSurface(theme, ink, sheet);
    final strong = taskBadgeInk(theme, ink, fill);
    const gap = SizedBox(height: 10);

    return _Tones(
      ink: ink,
      fill: fill,
      strong: strong,
      child: Material(
        color: sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.9,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _RoundButton(
                            tooltip: 'Закрыть',
                            onTap: () => Navigator.of(context).pop(),
                            child: Icon(
                              LucideIcons.x,
                              size: 18,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        _screenTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.17,
                          color: palette.textPrimary,
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _isSaving || _loadingSubtasks
                              ? const SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                )
                              : _RoundButton(
                                  tooltip: 'Сохранить',
                                  fill: fill,
                                  borderColor: ink,
                                  borderWidth: 1.5,
                                  onTap: _save,
                                  child: Icon(
                                    LucideIcons.check,
                                    size: 18,
                                    color: strong,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        _TitleCard(
                          iconKey: _selectedIconKey,
                          onPickIcon: () async {
                            final key = await IconPickerSheet.show(
                              context,
                              selected: _selectedIconKey,
                            );
                            if (key != null) {
                              setState(() => _selectedIconKey = key);
                            }
                          },
                          titleField: _Field(
                            controller: _titleController,
                            hint: 'Название',
                            style: theme.textTheme.titleLarge!.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: strong,
                            ),
                            autofocus: true,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Обязательное поле'
                                : null,
                          ),
                          descField: _Field(
                            controller: _descController,
                            hint: 'Описание',
                            style: theme.textTheme.bodySmall!.copyWith(
                              fontSize: 13,
                              color: palette.textSecondary,
                            ),
                            minLines: 1,
                            maxLines: 3,
                          ),
                        ),
                        gap,
                        // Shown as soon as the user belongs to a group at all.
                        if (groups.isNotEmpty || isGroup) ...[
                          _Section(
                            icon: LucideIcons.users,
                            title: 'Кому',
                            trailing: _Pill(
                              label: isGroup
                                  ? groups
                                            .where((g) => g.uid == _groupUid)
                                            .firstOrNull
                                            ?.name ??
                                        'Группа'
                                  : 'Личная задача',
                              onTap: canPickGroup
                                  ? () => _pickGroup(groups)
                                  : null,
                            ),
                            children: [
                              if (isGroup)
                                _AssigneeTiles(
                                  members: members,
                                  me: me,
                                  selected: _assigneeUid,
                                  onPick: (uid) =>
                                      setState(() => _assigneeUid = uid),
                                ),
                            ],
                          ),
                          gap,
                        ],
                        if (isValue)
                          _Section(
                            icon: LucideIcons.calendar,
                            title: 'Отслеживать с',
                            trailing: _Pill(
                              label: DateFormat(
                                'd MMMM yyyy',
                                'ru_RU',
                              ).format(_selectedDate),
                              onTap: _pickDate,
                            ),
                          )
                        else
                          _Section(
                            icon: LucideIcons.clock,
                            title: 'Когда',
                            trailing: _dateEnabled
                                ? _Pill(
                                    label: _whenLabel(_selectedDate),
                                    onTap: _pickDate,
                                  )
                                : null,
                            children: [
                              Column(
                                children: [
                                  _SwitchRow(
                                    label: 'Указать дату',
                                    value: _dateEnabled,
                                    // No date, no time: a time is a time on
                                    // some day.
                                    onChanged: (v) => setState(() {
                                      _dateEnabled = v;
                                      if (!v) _timeEnabled = false;
                                    }),
                                  ),
                                  _SwitchRow(
                                    label: 'Указать время',
                                    value: _timeEnabled,
                                    // A task saved before this rule may carry a
                                    // time without a date — it can still be
                                    // switched off.
                                    onChanged: _dateEnabled || _timeEnabled
                                        ? (v) =>
                                              setState(() => _timeEnabled = v)
                                        : null,
                                  ),
                                ],
                              ),
                              if (_timeEnabled) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TimeBlock(
                                        label: 'С',
                                        value: _fmtClockTime(_startMinutes),
                                        onTap: _pickTime,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _TimeBlock(
                                        label:
                                            _durationMinutes != null &&
                                                _durationMinutes! > 0
                                            ? 'До · ${_formatDurationLabel(_durationMinutes!)}'
                                            : 'До',
                                        value:
                                            _durationMinutes != null &&
                                                _durationMinutes! > 0
                                            ? _endLabel
                                            : '—',
                                        onTap: _pickEnd,
                                      ),
                                    ),
                                  ],
                                ),
                                _DurationSelector(
                                  value: _durationMinutes,
                                  onChanged: (v) =>
                                      setState(() => _durationMinutes = v),
                                ),
                              ],
                            ],
                          ),
                        gap,
                        _Section(
                          icon: LucideIcons.chart_column,
                          title: 'Отслеживать',
                          trailing: switch (_trackingMode) {
                            TrackingMode.counter => _Pill(
                              label: 'Цель: $_targetValueLabel',
                              onTap: () => _enterTarget(allowDecimal: false),
                            ),
                            TrackingMode.timer => _Pill(
                              label: 'Цель: $_targetDurationLabel',
                              onTap: _enterTargetDuration,
                            ),
                            TrackingMode.checkbox || TrackingMode.value => null,
                          },
                          children: [
                            _ModeSelector(
                              value: _trackingMode,
                              onChanged: _changeTrackingMode,
                              allowValue: !isGroup,
                            ),
                          ],
                        ),
                        // A "Значение" task is not scheduled on any day, so there is
                        // nothing for a repeat rule to describe.
                        // A group task is one-off: groups hold no habits.
                        if (!isValue && !isGroup) ...[
                          gap,
                          _Section(
                            icon: LucideIcons.repeat,
                            title: 'Повторять',
                            trailing: _FormSwitch(
                              value: _repeatEnabled,
                              onChanged: (v) =>
                                  setState(() => _repeatEnabled = v),
                            ),
                            children: [
                              if (_repeatEnabled) ...[
                                _RepeatTypeSelector(
                                  value: _repeatType,
                                  onChanged: _onRepeatTypeChanged,
                                ),
                                if (_repeatType == RepeatType.weekly)
                                  _WeekdayPicker(
                                    selected: _repeatWeekdays,
                                    onToggle: (d) =>
                                        _toggleDay(_repeatWeekdays, d),
                                  ),
                                if (_repeatType == RepeatType.monthly)
                                  _MonthDayPicker(
                                    selected: _repeatMonthDays,
                                    onToggle: (d) =>
                                        _toggleDay(_repeatMonthDays, d),
                                  ),
                                if (_repeatType != RepeatType.daily)
                                  _StepperRow(
                                    label: 'Повторять каждые',
                                    valueText:
                                        '$_repeatInterval $_intervalUnitLabel',
                                    onMinus: _repeatInterval > 1
                                        ? () =>
                                              setState(() => _repeatInterval--)
                                        : null,
                                    onPlus: _repeatInterval < _maxInterval
                                        ? () =>
                                              setState(() => _repeatInterval++)
                                        : null,
                                  ),
                                _RepeatSummary(text: _repeatSummary),
                              ],
                            ],
                          ),
                          gap,
                          _Section(
                            icon: LucideIcons.list,
                            title: 'Подзадачи',
                            children: [
                              Column(
                                children: [
                                  for (var i = 0; i < _subtasks.length; i++)
                                    _SubtaskRow(
                                      key: ObjectKey(_subtasks[i]),
                                      draft: _subtasks[i],
                                      onToggle: () => setState(() {
                                        _subtasks[i].done = !_subtasks[i].done;
                                      }),
                                      onRemove: () => _removeSubtask(i),
                                      onSubmitted: _addSubtask,
                                    ),
                                  _AddSubtaskButton(onTap: _addSubtask),
                                ],
                              ),
                            ],
                          ),
                        ],
                        gap,
                        ColorPickerRow(
                          selected: _selectedColor,
                          onChanged: (c) => setState(() => _selectedColor = c),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The end time, marked "+1" when it falls on the next day.
  String get _endLabel {
    final end = _startMinutes + (_durationMinutes ?? 0);
    return '${_fmtClockTime(end)}${end >= 24 * 60 ? ' +1' : ''}';
  }

  Future<void> _pickGroup(List<TaskGroup> groups) async {
    final picked = await showOptionsSheet<String?>(
      context,
      title: 'Группа',
      options: [
        (null, 'Личная задача'),
        for (final g in groups) (g.uid, g.name),
      ],
      selected: _groupUid,
    );
    if (picked == null) return;
    setState(() {
      if (picked.$1 != _groupUid) _assigneeUid = null;
      _groupUid = picked.$1;
      if (_groupUid != null && _trackingMode == TrackingMode.value) {
        _trackingMode = TrackingMode.checkbox;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      // Watching cannot start tomorrow: "days since" would count backwards.
      lastDate: _trackingMode == TrackingMode.value
          ? _todayOnly()
          : DateTime(2030, 12, 31),
      locale: const Locale('ru', 'RU'),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  /// Opens the time sheet. The result is exact to the minute, so a time off the
  /// quarter-hour grid (15:31) is kept as typed.
  Future<void> _pickTime() async {
    final picked = await showTimePickerSheet(
      context,
      initialMinutes: _startMinutes,
    );
    if (picked != null) setState(() => _startMinutes = picked);
  }

  /// Opens the same sheet for the end time. The form stores a duration, not an
  /// end, so the pick is turned back into one — an end before the start is
  /// the next morning. The same minute as the start means "no duration".
  Future<void> _pickEnd() async {
    final hasDuration = _durationMinutes != null && _durationMinutes! > 0;
    final picked = await showTimePickerSheet(
      context,
      initialMinutes:
          (_startMinutes + (hasDuration ? _durationMinutes! : 30)) % (24 * 60),
    );
    if (picked == null) return;
    final diff = (picked - _startMinutes) % (24 * 60);
    setState(() => _durationMinutes = diff == 0 ? null : diff);
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

  /// Switching the mode carries the target over, so it has to be brought into
  /// the new mode's shape: a counter counts whole times and at least once. A
  /// "Значение" task takes no target and cannot start in the future.
  void _changeTrackingMode(TrackingMode mode) => setState(() {
    _trackingMode = mode;
    if (mode == TrackingMode.counter) {
      _targetValue = _counterTargetOf(_targetValue);
    }
    if (mode == TrackingMode.value) _clampDateToToday();
  });

  static DateTime _todayOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// A new task opened from a future day on the calendar carries that day; a
  /// "Значение" task cannot start in the future, so it is pulled back to today.
  void _clampDateToToday() {
    final today = _todayOnly();
    if (_selectedDate.isAfter(today)) _selectedDate = today;
  }

  /// [value] as a counter target: whole, and never below one.
  static double _counterTargetOf(double value) {
    final rounded = value.round().toDouble();
    return rounded < _minCounterTarget ? _minCounterTarget : rounded;
  }

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

  /// What the counter's stepper shows: "10 раз", or "без цели" at zero.
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
const _weekdayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// Selected weekdays as "пн, ср, пт", always in calendar order.
String _weekdayNames(Set<int> weekdays) {
  final sorted = weekdays.toList()..sort();
  return sorted.map((d) => _weekdayShortNames[d - 1]).join(', ');
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// The three tones of the task's colour the whole form is painted in
/// (DESIGN.md §2.4): [ink] for outlines, [fill] for large areas, [strong] for
/// glyphs and text written on [fill]. Picking another colour repaints the form.
class _Tones extends InheritedWidget {
  const _Tones({
    required this.ink,
    required this.fill,
    required this.strong,
    required super.child,
  });

  final Color ink;
  final Color fill;
  final Color strong;

  static _Tones of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Tones>()!;

  @override
  bool updateShouldNotify(_Tones old) =>
      ink != old.ink || fill != old.fill || strong != old.strong;
}

/// A white plate on the muted card: a time block, a mode tile, a pill. In the
/// dark theme the card is nearly the sheet's own tone, so the plate is a step
/// lighter instead.
Color _plate(ThemeData theme) => theme.brightness == Brightness.light
    ? AppPalette.of(theme).surface
    : AppPalette.of(theme).chip;

/// The grey of an off day disc and of the repeat switch's track. The palette's
/// own track is the dark card's colour, so there it would vanish.
Color _track(ThemeData theme) => theme.brightness == Brightness.light
    ? AppPalette.of(theme).segmentTrack
    : AppPalette.of(theme).chip;

/// Caption of a section and of the small labels on its plates.
TextStyle _captionStyle(ThemeData theme, {double size = 13}) =>
    theme.textTheme.labelMedium!.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: AppPalette.of(theme).textSecondary,
      letterSpacing: size * 0.08,
    );

/// A card of the sheet: a small icon and an upper-case caption, a control at the
/// right of the caption, then [children] 12px apart.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    this.trailing,
    this.children = const [],
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: _CreateTaskPageState._cardRadius,
        border: theme.brightness == Brightness.dark
            ? Border.all(color: palette.border)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: palette.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: _captionStyle(theme),
                    ),
                  ),
                  if (trailing != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: trailing,
                    ),
                ],
              ),
            ),
            for (final child in children) ...[
              const SizedBox(height: 12),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// The small rounded button at the right of a section's caption.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: _plate(theme),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          // `widthFactor` keeps the pill as wide as its text; `alignment` on the
          // container would stretch it to the card's limit.
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppPalette.of(theme).textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 44px round button of the sheet's header — close, save.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.fill,
    this.borderColor,
    this.borderWidth = 1,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final Color? fill;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    return Tooltip(
      message: tooltip,
      child: Material(
        color: fill ?? palette.surface,
        shape: CircleBorder(
          side: BorderSide(
            color: borderColor ?? palette.borderStrong,
            width: borderWidth,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// The task's title and description, on a box of the task's own colour.
class _TitleCard extends StatelessWidget {
  const _TitleCard({
    required this.iconKey,
    required this.onPickIcon,
    required this.titleField,
    required this.descField,
  });

  final String? iconKey;
  final VoidCallback onPickIcon;
  final Widget titleField;
  final Widget descField;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = _Tones.of(context);
    final previewIcon = taskIconFor(iconKey) ?? LucideIcons.star;
    final light = theme.brightness == Brightness.light;
    return DecoratedBox(
      key: const ValueKey('titleCard'),
      decoration: BoxDecoration(
        color: tones.fill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tones.ink, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Tooltip(
              message: 'Выбрать иконку',
              child: GestureDetector(
                onTap: onPickIcon,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: light ? 0.7 : 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(previewIcon, size: 22, color: tones.strong),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [titleField, const SizedBox(height: 2), descField],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.style,
    this.minLines,
    this.maxLines = 1,
    this.autofocus = false,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final TextStyle style;
  final int? minLines;
  final int maxLines;
  final bool autofocus;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      textCapitalization: TextCapitalization.sentences,
      style: style,
      decoration: InputDecoration(
        hintText: hint,
        border: InputBorder.none,
        isDense: true,
        hintStyle: style.copyWith(color: AppPalette.of(theme).textTertiary),
        contentPadding: const EdgeInsets.symmetric(vertical: 2),
      ),
    );
  }
}

/// "Who is it for": the group's members and "everyone", one tile each.
class _AssigneeTiles extends StatelessWidget {
  const _AssigneeTiles({
    required this.members,
    required this.me,
    required this.selected,
    required this.onPick,
  });

  final List<GroupMember> members;
  final String? me;

  /// The member the task is handed to; null is "for everyone".
  final String? selected;
  final ValueChanged<String?> onPick;

  static const _columns = 4;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final options = <(String?, String, String)>[
      // Me first, then the others, then everyone.
      if (me != null) (me, 'Мне', 'Я'),
      for (final m in members)
        if (m.userUid != me)
          (m.userUid, memberName(m), _initialOf(memberName(m))),
      (null, 'Всем', '${members.length}'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final (uid, label, initial) in options)
              SizedBox(
                width: width,
                child: _AssigneeTile(
                  label: label,
                  initial: initial,
                  selected: uid == selected,
                  onTap: () => onPick(uid),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _initialOf(String name) =>
    name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first);

class _AssigneeTile extends StatelessWidget {
  const _AssigneeTile({
    required this.label,
    required this.initial,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String initial;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final tones = _Tones.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: _plate(theme),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? tones.ink : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: neutralChip(theme),
                shape: BoxShape.circle,
              ),
              child: Text(
                initial.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A switch painted in the task's colour.
class _FormSwitch extends StatelessWidget {
  const _FormSwitch({required this.value, required this.onChanged});

  final bool value;

  /// Null greys the switch out.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    final strong = _Tones.of(context).strong;
    return Opacity(
      opacity: onChanged == null ? 0.4 : 1,
      child: Switch(
        value: value,
        onChanged: onChanged,
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onBrandFill(strong)
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? strong
              : palette.switchOff,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}

/// A label with a [_FormSwitch] at its end.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                color: AppPalette.of(theme).textPrimary,
              ),
            ),
          ),
          _FormSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// "С 22:00" / "До · 30 мин 22:30": a caption over a big time, tap to change.
class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: _plate(theme),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _captionStyle(theme, size: 11),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.of(theme).textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Today, 16 Oct" / "Tue, 20 Oct" — the year only when it is not this one.
String _whenLabel(DateTime date) {
  final now = DateTime.now();
  final isToday =
      date.year == now.year && date.month == now.month && date.day == now.day;
  final day = DateFormat(
    date.year == now.year ? 'd MMM' : 'd MMM yyyy',
    'ru_RU',
  ).format(date);
  if (isToday) return 'Сегодня, $day';
  final weekday = DateFormat('E', 'ru_RU').format(date);
  return '${weekday[0].toUpperCase()}${weekday.substring(1)}, $day';
}

/// The "add a subtask" link that closes the subtasks card.
class _AddSubtaskButton extends StatelessWidget {
  const _AddSubtaskButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strong = _Tones.of(context).strong;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 44,
        width: double.infinity,
        child: Row(
          children: [
            Icon(LucideIcons.plus, size: 18, color: strong),
            const SizedBox(width: 12),
            Text(
              'Добавить подзадачу',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: strong,
              ),
            ),
          ],
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
    required this.onSubmitted,
  });

  final _SubtaskDraft draft;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  /// Enter on this row's keyboard — adds the next subtask below it.
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final strong = _Tones.of(context).strong;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: draft.done ? strong : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: draft.done ? strong : palette.iconMuted,
                    width: 1.5,
                  ),
                ),
                child: draft.done
                    ? Icon(
                        LucideIcons.check,
                        size: 13,
                        color: onBrandFill(strong),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: draft.controller,
              autofocus: draft.isNew,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmitted(),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                color: draft.done ? palette.textTertiary : palette.textPrimary,
                decoration: draft.done ? TextDecoration.lineThrough : null,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Подзадача',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  color: palette.textTertiary,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(LucideIcons.x, size: 16),
            color: palette.textTertiary,
            visualDensity: VisualDensity.compact,
            tooltip: 'Убрать подзадачу',
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
    final presets = [..._presets];
    // Show a custom value as its own selected chip if not among presets.
    if (value != null && value! > 0 && !presets.contains(value)) {
      presets.add(value!);
      presets.sort();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(context, null, 'Без длительности'),
          for (final m in presets) ...[
            const SizedBox(width: 8),
            _chip(context, m, _formatDurationLabel(m)),
          ],
        ],
      ),
    );
  }

  /// A 36px chip: dark when selected, a plate with an outline otherwise.
  Widget _chip(BuildContext context, int? minutes, String label) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final selected = value == minutes;
    return Material(
      color: selected ? palette.textPrimary : _plate(theme),
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? palette.textPrimary : palette.borderStrong,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => onChanged(minutes),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? palette.background : palette.textPrimary,
            ),
          ),
        ),
      ),
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
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
  const _ModeSelector({
    required this.value,
    required this.onChanged,
    this.allowValue = true,
  });
  final TrackingMode value;
  final ValueChanged<TrackingMode> onChanged;

  /// False for a group task: "Значение" is on no day, and a group holds only
  /// one-off tasks.
  final bool allowValue;

  static const _modes = [
    (TrackingMode.checkbox, LucideIcons.circle_check, 'Чекбокс'),
    (TrackingMode.counter, LucideIcons.circle_plus, 'Счётчик'),
    (TrackingMode.timer, LucideIcons.timer, 'Таймер'),
    (TrackingMode.value, LucideIcons.sliders_horizontal, 'Значение'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final tones = _Tones.of(context);
    final shown = _modes.where(
      (entry) => allowValue || entry.$1 != TrackingMode.value,
    );
    return Row(
      children: [
        for (final (index, (mode, icon, label)) in shown.indexed) ...[
          if (index > 0) const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 68,
                decoration: BoxDecoration(
                  // The selected tile takes the task's colour — light tone,
                  // outline and ink — and the others stay plain plates.
                  color: value == mode ? tones.fill : _plate(theme),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: value == mode ? tones.ink : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: value == mode
                          ? tones.strong
                          : palette.textSecondary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: value == mode
                            ? tones.strong
                            : palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The four repeat types as a grey segmented switch. There is no "no repeat"
/// segment — repetition is switched off by the switch in the card's caption.
class _RepeatTypeSelector extends StatelessWidget {
  const _RepeatTypeSelector({required this.value, required this.onChanged});
  final RepeatType value;
  final ValueChanged<RepeatType> onChanged;

  static const _types = [
    (RepeatType.daily, 'День'),
    (RepeatType.weekly, 'Неделя'),
    (RepeatType.monthly, 'Месяц'),
    (RepeatType.custom, 'N дней'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _track(theme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (type, label) in _types)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(type),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == type
                        ? (theme.brightness == Brightness.light
                              ? palette.surface
                              : palette.segmentSelected)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: value == type
                        ? [
                            BoxShadow(
                              color: surfaceShadow(theme, light: 0.1),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: value == type
                          ? palette.textPrimary
                          : palette.textSecondary,
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

/// A round day button of the weekday and month pickers: the task's strong tone
/// when on, a grey disc when off.
class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final strong = _Tones.of(context).strong;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? strong : _track(theme),
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? onBrandFill(strong) : palette.textPrimary,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var weekday = 1; weekday <= 7; weekday++)
          _DayDot(
            label: _weekdayLabels[weekday - 1],
            size: 40,
            selected: selected.contains(weekday),
            onTap: () => onToggle(weekday),
          ),
      ],
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
    final rows = (_lastDay / _columns).ceil();

    return Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (var col = 0; col < _columns; col++)
                Expanded(child: _slot(row * _columns + col + 1)),
            ],
          ),
        ],
      ],
    );
  }

  /// A day cell, or empty space for the slots past the 31st in the last row.
  Widget _slot(int day) {
    if (day > _lastDay) return const SizedBox(height: 36);
    return Center(
      child: _DayDot(
        label: '$day',
        size: 36,
        selected: selected.contains(day),
        onTap: () => onToggle(day),
      ),
    );
  }
}

/// A labelled row with a [−] value [+] control, e.g.
/// "Повторять каждые  [−] 2 недели [+]". [valueText] always carries the unit, so
/// the number never has to be interpreted on its own. Passing null for [onMinus]
/// or [onPlus] greys out that button.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.valueText,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String valueText;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final button = IconButton.styleFrom(
      fixedSize: const Size(40, 40),
      backgroundColor: _plate(theme),
      disabledBackgroundColor: _plate(theme),
      foregroundColor: palette.textPrimary,
      disabledForegroundColor: palette.iconMuted,
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 15,
              color: palette.textPrimary,
            ),
          ),
        ),
        IconButton(
          onPressed: onMinus,
          style: button,
          icon: const Icon(LucideIcons.minus, size: 18),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 76),
          child: Text(
            valueText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          onPressed: onPlus,
          style: button,
          icon: const Icon(LucideIcons.plus, size: 18),
        ),
      ],
    );
  }
}

class _RepeatSummary extends StatelessWidget {
  const _RepeatSummary({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          LucideIcons.calendar_sync,
          size: 16,
          color: _Tones.of(context).strong,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppPalette.of(theme).textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

String _fmtClockTime(int minutes) {
  final normalized = minutes % (24 * 60);
  final h = (normalized ~/ 60).toString().padLeft(2, '0');
  final m = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Opens [CreateTaskPage] as a bottom sheet.
Future<void> showCreateTaskSheet(
  BuildContext context, {
  TaskFormMode mode = TaskFormMode.create,
  Task? task,
  DateTime? initialDate,
  String? initialGroupUid,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => CreateTaskPage(
    mode: mode,
    task: task,
    initialDate: initialDate,
    initialGroupUid: initialGroupUid,
  ),
);
