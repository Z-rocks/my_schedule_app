// 用户覆盖层模型：保存用户对教务原始数据的修改，不污染原始字段
import 'time_place.dart';

/// 用户对某条原始数据（课程等）的覆盖层。
///
/// 展示时按 `userOverride?.customXxx ?? original.xxx` 叠加：
/// 字段为 `null` 表示"用户没有改这一项"，回落到原始值；
/// 字段非 `null` 表示"用户改过"，即使改成了空字符串也以覆盖层为准。
///
/// [hidden] 为 `true` 表示用户隐藏了这条数据（页面不展示），
/// 但原始数据仍然保留，撤销隐藏只需把它设回 `false`。
class UserOverride {
  /// 自定义课程名，`null` 表示未覆盖。
  final String? customName;

  /// 自定义教师名，`null` 表示未覆盖。
  final String? customTeacher;

  /// 自定义地点（考场 / 教室），`null` 表示未覆盖。
  /// 主要用于考试、作业等没有 [customTimePlaces] 概念的记录。
  final String? customLocation;

  /// 自定义时间（考试开考时间等），`null` 表示未覆盖。
  final DateTime? customTime;

  /// 自定义颜色，ARGB 整数，如 `0xFF1E88E5`；`null` 表示未覆盖。
  final int? customColor;

  /// 自定义完成状态（作业等可勾选的记录）；`null` 表示未覆盖、沿用原始值。
  final bool? customCompleted;

  /// 用户备注，`null` 表示没有备注。
  final String? note;

  /// 是否隐藏该条数据，默认 `false`。
  final bool hidden;

  /// 自定义时间地点列表，`null` 表示沿用原始安排；
  /// 空列表表示用户主动清空了所有安排。
  final List<TimePlace>? customTimePlaces;

  /// 最后一次修改时间。
  final DateTime updatedAt;

  const UserOverride({
    this.customName,
    this.customTeacher,
    this.customLocation,
    this.customTime,
    this.customColor,
    this.customCompleted,
    this.note,
    this.hidden = false,
    this.customTimePlaces,
    required this.updatedAt,
  });

  /// 从 JSON 构造，缺失或类型异常的字段使用安全默认值，不抛异常。
  factory UserOverride.fromJson(Map<String, dynamic> json) {
    return UserOverride(
      customName: _asNullableString(json['customName']),
      customTeacher: _asNullableString(json['customTeacher']),
      customLocation: _asNullableString(json['customLocation']),
      customTime: _asDateTime(json['customTime']),
      customColor: _asNullableInt(json['customColor']),
      customCompleted: _asNullableBool(json['customCompleted']),
      note: _asNullableString(json['note']),
      hidden: _asBool(json['hidden'], fallback: false),
      customTimePlaces: _asTimePlaceList(json['customTimePlaces']),
      updatedAt: _asDateTime(json['updatedAt']) ?? DateTime.now(),
    );
  }

  /// 是否为空覆盖层（用户什么都没改）。
  bool get isEmpty =>
      customName == null &&
      customTeacher == null &&
      customLocation == null &&
      customTime == null &&
      customColor == null &&
      customCompleted == null &&
      note == null &&
      !hidden &&
      customTimePlaces == null;

  /// 序列化为可写入 Hive / JSON 的 Map。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'customName': customName,
      'customTeacher': customTeacher,
      'customLocation': customLocation,
      'customTime': customTime?.toIso8601String(),
      'customColor': customColor,
      'customCompleted': customCompleted,
      'note': note,
      'hidden': hidden,
      'customTimePlaces':
          customTimePlaces?.map((TimePlace e) => e.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 复制并修改部分字段。
  ///
  /// 因为字段本身可为 `null`，这里用 `clearXxx` 布尔开关显式清空某个覆盖项：
  /// `clearCustomColor: true` 会把 [customColor] 设回 `null`（取消该覆盖）。
  UserOverride copyWith({
    String? customName,
    String? customTeacher,
    String? customLocation,
    DateTime? customTime,
    int? customColor,
    bool? customCompleted,
    String? note,
    bool? hidden,
    List<TimePlace>? customTimePlaces,
    DateTime? updatedAt,
    bool clearCustomName = false,
    bool clearCustomTeacher = false,
    bool clearCustomLocation = false,
    bool clearCustomTime = false,
    bool clearCustomColor = false,
    bool clearCustomCompleted = false,
    bool clearNote = false,
    bool clearCustomTimePlaces = false,
  }) {
    return UserOverride(
      customName: clearCustomName ? null : (customName ?? this.customName),
      customTeacher:
          clearCustomTeacher ? null : (customTeacher ?? this.customTeacher),
      customLocation:
          clearCustomLocation ? null : (customLocation ?? this.customLocation),
      customTime: clearCustomTime ? null : (customTime ?? this.customTime),
      customColor: clearCustomColor ? null : (customColor ?? this.customColor),
      customCompleted:
          clearCustomCompleted ? null : (customCompleted ?? this.customCompleted),
      note: clearNote ? null : (note ?? this.note),
      hidden: hidden ?? this.hidden,
      customTimePlaces: clearCustomTimePlaces
          ? null
          : (customTimePlaces ?? this.customTimePlaces),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'UserOverride(customName: $customName, '
      'customTeacher: $customTeacher, customLocation: $customLocation, '
      'customTime: $customTime, customColor: $customColor, '
      'customCompleted: $customCompleted, note: $note, '
      'hidden: $hidden, customTimePlaces: $customTimePlaces, '
      'updatedAt: $updatedAt)';
}

/// 安全地把任意值转成可空的 String。
String? _asNullableString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

/// 安全地把任意值转成可空的 int。
int? _asNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// 安全地把任意值转成 bool。
bool _asBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String text = value.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
  }
  return fallback;
}

/// 安全地把任意值转成可空的 bool，无法识别时返回 `null`。
bool? _asNullableBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String text = value.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
  }
  return null;
}

/// 安全地把任意值转成 DateTime。
DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// 安全地把任意值转成 `List<TimePlace>?`，`null` 保持为 `null`。
List<TimePlace>? _asTimePlaceList(Object? value) {
  if (value == null) return null;
  if (value is! List) return null;
  final List<TimePlace> result = <TimePlace>[];
  for (final Object? item in value) {
    if (item is Map) {
      result.add(TimePlace.fromJson(_asStringMap(item)));
    } else if (item is TimePlace) {
      result.add(item);
    }
  }
  return result;
}

/// 把 `Map`（键可能不是 String）安全地转成 `Map<String, dynamic>`。
Map<String, dynamic> _asStringMap(Map<dynamic, dynamic> map) {
  final Map<String, dynamic> result = <String, dynamic>{};
  map.forEach((dynamic key, dynamic value) {
    if (key != null) result[key.toString()] = value;
  });
  return result;
}