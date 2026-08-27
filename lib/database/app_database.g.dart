// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
    'uid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<int> parentId = GeneratedColumn<int>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TaskStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('active'),
      ).withConverter<TaskStatus>($TasksTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<RepeatType?, String> repeatType =
      GeneratedColumn<String>(
        'repeat_type',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<RepeatType?>($TasksTable.$converterrepeatTypen);
  static const VerificationMeta _repeatIntervalMeta = const VerificationMeta(
    'repeatInterval',
  );
  @override
  late final GeneratedColumn<int> repeatInterval = GeneratedColumn<int>(
    'repeat_interval',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repeatDaysMaskMeta = const VerificationMeta(
    'repeatDaysMask',
  );
  @override
  late final GeneratedColumn<int> repeatDaysMask = GeneratedColumn<int>(
    'repeat_days_mask',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TrackingMode, String>
  trackingMode = GeneratedColumn<String>(
    'tracking_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('checkbox'),
  ).withConverter<TrackingMode>($TasksTable.$convertertrackingMode);
  static const VerificationMeta _targetDurationMinutesMeta =
      const VerificationMeta('targetDurationMinutes');
  @override
  late final GeneratedColumn<int> targetDurationMinutes = GeneratedColumn<int>(
    'target_duration_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetValueMeta = const VerificationMeta(
    'targetValue',
  );
  @override
  late final GeneratedColumn<double> targetValue = GeneratedColumn<double>(
    'target_value',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _iconKeyMeta = const VerificationMeta(
    'iconKey',
  );
  @override
  late final GeneratedColumn<String> iconKey = GeneratedColumn<String>(
    'icon_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _iconCodePointMeta = const VerificationMeta(
    'iconCodePoint',
  );
  @override
  late final GeneratedColumn<int> iconCodePoint = GeneratedColumn<int>(
    'icon_code_point',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scheduledTimeMinutesMeta =
      const VerificationMeta('scheduledTimeMinutes');
  @override
  late final GeneratedColumn<int> scheduledTimeMinutes = GeneratedColumn<int>(
    'scheduled_time_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endTimeMinutesMeta = const VerificationMeta(
    'endTimeMinutes',
  );
  @override
  late final GeneratedColumn<int> endTimeMinutes = GeneratedColumn<int>(
    'end_time_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uid,
    dirty,
    parentId,
    title,
    description,
    status,
    repeatType,
    repeatInterval,
    repeatDaysMask,
    trackingMode,
    targetDurationMinutes,
    targetValue,
    iconKey,
    iconCodePoint,
    colorValue,
    scheduledTimeMinutes,
    endTimeMinutes,
    startDate,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Task> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uid')) {
      context.handle(
        _uidMeta,
        uid.isAcceptableOrUnknown(data['uid']!, _uidMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('repeat_interval')) {
      context.handle(
        _repeatIntervalMeta,
        repeatInterval.isAcceptableOrUnknown(
          data['repeat_interval']!,
          _repeatIntervalMeta,
        ),
      );
    }
    if (data.containsKey('repeat_days_mask')) {
      context.handle(
        _repeatDaysMaskMeta,
        repeatDaysMask.isAcceptableOrUnknown(
          data['repeat_days_mask']!,
          _repeatDaysMaskMeta,
        ),
      );
    }
    if (data.containsKey('target_duration_minutes')) {
      context.handle(
        _targetDurationMinutesMeta,
        targetDurationMinutes.isAcceptableOrUnknown(
          data['target_duration_minutes']!,
          _targetDurationMinutesMeta,
        ),
      );
    }
    if (data.containsKey('target_value')) {
      context.handle(
        _targetValueMeta,
        targetValue.isAcceptableOrUnknown(
          data['target_value']!,
          _targetValueMeta,
        ),
      );
    }
    if (data.containsKey('icon_key')) {
      context.handle(
        _iconKeyMeta,
        iconKey.isAcceptableOrUnknown(data['icon_key']!, _iconKeyMeta),
      );
    }
    if (data.containsKey('icon_code_point')) {
      context.handle(
        _iconCodePointMeta,
        iconCodePoint.isAcceptableOrUnknown(
          data['icon_code_point']!,
          _iconCodePointMeta,
        ),
      );
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    }
    if (data.containsKey('scheduled_time_minutes')) {
      context.handle(
        _scheduledTimeMinutesMeta,
        scheduledTimeMinutes.isAcceptableOrUnknown(
          data['scheduled_time_minutes']!,
          _scheduledTimeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('end_time_minutes')) {
      context.handle(
        _endTimeMinutesMeta,
        endTimeMinutes.isAcceptableOrUnknown(
          data['end_time_minutes']!,
          _endTimeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      status: $TasksTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      repeatType: $TasksTable.$converterrepeatTypen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}repeat_type'],
        ),
      ),
      repeatInterval: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repeat_interval'],
      ),
      repeatDaysMask: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repeat_days_mask'],
      ),
      trackingMode: $TasksTable.$convertertrackingMode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}tracking_mode'],
        )!,
      ),
      targetDurationMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_duration_minutes'],
      ),
      targetValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}target_value'],
      ),
      iconKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon_key'],
      ),
      iconCodePoint: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}icon_code_point'],
      ),
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      ),
      scheduledTimeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_time_minutes'],
      ),
      endTimeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_time_minutes'],
      ),
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TaskStatus, String, String> $converterstatus =
      const EnumNameConverter<TaskStatus>(TaskStatus.values);
  static JsonTypeConverter2<RepeatType, String, String> $converterrepeatType =
      const EnumNameConverter<RepeatType>(RepeatType.values);
  static JsonTypeConverter2<RepeatType?, String?, String?>
  $converterrepeatTypen = JsonTypeConverter2.asNullable($converterrepeatType);
  static JsonTypeConverter2<TrackingMode, String, String>
  $convertertrackingMode = const EnumNameConverter<TrackingMode>(
    TrackingMode.values,
  );
}

class Task extends DataClass implements Insertable<Task> {
  final int id;

  /// The task's identity across devices — see [SyncTombstones] for why the
  /// local [id] cannot be it.
  final String? uid;

  /// Changed here and not yet sent. See [SyncTombstones].
  final bool dirty;
  final int? parentId;
  final String title;
  final String? description;
  final TaskStatus status;
  final RepeatType? repeatType;
  final int? repeatInterval;

  /// Bitmask of the days a repeating task lands on, where day `d` sets bit
  /// `d - 1`. What a day means depends on [repeatType]: for
  /// [RepeatType.weekly] it is [DateTime.weekday] (Monday = bit 0 … Sunday =
  /// bit 6), for [RepeatType.monthly] it is the day of the month (1 … 31).
  /// Null means "not specified" — such tasks fall back to the weekday or day of
  /// month of their anchor date, as they did before this column existed.
  /// [RepeatType.daily] and [RepeatType.custom] ignore it.
  final int? repeatDaysMask;
  final TrackingMode trackingMode;
  final int? targetDurationMinutes;
  final double? targetValue;

  /// Key into `taskIcons` — see [lib/utils/task_icons.dart]. What the app
  /// reads and writes.
  final String? iconKey;

