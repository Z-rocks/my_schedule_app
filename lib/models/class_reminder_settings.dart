// 上课提醒设置：开关 + 提前多少分钟。
//
// 与作业提醒（`HomeworkReminderSettings`）**刻意分开存**：两者的开关语义
// 完全不同——作业提醒是"快到截止了提醒我"，上课提醒是"快到上课了提醒我"，
// 一个用户很可能只想要后者（作业能自己看，上课会忘）。
//
// 档位只有一档生效（不像作业可以多档叠加）：一节课提醒两次（课前 30 分钟
// 和课前 5 分钟）意义不大，反而吵。所以 [offsetMinutes] 是**单值**。
import 'dart:convert';

/// 默认提前量（分钟）。
const int kDefaultClassReminderOffset = 15;

/// 可选提前量（分钟）。5 分钟太赶、60 分钟太早，都留着但默认 15。
const List<int> kClassReminderOffsetOptions = <int>[5, 10, 15, 20, 30, 60];

/// 上课提醒设置。
class ClassReminderSettings {
  const ClassReminderSettings({
    this.enabled = false,
    this.offsetMinutes = kDefaultClassReminderOffset,
  });

  /// 是否启用。默认关闭——通知属于"会打扰用户"的能力，必须用户主动开。
  final bool enabled;

  /// 提前多少分钟提醒。
  final int offsetMinutes;

  /// 实际会生效（开关打开且提前量合法）。
  bool get isEffective => enabled && offsetMinutes > 0;

  ClassReminderSettings copyWith({bool? enabled, int? offsetMinutes}) {
    return ClassReminderSettings(
      enabled: enabled ?? this.enabled,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'offsetMinutes': offsetMinutes,
      };

  /// 从 JSON 解析；坏数据回落默认值（不抛异常）。
  factory ClassReminderSettings.fromJson(Map<String, dynamic> json) {
    final Object? enabled = json['enabled'];
    final Object? offset = json['offsetMinutes'];
    return ClassReminderSettings(
      enabled: enabled is bool ? enabled : false,
      offsetMinutes: offset is int && offset > 0 && offset <= 24 * 60
          ? offset
          : kDefaultClassReminderOffset,
    );
  }

  /// 从存储的字符串解析；`null` / 坏 JSON 返回默认设置。
  static ClassReminderSettings tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const ClassReminderSettings();
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const ClassReminderSettings();
      }
      return ClassReminderSettings.fromJson(decoded);
    } catch (_) {
      return const ClassReminderSettings();
    }
  }

  String encode() => jsonEncode(toJson());
}
