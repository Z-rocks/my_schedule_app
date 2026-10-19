// 作业提醒设置模型：开关 + 多档"提前多少分钟提醒"。
//
// 设计取舍：**全局一套档位**，不给每份作业单独配。
// 理由：作业是插件同步来的、会随时增删，逐条配置意味着"新作业没配置 = 不提醒"
// 这种沉默失效；而用户的真实诉求是"快到截止了提醒我几次"，
// 一套档位对所有作业生效才符合直觉（个别作业想静音可自行勾完成/隐藏）。
//
// 档位列表本身就是"通知几次"的答案：`[60, 30, 10]` = 截止前 1 小时 / 半小时 /
// 10 分钟各提醒一次，共 3 次。顺序在存储层统一成**降序**（离截止远的在前）。
import 'dart:convert';

/// 作业提醒设置。
class HomeworkReminderSettings {
  const HomeworkReminderSettings({
    this.enabled = false,
    this.offsetsMinutes = kDefaultReminderOffsets,
    this.notifyWhenCheckFails = true,
  });

  /// 是否启用作业提醒。默认关闭——通知属于"会打扰用户"的能力，
  /// 必须用户主动打开（首次打开时页面会引导授予通知权限）。
  final bool enabled;

  /// 每档提前的分钟数（降序、去重、已归一）。
  ///
  /// 空列表 = 一档都不提醒（等价于关闭，但保留 enabled 语义便于 UI 表达）。
  final List<int> offsetsMinutes;

  /// 发通知前校验作业状态失败（断网 / 未登录 / 插件不可用）时，
  /// 是否**仍然提醒**。
  ///
  /// 默认 `true`：漏掉截止的代价远大于多打扰一次；而且失败原因往往是
  /// "当时没网"，那时更需要提醒用户去手动确认。
  final bool notifyWhenCheckFails;

  /// 通知次数 = 档位数。
  int get notificationCount => offsetsMinutes.length;

  /// 是否实际上会提醒（开关打开且至少一档）。
  bool get isEffective => enabled && offsetsMinutes.isNotEmpty;

  /// 复制并修改部分字段。
  HomeworkReminderSettings copyWith({
    bool? enabled,
    List<int>? offsetsMinutes,
    bool? notifyWhenCheckFails,
  }) {
    return HomeworkReminderSettings(
      enabled: enabled ?? this.enabled,
      offsetsMinutes: normalizeOffsets(offsetsMinutes ?? this.offsetsMinutes),
      notifyWhenCheckFails: notifyWhenCheckFails ?? this.notifyWhenCheckFails,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'offsetsMinutes': offsetsMinutes,
        'notifyWhenCheckFails': notifyWhenCheckFails,
      };

  /// 解析设置；坏数据 / 缺字段回落默认值，**不抛异常**。
  factory HomeworkReminderSettings.fromJson(Map<String, dynamic> json) {
    final Object? rawOffsets = json['offsetsMinutes'];
    final List<int> offsets = rawOffsets is List
        ? normalizeOffsets(rawOffsets.map(_asInt).where((int m) => m > 0))
        : kDefaultReminderOffsets;
    return HomeworkReminderSettings(
      enabled: json['enabled'] == true,
      offsetsMinutes: offsets,
      notifyWhenCheckFails: json['notifyWhenCheckFails'] != false,
    );
  }

  /// 从存储里的 JSON 字符串解析；空 / 坏数据返回默认值。
  static HomeworkReminderSettings decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const HomeworkReminderSettings();
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return const HomeworkReminderSettings();
      final Map<String, dynamic> json = <String, dynamic>{};
      decoded.forEach((dynamic key, dynamic value) {
        if (key != null) json['$key'] = value;
      });
      return HomeworkReminderSettings.fromJson(json);
    } catch (_) {
      return const HomeworkReminderSettings();
    }
  }

  /// 编码成可写入 `settings` Box 的字符串。
  String encode() => jsonEncode(toJson());

  /// 归一化档位：只保留正数 → 去重 → 降序 → 截断到 [kMaxReminderOffsets] 档。
  ///
  /// 降序是有意的：UI 与"第 N 次提醒"的编号都按"离截止从远到近"排，
  /// 用户读起来才是"1 小时前、30 分钟前、10 分钟前"。
  static List<int> normalizeOffsets(Iterable<int> raw) {
    final List<int> cleaned = raw.where((int m) => m > 0).toSet().toList()
      ..sort((int a, int b) => b.compareTo(a));
    if (cleaned.length > kMaxReminderOffsets) {
      return List<int>.unmodifiable(cleaned.sublist(0, kMaxReminderOffsets));
    }
    return List<int>.unmodifiable(cleaned);
  }

  /// 面向用户的档位文案，如 `截止前 1 小时 / 30 分钟 / 10 分钟`。
  String describeOffsets() {
    if (offsetsMinutes.isEmpty) return '未设置提醒时间';
    return offsetsMinutes.map(describeOffset).join(' / ');
  }

  /// 单个档位的文案：整小时用"小时"，其余用"分钟"。
  static String describeOffset(int minutes) {
    if (minutes >= 60 && minutes % 60 == 0) {
      final int hours = minutes ~/ 60;
      return hours >= 24 && hours % 24 == 0
          ? '截止前 ${hours ~/ 24} 天'
          : '截止前 $hours 小时';
    }
    return '截止前 $minutes 分钟';
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}

/// 默认档位：1 小时 / 30 分钟 / 10 分钟。
const List<int> kDefaultReminderOffsets = <int>[60, 30, 10];

/// 最多允许几档（防止用户手滑配出几十条通知）。
const int kMaxReminderOffsets = 6;

/// 单档最小值（1 分钟）与最大值（14 天）。
const int kMinReminderOffset = 1;
const int kMaxReminderOffset = 14 * 24 * 60;
