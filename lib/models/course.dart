// 课程模型：课表的核心数据单元，由插件产出 + 用户覆盖层叠加展示
import 'time_place.dart';
import 'user_override.dart';

/// 用户自建课程的 [sourcePluginId] 固定值。
const String kUserSourcePluginId = 'user';

/// 一门课程。
///
/// 原始字段来自插件（或用户自建），**只读**；
/// 用户的修改全部放在 [userOverride] 里，二者分离存储。
/// 展示层应使用 `displayName` / `displayTeacher` / `displayColor` 等
/// `displayXxx` 取值，不要在 UI 里手写合并逻辑。
class Course {
  /// 课程唯一 ID。插件产出时建议用 `"<插件ID>:<教务课程号>"` 形式，
  /// 用户自建课程建议用 `"user:<时间戳>"`。
  final String id;

  /// 课程名。
  final String name;

  /// 任课教师，可能为空字符串。
  final String teacher;

  /// 学分/学时，如 `3.0`。
  final double unit;

  /// 课程类别，如 `"必修"` / `"选修"`。
  final String category;

  /// 上课时间地点列表，可能为空。
  final List<TimePlace> timePlaces;

  /// 来源插件 ID，用户自建为 [kUserSourcePluginId]。
  final String sourcePluginId;

  /// 所属学期 id（`SemesterConfig.id`）。空串表示"没打归属"。
  ///
  /// **空串的语义是"属于当前学期"**，不是"不属于任何学期"——这是为了让
  /// 多学期归档上线前的旧数据（全都没有这个字段）在升级后仍然显示在课表上。
  /// 真正需要"归档隔离"时由 `SemesterArchiveService` 在切换学期那一刻
  /// 给这些旧课程补上旧学期 id（见 `stampSemester`）。
  final String semesterId;

  /// 用户覆盖层，`null` 表示用户没有做过任何修改。
  final UserOverride? userOverride;

  const Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.unit,
    required this.category,
    required this.timePlaces,
    required this.sourcePluginId,
    this.semesterId = '',
    this.userOverride,
  });

  /// 是否已明确归属某个学期（旧数据为 `false`）。
  bool get hasSemester => semesterId.isNotEmpty;

  /// 从 JSON 构造，缺失或类型异常的字段使用安全默认值，不抛异常。
  factory Course.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? overrideJson =
        _asStringMap(json['userOverride']);
    return Course(
      id: _asString(json['id']),
      name: _asString(json['name']),
      teacher: _asString(json['teacher']),
      unit: _asDouble(json['unit'], fallback: 0),
      category: _asString(json['category']),
      timePlaces: _asTimePlaceList(json['timePlaces']),
      sourcePluginId:
          _asString(json['sourcePluginId'], fallback: kUserSourcePluginId),
      semesterId: _asString(json['semesterId']),
      userOverride:
          overrideJson == null ? null : UserOverride.fromJson(overrideJson),
    );
  }

  /// 是否为用户自建课程。
  bool get isUserCreated => sourcePluginId == kUserSourcePluginId;

  /// 是否被用户隐藏（隐藏后列表与课表都不展示，但数据保留）。
  bool get isHidden => userOverride?.hidden ?? false;

  /// 展示用课程名。
  String get displayName => userOverride?.customName ?? name;

  /// 展示用教师名。
  String get displayTeacher => userOverride?.customTeacher ?? teacher;

  /// 展示用时间地点列表（用户改过则用用户的）。
  List<TimePlace> get displayTimePlaces =>
      userOverride?.customTimePlaces ?? timePlaces;

  /// 展示用颜色，ARGB 整数。用户未指定时返回 `null`，
  /// 由主题层按课程名哈希分配默认色，模型层不硬编码颜色。
  int? get displayColor => userOverride?.customColor;

  /// 该课程是否在第 [week] 周有安排。
  bool isActiveInWeek(int week) =>
      displayTimePlaces.any((TimePlace tp) => tp.isActiveInWeek(week));

  /// 该课程是否属于学期 [semesterId]。
  ///
  /// 规则（与 `SemesterArchiveService.coursesOf` 一致，此处只做单条判断）：
  /// - 课程已打归属 → 严格相等；
  /// - 课程没有归属（旧数据）→ 只有 [currentSemesterId] 认领它。
  bool belongsToSemester(
    String semesterId, {
    required String currentSemesterId,
  }) {
    if (hasSemester) return this.semesterId == semesterId;
    return semesterId == currentSemesterId;
  }

  /// 序列化为可写入 Hive / JSON 的 Map。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'teacher': teacher,
      'unit': unit,
      'category': category,
      'timePlaces': timePlaces.map((TimePlace e) => e.toJson()).toList(),
      'sourcePluginId': sourcePluginId,
      'semesterId': semesterId,
      'userOverride': userOverride?.toJson(),
    };
  }

  /// 复制并修改部分字段。
  ///
  /// [clearUserOverride] 为 `true` 时把 [userOverride] 设回 `null`（丢弃全部覆盖）。
  Course copyWith({
    String? id,
    String? name,
    String? teacher,
    double? unit,
    String? category,
    List<TimePlace>? timePlaces,
    String? sourcePluginId,
    String? semesterId,
    UserOverride? userOverride,
    bool clearUserOverride = false,
  }) {
    return Course(
      id: id ?? this.id,
      name: name ?? this.name,
      teacher: teacher ?? this.teacher,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      timePlaces: timePlaces ?? this.timePlaces,
      sourcePluginId: sourcePluginId ?? this.sourcePluginId,
      semesterId: semesterId ?? this.semesterId,
      userOverride:
          clearUserOverride ? null : (userOverride ?? this.userOverride),
    );
  }

  @override
  String toString() => 'Course(id: $id, name: $name, teacher: $teacher, '
      'unit: $unit, category: $category, timePlaces: $timePlaces, '
      'sourcePluginId: $sourcePluginId, semesterId: $semesterId, '
      'userOverride: $userOverride)';
}

/// 安全地把任意值转成 String。
String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

/// 安全地把任意值转成 double。
double _asDouble(Object? value, {required double fallback}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? fallback;
  return fallback;
}

/// 安全地把任意值转成 `List<TimePlace>`，忽略非法元素，`null` 返回空列表。
List<TimePlace> _asTimePlaceList(Object? value) {
  if (value is! List) return const <TimePlace>[];
  final List<TimePlace> result = <TimePlace>[];
  for (final Object? item in value) {
    if (item is Map) {
      result.add(TimePlace.fromJson(_asStringMap(item)!));
    } else if (item is TimePlace) {
      result.add(item);
    }
  }
  return result;
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