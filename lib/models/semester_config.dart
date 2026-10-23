// 学期配置模型：描述一个学期的起止与总周数（当前只保留一份）
import 'dart:convert';

/// 学期配置。
///
/// [startDate] 约定为**第 1 周的周一**，[endDate] 由它和 [totalWeeks] 派生。
///
/// ## [id] 是**派生**的，不是随机的
///
/// 多学期归档需要给每个学期一个稳定标识，用来把课程归到学期下
/// （`Course.semesterId`）。这里刻意用"名字 + 开学日期"派生出确定性 id
/// （见 [deriveSemesterId]），而不是随机 UUID：
/// - 同一份配置在任何设备、任何时刻算出来都一样 → 导出备份到另一台机器后，
///   课程与学期的关联不会断；
/// - 重复导入同一份备份不会产生两个"看起来一样但 id 不同"的学期。
///
/// 代价是"同名且同一天开学"的两个学期会被视为同一个——那本来就是同一个学期。
class SemesterConfig {
  /// 学期标识（`sem-` 前缀 + 派生哈希）。旧数据里可能为空串，
  /// 读取时用 [ensureId] 补齐，**不写回存储**（纯派生值，没必要落盘）。
  final String id;

  /// 学期名称，如 `"2026-2027学年第一学期"`。
  final String name;

  /// 第 1 周的周一（只用到年月日，时分秒会被归一化）。
  final DateTime startDate;

  /// 总周数，如 20，至少为 1。
  final int totalWeeks;

  /// 备注，`null` 表示没有。
  final String? description;

  const SemesterConfig({
    this.id = '',
    required this.name,
    required this.startDate,
    required this.totalWeeks,
    this.description,
  });

  /// 是否已经带 id（旧数据为 `false`）。
  bool get hasId => id.isNotEmpty;

  /// 保证有 id：没有就按 [deriveSemesterId] 补一个。
  SemesterConfig ensureId() =>
      hasId ? this : copyWith(id: deriveSemesterId(name, startDate));

  /// 学期结束日期（最后一周的周日）。
  ///
  /// **派生值，不存 JSON**：它完全由 [startDate] 与 [totalWeeks] 决定，
  /// 存下来只会多一个可能不一致的字段。第 1 周是 7 天，
  /// 所以最后一周周日 = 起始日 + (totalWeeks * 7 - 1) 天。
  DateTime get endDate =>
      startDate.add(Duration(days: totalWeeks * 7 - 1));

  /// 从 JSON 构造，缺失或类型异常的字段使用安全默认值，不抛异常。
  ///
  /// 注意：兜底值只保证"不崩"，不代表数据可信。存储层请用 [tryDecode]，
  /// 它会拒绝缺关键字段的数据，避免用兜底值伪造出一个学期。
  factory SemesterConfig.fromJson(Map<String, dynamic> json) {
    final int totalWeeks = _asInt(json['totalWeeks'], fallback: 1);
    return SemesterConfig(
      id: _asString(json['id']),
      name: _asString(json['name']),
      startDate: _asDateTime(json['startDate']) ?? DateTime.now(),
      totalWeeks: totalWeeks < 1 ? 1 : totalWeeks,
      description: _asNullableString(json['description']),
    );
  }

  /// 从存储字符串解析学期配置；任何不可用的输入返回 `null`。
  ///
  /// 返回 `null` 的判定（供 `SemesterProvider` 区分"没有配置"）：
  /// - `raw` 为 `null` / 空串
  /// - 不是合法 JSON，或不是 JSON 对象
  /// - 缺少或无法解析 `startDate`（关键字段，不能用兜底值糊过去）
  /// - `totalWeeks` 缺失或 < 1
  static SemesterConfig? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> json = <String, dynamic>{};
      decoded.forEach((dynamic key, dynamic value) {
        if (key != null) json[key.toString()] = value;
      });

      if (_asDateTime(json['startDate']) == null) return null;
      final int? totalWeeks = _asIntOrNull(json['totalWeeks']);
      if (totalWeeks == null || totalWeeks < 1) return null;

      return SemesterConfig.fromJson(json);
    } catch (error) {
      return null;
    }
  }

  /// 序列化为可写入 Hive / JSON 的 Map（**不含** [endDate]）。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'startDate': startDate.toIso8601String(),
      'totalWeeks': totalWeeks,
      'description': description,
    };
  }

  /// 复制并修改部分字段；`clearDescription` 用于显式把备注置空。
  SemesterConfig copyWith({
    String? id,
    String? name,
    DateTime? startDate,
    int? totalWeeks,
    String? description,
    bool clearDescription = false,
  }) {
    return SemesterConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      description: clearDescription ? null : (description ?? this.description),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SemesterConfig &&
        other.id == id &&
        other.name == name &&
        other.startDate == startDate &&
        other.totalWeeks == totalWeeks &&
        other.description == description;
  }

  @override
  int get hashCode => Object.hash(id, name, startDate, totalWeeks, description);

  @override
  String toString() => 'SemesterConfig(id: $id, name: $name, '
      'startDate: $startDate, totalWeeks: $totalWeeks, '
      'description: $description)';
}

/// 由"学期名 + 开学日期"派生一个确定性 id（`sem-` + 8 位十六进制）。
///
/// 用 FNV-1a 而不是 `String.hashCode`：后者不保证跨进程 / 跨版本稳定，
/// 而这个 id 会写进课程数据并跟着备份走，必须长期一致。
///
/// 只取"年月日"，时分秒不影响结果——同一学期的开学时间改个几点钟，
/// 不该变成另一个学期。
String deriveSemesterId(String name, DateTime startDate) {
  final String key = '${name.trim()}|${startDate.year}-'
      '${startDate.month.toString().padLeft(2, '0')}-'
      '${startDate.day.toString().padLeft(2, '0')}';
  int hash = 0x811C9DC5;
  for (final int unit in key.codeUnits) {
    hash = ((hash ^ (unit & 0xFF)) * 0x01000193) & 0xFFFFFFFF;
  }
  return 'sem-${hash.toRadixString(16).padLeft(8, '0')}';
}

/// 安全地把任意值转成 String。
String _asString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

/// 安全地把任意值转成可空的 String。
String? _asNullableString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

/// 安全地把任意值转成 int。
int _asInt(Object? value, {required int fallback}) =>
    _asIntOrNull(value) ?? fallback;

/// 安全地把任意值转成可空的 int。
int? _asIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// 安全地把任意值转成 DateTime。
DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}