// 考试模型：记录一门考试的科目、时间、地点与座位信息
import 'user_override.dart';

/// 一场考试。
///
/// 原始字段来自插件，用户的修改放在 [userOverride] 中（例如改了考场或备注）。
class Exam {
  /// 考试唯一 ID，插件产出时建议 `"<插件ID>:<考试ID>"`。
  final String id;

  /// 考试科目名。
  final String name;

  /// 考试开始时间。
  final DateTime startTime;

  /// 考试结束时间，`null` 表示未知（由时长推算或仅知开考时间）。
  final DateTime? endTime;

  /// 考场地点。
  final String location;

  /// 座位号，可能为空字符串（教务未公布）。
  final String seatNumber;

  /// 考试形式，如 `"闭卷"` / `"开卷"` / `"机考"`。
  final String examType;

  /// 学分，与课程保持一致；未知为 0。
  final double unit;

  /// 考试时长（分钟），未知为 0。
  final int durationMinutes;

  /// 关联的课程 ID，用于从考试跳回课程详情；无关联为空字符串。
  final String courseId;

  /// 所属课程名（**Phase 8**）。
  ///
  /// 与 [courseId] 的分工：ID 用来跳转，名字用来**展示**。
  /// 之所以要单独存名字而不是"用 ID 去 `CourseProvider` 查"：
  /// 插件给的考试 `courseId` 与课程条目的 `id` 未必同构
  /// （学习通的课程条目 id 还带班级后缀），查不到时列表就成了一片空白。
  final String courseName;

  /// 补充说明（**Phase 8**）：插件给出的非结构化备注，如
  /// `"待做 · 完成任务点80%"`。
  ///
  /// 与 [UserOverride.note] 的区别：本字段是**插件原文**，
  /// 用户的备注在覆盖层里，展示时后者优先（见 [displayNote]）。
  final String note;

  /// 来源插件 ID，用户自建为 `'user'`。
  final String sourcePluginId;

  /// 提前提醒的分钟数，0 表示不提醒。
  final int remindMinutesBefore;

  /// 用户覆盖层，`null` 表示用户没有做过任何修改。
  final UserOverride? userOverride;

  const Exam({
    required this.id,
    required this.name,
    required this.startTime,
    this.endTime,
    this.location = '',
    this.seatNumber = '',
    this.examType = '',
    this.unit = 0,
    this.durationMinutes = 0,
    this.courseId = '',
    this.courseName = '',
    this.note = '',
    required this.sourcePluginId,
    this.remindMinutesBefore = 0,
    this.userOverride,
  });