  /// Legacy: the Material Icons code point tasks carried before [iconKey].
  /// Kept only so the schema v10 migration can translate old rows; nothing in
  /// the app reads it.
  final int? iconCodePoint;
  final int? colorValue;
  final int? scheduledTimeMinutes;
  final int? endTimeMinutes;
  final DateTime? startDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Task({
    required this.id,
    this.uid,
    required this.dirty,
    this.parentId,
    required this.title,
    this.description,
    required this.status,
    this.repeatType,
    this.repeatInterval,
    this.repeatDaysMask,
    required this.trackingMode,
    this.targetDurationMinutes,
    this.targetValue,
    this.iconKey,
    this.iconCodePoint,
    this.colorValue,
    this.scheduledTimeMinutes,
    this.endTimeMinutes,
    this.startDate,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || uid != null) {
      map['uid'] = Variable<String>(uid);
    }
    map['dirty'] = Variable<bool>(dirty);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<int>(parentId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    {
      map['status'] = Variable<String>(
        $TasksTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || repeatType != null) {
      map['repeat_type'] = Variable<String>(
        $TasksTable.$converterrepeatTypen.toSql(repeatType),
      );
    }
    if (!nullToAbsent || repeatInterval != null) {
      map['repeat_interval'] = Variable<int>(repeatInterval);
    }
    if (!nullToAbsent || repeatDaysMask != null) {
      map['repeat_days_mask'] = Variable<int>(repeatDaysMask);
    }
    {
      map['tracking_mode'] = Variable<String>(
        $TasksTable.$convertertrackingMode.toSql(trackingMode),
      );
    }
    if (!nullToAbsent || targetDurationMinutes != null) {
      map['target_duration_minutes'] = Variable<int>(targetDurationMinutes);
    }
    if (!nullToAbsent || targetValue != null) {
      map['target_value'] = Variable<double>(targetValue);
    }
    if (!nullToAbsent || iconKey != null) {
      map['icon_key'] = Variable<String>(iconKey);
    }
    if (!nullToAbsent || iconCodePoint != null) {
      map['icon_code_point'] = Variable<int>(iconCodePoint);
    }
    if (!nullToAbsent || colorValue != null) {
      map['color_value'] = Variable<int>(colorValue);
    }
    if (!nullToAbsent || scheduledTimeMinutes != null) {
      map['scheduled_time_minutes'] = Variable<int>(scheduledTimeMinutes);
    }
    if (!nullToAbsent || endTimeMinutes != null) {
      map['end_time_minutes'] = Variable<int>(endTimeMinutes);
    }
    if (!nullToAbsent || startDate != null) {
      map['start_date'] = Variable<DateTime>(startDate);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      uid: uid == null && nullToAbsent ? const Value.absent() : Value(uid),
      dirty: Value(dirty),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      status: Value(status),
      repeatType: repeatType == null && nullToAbsent
          ? const Value.absent()
          : Value(repeatType),
      repeatInterval: repeatInterval == null && nullToAbsent
          ? const Value.absent()
          : Value(repeatInterval),
      repeatDaysMask: repeatDaysMask == null && nullToAbsent
          ? const Value.absent()
          : Value(repeatDaysMask),
      trackingMode: Value(trackingMode),
      targetDurationMinutes: targetDurationMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDurationMinutes),
      targetValue: targetValue == null && nullToAbsent
          ? const Value.absent()
          : Value(targetValue),
      iconKey: iconKey == null && nullToAbsent
          ? const Value.absent()
          : Value(iconKey),
      iconCodePoint: iconCodePoint == null && nullToAbsent
          ? const Value.absent()
          : Value(iconCodePoint),
      colorValue: colorValue == null && nullToAbsent
          ? const Value.absent()
          : Value(colorValue),
      scheduledTimeMinutes: scheduledTimeMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledTimeMinutes),
      endTimeMinutes: endTimeMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(endTimeMinutes),
      startDate: startDate == null && nullToAbsent
          ? const Value.absent()
          : Value(startDate),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Task.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<int>(json['id']),
      uid: serializer.fromJson<String?>(json['uid']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      parentId: serializer.fromJson<int?>(json['parentId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      status: $TasksTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      repeatType: $TasksTable.$converterrepeatTypen.fromJson(
        serializer.fromJson<String?>(json['repeatType']),
      ),
      repeatInterval: serializer.fromJson<int?>(json['repeatInterval']),
      repeatDaysMask: serializer.fromJson<int?>(json['repeatDaysMask']),
      trackingMode: $TasksTable.$convertertrackingMode.fromJson(
        serializer.fromJson<String>(json['trackingMode']),
      ),
      targetDurationMinutes: serializer.fromJson<int?>(
        json['targetDurationMinutes'],
      ),
      targetValue: serializer.fromJson<double?>(json['targetValue']),
      iconKey: serializer.fromJson<String?>(json['iconKey']),
      iconCodePoint: serializer.fromJson<int?>(json['iconCodePoint']),
      colorValue: serializer.fromJson<int?>(json['colorValue']),
      scheduledTimeMinutes: serializer.fromJson<int?>(
        json['scheduledTimeMinutes'],
      ),
      endTimeMinutes: serializer.fromJson<int?>(json['endTimeMinutes']),
      startDate: serializer.fromJson<DateTime?>(json['startDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uid': serializer.toJson<String?>(uid),
      'dirty': serializer.toJson<bool>(dirty),
      'parentId': serializer.toJson<int?>(parentId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'status': serializer.toJson<String>(
        $TasksTable.$converterstatus.toJson(status),
      ),
      'repeatType': serializer.toJson<String?>(
        $TasksTable.$converterrepeatTypen.toJson(repeatType),
      ),
      'repeatInterval': serializer.toJson<int?>(repeatInterval),
      'repeatDaysMask': serializer.toJson<int?>(repeatDaysMask),
      'trackingMode': serializer.toJson<String>(
        $TasksTable.$convertertrackingMode.toJson(trackingMode),
      ),
      'targetDurationMinutes': serializer.toJson<int?>(targetDurationMinutes),
      'targetValue': serializer.toJson<double?>(targetValue),
      'iconKey': serializer.toJson<String?>(iconKey),
      'iconCodePoint': serializer.toJson<int?>(iconCodePoint),
      'colorValue': serializer.toJson<int?>(colorValue),
      'scheduledTimeMinutes': serializer.toJson<int?>(scheduledTimeMinutes),
      'endTimeMinutes': serializer.toJson<int?>(endTimeMinutes),
      'startDate': serializer.toJson<DateTime?>(startDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Task copyWith({
    int? id,
    Value<String?> uid = const Value.absent(),
    bool? dirty,
    Value<int?> parentId = const Value.absent(),
    String? title,
    Value<String?> description = const Value.absent(),
    TaskStatus? status,
    Value<RepeatType?> repeatType = const Value.absent(),
    Value<int?> repeatInterval = const Value.absent(),
    Value<int?> repeatDaysMask = const Value.absent(),
    TrackingMode? trackingMode,
    Value<int?> targetDurationMinutes = const Value.absent(),
    Value<double?> targetValue = const Value.absent(),
    Value<String?> iconKey = const Value.absent(),
    Value<int?> iconCodePoint = const Value.absent(),
    Value<int?> colorValue = const Value.absent(),
    Value<int?> scheduledTimeMinutes = const Value.absent(),
    Value<int?> endTimeMinutes = const Value.absent(),
    Value<DateTime?> startDate = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Task(
    id: id ?? this.id,
    uid: uid.present ? uid.value : this.uid,
    dirty: dirty ?? this.dirty,
    parentId: parentId.present ? parentId.value : this.parentId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    status: status ?? this.status,
    repeatType: repeatType.present ? repeatType.value : this.repeatType,
    repeatInterval: repeatInterval.present
        ? repeatInterval.value
        : this.repeatInterval,
    repeatDaysMask: repeatDaysMask.present
        ? repeatDaysMask.value
        : this.repeatDaysMask,
    trackingMode: trackingMode ?? this.trackingMode,
    targetDurationMinutes: targetDurationMinutes.present
        ? targetDurationMinutes.value
        : this.targetDurationMinutes,
    targetValue: targetValue.present ? targetValue.value : this.targetValue,
    iconKey: iconKey.present ? iconKey.value : this.iconKey,
    iconCodePoint: iconCodePoint.present
        ? iconCodePoint.value
        : this.iconCodePoint,
    colorValue: colorValue.present ? colorValue.value : this.colorValue,
    scheduledTimeMinutes: scheduledTimeMinutes.present
        ? scheduledTimeMinutes.value
        : this.scheduledTimeMinutes,
    endTimeMinutes: endTimeMinutes.present
        ? endTimeMinutes.value
        : this.endTimeMinutes,
    startDate: startDate.present ? startDate.value : this.startDate,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      uid: data.uid.present ? data.uid.value : this.uid,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      status: data.status.present ? data.status.value : this.status,
      repeatType: data.repeatType.present
          ? data.repeatType.value
          : this.repeatType,
      repeatInterval: data.repeatInterval.present
          ? data.repeatInterval.value
          : this.repeatInterval,
      repeatDaysMask: data.repeatDaysMask.present
          ? data.repeatDaysMask.value
          : this.repeatDaysMask,
      trackingMode: data.trackingMode.present
          ? data.trackingMode.value
          : this.trackingMode,
      targetDurationMinutes: data.targetDurationMinutes.present
          ? data.targetDurationMinutes.value
          : this.targetDurationMinutes,
      targetValue: data.targetValue.present
          ? data.targetValue.value
          : this.targetValue,
      iconKey: data.iconKey.present ? data.iconKey.value : this.iconKey,
      iconCodePoint: data.iconCodePoint.present
          ? data.iconCodePoint.value
          : this.iconCodePoint,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      scheduledTimeMinutes: data.scheduledTimeMinutes.present
          ? data.scheduledTimeMinutes.value
          : this.scheduledTimeMinutes,
      endTimeMinutes: data.endTimeMinutes.present
          ? data.endTimeMinutes.value
          : this.endTimeMinutes,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dirty: $dirty, ')
          ..write('parentId: $parentId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('repeatType: $repeatType, ')
          ..write('repeatInterval: $repeatInterval, ')
          ..write('repeatDaysMask: $repeatDaysMask, ')
          ..write('trackingMode: $trackingMode, ')
          ..write('targetDurationMinutes: $targetDurationMinutes, ')
          ..write('targetValue: $targetValue, ')
          ..write('iconKey: $iconKey, ')
          ..write('iconCodePoint: $iconCodePoint, ')
          ..write('colorValue: $colorValue, ')
          ..write('scheduledTimeMinutes: $scheduledTimeMinutes, ')
          ..write('endTimeMinutes: $endTimeMinutes, ')
          ..write('startDate: $startDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    uid,
    dirty,
    parentId,
    title,
    description,
    status,
    repeatType,
    repeatInterval,
    repeatDaysMask,
    trackingMode,
    targetDurationMinutes,
    targetValue,
    iconKey,
    iconCodePoint,
    colorValue,
    scheduledTimeMinutes,
    endTimeMinutes,
    startDate,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.uid == this.uid &&
          other.dirty == this.dirty &&
          other.parentId == this.parentId &&
          other.title == this.title &&
          other.description == this.description &&
          other.status == this.status &&
          other.repeatType == this.repeatType &&
          other.repeatInterval == this.repeatInterval &&
          other.repeatDaysMask == this.repeatDaysMask &&
          other.trackingMode == this.trackingMode &&
          other.targetDurationMinutes == this.targetDurationMinutes &&
          other.targetValue == this.targetValue &&
          other.iconKey == this.iconKey &&
          other.iconCodePoint == this.iconCodePoint &&
          other.colorValue == this.colorValue &&
          other.scheduledTimeMinutes == this.scheduledTimeMinutes &&
          other.endTimeMinutes == this.endTimeMinutes &&
          other.startDate == this.startDate &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<int> id;
  final Value<String?> uid;
  final Value<bool> dirty;
  final Value<int?> parentId;
  final Value<String> title;
  final Value<String?> description;
  final Value<TaskStatus> status;
  final Value<RepeatType?> repeatType;
  final Value<int?> repeatInterval;
  final Value<int?> repeatDaysMask;
  final Value<TrackingMode> trackingMode;
  final Value<int?> targetDurationMinutes;
  final Value<double?> targetValue;
  final Value<String?> iconKey;
  final Value<int?> iconCodePoint;
  final Value<int?> colorValue;
  final Value<int?> scheduledTimeMinutes;
  final Value<int?> endTimeMinutes;
  final Value<DateTime?> startDate;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.dirty = const Value.absent(),
    this.parentId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.repeatType = const Value.absent(),
    this.repeatInterval = const Value.absent(),
    this.repeatDaysMask = const Value.absent(),
    this.trackingMode = const Value.absent(),
    this.targetDurationMinutes = const Value.absent(),
    this.targetValue = const Value.absent(),
    this.iconKey = const Value.absent(),
    this.iconCodePoint = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.scheduledTimeMinutes = const Value.absent(),
    this.endTimeMinutes = const Value.absent(),
    this.startDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  TasksCompanion.insert({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.dirty = const Value.absent(),
    this.parentId = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.repeatType = const Value.absent(),
    this.repeatInterval = const Value.absent(),
    this.repeatDaysMask = const Value.absent(),
    this.trackingMode = const Value.absent(),
    this.targetDurationMinutes = const Value.absent(),
    this.targetValue = const Value.absent(),
    this.iconKey = const Value.absent(),
    this.iconCodePoint = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.scheduledTimeMinutes = const Value.absent(),
    this.endTimeMinutes = const Value.absent(),
    this.startDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : title = Value(title);
  static Insertable<Task> custom({
    Expression<int>? id,
    Expression<String>? uid,
    Expression<bool>? dirty,
    Expression<int>? parentId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? status,
    Expression<String>? repeatType,
    Expression<int>? repeatInterval,
    Expression<int>? repeatDaysMask,
    Expression<String>? trackingMode,
    Expression<int>? targetDurationMinutes,
    Expression<double>? targetValue,
    Expression<String>? iconKey,
    Expression<int>? iconCodePoint,
    Expression<int>? colorValue,
    Expression<int>? scheduledTimeMinutes,
    Expression<int>? endTimeMinutes,
    Expression<DateTime>? startDate,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uid != null) 'uid': uid,
      if (dirty != null) 'dirty': dirty,
      if (parentId != null) 'parent_id': parentId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (repeatType != null) 'repeat_type': repeatType,
      if (repeatInterval != null) 'repeat_interval': repeatInterval,
      if (repeatDaysMask != null) 'repeat_days_mask': repeatDaysMask,
      if (trackingMode != null) 'tracking_mode': trackingMode,
      if (targetDurationMinutes != null)
        'target_duration_minutes': targetDurationMinutes,
      if (targetValue != null) 'target_value': targetValue,
      if (iconKey != null) 'icon_key': iconKey,
      if (iconCodePoint != null) 'icon_code_point': iconCodePoint,
      if (colorValue != null) 'color_value': colorValue,
      if (scheduledTimeMinutes != null)
        'scheduled_time_minutes': scheduledTimeMinutes,
      if (endTimeMinutes != null) 'end_time_minutes': endTimeMinutes,
      if (startDate != null) 'start_date': startDate,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  TasksCompanion copyWith({
    Value<int>? id,
    Value<String?>? uid,
    Value<bool>? dirty,
    Value<int?>? parentId,
    Value<String>? title,
    Value<String?>? description,
    Value<TaskStatus>? status,
    Value<RepeatType?>? repeatType,
    Value<int?>? repeatInterval,
    Value<int?>? repeatDaysMask,
    Value<TrackingMode>? trackingMode,
    Value<int?>? targetDurationMinutes,
    Value<double?>? targetValue,
    Value<String?>? iconKey,
    Value<int?>? iconCodePoint,
    Value<int?>? colorValue,
    Value<int?>? scheduledTimeMinutes,
    Value<int?>? endTimeMinutes,
    Value<DateTime?>? startDate,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      dirty: dirty ?? this.dirty,
      parentId: parentId ?? this.parentId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      repeatType: repeatType ?? this.repeatType,
      repeatInterval: repeatInterval ?? this.repeatInterval,
      repeatDaysMask: repeatDaysMask ?? this.repeatDaysMask,
      trackingMode: trackingMode ?? this.trackingMode,
      targetDurationMinutes:
          targetDurationMinutes ?? this.targetDurationMinutes,
      targetValue: targetValue ?? this.targetValue,
      iconKey: iconKey ?? this.iconKey,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      colorValue: colorValue ?? this.colorValue,
      scheduledTimeMinutes: scheduledTimeMinutes ?? this.scheduledTimeMinutes,
      endTimeMinutes: endTimeMinutes ?? this.endTimeMinutes,
      startDate: startDate ?? this.startDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<int>(parentId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $TasksTable.$converterstatus.toSql(status.value),
      );
    }
    if (repeatType.present) {
      map['repeat_type'] = Variable<String>(
        $TasksTable.$converterrepeatTypen.toSql(repeatType.value),
      );
    }
    if (repeatInterval.present) {
      map['repeat_interval'] = Variable<int>(repeatInterval.value);
    }
    if (repeatDaysMask.present) {
      map['repeat_days_mask'] = Variable<int>(repeatDaysMask.value);
    }
    if (trackingMode.present) {
      map['tracking_mode'] = Variable<String>(
        $TasksTable.$convertertrackingMode.toSql(trackingMode.value),
      );
    }
    if (targetDurationMinutes.present) {
      map['target_duration_minutes'] = Variable<int>(
        targetDurationMinutes.value,
      );
    }
    if (targetValue.present) {
      map['target_value'] = Variable<double>(targetValue.value);
    }
    if (iconKey.present) {
      map['icon_key'] = Variable<String>(iconKey.value);
    }
    if (iconCodePoint.present) {
      map['icon_code_point'] = Variable<int>(iconCodePoint.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (scheduledTimeMinutes.present) {
      map['scheduled_time_minutes'] = Variable<int>(scheduledTimeMinutes.value);
    }
    if (endTimeMinutes.present) {
      map['end_time_minutes'] = Variable<int>(endTimeMinutes.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dirty: $dirty, ')
          ..write('parentId: $parentId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('repeatType: $repeatType, ')
          ..write('repeatInterval: $repeatInterval, ')
          ..write('repeatDaysMask: $repeatDaysMask, ')
          ..write('trackingMode: $trackingMode, ')
          ..write('targetDurationMinutes: $targetDurationMinutes, ')
          ..write('targetValue: $targetValue, ')
          ..write('iconKey: $iconKey, ')
          ..write('iconCodePoint: $iconCodePoint, ')
          ..write('colorValue: $colorValue, ')
          ..write('scheduledTimeMinutes: $scheduledTimeMinutes, ')
          ..write('endTimeMinutes: $endTimeMinutes, ')
          ..write('startDate: $startDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TaskLogsTable extends TaskLogs with TableInfo<$TaskLogsTable, TaskLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<int> taskId = GeneratedColumn<int>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id)',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<double> value = GeneratedColumn<double>(
    'value',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: Constant(DateTime.fromMillisecondsSinceEpoch(0)),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    date,
    completed,
    value,
    dirty,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}task_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TaskLogsTable createAlias(String alias) {
    return $TaskLogsTable(attachedDatabase, alias);
  }
}

class TaskLog extends DataClass implements Insertable<TaskLog> {
  final int id;
  final int taskId;

  /// The calendar day this row is about, as **local midnight**. Never an
  /// instant: see the class comment, and [TasksDao.dayOf], which is the only
  /// thing that writes it.
  final DateTime date;
  final bool completed;
  final double? value;

  /// Changed here and not yet sent. See [SyncTombstones].
  final bool dirty;

  /// When the **device** last changed this row. Needed because the merge rule
  /// compares edit times and a log had no notion of one.
  ///
  /// The default is a bare constant — the epoch — and that is not laziness.
  /// SQLite refuses `ALTER TABLE ... ADD COLUMN` when the default is not
  /// constant: `CURRENT_TIMESTAMP`, which is what drift emits for
  /// `currentDateAndTime`, fails with "Cannot add a column with non-constant
  /// default". Worse, it fails **only on a table that already has rows** — an
  /// empty one accepts it — so the obvious spelling migrates a developer's
  /// device and bricks every phone that has ever ticked a day. The v14
  /// migration stamps the existing rows itself, and every write in [TasksDao]
  /// passes a value, so the epoch is never what a row actually carries.
  final DateTime updatedAt;
  const TaskLog({
    required this.id,
    required this.taskId,
    required this.date,
    required this.completed,
    this.value,
    required this.dirty,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['task_id'] = Variable<int>(taskId);
    map['date'] = Variable<DateTime>(date);
    map['completed'] = Variable<bool>(completed);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<double>(value);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TaskLogsCompanion toCompanion(bool nullToAbsent) {
    return TaskLogsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      date: Value(date),
      completed: Value(completed),
      value: value == null && nullToAbsent
          ? const Value.absent()
          : Value(value),
      dirty: Value(dirty),
      updatedAt: Value(updatedAt),
    );
  }

  factory TaskLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskLog(
      id: serializer.fromJson<int>(json['id']),
      taskId: serializer.fromJson<int>(json['taskId']),
      date: serializer.fromJson<DateTime>(json['date']),
      completed: serializer.fromJson<bool>(json['completed']),
      value: serializer.fromJson<double?>(json['value']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'taskId': serializer.toJson<int>(taskId),
      'date': serializer.toJson<DateTime>(date),
      'completed': serializer.toJson<bool>(completed),
      'value': serializer.toJson<double?>(value),
      'dirty': serializer.toJson<bool>(dirty),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TaskLog copyWith({
    int? id,
    int? taskId,
    DateTime? date,
    bool? completed,
    Value<double?> value = const Value.absent(),
    bool? dirty,
    DateTime? updatedAt,
  }) => TaskLog(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    date: date ?? this.date,
    completed: completed ?? this.completed,
    value: value.present ? value.value : this.value,
    dirty: dirty ?? this.dirty,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TaskLog copyWithCompanion(TaskLogsCompanion data) {
    return TaskLog(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      date: data.date.present ? data.date.value : this.date,
      completed: data.completed.present ? data.completed.value : this.completed,
      value: data.value.present ? data.value.value : this.value,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskLog(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('date: $date, ')
          ..write('completed: $completed, ')
          ..write('value: $value, ')
          ..write('dirty: $dirty, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, taskId, date, completed, value, dirty, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskLog &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.date == this.date &&
          other.completed == this.completed &&
          other.value == this.value &&
          other.dirty == this.dirty &&
          other.updatedAt == this.updatedAt);
}

class TaskLogsCompanion extends UpdateCompanion<TaskLog> {
  final Value<int> id;
  final Value<int> taskId;
  final Value<DateTime> date;
  final Value<bool> completed;
  final Value<double?> value;
  final Value<bool> dirty;
  final Value<DateTime> updatedAt;
  const TaskLogsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.date = const Value.absent(),
    this.completed = const Value.absent(),
    this.value = const Value.absent(),
    this.dirty = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  TaskLogsCompanion.insert({
    this.id = const Value.absent(),
    required int taskId,
    required DateTime date,
    this.completed = const Value.absent(),
    this.value = const Value.absent(),
    this.dirty = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : taskId = Value(taskId),
       date = Value(date);
  static Insertable<TaskLog> custom({
    Expression<int>? id,
    Expression<int>? taskId,
    Expression<DateTime>? date,
    Expression<bool>? completed,
    Expression<double>? value,
    Expression<bool>? dirty,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (date != null) 'date': date,
      if (completed != null) 'completed': completed,
      if (value != null) 'value': value,
      if (dirty != null) 'dirty': dirty,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  TaskLogsCompanion copyWith({
    Value<int>? id,
    Value<int>? taskId,
    Value<DateTime>? date,
    Value<bool>? completed,
    Value<double?>? value,
    Value<bool>? dirty,
    Value<DateTime>? updatedAt,
  }) {
    return TaskLogsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      date: date ?? this.date,
      completed: completed ?? this.completed,
      value: value ?? this.value,
      dirty: dirty ?? this.dirty,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<int>(taskId.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (value.present) {
      map['value'] = Variable<double>(value.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskLogsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('date: $date, ')
          ..write('completed: $completed, ')
          ..write('value: $value, ')
          ..write('dirty: $dirty, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TaskSessionsTable extends TaskSessions
    with TableInfo<$TaskSessionsTable, TaskSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<int> taskId = GeneratedColumn<int>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id)',
    ),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    startedAt,
    endedAt,
    durationSeconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}task_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      ),
    );
  }

  @override
  $TaskSessionsTable createAlias(String alias) {
    return $TaskSessionsTable(attachedDatabase, alias);
  }
}

class TaskSession extends DataClass implements Insertable<TaskSession> {
  final int id;
  final int taskId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  const TaskSession({
    required this.id,
    required this.taskId,
    required this.startedAt,
    this.endedAt,
    this.durationSeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['task_id'] = Variable<int>(taskId);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    if (!nullToAbsent || durationSeconds != null) {
      map['duration_seconds'] = Variable<int>(durationSeconds);
    }
    return map;
  }

  TaskSessionsCompanion toCompanion(bool nullToAbsent) {
    return TaskSessionsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      durationSeconds: durationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSeconds),
    );
  }

  factory TaskSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskSession(
      id: serializer.fromJson<int>(json['id']),
      taskId: serializer.fromJson<int>(json['taskId']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      durationSeconds: serializer.fromJson<int?>(json['durationSeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'taskId': serializer.toJson<int>(taskId),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'durationSeconds': serializer.toJson<int?>(durationSeconds),
    };
  }

  TaskSession copyWith({
    int? id,
    int? taskId,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    Value<int?> durationSeconds = const Value.absent(),
  }) => TaskSession(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    durationSeconds: durationSeconds.present
        ? durationSeconds.value
        : this.durationSeconds,
  );
  TaskSession copyWithCompanion(TaskSessionsCompanion data) {
    return TaskSession(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskSession(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationSeconds: $durationSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, taskId, startedAt, endedAt, durationSeconds);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskSession &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.durationSeconds == this.durationSeconds);
}

class TaskSessionsCompanion extends UpdateCompanion<TaskSession> {
  final Value<int> id;
  final Value<int> taskId;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int?> durationSeconds;
  const TaskSessionsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
  });
  TaskSessionsCompanion.insert({
    this.id = const Value.absent(),
    required int taskId,
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
  }) : taskId = Value(taskId),
       startedAt = Value(startedAt);
  static Insertable<TaskSession> custom({
    Expression<int>? id,
    Expression<int>? taskId,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? durationSeconds,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
    });
  }

  TaskSessionsCompanion copyWith({
    Value<int>? id,
    Value<int>? taskId,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<int?>? durationSeconds,
  }) {
    return TaskSessionsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<int>(taskId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskSessionsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationSeconds: $durationSeconds')
          ..write(')'))
        .toString();
  }
}

class $EventsTable extends Events with TableInfo<$EventsTable, Event> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<DateTime> endDate = GeneratedColumn<DateTime>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EventType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('personal'),
      ).withConverter<EventType>($EventsTable.$convertertype);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    description,
    startDate,
    endDate,
    type,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<Event> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Event map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Event(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_date'],
      ),
      type: $EventsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EventType, String, String> $convertertype =
      const EnumNameConverter<EventType>(EventType.values);
}

class Event extends DataClass implements Insertable<Event> {
  final int id;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime? endDate;
  final EventType type;
  const Event({
    required this.id,
    required this.title,
    this.description,
    required this.startDate,
    this.endDate,
    required this.type,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['start_date'] = Variable<DateTime>(startDate);
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<DateTime>(endDate);
    }
    {
      map['type'] = Variable<String>($EventsTable.$convertertype.toSql(type));
    }
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      id: Value(id),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      startDate: Value(startDate),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      type: Value(type),
    );
  }

  factory Event.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Event(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      startDate: serializer.fromJson<DateTime>(json['startDate']),
      endDate: serializer.fromJson<DateTime?>(json['endDate']),
      type: $EventsTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'startDate': serializer.toJson<DateTime>(startDate),
      'endDate': serializer.toJson<DateTime?>(endDate),
      'type': serializer.toJson<String>(
        $EventsTable.$convertertype.toJson(type),
      ),
    };
  }

  Event copyWith({
    int? id,
    String? title,
    Value<String?> description = const Value.absent(),
    DateTime? startDate,
    Value<DateTime?> endDate = const Value.absent(),
    EventType? type,
  }) => Event(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    startDate: startDate ?? this.startDate,
    endDate: endDate.present ? endDate.value : this.endDate,
    type: type ?? this.type,
  );
  Event copyWithCompanion(EventsCompanion data) {
    return Event(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      type: data.type.present ? data.type.value : this.type,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Event(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('type: $type')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, description, startDate, endDate, type);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Event &&
          other.id == this.id &&
          other.title == this.title &&
          other.description == this.description &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate &&
          other.type == this.type);
}

class EventsCompanion extends UpdateCompanion<Event> {
  final Value<int> id;
  final Value<String> title;
  final Value<String?> description;
  final Value<DateTime> startDate;
  final Value<DateTime?> endDate;
  final Value<EventType> type;
  const EventsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.type = const Value.absent(),
  });
  EventsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    required DateTime startDate,
    this.endDate = const Value.absent(),
    this.type = const Value.absent(),
  }) : title = Value(title),
       startDate = Value(startDate);
  static Insertable<Event> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? description,
    Expression<DateTime>? startDate,
    Expression<DateTime>? endDate,
    Expression<String>? type,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (type != null) 'type': type,
    });
  }

  EventsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String?>? description,
    Value<DateTime>? startDate,
    Value<DateTime?>? endDate,
    Value<EventType>? type,
  }) {
    return EventsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      type: type ?? this.type,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<DateTime>(endDate.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $EventsTable.$convertertype.toSql(type.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('type: $type')
          ..write(')'))
        .toString();
  }
}

class $DiaryEntriesTable extends DiaryEntries
    with TableInfo<$DiaryEntriesTable, DiaryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiaryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
    'uid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _coverImageMeta = const VerificationMeta(
    'coverImage',
  );
  @override
  late final GeneratedColumn<String> coverImage = GeneratedColumn<String>(
    'cover_image',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imagesMeta = const VerificationMeta('images');
  @override
  late final GeneratedColumn<String> images = GeneratedColumn<String>(
    'images',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DiaryEntryStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('normal'),
      ).withConverter<DiaryEntryStatus>($DiaryEntriesTable.$converterstatus);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uid,
    dirty,
    title,
    body,
    coverImage,
    images,
    isFavorite,
    status,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diary_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiaryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uid')) {
      context.handle(
        _uidMeta,
        uid.isAcceptableOrUnknown(data['uid']!, _uidMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('cover_image')) {
      context.handle(
        _coverImageMeta,
        coverImage.isAcceptableOrUnknown(data['cover_image']!, _coverImageMeta),
      );
    }
    if (data.containsKey('images')) {
      context.handle(
        _imagesMeta,
        images.isAcceptableOrUnknown(data['images']!, _imagesMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DiaryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiaryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      coverImage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_image'],
      ),
      images: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}images'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      status: $DiaryEntriesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DiaryEntriesTable createAlias(String alias) {
    return $DiaryEntriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<DiaryEntryStatus, String, String> $converterstatus =
      const EnumNameConverter<DiaryEntryStatus>(DiaryEntryStatus.values);
}

class DiaryEntry extends DataClass implements Insertable<DiaryEntry> {
  final int id;

  /// The note's identity across devices — see [SyncTombstones] for why the
  /// local [id] cannot be it.
  final String? uid;

  /// Changed here and not yet sent. See [SyncTombstones].
  final bool dirty;
  final String title;

  /// The note's text as a Parchment (Quill.js) Delta, JSON-encoded. Plain text
  /// cannot hold what the editor produces — headings, lists, pictures — and the
  /// format is the one both Fleather and Quill read, so the choice of editor is
  /// not baked into the data.
  ///
  /// Image operations inside it carry a **file name**, not a path; see
  /// [noteImagesDirectory].
  final String body;

  /// File name of the cover inside the app's note-images directory, never an
  /// absolute path: the container the directory lives in is not stable across
  /// launches on iOS, so a stored path goes dead after an update.
  final String? coverImage;

  /// The pictures attached to the note, in the order they were added, as a JSON
  /// array of file names in the same directory as [coverImage].
  ///
  /// They belong to the note as a whole and are shown after its text, so they
  /// are not part of [body]: an attachment is not a character in the document,
  /// and reordering or dropping one must not rewrite the text around it. SQLite
  /// has no array type, hence JSON in a text column rather than a table of its
  /// own — nothing ever queries a single picture.
  final String images;
  final bool isFavorite;
  final DiaryEntryStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  const DiaryEntry({
    required this.id,
    this.uid,
    required this.dirty,
    required this.title,
    required this.body,
    this.coverImage,
    required this.images,
    required this.isFavorite,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || uid != null) {
      map['uid'] = Variable<String>(uid);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || coverImage != null) {
      map['cover_image'] = Variable<String>(coverImage);
    }
    map['images'] = Variable<String>(images);
    map['is_favorite'] = Variable<bool>(isFavorite);
    {
      map['status'] = Variable<String>(
        $DiaryEntriesTable.$converterstatus.toSql(status),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DiaryEntriesCompanion toCompanion(bool nullToAbsent) {
    return DiaryEntriesCompanion(
      id: Value(id),
      uid: uid == null && nullToAbsent ? const Value.absent() : Value(uid),
      dirty: Value(dirty),
      title: Value(title),
      body: Value(body),
      coverImage: coverImage == null && nullToAbsent
          ? const Value.absent()
          : Value(coverImage),
      images: Value(images),
      isFavorite: Value(isFavorite),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DiaryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiaryEntry(
      id: serializer.fromJson<int>(json['id']),
      uid: serializer.fromJson<String?>(json['uid']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      coverImage: serializer.fromJson<String?>(json['coverImage']),
      images: serializer.fromJson<String>(json['images']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      status: $DiaryEntriesTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uid': serializer.toJson<String?>(uid),
      'dirty': serializer.toJson<bool>(dirty),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'coverImage': serializer.toJson<String?>(coverImage),
      'images': serializer.toJson<String>(images),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'status': serializer.toJson<String>(
        $DiaryEntriesTable.$converterstatus.toJson(status),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DiaryEntry copyWith({
    int? id,
    Value<String?> uid = const Value.absent(),
    bool? dirty,
    String? title,
    String? body,
    Value<String?> coverImage = const Value.absent(),
    String? images,
    bool? isFavorite,
    DiaryEntryStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DiaryEntry(
    id: id ?? this.id,
    uid: uid.present ? uid.value : this.uid,
    dirty: dirty ?? this.dirty,
    title: title ?? this.title,
    body: body ?? this.body,
    coverImage: coverImage.present ? coverImage.value : this.coverImage,
    images: images ?? this.images,
    isFavorite: isFavorite ?? this.isFavorite,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DiaryEntry copyWithCompanion(DiaryEntriesCompanion data) {
    return DiaryEntry(
      id: data.id.present ? data.id.value : this.id,
      uid: data.uid.present ? data.uid.value : this.uid,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      coverImage: data.coverImage.present
          ? data.coverImage.value
          : this.coverImage,
      images: data.images.present ? data.images.value : this.images,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiaryEntry(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dirty: $dirty, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('coverImage: $coverImage, ')
          ..write('images: $images, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uid,
    dirty,
    title,
    body,
    coverImage,
    images,
    isFavorite,
    status,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiaryEntry &&
          other.id == this.id &&
          other.uid == this.uid &&
          other.dirty == this.dirty &&
          other.title == this.title &&
          other.body == this.body &&
          other.coverImage == this.coverImage &&
          other.images == this.images &&
          other.isFavorite == this.isFavorite &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DiaryEntriesCompanion extends UpdateCompanion<DiaryEntry> {
  final Value<int> id;
  final Value<String?> uid;
  final Value<bool> dirty;
  final Value<String> title;
  final Value<String> body;
  final Value<String?> coverImage;
  final Value<String> images;
  final Value<bool> isFavorite;
  final Value<DiaryEntryStatus> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const DiaryEntriesCompanion({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.dirty = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.coverImage = const Value.absent(),
    this.images = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DiaryEntriesCompanion.insert({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.dirty = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.coverImage = const Value.absent(),
    this.images = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<DiaryEntry> custom({
    Expression<int>? id,
    Expression<String>? uid,
    Expression<bool>? dirty,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? coverImage,
    Expression<String>? images,
    Expression<bool>? isFavorite,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uid != null) 'uid': uid,
      if (dirty != null) 'dirty': dirty,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (coverImage != null) 'cover_image': coverImage,
      if (images != null) 'images': images,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DiaryEntriesCompanion copyWith({
    Value<int>? id,
    Value<String?>? uid,
    Value<bool>? dirty,
    Value<String>? title,
    Value<String>? body,
    Value<String?>? coverImage,
    Value<String>? images,
    Value<bool>? isFavorite,
    Value<DiaryEntryStatus>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return DiaryEntriesCompanion(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      dirty: dirty ?? this.dirty,
      title: title ?? this.title,
      body: body ?? this.body,
      coverImage: coverImage ?? this.coverImage,
      images: images ?? this.images,
      isFavorite: isFavorite ?? this.isFavorite,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (coverImage.present) {
      map['cover_image'] = Variable<String>(coverImage.value);
    }
    if (images.present) {
      map['images'] = Variable<String>(images.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $DiaryEntriesTable.$converterstatus.toSql(status.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiaryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dirty: $dirty, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('coverImage: $coverImage, ')
          ..write('images: $images, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $NoteMoodsTable extends NoteMoods
    with TableInfo<$NoteMoodsTable, NoteMood> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteMoodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
    'uid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
    'emoji',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uid,
    dirty,
    name,
    emoji,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_moods';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteMood> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uid')) {
      context.handle(
        _uidMeta,
        uid.isAcceptableOrUnknown(data['uid']!, _uidMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('emoji')) {
      context.handle(
        _emojiMeta,
        emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta),
      );
    } else if (isInserting) {
      context.missing(_emojiMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteMood map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteMood(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      emoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NoteMoodsTable createAlias(String alias) {
    return $NoteMoodsTable(attachedDatabase, alias);
  }
}

class NoteMood extends DataClass implements Insertable<NoteMood> {
  final int id;

  /// Identity across devices. The eight seeded moods carry the **fixed** uids
  /// of `defaultNoteMoods` rather than fresh ones: the seeding runs separately
  /// on every device, so without that two phones would send the same eight
  /// moods up as sixteen rows.
  final String? uid;

  /// Changed here and not yet sent. See [SyncTombstones].
  final bool dirty;

  /// What the chip says — "Спокойствие". Unique in practice, not by constraint:
  /// the picker refuses a name it already holds, which is a better place to say
  /// so than a failed insert.
  final String name;

  /// The emoji itself, as text — 🌿, not a code point. It is drawn by the
  /// platform's emoji font, which the app neither ships nor subsets, so there is
  /// nothing to look a glyph up in and nothing that could go stale.
  final String emoji;
  final DateTime createdAt;
  const NoteMood({
    required this.id,
    this.uid,
    required this.dirty,
    required this.name,
    required this.emoji,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || uid != null) {
      map['uid'] = Variable<String>(uid);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['name'] = Variable<String>(name);
    map['emoji'] = Variable<String>(emoji);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NoteMoodsCompanion toCompanion(bool nullToAbsent) {
    return NoteMoodsCompanion(
      id: Value(id),
      uid: uid == null && nullToAbsent ? const Value.absent() : Value(uid),
      dirty: Value(dirty),
      name: Value(name),
      emoji: Value(emoji),
      createdAt: Value(createdAt),
    );
  }

  factory NoteMood.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteMood(
      id: serializer.fromJson<int>(json['id']),
      uid: serializer.fromJson<String?>(json['uid']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      name: serializer.fromJson<String>(json['name']),
      emoji: serializer.fromJson<String>(json['emoji']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uid': serializer.toJson<String?>(uid),
      'dirty': serializer.toJson<bool>(dirty),
      'name': serializer.toJson<String>(name),
      'emoji': serializer.toJson<String>(emoji),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NoteMood copyWith({
    int? id,
    Value<String?> uid = const Value.absent(),
    bool? dirty,
    String? name,
    String? emoji,
    DateTime? createdAt,
  }) => NoteMood(
    id: id ?? this.id,
    uid: uid.present ? uid.value : this.uid,
    dirty: dirty ?? this.dirty,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    createdAt: createdAt ?? this.createdAt,
  );
  NoteMood copyWithCompanion(NoteMoodsCompanion data) {
    return NoteMood(
      id: data.id.present ? data.id.value : this.id,
      uid: data.uid.present ? data.uid.value : this.uid,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      name: data.name.present ? data.name.value : this.name,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteMood(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dirty: $dirty, ')
          ..write('name: $name, ')
          ..write('emoji: $emoji, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, uid, dirty, name, emoji, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteMood &&
          other.id == this.id &&
          other.uid == this.uid &&
          other.dirty == this.dirty &&
          other.name == this.name &&
          other.emoji == this.emoji &&
          other.createdAt == this.createdAt);
}

class NoteMoodsCompanion extends UpdateCompanion<NoteMood> {
  final Value<int> id;
  final Value<String?> uid;
  final Value<bool> dirty;
  final Value<String> name;
  final Value<String> emoji;
  final Value<DateTime> createdAt;
  const NoteMoodsCompanion({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.dirty = const Value.absent(),
    this.name = const Value.absent(),
    this.emoji = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  NoteMoodsCompanion.insert({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.dirty = const Value.absent(),
    required String name,
    required String emoji,
    this.createdAt = const Value.absent(),
  }) : name = Value(name),
       emoji = Value(emoji);
  static Insertable<NoteMood> custom({
    Expression<int>? id,
    Expression<String>? uid,
    Expression<bool>? dirty,
    Expression<String>? name,
    Expression<String>? emoji,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uid != null) 'uid': uid,
      if (dirty != null) 'dirty': dirty,
      if (name != null) 'name': name,
      if (emoji != null) 'emoji': emoji,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  NoteMoodsCompanion copyWith({
    Value<int>? id,
    Value<String?>? uid,
    Value<bool>? dirty,
    Value<String>? name,
    Value<String>? emoji,
    Value<DateTime>? createdAt,
  }) {
    return NoteMoodsCompanion(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      dirty: dirty ?? this.dirty,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteMoodsCompanion(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dirty: $dirty, ')
          ..write('name: $name, ')
          ..write('emoji: $emoji, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $NoteTagsTable extends NoteTags with TableInfo<$NoteTagsTable, NoteTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
    'uid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorKeyMeta = const VerificationMeta(
    'colorKey',
  );
  @override
  late final GeneratedColumn<String> colorKey = GeneratedColumn<String>(
    'color_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('violet'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uid,
    dirty,
    name,
    colorKey,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uid')) {
      context.handle(
        _uidMeta,
        uid.isAcceptableOrUnknown(data['uid']!, _uidMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_key')) {
      context.handle(
        _colorKeyMeta,
        colorKey.isAcceptableOrUnknown(data['color_key']!, _colorKeyMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteTag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_key'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NoteTagsTable createAlias(String alias) {
    return $NoteTagsTable(attachedDatabase, alias);
  }
}

class NoteTag extends DataClass implements Insertable<NoteTag> {
  final int id;

  /// Identity across devices. See [SyncTombstones].
  final String? uid;

  /// Changed here and not yet sent. See [SyncTombstones].
  final bool dirty;

  /// Without the leading "#" — that is punctuation the chip draws, not part of
  /// the name, and storing it would put it into every comparison.
  final String name;

  /// Which family of `taskPalette` the chip is painted in — `violet`, `red`,
  /// and so on. A **key**, not the colour itself.
  ///
  /// A task stores its raw ARGB, and a tag used to as well. The difference is
  /// that a tag travels: it goes to the server and comes back on another phone,
  /// possibly running a different version of the app. A number like
  /// `0xFF8B7CF6` only means something inside one version of one palette —
  /// exactly the reason task icons stopped storing a Material code point in
  /// migration v10 and started storing a key into `taskIcons`.
  ///
  /// With a key the design can be repainted and every tag ever written follows,
  /// everywhere, with no migration. It also sidesteps a mismatch that only
  /// showed up at the boundary: an opaque ARGB begins with `0xFF` and so
  /// exceeds 2^31, which SQLite stored without comment and Postgres `integer`
  /// refused outright.
  final String colorKey;
  final DateTime createdAt;
  const NoteTag({
    required this.id,
    this.uid,
    required this.dirty,
    required this.name,
    required this.colorKey,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || uid != null) {
      map['uid'] = Variable<String>(uid);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['name'] = Variable<String>(name);
    map['color_key'] = Variable<String>(colorKey);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NoteTagsCompanion toCompanion(bool nullToAbsent) {
    return NoteTagsCompanion(
      id: Value(id),
      uid: uid == null && nullToAbsent ? const Value.absent() : Value(uid),
      dirty: Value(dirty),
      name: Value(name),
      colorKey: Value(colorKey),
      createdAt: Value(createdAt),
    );
  }

  factory NoteTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteTag(
      id: serializer.fromJson<int>(json['id']),
      uid: serializer.fromJson<String?>(json['uid']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      name: serializer.fromJson<String>(json['name']),
      colorKey: serializer.fromJson<String>(json['colorKey']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uid': serializer.toJson<String?>(uid),
      'dirty': serializer.toJson<bool>(dirty),
      'name': serializer.toJson<String>(name),
      'colorKey': serializer.toJson<String>(colorKey),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NoteTag copyWith({
    int? id,
    Value<String?> uid = const Value.absent(),
    bool? dirty,
    String? name,
    String? colorKey,
    DateTime? createdAt,
  }) => NoteTag(
    id: id ?? this.id,
    uid: uid.present ? uid.value : this.uid,
    dirty: dirty ?? this.dirty,
    name: name ?? this.name,
    colorKey: colorKey ?? this.colorKey,
    createdAt: createdAt ?? this.createdAt,
  );
  NoteTag copyWithCompanion(NoteTagsCompanion data) {
    return NoteTag(
      id: data.id.present ? data.id.value : this.id,
      uid: data.uid.present ? data.uid.value : this.uid,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      name: data.name.present ? data.name.value : this.name,
      colorKey: data.colorKey.present ? data.colorKey.value : this.colorKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteTag(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dirty: $dirty, ')
          ..write('name: $name, ')
          ..write('colorKey: $colorKey, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, uid, dirty, name, colorKey, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteTag &&
          other.id == this.id &&
          other.uid == this.uid &&
          other.dirty == this.dirty &&
          other.name == this.name &&
          other.colorKey == this.colorKey &&
          other.createdAt == this.createdAt);
}

class NoteTagsCompanion extends UpdateCompanion<NoteTag> {
  final Value<int> id;
  final Value<String?> uid;
  final Value<bool> dirty;
  final Value<String> name;
  final Value<String> colorKey;
  final Value<DateTime> createdAt;
  const NoteTagsCompanion({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.dirty = const Value.absent(),
    this.name = const Value.absent(),
    this.colorKey = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  NoteTagsCompanion.insert({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.dirty = const Value.absent(),
    required String name,
    this.colorKey = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<NoteTag> custom({
    Expression<int>? id,
    Expression<String>? uid,
    Expression<bool>? dirty,
    Expression<String>? name,
    Expression<String>? colorKey,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uid != null) 'uid': uid,
      if (dirty != null) 'dirty': dirty,
      if (name != null) 'name': name,
      if (colorKey != null) 'color_key': colorKey,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  NoteTagsCompanion copyWith({
    Value<int>? id,
    Value<String?>? uid,
    Value<bool>? dirty,
    Value<String>? name,
    Value<String>? colorKey,
    Value<DateTime>? createdAt,
  }) {
    return NoteTagsCompanion(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      dirty: dirty ?? this.dirty,
      name: name ?? this.name,
      colorKey: colorKey ?? this.colorKey,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorKey.present) {
      map['color_key'] = Variable<String>(colorKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteTagsCompanion(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dirty: $dirty, ')
          ..write('name: $name, ')
          ..write('colorKey: $colorKey, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DiaryEntryMoodsTable extends DiaryEntryMoods
    with TableInfo<$DiaryEntryMoodsTable, DiaryEntryMood> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiaryEntryMoodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<int> entryId = GeneratedColumn<int>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES diary_entries (id)',
    ),
  );
  static const VerificationMeta _moodIdMeta = const VerificationMeta('moodId');
  @override
  late final GeneratedColumn<int> moodId = GeneratedColumn<int>(
    'mood_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES note_moods (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [entryId, moodId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diary_entry_moods';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiaryEntryMood> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('mood_id')) {
      context.handle(
        _moodIdMeta,
        moodId.isAcceptableOrUnknown(data['mood_id']!, _moodIdMeta),
      );
    } else if (isInserting) {
      context.missing(_moodIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entryId, moodId};
  @override
  DiaryEntryMood map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiaryEntryMood(
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entry_id'],
      )!,
      moodId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mood_id'],
      )!,
    );
  }

  @override
  $DiaryEntryMoodsTable createAlias(String alias) {
    return $DiaryEntryMoodsTable(attachedDatabase, alias);
  }
}

class DiaryEntryMood extends DataClass implements Insertable<DiaryEntryMood> {
  final int entryId;
  final int moodId;
  const DiaryEntryMood({required this.entryId, required this.moodId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entry_id'] = Variable<int>(entryId);
    map['mood_id'] = Variable<int>(moodId);
    return map;
  }

  DiaryEntryMoodsCompanion toCompanion(bool nullToAbsent) {
    return DiaryEntryMoodsCompanion(
      entryId: Value(entryId),
      moodId: Value(moodId),
    );
  }

  factory DiaryEntryMood.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiaryEntryMood(
      entryId: serializer.fromJson<int>(json['entryId']),
      moodId: serializer.fromJson<int>(json['moodId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entryId': serializer.toJson<int>(entryId),
      'moodId': serializer.toJson<int>(moodId),
    };
  }

  DiaryEntryMood copyWith({int? entryId, int? moodId}) => DiaryEntryMood(
    entryId: entryId ?? this.entryId,
    moodId: moodId ?? this.moodId,
  );
  DiaryEntryMood copyWithCompanion(DiaryEntryMoodsCompanion data) {
    return DiaryEntryMood(
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      moodId: data.moodId.present ? data.moodId.value : this.moodId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiaryEntryMood(')
          ..write('entryId: $entryId, ')
          ..write('moodId: $moodId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entryId, moodId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiaryEntryMood &&
          other.entryId == this.entryId &&
          other.moodId == this.moodId);
}

class DiaryEntryMoodsCompanion extends UpdateCompanion<DiaryEntryMood> {
  final Value<int> entryId;
  final Value<int> moodId;
  final Value<int> rowid;
  const DiaryEntryMoodsCompanion({
    this.entryId = const Value.absent(),
    this.moodId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiaryEntryMoodsCompanion.insert({
    required int entryId,
    required int moodId,
    this.rowid = const Value.absent(),
  }) : entryId = Value(entryId),
       moodId = Value(moodId);
  static Insertable<DiaryEntryMood> custom({
    Expression<int>? entryId,
    Expression<int>? moodId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entryId != null) 'entry_id': entryId,
      if (moodId != null) 'mood_id': moodId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiaryEntryMoodsCompanion copyWith({
    Value<int>? entryId,
    Value<int>? moodId,
    Value<int>? rowid,
  }) {
    return DiaryEntryMoodsCompanion(
      entryId: entryId ?? this.entryId,
      moodId: moodId ?? this.moodId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entryId.present) {
      map['entry_id'] = Variable<int>(entryId.value);
    }
    if (moodId.present) {
      map['mood_id'] = Variable<int>(moodId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiaryEntryMoodsCompanion(')
          ..write('entryId: $entryId, ')
          ..write('moodId: $moodId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiaryEntryTagsTable extends DiaryEntryTags
    with TableInfo<$DiaryEntryTagsTable, DiaryEntryTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiaryEntryTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<int> entryId = GeneratedColumn<int>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES diary_entries (id)',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<int> tagId = GeneratedColumn<int>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES note_tags (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [entryId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diary_entry_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiaryEntryTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entryId, tagId};
  @override
  DiaryEntryTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiaryEntryTag(
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entry_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $DiaryEntryTagsTable createAlias(String alias) {
    return $DiaryEntryTagsTable(attachedDatabase, alias);
  }
}

class DiaryEntryTag extends DataClass implements Insertable<DiaryEntryTag> {
  final int entryId;
  final int tagId;
  const DiaryEntryTag({required this.entryId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entry_id'] = Variable<int>(entryId);
    map['tag_id'] = Variable<int>(tagId);
    return map;
  }

  DiaryEntryTagsCompanion toCompanion(bool nullToAbsent) {
    return DiaryEntryTagsCompanion(
      entryId: Value(entryId),
      tagId: Value(tagId),
    );
  }

  factory DiaryEntryTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiaryEntryTag(
      entryId: serializer.fromJson<int>(json['entryId']),
      tagId: serializer.fromJson<int>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entryId': serializer.toJson<int>(entryId),
      'tagId': serializer.toJson<int>(tagId),
    };
  }

  DiaryEntryTag copyWith({int? entryId, int? tagId}) => DiaryEntryTag(
    entryId: entryId ?? this.entryId,
    tagId: tagId ?? this.tagId,
  );
  DiaryEntryTag copyWithCompanion(DiaryEntryTagsCompanion data) {
    return DiaryEntryTag(
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiaryEntryTag(')
          ..write('entryId: $entryId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entryId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiaryEntryTag &&
          other.entryId == this.entryId &&
          other.tagId == this.tagId);
}

class DiaryEntryTagsCompanion extends UpdateCompanion<DiaryEntryTag> {
  final Value<int> entryId;
  final Value<int> tagId;
  final Value<int> rowid;
  const DiaryEntryTagsCompanion({
    this.entryId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiaryEntryTagsCompanion.insert({
    required int entryId,
    required int tagId,
    this.rowid = const Value.absent(),
  }) : entryId = Value(entryId),
       tagId = Value(tagId);
  static Insertable<DiaryEntryTag> custom({
    Expression<int>? entryId,
    Expression<int>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entryId != null) 'entry_id': entryId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiaryEntryTagsCompanion copyWith({
    Value<int>? entryId,
    Value<int>? tagId,
    Value<int>? rowid,
  }) {
    return DiaryEntryTagsCompanion(
      entryId: entryId ?? this.entryId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entryId.present) {
      map['entry_id'] = Variable<int>(entryId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<int>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiaryEntryTagsCompanion(')
          ..write('entryId: $entryId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncTombstonesTable extends SyncTombstones
    with TableInfo<$SyncTombstonesTable, SyncTombstone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceTableMeta = const VerificationMeta(
    'sourceTable',
  );
  @override
  late final GeneratedColumn<String> sourceTable = GeneratedColumn<String>(
    'source_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
    'uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [sourceTable, uid, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncTombstone> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_table')) {
      context.handle(
        _sourceTableMeta,
        sourceTable.isAcceptableOrUnknown(
          data['source_table']!,
          _sourceTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceTableMeta);
    }
    if (data.containsKey('uid')) {
      context.handle(
        _uidMeta,
        uid.isAcceptableOrUnknown(data['uid']!, _uidMeta),
      );
    } else if (isInserting) {
      context.missing(_uidMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceTable, uid};
  @override
  SyncTombstone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncTombstone(
      sourceTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_table'],
      )!,
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      )!,
    );
  }

  @override
  $SyncTombstonesTable createAlias(String alias) {
    return $SyncTombstonesTable(attachedDatabase, alias);
  }
}

class SyncTombstone extends DataClass implements Insertable<SyncTombstone> {
  /// Which table the row was in — `diary_entries`, `note_moods`, `note_tags`,
  /// `tasks`. A plain string: this table outlives the row it describes, so it
  /// cannot point at one. Not `tableName`, which is drift's own on [Table].
  ///
  /// It is also the name the **server** knows the table by, because that is
  /// what the push uses to address the row it has to mark deleted. The two
  /// spellings have to stay the same on both sides.
  final String sourceTable;

  /// The [DiaryEntries.uid] or [Tasks.uid] of what was deleted.
  ///
  /// [TaskLogs] never appears here, and that is a property of the app rather
  /// than an omission: the only statement in it that deletes a log deletes
  /// every log of one task, so a log's disappearance is always already told by
  /// its task's. On the server the same fact is a foreign key.
  final String uid;
  final DateTime deletedAt;
  const SyncTombstone({
    required this.sourceTable,
    required this.uid,
    required this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_table'] = Variable<String>(sourceTable);
    map['uid'] = Variable<String>(uid);
    map['deleted_at'] = Variable<DateTime>(deletedAt);
    return map;
  }

  SyncTombstonesCompanion toCompanion(bool nullToAbsent) {
    return SyncTombstonesCompanion(
      sourceTable: Value(sourceTable),
      uid: Value(uid),
      deletedAt: Value(deletedAt),
    );
  }

  factory SyncTombstone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncTombstone(
      sourceTable: serializer.fromJson<String>(json['sourceTable']),
      uid: serializer.fromJson<String>(json['uid']),
      deletedAt: serializer.fromJson<DateTime>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceTable': serializer.toJson<String>(sourceTable),
      'uid': serializer.toJson<String>(uid),
      'deletedAt': serializer.toJson<DateTime>(deletedAt),
    };
  }

  SyncTombstone copyWith({
    String? sourceTable,
    String? uid,
    DateTime? deletedAt,
  }) => SyncTombstone(
    sourceTable: sourceTable ?? this.sourceTable,
    uid: uid ?? this.uid,
    deletedAt: deletedAt ?? this.deletedAt,
  );
  SyncTombstone copyWithCompanion(SyncTombstonesCompanion data) {
    return SyncTombstone(
      sourceTable: data.sourceTable.present
          ? data.sourceTable.value
          : this.sourceTable,
      uid: data.uid.present ? data.uid.value : this.uid,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncTombstone(')
          ..write('sourceTable: $sourceTable, ')
          ..write('uid: $uid, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceTable, uid, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncTombstone &&
          other.sourceTable == this.sourceTable &&
          other.uid == this.uid &&
          other.deletedAt == this.deletedAt);
}

class SyncTombstonesCompanion extends UpdateCompanion<SyncTombstone> {
  final Value<String> sourceTable;
  final Value<String> uid;
  final Value<DateTime> deletedAt;
  final Value<int> rowid;
  const SyncTombstonesCompanion({
    this.sourceTable = const Value.absent(),
    this.uid = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncTombstonesCompanion.insert({
    required String sourceTable,
    required String uid,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sourceTable = Value(sourceTable),
       uid = Value(uid);
  static Insertable<SyncTombstone> custom({
    Expression<String>? sourceTable,
    Expression<String>? uid,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceTable != null) 'source_table': sourceTable,
      if (uid != null) 'uid': uid,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncTombstonesCompanion copyWith({
    Value<String>? sourceTable,
    Value<String>? uid,
    Value<DateTime>? deletedAt,
    Value<int>? rowid,
  }) {
    return SyncTombstonesCompanion(
      sourceTable: sourceTable ?? this.sourceTable,
      uid: uid ?? this.uid,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceTable.present) {
      map['source_table'] = Variable<String>(sourceTable.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncTombstonesCompanion(')
          ..write('sourceTable: $sourceTable, ')
          ..write('uid: $uid, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $TaskLogsTable taskLogs = $TaskLogsTable(this);
  late final $TaskSessionsTable taskSessions = $TaskSessionsTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $DiaryEntriesTable diaryEntries = $DiaryEntriesTable(this);
  late final $NoteMoodsTable noteMoods = $NoteMoodsTable(this);
  late final $NoteTagsTable noteTags = $NoteTagsTable(this);
  late final $DiaryEntryMoodsTable diaryEntryMoods = $DiaryEntryMoodsTable(
    this,
  );
  late final $DiaryEntryTagsTable diaryEntryTags = $DiaryEntryTagsTable(this);
  late final $SyncTombstonesTable syncTombstones = $SyncTombstonesTable(this);
  late final Index tasksUid = Index(
    'tasks_uid',
    'CREATE UNIQUE INDEX tasks_uid ON tasks (uid)',
  );
  late final Index taskLogsTaskDay = Index(
    'task_logs_task_day',
    'CREATE UNIQUE INDEX task_logs_task_day ON task_logs (task_id, date)',
  );
  late final Index diaryEntriesUid = Index(
    'diary_entries_uid',
    'CREATE UNIQUE INDEX diary_entries_uid ON diary_entries (uid)',
  );
  late final Index noteMoodsUid = Index(
    'note_moods_uid',
    'CREATE UNIQUE INDEX note_moods_uid ON note_moods (uid)',
  );
  late final Index noteTagsUid = Index(
    'note_tags_uid',
    'CREATE UNIQUE INDEX note_tags_uid ON note_tags (uid)',
  );
  late final TasksDao tasksDao = TasksDao(this as AppDatabase);
  late final EventsDao eventsDao = EventsDao(this as AppDatabase);
  late final DiaryDao diaryDao = DiaryDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tasks,
    taskLogs,
    taskSessions,
    events,
    diaryEntries,
    noteMoods,
    noteTags,
    diaryEntryMoods,
    diaryEntryTags,
    syncTombstones,
    tasksUid,
    taskLogsTaskDay,
    diaryEntriesUid,
    noteMoodsUid,
    noteTagsUid,
  ];
}

typedef $$TasksTableCreateCompanionBuilder =
    TasksCompanion Function({
      Value<int> id,
      Value<String?> uid,
      Value<bool> dirty,
      Value<int?> parentId,
      required String title,
      Value<String?> description,
      Value<TaskStatus> status,
      Value<RepeatType?> repeatType,
      Value<int?> repeatInterval,
      Value<int?> repeatDaysMask,
      Value<TrackingMode> trackingMode,
      Value<int?> targetDurationMinutes,
      Value<double?> targetValue,
      Value<String?> iconKey,
      Value<int?> iconCodePoint,
      Value<int?> colorValue,
      Value<int?> scheduledTimeMinutes,
      Value<int?> endTimeMinutes,
      Value<DateTime?> startDate,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$TasksTableUpdateCompanionBuilder =
    TasksCompanion Function({
      Value<int> id,
      Value<String?> uid,
      Value<bool> dirty,
      Value<int?> parentId,
      Value<String> title,
      Value<String?> description,
      Value<TaskStatus> status,
      Value<RepeatType?> repeatType,
      Value<int?> repeatInterval,
      Value<int?> repeatDaysMask,
      Value<TrackingMode> trackingMode,
      Value<int?> targetDurationMinutes,
      Value<double?> targetValue,
      Value<String?> iconKey,
      Value<int?> iconCodePoint,
      Value<int?> colorValue,
      Value<int?> scheduledTimeMinutes,
      Value<int?> endTimeMinutes,
      Value<DateTime?> startDate,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$TasksTableReferences
    extends BaseReferences<_$AppDatabase, $TasksTable, Task> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TasksTable _parentIdTable(_$AppDatabase db) =>
      db.tasks.createAlias('tasks__parent_id__tasks__id');

  $$TasksTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<int>('parent_id');
    if ($_column == null) return null;
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$TaskLogsTable, List<TaskLog>> _taskLogsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.taskLogs,
    aliasName: 'tasks__id__task_logs__task_id',
  );

  $$TaskLogsTableProcessedTableManager get taskLogsRefs {
    final manager = $$TaskLogsTableTableManager(
      $_db,
      $_db.taskLogs,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_taskLogsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TaskSessionsTable, List<TaskSession>>
  _taskSessionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.taskSessions,
    aliasName: 'tasks__id__task_sessions__task_id',
  );

  $$TaskSessionsTableProcessedTableManager get taskSessionsRefs {
    final manager = $$TaskSessionsTableTableManager(
      $_db,
      $_db.taskSessions,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_taskSessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TaskStatus, TaskStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<RepeatType?, RepeatType, String>
  get repeatType => $composableBuilder(
    column: $table.repeatType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get repeatInterval => $composableBuilder(
    column: $table.repeatInterval,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repeatDaysMask => $composableBuilder(
    column: $table.repeatDaysMask,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TrackingMode, TrackingMode, String>
  get trackingMode => $composableBuilder(
    column: $table.trackingMode,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get targetDurationMinutes => $composableBuilder(
    column: $table.targetDurationMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconKey => $composableBuilder(
    column: $table.iconKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get iconCodePoint => $composableBuilder(
    column: $table.iconCodePoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scheduledTimeMinutes => $composableBuilder(
    column: $table.scheduledTimeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endTimeMinutes => $composableBuilder(
    column: $table.endTimeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$TasksTableFilterComposer get parentId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> taskLogsRefs(
    Expression<bool> Function($$TaskLogsTableFilterComposer f) f,
  ) {
    final $$TaskLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskLogs,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskLogsTableFilterComposer(
            $db: $db,
            $table: $db.taskLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> taskSessionsRefs(
    Expression<bool> Function($$TaskSessionsTableFilterComposer f) f,
  ) {
    final $$TaskSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskSessions,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskSessionsTableFilterComposer(
            $db: $db,
            $table: $db.taskSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repeatType => $composableBuilder(
    column: $table.repeatType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repeatInterval => $composableBuilder(
    column: $table.repeatInterval,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repeatDaysMask => $composableBuilder(
    column: $table.repeatDaysMask,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackingMode => $composableBuilder(
    column: $table.trackingMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetDurationMinutes => $composableBuilder(
    column: $table.targetDurationMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconKey => $composableBuilder(
    column: $table.iconKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get iconCodePoint => $composableBuilder(
    column: $table.iconCodePoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledTimeMinutes => $composableBuilder(
    column: $table.scheduledTimeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endTimeMinutes => $composableBuilder(
    column: $table.endTimeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TasksTableOrderingComposer get parentId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<TaskStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RepeatType?, String> get repeatType =>
      $composableBuilder(
        column: $table.repeatType,
        builder: (column) => column,
      );

  GeneratedColumn<int> get repeatInterval => $composableBuilder(
    column: $table.repeatInterval,
    builder: (column) => column,
  );

  GeneratedColumn<int> get repeatDaysMask => $composableBuilder(
    column: $table.repeatDaysMask,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<TrackingMode, String> get trackingMode =>
      $composableBuilder(
        column: $table.trackingMode,
        builder: (column) => column,
      );

  GeneratedColumn<int> get targetDurationMinutes => $composableBuilder(
    column: $table.targetDurationMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get iconKey =>
      $composableBuilder(column: $table.iconKey, builder: (column) => column);

  GeneratedColumn<int> get iconCodePoint => $composableBuilder(
    column: $table.iconCodePoint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scheduledTimeMinutes => $composableBuilder(
    column: $table.scheduledTimeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endTimeMinutes => $composableBuilder(
    column: $table.endTimeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$TasksTableAnnotationComposer get parentId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> taskLogsRefs<T extends Object>(
    Expression<T> Function($$TaskLogsTableAnnotationComposer a) f,
  ) {
    final $$TaskLogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskLogs,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskLogsTableAnnotationComposer(
            $db: $db,
            $table: $db.taskLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> taskSessionsRefs<T extends Object>(
    Expression<T> Function($$TaskSessionsTableAnnotationComposer a) f,
  ) {
    final $$TaskSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskSessions,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.taskSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          Task,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (Task, $$TasksTableReferences),
          Task,
          PrefetchHooks Function({
            bool parentId,
            bool taskLogsRefs,
            bool taskSessionsRefs,
          })
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> uid = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int?> parentId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<TaskStatus> status = const Value.absent(),
                Value<RepeatType?> repeatType = const Value.absent(),
                Value<int?> repeatInterval = const Value.absent(),
                Value<int?> repeatDaysMask = const Value.absent(),
                Value<TrackingMode> trackingMode = const Value.absent(),
                Value<int?> targetDurationMinutes = const Value.absent(),
                Value<double?> targetValue = const Value.absent(),
                Value<String?> iconKey = const Value.absent(),
                Value<int?> iconCodePoint = const Value.absent(),
                Value<int?> colorValue = const Value.absent(),
                Value<int?> scheduledTimeMinutes = const Value.absent(),
                Value<int?> endTimeMinutes = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                uid: uid,
                dirty: dirty,
                parentId: parentId,
                title: title,
                description: description,
                status: status,
                repeatType: repeatType,
                repeatInterval: repeatInterval,
                repeatDaysMask: repeatDaysMask,
                trackingMode: trackingMode,
                targetDurationMinutes: targetDurationMinutes,
                targetValue: targetValue,
                iconKey: iconKey,
                iconCodePoint: iconCodePoint,
                colorValue: colorValue,
                scheduledTimeMinutes: scheduledTimeMinutes,
                endTimeMinutes: endTimeMinutes,
                startDate: startDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> uid = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int?> parentId = const Value.absent(),
                required String title,
                Value<String?> description = const Value.absent(),
                Value<TaskStatus> status = const Value.absent(),
                Value<RepeatType?> repeatType = const Value.absent(),
                Value<int?> repeatInterval = const Value.absent(),
                Value<int?> repeatDaysMask = const Value.absent(),
                Value<TrackingMode> trackingMode = const Value.absent(),
                Value<int?> targetDurationMinutes = const Value.absent(),
                Value<double?> targetValue = const Value.absent(),
                Value<String?> iconKey = const Value.absent(),
                Value<int?> iconCodePoint = const Value.absent(),
                Value<int?> colorValue = const Value.absent(),
                Value<int?> scheduledTimeMinutes = const Value.absent(),
                Value<int?> endTimeMinutes = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                uid: uid,
                dirty: dirty,
                parentId: parentId,
                title: title,
                description: description,
                status: status,
                repeatType: repeatType,
                repeatInterval: repeatInterval,
                repeatDaysMask: repeatDaysMask,
                trackingMode: trackingMode,
                targetDurationMinutes: targetDurationMinutes,
                targetValue: targetValue,
                iconKey: iconKey,
                iconCodePoint: iconCodePoint,
                colorValue: colorValue,
                scheduledTimeMinutes: scheduledTimeMinutes,
                endTimeMinutes: endTimeMinutes,
                startDate: startDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TasksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                parentId = false,
                taskLogsRefs = false,
                taskSessionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (taskLogsRefs) db.taskLogs,
                    if (taskSessionsRefs) db.taskSessions,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (parentId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.parentId,
                                    referencedTable: $$TasksTableReferences
                                        ._parentIdTable(db),
                                    referencedColumn: $$TasksTableReferences
                                        ._parentIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (taskLogsRefs)
                        await $_getPrefetchedData<Task, $TasksTable, TaskLog>(
                          currentTable: table,
                          referencedTable: $$TasksTableReferences
                              ._taskLogsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).taskLogsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (taskSessionsRefs)
                        await $_getPrefetchedData<
                          Task,
                          $TasksTable,
                          TaskSession
                        >(
                          currentTable: table,
                          referencedTable: $$TasksTableReferences
                              ._taskSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).taskSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      Task,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (Task, $$TasksTableReferences),
      Task,
      PrefetchHooks Function({
        bool parentId,
        bool taskLogsRefs,
        bool taskSessionsRefs,
      })
    >;
typedef $$TaskLogsTableCreateCompanionBuilder =
    TaskLogsCompanion Function({
      Value<int> id,
      required int taskId,
      required DateTime date,
      Value<bool> completed,
      Value<double?> value,
      Value<bool> dirty,
      Value<DateTime> updatedAt,
    });
typedef $$TaskLogsTableUpdateCompanionBuilder =
    TaskLogsCompanion Function({
      Value<int> id,
      Value<int> taskId,
      Value<DateTime> date,
      Value<bool> completed,
      Value<double?> value,
      Value<bool> dirty,
      Value<DateTime> updatedAt,
    });

final class $$TaskLogsTableReferences
    extends BaseReferences<_$AppDatabase, $TaskLogsTable, TaskLog> {
  $$TaskLogsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TasksTable _taskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias('task_logs__task_id__tasks__id');

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<int>('task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskLogsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskLogsTable> {
  $$TaskLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskLogsTable> {
  $$TaskLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskLogsTable> {
  $$TaskLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<double> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskLogsTable,
          TaskLog,
          $$TaskLogsTableFilterComposer,
          $$TaskLogsTableOrderingComposer,
          $$TaskLogsTableAnnotationComposer,
          $$TaskLogsTableCreateCompanionBuilder,
          $$TaskLogsTableUpdateCompanionBuilder,
          (TaskLog, $$TaskLogsTableReferences),
          TaskLog,
          PrefetchHooks Function({bool taskId})
        > {
  $$TaskLogsTableTableManager(_$AppDatabase db, $TaskLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> taskId = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<double?> value = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TaskLogsCompanion(
                id: id,
                taskId: taskId,
                date: date,
                completed: completed,
                value: value,
                dirty: dirty,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int taskId,
                required DateTime date,
                Value<bool> completed = const Value.absent(),
                Value<double?> value = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TaskLogsCompanion.insert(
                id: id,
                taskId: taskId,
                date: date,
                completed: completed,
                value: value,
                dirty: dirty,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TaskLogsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable: $$TaskLogsTableReferences
                                    ._taskIdTable(db),
                                referencedColumn: $$TaskLogsTableReferences
                                    ._taskIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TaskLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskLogsTable,
      TaskLog,
      $$TaskLogsTableFilterComposer,
      $$TaskLogsTableOrderingComposer,
      $$TaskLogsTableAnnotationComposer,
      $$TaskLogsTableCreateCompanionBuilder,
      $$TaskLogsTableUpdateCompanionBuilder,
      (TaskLog, $$TaskLogsTableReferences),
      TaskLog,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$TaskSessionsTableCreateCompanionBuilder =
    TaskSessionsCompanion Function({
      Value<int> id,
      required int taskId,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      Value<int?> durationSeconds,
    });
typedef $$TaskSessionsTableUpdateCompanionBuilder =
    TaskSessionsCompanion Function({
      Value<int> id,
      Value<int> taskId,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<int?> durationSeconds,
    });

final class $$TaskSessionsTableReferences
    extends BaseReferences<_$AppDatabase, $TaskSessionsTable, TaskSession> {
  $$TaskSessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TasksTable _taskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias('task_sessions__task_id__tasks__id');

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<int>('task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskSessionsTable> {
  $$TaskSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskSessionsTable> {
  $$TaskSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskSessionsTable> {
  $$TaskSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskSessionsTable,
          TaskSession,
          $$TaskSessionsTableFilterComposer,
          $$TaskSessionsTableOrderingComposer,
          $$TaskSessionsTableAnnotationComposer,
          $$TaskSessionsTableCreateCompanionBuilder,
          $$TaskSessionsTableUpdateCompanionBuilder,
          (TaskSession, $$TaskSessionsTableReferences),
          TaskSession,
          PrefetchHooks Function({bool taskId})
        > {
  $$TaskSessionsTableTableManager(_$AppDatabase db, $TaskSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> taskId = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
              }) => TaskSessionsCompanion(
                id: id,
                taskId: taskId,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int taskId,
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
              }) => TaskSessionsCompanion.insert(
                id: id,
                taskId: taskId,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TaskSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable: $$TaskSessionsTableReferences
                                    ._taskIdTable(db),
                                referencedColumn: $$TaskSessionsTableReferences
                                    ._taskIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TaskSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskSessionsTable,
      TaskSession,
      $$TaskSessionsTableFilterComposer,
      $$TaskSessionsTableOrderingComposer,
      $$TaskSessionsTableAnnotationComposer,
      $$TaskSessionsTableCreateCompanionBuilder,
      $$TaskSessionsTableUpdateCompanionBuilder,
      (TaskSession, $$TaskSessionsTableReferences),
      TaskSession,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      Value<int> id,
      required String title,
      Value<String?> description,
      required DateTime startDate,
      Value<DateTime?> endDate,
      Value<EventType> type,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String?> description,
      Value<DateTime> startDate,
      Value<DateTime?> endDate,
      Value<EventType> type,
    });

class $$EventsTableFilterComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EventType, EventType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$EventsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EventType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventsTable,
          Event,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (Event, BaseReferences<_$AppDatabase, $EventsTable, Event>),
          Event,
          PrefetchHooks Function()
        > {
  $$EventsTableTableManager(_$AppDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<EventType> type = const Value.absent(),
              }) => EventsCompanion(
                id: id,
                title: title,
                description: description,
                startDate: startDate,
                endDate: endDate,
                type: type,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                Value<String?> description = const Value.absent(),
                required DateTime startDate,
                Value<DateTime?> endDate = const Value.absent(),
                Value<EventType> type = const Value.absent(),
              }) => EventsCompanion.insert(
                id: id,
                title: title,
                description: description,
                startDate: startDate,
                endDate: endDate,
                type: type,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventsTable,
      Event,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (Event, BaseReferences<_$AppDatabase, $EventsTable, Event>),
      Event,
      PrefetchHooks Function()
    >;
typedef $$DiaryEntriesTableCreateCompanionBuilder =
    DiaryEntriesCompanion Function({
      Value<int> id,
      Value<String?> uid,
      Value<bool> dirty,
      Value<String> title,
      Value<String> body,
      Value<String?> coverImage,
      Value<String> images,
      Value<bool> isFavorite,
      Value<DiaryEntryStatus> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$DiaryEntriesTableUpdateCompanionBuilder =
    DiaryEntriesCompanion Function({
      Value<int> id,
      Value<String?> uid,
      Value<bool> dirty,
      Value<String> title,
      Value<String> body,
      Value<String?> coverImage,
      Value<String> images,
      Value<bool> isFavorite,
      Value<DiaryEntryStatus> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$DiaryEntriesTableReferences
    extends BaseReferences<_$AppDatabase, $DiaryEntriesTable, DiaryEntry> {
  $$DiaryEntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DiaryEntryMoodsTable, List<DiaryEntryMood>>
  _diaryEntryMoodsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diaryEntryMoods,
    aliasName: 'diary_entries__id__diary_entry_moods__entry_id',
  );

  $$DiaryEntryMoodsTableProcessedTableManager get diaryEntryMoodsRefs {
    final manager = $$DiaryEntryMoodsTableTableManager(
      $_db,
      $_db.diaryEntryMoods,
    ).filter((f) => f.entryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _diaryEntryMoodsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DiaryEntryTagsTable, List<DiaryEntryTag>>
  _diaryEntryTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diaryEntryTags,
    aliasName: 'diary_entries__id__diary_entry_tags__entry_id',
  );

  $$DiaryEntryTagsTableProcessedTableManager get diaryEntryTagsRefs {
    final manager = $$DiaryEntryTagsTableTableManager(
      $_db,
      $_db.diaryEntryTags,
    ).filter((f) => f.entryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_diaryEntryTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DiaryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $DiaryEntriesTable> {
  $$DiaryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get images => $composableBuilder(
    column: $table.images,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DiaryEntryStatus, DiaryEntryStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> diaryEntryMoodsRefs(
    Expression<bool> Function($$DiaryEntryMoodsTableFilterComposer f) f,
  ) {
    final $$DiaryEntryMoodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diaryEntryMoods,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntryMoodsTableFilterComposer(
            $db: $db,
            $table: $db.diaryEntryMoods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> diaryEntryTagsRefs(
    Expression<bool> Function($$DiaryEntryTagsTableFilterComposer f) f,
  ) {
    final $$DiaryEntryTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diaryEntryTags,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntryTagsTableFilterComposer(
            $db: $db,
            $table: $db.diaryEntryTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DiaryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $DiaryEntriesTable> {
  $$DiaryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get images => $composableBuilder(
    column: $table.images,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DiaryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiaryEntriesTable> {
  $$DiaryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get images =>
      $composableBuilder(column: $table.images, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DiaryEntryStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> diaryEntryMoodsRefs<T extends Object>(
    Expression<T> Function($$DiaryEntryMoodsTableAnnotationComposer a) f,
  ) {
    final $$DiaryEntryMoodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diaryEntryMoods,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntryMoodsTableAnnotationComposer(
            $db: $db,
            $table: $db.diaryEntryMoods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> diaryEntryTagsRefs<T extends Object>(
    Expression<T> Function($$DiaryEntryTagsTableAnnotationComposer a) f,
  ) {
    final $$DiaryEntryTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diaryEntryTags,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntryTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.diaryEntryTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DiaryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiaryEntriesTable,
          DiaryEntry,
          $$DiaryEntriesTableFilterComposer,
          $$DiaryEntriesTableOrderingComposer,
          $$DiaryEntriesTableAnnotationComposer,
          $$DiaryEntriesTableCreateCompanionBuilder,
          $$DiaryEntriesTableUpdateCompanionBuilder,
          (DiaryEntry, $$DiaryEntriesTableReferences),
          DiaryEntry,
          PrefetchHooks Function({
            bool diaryEntryMoodsRefs,
            bool diaryEntryTagsRefs,
          })
        > {
  $$DiaryEntriesTableTableManager(_$AppDatabase db, $DiaryEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiaryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiaryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiaryEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> uid = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> coverImage = const Value.absent(),
                Value<String> images = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<DiaryEntryStatus> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DiaryEntriesCompanion(
                id: id,
                uid: uid,
                dirty: dirty,
                title: title,
                body: body,
                coverImage: coverImage,
                images: images,
                isFavorite: isFavorite,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> uid = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> coverImage = const Value.absent(),
                Value<String> images = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<DiaryEntryStatus> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DiaryEntriesCompanion.insert(
                id: id,
                uid: uid,
                dirty: dirty,
                title: title,
                body: body,
                coverImage: coverImage,
                images: images,
                isFavorite: isFavorite,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiaryEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({diaryEntryMoodsRefs = false, diaryEntryTagsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (diaryEntryMoodsRefs) db.diaryEntryMoods,
                    if (diaryEntryTagsRefs) db.diaryEntryTags,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (diaryEntryMoodsRefs)
                        await $_getPrefetchedData<
                          DiaryEntry,
                          $DiaryEntriesTable,
                          DiaryEntryMood
                        >(
                          currentTable: table,
                          referencedTable: $$DiaryEntriesTableReferences
                              ._diaryEntryMoodsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DiaryEntriesTableReferences(
                                db,
                                table,
                                p0,
                              ).diaryEntryMoodsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.entryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (diaryEntryTagsRefs)
                        await $_getPrefetchedData<
                          DiaryEntry,
                          $DiaryEntriesTable,
                          DiaryEntryTag
                        >(
                          currentTable: table,
                          referencedTable: $$DiaryEntriesTableReferences
                              ._diaryEntryTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DiaryEntriesTableReferences(
                                db,
                                table,
                                p0,
                              ).diaryEntryTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.entryId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$DiaryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiaryEntriesTable,
      DiaryEntry,
      $$DiaryEntriesTableFilterComposer,
      $$DiaryEntriesTableOrderingComposer,
      $$DiaryEntriesTableAnnotationComposer,
      $$DiaryEntriesTableCreateCompanionBuilder,
      $$DiaryEntriesTableUpdateCompanionBuilder,
      (DiaryEntry, $$DiaryEntriesTableReferences),
      DiaryEntry,
      PrefetchHooks Function({
        bool diaryEntryMoodsRefs,
        bool diaryEntryTagsRefs,
      })
    >;
typedef $$NoteMoodsTableCreateCompanionBuilder =
    NoteMoodsCompanion Function({
      Value<int> id,
      Value<String?> uid,
      Value<bool> dirty,
      required String name,
      required String emoji,
      Value<DateTime> createdAt,
    });
typedef $$NoteMoodsTableUpdateCompanionBuilder =
    NoteMoodsCompanion Function({
      Value<int> id,
      Value<String?> uid,
      Value<bool> dirty,
      Value<String> name,
      Value<String> emoji,
      Value<DateTime> createdAt,
    });

final class $$NoteMoodsTableReferences
    extends BaseReferences<_$AppDatabase, $NoteMoodsTable, NoteMood> {
  $$NoteMoodsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DiaryEntryMoodsTable, List<DiaryEntryMood>>
  _diaryEntryMoodsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diaryEntryMoods,
    aliasName: 'note_moods__id__diary_entry_moods__mood_id',
  );

  $$DiaryEntryMoodsTableProcessedTableManager get diaryEntryMoodsRefs {
    final manager = $$DiaryEntryMoodsTableTableManager(
      $_db,
      $_db.diaryEntryMoods,
    ).filter((f) => f.moodId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _diaryEntryMoodsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NoteMoodsTableFilterComposer
    extends Composer<_$AppDatabase, $NoteMoodsTable> {
  $$NoteMoodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> diaryEntryMoodsRefs(
    Expression<bool> Function($$DiaryEntryMoodsTableFilterComposer f) f,
  ) {
    final $$DiaryEntryMoodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diaryEntryMoods,
      getReferencedColumn: (t) => t.moodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntryMoodsTableFilterComposer(
            $db: $db,
            $table: $db.diaryEntryMoods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NoteMoodsTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteMoodsTable> {
  $$NoteMoodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteMoodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteMoodsTable> {
  $$NoteMoodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> diaryEntryMoodsRefs<T extends Object>(
    Expression<T> Function($$DiaryEntryMoodsTableAnnotationComposer a) f,
  ) {
    final $$DiaryEntryMoodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diaryEntryMoods,
      getReferencedColumn: (t) => t.moodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntryMoodsTableAnnotationComposer(
            $db: $db,
            $table: $db.diaryEntryMoods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NoteMoodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteMoodsTable,
          NoteMood,
          $$NoteMoodsTableFilterComposer,
          $$NoteMoodsTableOrderingComposer,
          $$NoteMoodsTableAnnotationComposer,
          $$NoteMoodsTableCreateCompanionBuilder,
          $$NoteMoodsTableUpdateCompanionBuilder,
          (NoteMood, $$NoteMoodsTableReferences),
          NoteMood,
          PrefetchHooks Function({bool diaryEntryMoodsRefs})
        > {
  $$NoteMoodsTableTableManager(_$AppDatabase db, $NoteMoodsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteMoodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteMoodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteMoodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> uid = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => NoteMoodsCompanion(
                id: id,
                uid: uid,
                dirty: dirty,
                name: name,
                emoji: emoji,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> uid = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                required String name,
                required String emoji,
                Value<DateTime> createdAt = const Value.absent(),
              }) => NoteMoodsCompanion.insert(
                id: id,
                uid: uid,
                dirty: dirty,
                name: name,
                emoji: emoji,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$NoteMoodsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({diaryEntryMoodsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (diaryEntryMoodsRefs) db.diaryEntryMoods,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (diaryEntryMoodsRefs)
                    await $_getPrefetchedData<
                      NoteMood,
                      $NoteMoodsTable,
                      DiaryEntryMood
                    >(
                      currentTable: table,
                      referencedTable: $$NoteMoodsTableReferences
                          ._diaryEntryMoodsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$NoteMoodsTableReferences(
                            db,
                            table,
                            p0,
                          ).diaryEntryMoodsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.moodId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NoteMoodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteMoodsTable,
      NoteMood,
      $$NoteMoodsTableFilterComposer,
      $$NoteMoodsTableOrderingComposer,
      $$NoteMoodsTableAnnotationComposer,
      $$NoteMoodsTableCreateCompanionBuilder,
      $$NoteMoodsTableUpdateCompanionBuilder,
      (NoteMood, $$NoteMoodsTableReferences),
      NoteMood,
      PrefetchHooks Function({bool diaryEntryMoodsRefs})
    >;
typedef $$NoteTagsTableCreateCompanionBuilder =
    NoteTagsCompanion Function({
      Value<int> id,
      Value<String?> uid,
      Value<bool> dirty,
      required String name,
      Value<String> colorKey,
      Value<DateTime> createdAt,
    });
typedef $$NoteTagsTableUpdateCompanionBuilder =
    NoteTagsCompanion Function({
      Value<int> id,
      Value<String?> uid,
      Value<bool> dirty,
      Value<String> name,
      Value<String> colorKey,
      Value<DateTime> createdAt,
    });

final class $$NoteTagsTableReferences
    extends BaseReferences<_$AppDatabase, $NoteTagsTable, NoteTag> {
  $$NoteTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DiaryEntryTagsTable, List<DiaryEntryTag>>
  _diaryEntryTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diaryEntryTags,
    aliasName: 'note_tags__id__diary_entry_tags__tag_id',
  );

  $$DiaryEntryTagsTableProcessedTableManager get diaryEntryTagsRefs {
    final manager = $$DiaryEntryTagsTableTableManager(
      $_db,
      $_db.diaryEntryTags,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_diaryEntryTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NoteTagsTableFilterComposer
    extends Composer<_$AppDatabase, $NoteTagsTable> {
  $$NoteTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorKey => $composableBuilder(
    column: $table.colorKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> diaryEntryTagsRefs(
    Expression<bool> Function($$DiaryEntryTagsTableFilterComposer f) f,
  ) {
    final $$DiaryEntryTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diaryEntryTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntryTagsTableFilterComposer(
            $db: $db,
            $table: $db.diaryEntryTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NoteTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteTagsTable> {
  $$NoteTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorKey => $composableBuilder(
    column: $table.colorKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteTagsTable> {
  $$NoteTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorKey =>
      $composableBuilder(column: $table.colorKey, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> diaryEntryTagsRefs<T extends Object>(
    Expression<T> Function($$DiaryEntryTagsTableAnnotationComposer a) f,
  ) {
    final $$DiaryEntryTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diaryEntryTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntryTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.diaryEntryTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NoteTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteTagsTable,
          NoteTag,
          $$NoteTagsTableFilterComposer,
          $$NoteTagsTableOrderingComposer,
          $$NoteTagsTableAnnotationComposer,
          $$NoteTagsTableCreateCompanionBuilder,
          $$NoteTagsTableUpdateCompanionBuilder,
          (NoteTag, $$NoteTagsTableReferences),
          NoteTag,
          PrefetchHooks Function({bool diaryEntryTagsRefs})
        > {
  $$NoteTagsTableTableManager(_$AppDatabase db, $NoteTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> uid = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> colorKey = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => NoteTagsCompanion(
                id: id,
                uid: uid,
                dirty: dirty,
                name: name,
                colorKey: colorKey,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> uid = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                required String name,
                Value<String> colorKey = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => NoteTagsCompanion.insert(
                id: id,
                uid: uid,
                dirty: dirty,
                name: name,
                colorKey: colorKey,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$NoteTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({diaryEntryTagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (diaryEntryTagsRefs) db.diaryEntryTags,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (diaryEntryTagsRefs)
                    await $_getPrefetchedData<
                      NoteTag,
                      $NoteTagsTable,
                      DiaryEntryTag
                    >(
                      currentTable: table,
                      referencedTable: $$NoteTagsTableReferences
                          ._diaryEntryTagsRefsTable(db),
                      managerFromTypedResult: (p0) => $$NoteTagsTableReferences(
                        db,
                        table,
                        p0,
                      ).diaryEntryTagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NoteTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteTagsTable,
      NoteTag,
      $$NoteTagsTableFilterComposer,
      $$NoteTagsTableOrderingComposer,
      $$NoteTagsTableAnnotationComposer,
      $$NoteTagsTableCreateCompanionBuilder,
      $$NoteTagsTableUpdateCompanionBuilder,
      (NoteTag, $$NoteTagsTableReferences),
      NoteTag,
      PrefetchHooks Function({bool diaryEntryTagsRefs})
    >;
typedef $$DiaryEntryMoodsTableCreateCompanionBuilder =
    DiaryEntryMoodsCompanion Function({
      required int entryId,
      required int moodId,
      Value<int> rowid,
    });
typedef $$DiaryEntryMoodsTableUpdateCompanionBuilder =
    DiaryEntryMoodsCompanion Function({
      Value<int> entryId,
      Value<int> moodId,
      Value<int> rowid,
    });

final class $$DiaryEntryMoodsTableReferences
    extends
        BaseReferences<_$AppDatabase, $DiaryEntryMoodsTable, DiaryEntryMood> {
  $$DiaryEntryMoodsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DiaryEntriesTable _entryIdTable(_$AppDatabase db) => db.diaryEntries
      .createAlias('diary_entry_moods__entry_id__diary_entries__id');

  $$DiaryEntriesTableProcessedTableManager get entryId {
    final $_column = $_itemColumn<int>('entry_id')!;

    final manager = $$DiaryEntriesTableTableManager(
      $_db,
      $_db.diaryEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_entryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $NoteMoodsTable _moodIdTable(_$AppDatabase db) =>
      db.noteMoods.createAlias('diary_entry_moods__mood_id__note_moods__id');

  $$NoteMoodsTableProcessedTableManager get moodId {
    final $_column = $_itemColumn<int>('mood_id')!;

    final manager = $$NoteMoodsTableTableManager(
      $_db,
      $_db.noteMoods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_moodIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DiaryEntryMoodsTableFilterComposer
    extends Composer<_$AppDatabase, $DiaryEntryMoodsTable> {
  $$DiaryEntryMoodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$DiaryEntriesTableFilterComposer get entryId {
    final $$DiaryEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.diaryEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntriesTableFilterComposer(
            $db: $db,
            $table: $db.diaryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NoteMoodsTableFilterComposer get moodId {
    final $$NoteMoodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.moodId,
      referencedTable: $db.noteMoods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteMoodsTableFilterComposer(
            $db: $db,
            $table: $db.noteMoods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiaryEntryMoodsTableOrderingComposer
    extends Composer<_$AppDatabase, $DiaryEntryMoodsTable> {
  $$DiaryEntryMoodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$DiaryEntriesTableOrderingComposer get entryId {
    final $$DiaryEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.diaryEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.diaryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NoteMoodsTableOrderingComposer get moodId {
    final $$NoteMoodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.moodId,
      referencedTable: $db.noteMoods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteMoodsTableOrderingComposer(
            $db: $db,
            $table: $db.noteMoods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiaryEntryMoodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiaryEntryMoodsTable> {
  $$DiaryEntryMoodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$DiaryEntriesTableAnnotationComposer get entryId {
    final $$DiaryEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.diaryEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.diaryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NoteMoodsTableAnnotationComposer get moodId {
    final $$NoteMoodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.moodId,
      referencedTable: $db.noteMoods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteMoodsTableAnnotationComposer(
            $db: $db,
            $table: $db.noteMoods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiaryEntryMoodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiaryEntryMoodsTable,
          DiaryEntryMood,
          $$DiaryEntryMoodsTableFilterComposer,
          $$DiaryEntryMoodsTableOrderingComposer,
          $$DiaryEntryMoodsTableAnnotationComposer,
          $$DiaryEntryMoodsTableCreateCompanionBuilder,
          $$DiaryEntryMoodsTableUpdateCompanionBuilder,
          (DiaryEntryMood, $$DiaryEntryMoodsTableReferences),
          DiaryEntryMood,
          PrefetchHooks Function({bool entryId, bool moodId})
        > {
  $$DiaryEntryMoodsTableTableManager(
    _$AppDatabase db,
    $DiaryEntryMoodsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiaryEntryMoodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiaryEntryMoodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiaryEntryMoodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> entryId = const Value.absent(),
                Value<int> moodId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiaryEntryMoodsCompanion(
                entryId: entryId,
                moodId: moodId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int entryId,
                required int moodId,
                Value<int> rowid = const Value.absent(),
              }) => DiaryEntryMoodsCompanion.insert(
                entryId: entryId,
                moodId: moodId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiaryEntryMoodsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entryId = false, moodId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (entryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.entryId,
                                referencedTable:
                                    $$DiaryEntryMoodsTableReferences
                                        ._entryIdTable(db),
                                referencedColumn:
                                    $$DiaryEntryMoodsTableReferences
                                        ._entryIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (moodId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.moodId,
                                referencedTable:
                                    $$DiaryEntryMoodsTableReferences
                                        ._moodIdTable(db),
                                referencedColumn:
                                    $$DiaryEntryMoodsTableReferences
                                        ._moodIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DiaryEntryMoodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiaryEntryMoodsTable,
      DiaryEntryMood,
      $$DiaryEntryMoodsTableFilterComposer,
      $$DiaryEntryMoodsTableOrderingComposer,
      $$DiaryEntryMoodsTableAnnotationComposer,
      $$DiaryEntryMoodsTableCreateCompanionBuilder,
      $$DiaryEntryMoodsTableUpdateCompanionBuilder,
      (DiaryEntryMood, $$DiaryEntryMoodsTableReferences),
      DiaryEntryMood,
      PrefetchHooks Function({bool entryId, bool moodId})
    >;
typedef $$DiaryEntryTagsTableCreateCompanionBuilder =
    DiaryEntryTagsCompanion Function({
      required int entryId,
      required int tagId,
      Value<int> rowid,
    });
typedef $$DiaryEntryTagsTableUpdateCompanionBuilder =
    DiaryEntryTagsCompanion Function({
      Value<int> entryId,
      Value<int> tagId,
      Value<int> rowid,
    });

final class $$DiaryEntryTagsTableReferences
    extends BaseReferences<_$AppDatabase, $DiaryEntryTagsTable, DiaryEntryTag> {
  $$DiaryEntryTagsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DiaryEntriesTable _entryIdTable(_$AppDatabase db) => db.diaryEntries
      .createAlias('diary_entry_tags__entry_id__diary_entries__id');

  $$DiaryEntriesTableProcessedTableManager get entryId {
    final $_column = $_itemColumn<int>('entry_id')!;

    final manager = $$DiaryEntriesTableTableManager(
      $_db,
      $_db.diaryEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_entryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $NoteTagsTable _tagIdTable(_$AppDatabase db) =>
      db.noteTags.createAlias('diary_entry_tags__tag_id__note_tags__id');

  $$NoteTagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<int>('tag_id')!;

    final manager = $$NoteTagsTableTableManager(
      $_db,
      $_db.noteTags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DiaryEntryTagsTableFilterComposer
    extends Composer<_$AppDatabase, $DiaryEntryTagsTable> {
  $$DiaryEntryTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$DiaryEntriesTableFilterComposer get entryId {
    final $$DiaryEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.diaryEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntriesTableFilterComposer(
            $db: $db,
            $table: $db.diaryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NoteTagsTableFilterComposer get tagId {
    final $$NoteTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.noteTags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTagsTableFilterComposer(
            $db: $db,
            $table: $db.noteTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiaryEntryTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $DiaryEntryTagsTable> {
  $$DiaryEntryTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$DiaryEntriesTableOrderingComposer get entryId {
    final $$DiaryEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.diaryEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.diaryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NoteTagsTableOrderingComposer get tagId {
    final $$NoteTagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.noteTags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTagsTableOrderingComposer(
            $db: $db,
            $table: $db.noteTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiaryEntryTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiaryEntryTagsTable> {
  $$DiaryEntryTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$DiaryEntriesTableAnnotationComposer get entryId {
    final $$DiaryEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.diaryEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.diaryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NoteTagsTableAnnotationComposer get tagId {
    final $$NoteTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.noteTags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.noteTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiaryEntryTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiaryEntryTagsTable,
          DiaryEntryTag,
          $$DiaryEntryTagsTableFilterComposer,
          $$DiaryEntryTagsTableOrderingComposer,
          $$DiaryEntryTagsTableAnnotationComposer,
          $$DiaryEntryTagsTableCreateCompanionBuilder,
          $$DiaryEntryTagsTableUpdateCompanionBuilder,
          (DiaryEntryTag, $$DiaryEntryTagsTableReferences),
          DiaryEntryTag,
          PrefetchHooks Function({bool entryId, bool tagId})
        > {
  $$DiaryEntryTagsTableTableManager(
    _$AppDatabase db,
    $DiaryEntryTagsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiaryEntryTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiaryEntryTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiaryEntryTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> entryId = const Value.absent(),
                Value<int> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiaryEntryTagsCompanion(
                entryId: entryId,
                tagId: tagId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int entryId,
                required int tagId,
                Value<int> rowid = const Value.absent(),
              }) => DiaryEntryTagsCompanion.insert(
                entryId: entryId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiaryEntryTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entryId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (entryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.entryId,
                                referencedTable: $$DiaryEntryTagsTableReferences
                                    ._entryIdTable(db),
                                referencedColumn:
                                    $$DiaryEntryTagsTableReferences
                                        ._entryIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable: $$DiaryEntryTagsTableReferences
                                    ._tagIdTable(db),
                                referencedColumn:
                                    $$DiaryEntryTagsTableReferences
                                        ._tagIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DiaryEntryTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiaryEntryTagsTable,
      DiaryEntryTag,
      $$DiaryEntryTagsTableFilterComposer,
      $$DiaryEntryTagsTableOrderingComposer,
      $$DiaryEntryTagsTableAnnotationComposer,
      $$DiaryEntryTagsTableCreateCompanionBuilder,
      $$DiaryEntryTagsTableUpdateCompanionBuilder,
      (DiaryEntryTag, $$DiaryEntryTagsTableReferences),
      DiaryEntryTag,
      PrefetchHooks Function({bool entryId, bool tagId})
    >;
typedef $$SyncTombstonesTableCreateCompanionBuilder =
    SyncTombstonesCompanion Function({
      required String sourceTable,
      required String uid,
      Value<DateTime> deletedAt,
      Value<int> rowid,
    });
typedef $$SyncTombstonesTableUpdateCompanionBuilder =
    SyncTombstonesCompanion Function({
      Value<String> sourceTable,
      Value<String> uid,
      Value<DateTime> deletedAt,
      Value<int> rowid,
    });

class $$SyncTombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceTable => $composableBuilder(
    column: $table.sourceTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncTombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceTable => $composableBuilder(
    column: $table.sourceTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncTombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceTable => $composableBuilder(
    column: $table.sourceTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$SyncTombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncTombstonesTable,
          SyncTombstone,
          $$SyncTombstonesTableFilterComposer,
          $$SyncTombstonesTableOrderingComposer,
          $$SyncTombstonesTableAnnotationComposer,
          $$SyncTombstonesTableCreateCompanionBuilder,
          $$SyncTombstonesTableUpdateCompanionBuilder,
          (
            SyncTombstone,
            BaseReferences<_$AppDatabase, $SyncTombstonesTable, SyncTombstone>,
          ),
          SyncTombstone,
          PrefetchHooks Function()
        > {
  $$SyncTombstonesTableTableManager(
    _$AppDatabase db,
    $SyncTombstonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncTombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncTombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncTombstonesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceTable = const Value.absent(),
                Value<String> uid = const Value.absent(),
                Value<DateTime> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncTombstonesCompanion(
                sourceTable: sourceTable,
                uid: uid,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceTable,
                required String uid,
                Value<DateTime> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncTombstonesCompanion.insert(
                sourceTable: sourceTable,
                uid: uid,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncTombstonesTable,
      SyncTombstone,
      $$SyncTombstonesTableFilterComposer,
      $$SyncTombstonesTableOrderingComposer,
      $$SyncTombstonesTableAnnotationComposer,
      $$SyncTombstonesTableCreateCompanionBuilder,
      $$SyncTombstonesTableUpdateCompanionBuilder,
      (
        SyncTombstone,
        BaseReferences<_$AppDatabase, $SyncTombstonesTable, SyncTombstone>,
      ),
      SyncTombstone,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$TaskLogsTableTableManager get taskLogs =>
      $$TaskLogsTableTableManager(_db, _db.taskLogs);
  $$TaskSessionsTableTableManager get taskSessions =>
      $$TaskSessionsTableTableManager(_db, _db.taskSessions);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$DiaryEntriesTableTableManager get diaryEntries =>
      $$DiaryEntriesTableTableManager(_db, _db.diaryEntries);
  $$NoteMoodsTableTableManager get noteMoods =>
      $$NoteMoodsTableTableManager(_db, _db.noteMoods);
  $$NoteTagsTableTableManager get noteTags =>
      $$NoteTagsTableTableManager(_db, _db.noteTags);
  $$DiaryEntryMoodsTableTableManager get diaryEntryMoods =>
      $$DiaryEntryMoodsTableTableManager(_db, _db.diaryEntryMoods);
  $$DiaryEntryTagsTableTableManager get diaryEntryTags =>
      $$DiaryEntryTagsTableTableManager(_db, _db.diaryEntryTags);
  $$SyncTombstonesTableTableManager get syncTombstones =>
      $$SyncTombstonesTableTableManager(_db, _db.syncTombstones);
}
