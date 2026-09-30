// Phase 4.4：节次时间读取服务。
//
// 为什么需要它：课表左侧时间列原本用**硬编码**的 `kDefaultSectionTimes`
// （`timetable_view.dart`），但各校作息不同——NCST 第 3 节是 10:25，
// 别的学校可能是 10:20 或 10:30。写死在客户端等于"永远显示错误的作息"。
//
// 数据来源：插件在同步时把真实作息写进自己的私有 KV——
// NCST 插件执行 `ctx.storage.set('section_times', JSON.stringify(map))`，
// 宿主落到 Hive `plugin_data` Box，键为 `<pluginId>:section_times`
// （CONTEXT 3.5「插件私有 KV」，分隔符见 `PluginContext.kStorageKeySeparator`）。
//
// 本服务**不含任何学校信息**：只按"哪个插件声明了 timetable 能力"去读它自己的 KV，
// 键名 `section_times` 是内核与插件约定的**能力契约**，不是学校字段（CONTEXT 3.1）。
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/plugin_meta.dart';
import 'storage_service.dart';

/// 插件私有 KV 里存放节次时间的键名（内核 ↔ 插件的能力契约）。
///
/// 与 `ncst-jwxt.js` 里 `ctx.storage.set('section_times', ...)` 必须一致；
/// 插件换名字等于换契约，两边要同改。
const String kSectionTimesStorageKey = 'section_times';

/// 声明该能力的插件才被认为"提供课表作息"。
const String kTimetableCapability = 'timetable';

/// 从插件私有 KV 读出的节次时间表。
///
/// 与 `kDefaultSectionTimes`（`Map<int, String>`）形状一致，
/// 所以课表页可以直接二选一传入，UI 无需分支。
@immutable
class SectionTimes {
  const SectionTimes({
    required this.times,
    required this.pluginId,
    required this.pluginName,
  });

  /// 节次 → 时间文本（`3 → '10:25-11:10'`），键升序。
  final Map<int, String> times;

  /// 提供这份作息的插件 id（供 UI 显示"作息来源"与排查用）。
  final String pluginId;

  /// 提供这份作息的插件显示名。
  final String pluginName;

  /// 是否拿到了任何一条。
  bool get isEmpty => times.isEmpty;

  /// 条数。
  int get length => times.length;

  /// 取某一节的时间；没有返回 `null`（调用方自行回退）。
  String? operator [](int session) => times[session];

  /// 带上节次前缀的展示文本：`3 → '3 10:25-11:10'`（供设置页/排查用）。
  List<String> get displayLines => times.entries
      .map((MapEntry<int, String> e) => '${e.key} ${e.value}')
      .toList(growable: false);

  @override
  String toString() =>
      'SectionTimes($pluginId, ${times.length} 节)';
}

/// 节次时间服务（纯静态类）。
///
/// 契约：**任何失败都返回 `null`**，绝不抛异常——作息读不到时课表应该
/// 静默回退到内置默认值，而不是让整个课表页崩掉。
class SectionTimeService {
  /// 纯静态工具类，禁止实例化。
  SectionTimeService._();

  /// 从**已启用**且声明了 timetable 能力的插件里找一份作息。
  ///
  /// 多个插件都提供时，返回**第一个能成功解析出非空作息**的那份
  /// （按 `plugins` 顺序，即用户安装顺序），不会混合两个学校的作息——
  /// 混起来会得到"第 3 节 10:25，但第 5 节是另一个学校的时间"这种错乱结果。
  static SectionTimes? fromPlugins(List<PluginMeta> plugins) {
    for (final PluginMeta meta in plugins) {
      if (!meta.enabled) continue;
      if (!meta.effectiveCapabilities.contains(kTimetableCapability)) continue;
      final SectionTimes? parsed = fromPlugin(meta);
      if (parsed != null && !parsed.isEmpty) return parsed;
    }
    return null;
  }

  /// 读某一**个**插件的作息（不检查能力声明 / 启用状态，便于单独调用与排查）。
  static SectionTimes? fromPlugin(PluginMeta meta) {
    final String? raw = _readRaw(meta.id);
    if (raw == null || raw.trim().isEmpty) return null;
    final Map<int, String>? times = parse(raw);
    if (times == null || times.isEmpty) return null;
    return SectionTimes(
      times: times,
      pluginId: meta.id,
      pluginName: meta.name,
    );
  }

  /// 读某个插件的原始 KV 字符串；未初始化 / 读失败返回 `null`。
  static String? _readRaw(String pluginId) {
    try {
      final String key = '$pluginId:$kSectionTimesStorageKey';
      return StorageService.pluginDataBox.get(key);
    } catch (e) {
      // StorageService 未初始化时 pluginDataBox 抛 StateError——
      // 这是"还没准备好"而不是错误状态，按"没有作息"处理。
      debugPrint('[SectionTimeService] 读取 $pluginId 的作息失败：$e');
      return null;
    }
  }

  /// 解析插件写下的 JSON 对象 `{"第3节":"10:25-11:10", ...}`。
  ///
  /// 容错策略（任何一条坏数据只丢那一条，不影响其余）：
  /// - 非 JSON / 非对象 → 返回 `null`（整份不可用）；
  /// - 键解析不出节次号 → 跳过该条；
  /// - 值是空串 / 非法类型 → 跳过该条；
  /// - 节次号重复 → **后者覆盖前者**（与 `CookieService` 同名覆盖同思路）。
  static Map<int, String>? parse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      debugPrint('[SectionTimeService] 作息不是合法 JSON，忽略：$e');
      return null;
    }
    if (decoded is! Map) {
      debugPrint('[SectionTimeService] 作息不是 JSON 对象，忽略');
      return null;
    }

    final Map<int, String> result = <int, String>{};
    decoded.forEach((dynamic key, dynamic value) {
      if (key == null || value == null) return;
      final int? session = parseSessionNumber('$key');
      if (session == null) return;
      final String text = '$value'.trim();
      if (text.isEmpty) return;
      result[session] = text;
    });

    if (result.isEmpty) return null;
    // 输出按节次升序，便于 UI 顺序渲染与人工核对。
    final List<int> sessions = result.keys.toList()..sort();
    return <int, String>{
      for (final int session in sessions) session: result[session]!,
    };
  }

  /// 从插件给的键里取出节次号。
  ///
  /// 实际见过的形状（NCST 是第一种）：
  /// - `"第3节"` / `"第 3 节"`
  /// - `"3"` / `"3节"` / `"第3"` / `"3.0"`
  ///
  /// 取**第一段连续数字**，然后按整数解析。取不到数字、或数字不在
  /// `1..kMaxSessions` 内（与 `TimetableLogic.kMaxSessions` 对齐）→ 返回 `null`。
  static int? parseSessionNumber(String key) {
    final RegExpMatch? match = RegExp(r'\d+').firstMatch(key);
    if (match == null) return null;
    final int? value = int.tryParse(match.group(0)!);
    if (value == null || value < 1 || value > _kMaxSessions) return null;
    return value;
  }

  /// 与 `TimetableLogic.kMaxSessions` 保持一致（12 节）。
  ///
  /// 在这里复制常量而不是 import `timetable_logic.dart`：
  /// 本服务属于"读插件数据"这一层，不该反向依赖课表渲染逻辑；
  /// 将来若节次上限变化，`timetable_logic` 的测试会先失败并提醒同步这里。
  static const int _kMaxSessions = 12;
}
