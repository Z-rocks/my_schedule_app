// 作业模型：记录一项作业的内容、截止时间与完成状态
import 'user_override.dart';

/// 一项作业。
///
/// 原始字段来自插件（教务 / 学习通），用户的修改与完成状态放在 [userOverride] 中。
class Homework {
  /// 作业唯一 ID，插件产出时建议 `"<插件ID>:<作业ID>"`。
  final String id;

  /// 作业标题。
  final String title;

  /// 作业详细要求，可能为空字符串。
  final String description;

  /// 所属课程名；知道课程 ID 时 [courseId] 更可靠。
  final String courseName;

  /// 关联的课程 ID，用于跳转；无关联为空字符串。
  final String courseId;

  /// 截止时间，`null` 表示无截止时间。
  final DateTime? deadline;

  /// 发布时间，`null` 表示未知。
  final DateTime? publishTime;

  /// 是否已完成（来自插件或用户的原始值）。
  final bool completed;

  /// 提交方式/状态原文，如 `"在线提交"` / `"未提交"`。
  final String submitStatus;

  /// 附件名称列表（不存二进制，只存文件名与下载地址）。
  final List<String> attachments;

  /// 来源插件 ID，用户自建为 `'user'`。
  final String sourcePluginId;

  /// 提前提醒的分钟数，0 表示不提醒。
  final int remindMinutesBefore;

  /// 用户覆盖层，`null` 表示用户没有做过任何修改。
  final UserOverride? userOverride;

  const Homework({
    required this.id,
    required this.title,
    this.description = '',
    this.courseName = '',
    this.courseId = '',
    this.deadline,
    this.publishTime,
    this.completed = false,
    this.submitStatus = '',
    this.attachments = const <String>[],
    required this.sourcePluginId,
    this.remindMinutesBefore = 0,
    this.userOverride,
  });

  /// 从 JSON 构造，缺失或类型异常的字段使用安全默认值，不抛异常。
  factory Homework.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? overrideJson =
        _asStringMap(json['userOverride']);
    return Homework(
      id: _asString(json['id']),
      title: _asString(json['title']),
      description: _asString(json['description']),
      courseName: _asString(json['courseName']),
      courseId: _asString(json['courseId']),
      deadline: _asDateTime(json['deadline']),
      publishTime: _asDateTime(json['publishTime']),
      completed: _asBool(json['completed']),
      submitStatus: _asString(json['submitStatus']),
      attachments: _asStringList(json['attachments']),
      sourcePluginId: _asString(json['sourcePluginId'], fallback: 'user'),
      remindMinutesBefore: _asInt(json['remindMinutesBefore']),
      userOverride:
          overrideJson == null ? null : UserOverride.fromJson(overrideJson),
    );
  }

  /// 是否为用户自建作业。
  bool get isUserCreated => sourcePluginId == 'user';

  /// 是否被用户隐藏。
  bool get isHidden => userOverride?.hidden ?? false;

  /// 展示用标题。
  String get displayTitle => userOverride?.customName ?? title;

  /// 展示用截止时间（用户可改期）。
  DateTime? get displayDeadline => userOverride?.customTime ?? deadline;

  /// 展示用颜色，ARGB 整数；`null` 时由主题层分配。
  int? get displayColor => userOverride?.customColor;

  /// 是否已完成：用户勾选过则以用户为准，否则用插件给的 [completed]。
  ///
  /// 用户的勾选状态存在覆盖层里，因此同步时不会被插件数据覆盖掉。
  bool get isCompleted => userOverride?.customCompleted ?? completed;

  /// 是否已逾期（相对于 [now]）。
  bool isOverdue(DateTime now) {
    final DateTime? due = displayDeadline;
    if (due == null || isCompleted) return false;
    return now.isAfter(due);
  }

  /// 距离截止还有多久；无截止时间返回 `null`，已逾期返回 [Duration.zero]。
  Duration? timeUntilDeadline(DateTime now) {
    final DateTime? due = displayDeadline;
    if (due == null) return null;
    final Duration left = due.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// 距离截止的天数（向上取整）；无截止时间或已逾期返回 0。
  int daysUntilDeadline(DateTime now) {
    final Duration? left = timeUntilDeadline(now);
    if (left == null || left == Duration.zero) return 0;
    return (left.inMinutes / (60 * 24)).ceil();
  }

  /// 序列化为可写入 Hive / JSON 的 Map。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'description': description,
      'courseName': courseName,
      'courseId': courseId,
      'deadline': deadline?.toIso8601String(),
      'publishTime': publishTime?.toIso8601String(),
      'completed': completed,
      'submitStatus': submitStatus,
      'attachments': attachments,
      'sourcePluginId': sourcePluginId,
      'remindMinutesBefore': remindMinutesBefore,
      'userOverride': userOverride?.toJson(),
    };
  }

  /// 复制并修改部分字段。[clearDeadline] / [clearUserOverride] 用于显式置空。
  Homework copyWith({
    String? id,
    String? title,
    String? description,
    String? courseName,
    String? courseId,
    DateTime? deadline,
    DateTime? publishTime,
    bool? completed,
    String? submitStatus,
    List<String>? attachments,
    String? sourcePluginId,
    int? remindMinutesBefore,
    UserOverride? userOverride,
    bool clearDeadline = false,
    bool clearPublishTime = false,
    bool clearUserOverride = false,
  }) {
    return Homework(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      courseName: courseName ?? this.courseName,
      courseId: courseId ?? this.courseId,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      publishTime: clearPublishTime ? null : (publishTime ?? this.publishTime),
      completed: completed ?? this.completed,
      submitStatus: submitStatus ?? this.submitStatus,
      attachments: attachments ?? this.attachments,
      sourcePluginId: sourcePluginId ?? this.sourcePluginId,
      remindMinutesBefore: remindMinutesBefore ?? this.remindMinutesBefore,
      userOverride:
          clearUserOverride ? null : (userOverride ?? this.userOverride),
    );
  }

  @override
  String toString() => 'Homework(id: $id, title: $title, '
      'description: $description, courseName: $courseName, '
      'courseId: $courseId, deadline: $deadline, publishTime: $publishTime, '
      'completed: $completed, submitStatus: $submitStatus, '
      'attachments: $attachments, sourcePluginId: $sourcePluginId, '
      'remindMinutesBefore: $remindMinutesBefore, '
      'userOverride: $userOverride)';
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

/// 安全地把任意值转成 bool。
bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String text = value.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
  }
  return false;
}

/// 安全地把任意值转成 DateTime。
DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// 安全地把任意值转成 `List<String>`，忽略无法转换的元素。
List<String> _asStringList(Object? value) {
  if (value is! List) return const <String>[];
  final List<String> result = <String>[];
  for (final Object? item in value) {
    if (item is String) {
      result.add(item);
    } else if (item != null) {
      result.add(item.toString());
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