// 消息模型：本地通知与模块内消息的统一载体
import 'sync_report.dart';

/// 消息类型，决定图标、分组与点击后的跳转目标。
enum MessageType {
  /// 上课提醒。
  course,

  /// 考试提醒。
  exam,

  /// 作业提醒 / 截止提醒。
  homework,

  /// 成绩公布。
  grade,

  /// 系统通知（同步结果、插件更新等）。
  system,

  /// 其他 / 未知类型。
  other;

  /// 从 JSON 中的字符串安全解析，无法识别时返回 [MessageType.other]。
  static MessageType fromName(Object? value) {
    if (value is MessageType) return value;
    if (value is! String) return MessageType.other;
    final String key = value.trim().toLowerCase();
    for (final MessageType type in MessageType.values) {
      if (type.name == key) return type;
    }
    return MessageType.other;
  }

  /// 用于展示的中文标签。
  String get label {
    switch (this) {
      case MessageType.course:
        return '上课提醒';
      case MessageType.exam:
        return '考试提醒';
      case MessageType.homework:
        return '作业提醒';
      case MessageType.grade:
        return '成绩通知';
      case MessageType.system:
        return '系统通知';
      case MessageType.other:
        return '其他消息';
    }
  }
}

/// 一条消息。
///
/// 由本地通知服务或插件产生，展示在"消息"模块中。
/// [targetId] 配合 [type] 决定点击后跳转到哪条课程 / 考试 / 作业。
class Message {
  /// 消息唯一 ID。
  final String id;

  /// 消息类型。
  final MessageType type;

  /// 消息标题。
  final String title;

  /// 消息正文。
  final String body;

  /// 产生时间。
  final DateTime createdAt;

  /// 是否已读，默认 `false`。
  final bool read;

  /// 关联目标 ID（课程 / 考试 / 作业的 ID）；无关联为空字符串。
  final String targetId;

  /// 来源插件 ID，内核自身产生为 `'system'`。
  final String sourcePluginId;

  /// 附加数据，供插件自由携带上下文；默认空 Map。
  final Map<String, dynamic> extra;

  const Message({
    required this.id,
    required this.type,
    required this.title,
    this.body = '',
    required this.createdAt,
    this.read = false,
    this.targetId = '',
    this.sourcePluginId = 'system',
    this.extra = const <String, dynamic>{},
  });

  /// 从 JSON 构造，缺失或类型异常的字段使用安全默认值，不抛异常。
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: _asString(json['id']),
      type: MessageType.fromName(json['type']),
      title: _asString(json['title']),
      body: _asString(json['body']),
      createdAt: _asDateTime(json['createdAt']) ?? DateTime.now(),
      read: _asBool(json['read']),
      targetId: _asString(json['targetId']),
      sourcePluginId: _asString(json['sourcePluginId'], fallback: 'system'),
      extra: _asStringMap(json['extra']) ?? const <String, dynamic>{},
    );
  }

  /// 是否未读（与 [read] 相反，便于列表过滤）。
  bool get isUnread => !read;

  /// 是否为系统消息。
  bool get isSystem => sourcePluginId == 'system';

  /// 该消息是否可以跳转到具体条目。
  bool get hasTarget => targetId.isNotEmpty;

  /// 是否在 [now] 的今天之内。
  bool isToday(DateTime now) =>
      createdAt.year == now.year &&
      createdAt.month == now.month &&
      createdAt.day == now.day;

  /// 由一次同步结果构造一条系统消息（**Phase 7**）。
  ///
  /// 只读 [SyncReport] 的公开字段——报告里的统计全部是内核自己算的，
  /// 不含任何学校信息（CONTEXT 3.1）。
  ///
  /// [itemLabel] / [itemUnit] 是**被同步条目的量词**（Phase 8 新增）：
  /// 课程是「门课程」，作业是「份作业」，考试是「场考试」。
  /// 默认值与 Phase 7 完全一致，因此课程同步的文案没有任何变化。
  ///
  /// 幂等：id 用 `pluginId + 秒级时间戳`。`CourseSyncService` 会重试，
  /// 但重试发生在同一次点击内（同一秒），所以只会得到一条消息。
  factory Message.fromSyncReport({
    required SyncReport report,
    required String pluginName,
    DateTime? now,
    String itemLabel = '课程',
    String itemUnit = '门',
  }) {
    final DateTime created = now ?? DateTime.now();
    final List<String> lines = <String>[];
    final String counted = '$itemUnit$itemLabel';

    if (!report.isSuccess) {
      lines.add(report.reason.isEmpty ? '同步失败' : report.reason);
    } else if (report.totalCourses == 0) {
      lines.add(itemLabel == '课程' ? '这学期没有课程' : '没有$itemLabel');
    } else if (!report.hasChanges) {
      lines.add('${report.totalCourses}$counted已是最新，无需更新');
    } else {
      lines.add('新增 ${report.added} · 更新 ${report.updated} '
          '· 未变 ${report.unchanged}');
    }
    if (report.skipped > 0) lines.add('跳过 ${report.skipped} 条（数据不完整）');
    if (report.userEdited > 0) {
      lines.add('其中 ${report.userEdited}$counted保留了你的修改');
    }
    if (report.sectionTimes > 0) lines.add('节次时间 ${report.sectionTimes} 条');
    if (report.attempts > 1) lines.add('共尝试 ${report.attempts} 次');
    if (report.warnings.isNotEmpty) {
      lines.add('${report.warnings.length} 条警告（详见日志）');
    }

    return Message(
      id: 'sync_${report.pluginId}_${created.millisecondsSinceEpoch ~/ 1000}',
      type: MessageType.system,
      title: report.isSuccess
          ? (report.hasChanges
              ? '$pluginName 同步完成'
              : '$pluginName 无需更新')
          : '$pluginName 同步失败',
      body: lines.join('\n'),
      createdAt: created,
      sourcePluginId: report.pluginId,
      extra: <String, dynamic>{'outcome': report.outcome.name},
    );
  }

  /// 序列化为可写入 Hive / JSON 的 Map。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'title': title,
      'body': body,
      'createdAt': createdAt.toIso8601String(),
      'read': read,
      'targetId': targetId,
      'sourcePluginId': sourcePluginId,
      'extra': extra,
    };
  }

  /// 复制并修改部分字段。
  Message copyWith({
    String? id,
    MessageType? type,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? read,
    String? targetId,
    String? sourcePluginId,
    Map<String, dynamic>? extra,
  }) {
    return Message(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      read: read ?? this.read,
      targetId: targetId ?? this.targetId,
      sourcePluginId: sourcePluginId ?? this.sourcePluginId,
      extra: extra ?? this.extra,
    );
  }

  @override
  String toString() => 'Message(id: $id, type: ${type.name}, title: $title, '
      'body: $body, createdAt: $createdAt, read: $read, targetId: $targetId, '
      'sourcePluginId: $sourcePluginId, extra: $extra)';
}

/// 安全地把任意值转成 String。
String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
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

/// 把 `Map`（键可能不是 String）安全地转成 `Map<String, dynamic>`，非 Map 返回 `null`。
Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is! Map) return null;
  final Map<String, dynamic> result = <String, dynamic>{};
  value.forEach((dynamic key, dynamic item) {
    if (key != null) result[key.toString()] = item;
  });
  return result;
}