  /// 从 JSON 构造，缺失或类型异常的字段使用安全默认值，不抛异常。
  factory Exam.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? overrideJson =
        _asStringMap(json['userOverride']);
    final DateTime startTime = _asDateTime(json['startTime']) ?? _epoch;
    return Exam(
      id: _asString(json['id']),
      name: _asString(json['name']),
      startTime: startTime,
      endTime: _asDateTime(json['endTime']),
      location: _asString(json['location']),
      seatNumber: _asString(json['seatNumber']),
      examType: _asString(json['examType']),
      unit: _asDouble(json['unit']),
      durationMinutes: _asInt(json['durationMinutes']),
      courseId: _asString(json['courseId']),
      courseName: _asString(json['courseName']),
      note: _asString(json['note']),
      sourcePluginId: _asString(json['sourcePluginId'], fallback: 'user'),
      remindMinutesBefore: _asInt(json['remindMinutesBefore']),
      userOverride:
          overrideJson == null ? null : UserOverride.fromJson(overrideJson),
    );
  }

  /// 是否为用户自建考试。
  bool get isUserCreated => sourcePluginId == 'user';

  /// 是否被用户隐藏。
  bool get isHidden => userOverride?.hidden ?? false;

  /// 展示用科目名。
  String get displayName => userOverride?.customName ?? name;

  /// 展示用考场地点。
  String get displayLocation => userOverride?.customLocation ?? location;

  /// 展示用开考时间。
  DateTime get displayStartTime => userOverride?.customTime ?? startTime;

  /// 展示用颜色，ARGB 整数；`null` 时由主题层分配。
  int? get displayColor => userOverride?.customColor;

  /// 展示用备注：用户写过备注就以用户的为准，否则用插件原文 [note]。
  String get displayNote {
    final String? custom = userOverride?.note;
    if (custom != null && custom.trim().isNotEmpty) return custom;
    return note;
  }

  /// 实际结束时间：优先用 [endTime]，否则由 [displayStartTime] + [durationMinutes] 推算。
  DateTime get effectiveEndTime =>
      endTime ?? displayStartTime.add(Duration(minutes: durationMinutes));

  /// 考试是否已经开始（相对于 [now]）。
  bool hasStarted(DateTime now) => !now.isBefore(displayStartTime);

  /// 距离考试开始还有多久；已开始返回 [Duration.zero]。
  Duration timeUntil(DateTime now) {
    if (hasStarted(now)) return Duration.zero;
    return displayStartTime.difference(now);
  }

  /// 距离考试的天数（向上取整），已开始返回 0。
  int daysUntil(DateTime now) {
    final Duration left = timeUntil(now);
    if (left == Duration.zero) return 0;
    return (left.inMinutes / (60 * 24)).ceil();
  }

  /// 序列化为可写入 Hive / JSON 的 Map。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'location': location,
      'seatNumber': seatNumber,
      'examType': examType,
      'unit': unit,
      'durationMinutes': durationMinutes,
      'courseId': courseId,
      'courseName': courseName,
      'note': note,
      'sourcePluginId': sourcePluginId,
      'remindMinutesBefore': remindMinutesBefore,
      'userOverride': userOverride?.toJson(),
    };
  }

  /// 复制并修改部分字段。[clearEndTime] / [clearUserOverride] 用于显式置空。
  Exam copyWith({
    String? id,
    String? name,
    DateTime? startTime,
    DateTime? endTime,
    String? location,
    String? seatNumber,
    String? examType,
    double? unit,
    int? durationMinutes,
    String? courseId,
    String? courseName,
    String? note,
    String? sourcePluginId,
    int? remindMinutesBefore,
    UserOverride? userOverride,
    bool clearEndTime = false,
    bool clearUserOverride = false,
  }) {
    return Exam(
      id: id ?? this.id,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      location: location ?? this.location,
      seatNumber: seatNumber ?? this.seatNumber,
      examType: examType ?? this.examType,
      unit: unit ?? this.unit,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      note: note ?? this.note,
      sourcePluginId: sourcePluginId ?? this.sourcePluginId,
      remindMinutesBefore: remindMinutesBefore ?? this.remindMinutesBefore,
      userOverride:
          clearUserOverride ? null : (userOverride ?? this.userOverride),
    );
  }

  @override
  String toString() => 'Exam(id: $id, name: $name, startTime: $startTime, '
      'endTime: $endTime, location: $location, seatNumber: $seatNumber, '
      'examType: $examType, unit: $unit, durationMinutes: $durationMinutes, '
      'courseId: $courseId, courseName: $courseName, note: $note, '
      'sourcePluginId: $sourcePluginId, '
      'remindMinutesBefore: $remindMinutesBefore, '
      'userOverride: $userOverride)';

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
}

/// 安全地把任意值转成 String。
String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

/// 安全地把任意值转成 int。
int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// 安全地把任意值转成 double。
double _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

/// 安全地把任意值转成 DateTime。
DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// 把 `Map`（键可能不是 String）安全地转成 `Map<String, dynamic>`，非 Map 返回 `null`。
Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is! Map) return null;
  final Map<String, dynamic> result = <String, dynamic>{};
  value.forEach((dynamic key, dynamic item) {
    if (key != null) result[key.toString()] = item;
  });
  return result;
}