// 多学期归档：把"一个学期"变成"多个学期"，并让课程各自归属到学期下。
//
// ## 为什么先只做接口层
//
// 归档的**数据模型**必须先定下来，否则后面每次同步、每次改课都要再改一遍
// 存储格式。UI（学期列表页、切换学期、删除归档）可以后补，但
// `Course.semesterId` / `SemesterConfig.id` 这两个字段一旦上线就不能再动
// （CONTEXT 4.2.1：纯新增字段免迁移，改语义要迁移）。
//
// ## 存储布局
//
// - `settings` Box `semester_config` → **当前**学期（沿用单学期时代的键，
//   读取路径完全不变）；
// - `settings` Box `semester_archive` → 已归档学期数组（JSON）。
//
// 拆成两个键而不是一个列表，是为了让"读当前学期"这条最热的路径
// （每次启动、每次算周次）不必解析整个归档列表。
//
// ## 兼容旧数据的核心规则
//
// 旧课程的 `semesterId` 是空串。空串的语义被定为**"属于当前学期"**，
// 而不是"无归属"——否则升级后课表会瞬间变空，用户会以为数据丢了。
//
// 代价是：切换学期的那一刻，必须先把这些"空串课程"打上**旧学期**的 id，
// 否则它们会被新学期认领。这件事由 [SemesterArchiveService.switchTo]
// 自动完成（见 `stampUnassignedCourses`）。
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/course.dart';
import '../models/semester_config.dart';
import 'app_log.dart';
import 'storage_service.dart';

/// 最多保留多少个归档学期。
///
/// 一个学期一条，12 条 ≈ 6 年，够用到毕业。超出时丢弃**开学日期最早**的，
/// 而不是归档时间最早的——归档顺序可能被用户手动折腾乱，开学日期不会。
const int kMaxArchivedSemesters = 12;

/// 一条归档记录：学期配置 + 归档时刻。
class SemesterArchiveEntry {
  const SemesterArchiveEntry({
    required this.config,
    required this.archivedAt,
  });

  final SemesterConfig config;

  /// 归档时间（仅用于展示"什么时候收起来的"，排序用 [SemesterConfig.startDate]）。
  final DateTime archivedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'config': config.toJson(),
        'archivedAt': archivedAt.toIso8601String(),
      };

  /// 从 JSON 构造；`config` 不可解析时返回 `null`（整条丢弃，不伪造学期）。
  static SemesterArchiveEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? configRaw = raw['config'];
    if (configRaw is! Map) return null;

    final Map<String, dynamic> configJson = <String, dynamic>{};
    configRaw.forEach((dynamic key, dynamic value) {
      if (key != null) configJson[key.toString()] = value;
    });
    // 复用 tryDecode 的严格校验：缺 startDate / totalWeeks 的一律不算学期。
    final SemesterConfig? config =
        SemesterConfig.tryDecode(jsonEncode(configJson));
    if (config == null) return null;

    final Object? archivedRaw = raw['archivedAt'];
    final DateTime archivedAt = archivedRaw is String
        ? (DateTime.tryParse(archivedRaw) ?? DateTime.now())
        : DateTime.now();
    return SemesterArchiveEntry(config: config, archivedAt: archivedAt);
  }

  /// 解析归档列表；坏条目逐条跳过，整体坏了返回空列表。
  static List<SemesterArchiveEntry> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <SemesterArchiveEntry>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <SemesterArchiveEntry>[];
      final List<SemesterArchiveEntry> result = <SemesterArchiveEntry>[];
      for (final Object? item in decoded) {
        final SemesterArchiveEntry? entry = tryFromJson(item);
        if (entry != null) result.add(entry);
      }
      return result;
    } catch (error) {
      debugPrint('[SemesterArchive] 归档列表解析失败：$error');
      return const <SemesterArchiveEntry>[];
    }
  }

  static String encodeList(List<SemesterArchiveEntry> entries) => jsonEncode(
        entries.map((SemesterArchiveEntry e) => e.toJson()).toList(),
      );

  @override
  String toString() =>
      'SemesterArchiveEntry(${config.name}, archivedAt: $archivedAt)';
}

/// 切换学期的结果。
class SemesterSwitchResult {
  const SemesterSwitchResult({
    required this.ok,
    required this.message,
    this.current,
    this.stampedCourses = 0,
    this.archivedCount = 0,
  });

  final bool ok;

  /// 给用户看的一句话（UI 直接显示）。
  final String message;

  /// 切换后的当前学期。
  final SemesterConfig? current;

  /// 本次被补上归属的课程数（旧数据迁移量）。
  final int stampedCourses;

  /// 归档里现在有多少个学期。
  final int archivedCount;
}

/// 多学期归档服务（纯静态，只读写存储，不碰 Provider）。
///
/// **调用约定**：本服务会直接改写 `settings` / `courses` 两个 Box，
/// 但**不更新内存里的 Provider**。调用方（未来的学期管理页）在操作成功后
/// 必须让 `SemesterProvider` / `CourseProvider` 重新 `loadFromStorage()`，
/// 与 `DataBackupService.import` 之后的做法一致。
class SemesterArchiveService {
  SemesterArchiveService._();

  // ───────────────────── 读 ─────────────────────

  /// 当前学期；没设置返回 `null`。
  ///
  /// 返回的配置**保证带 id**（旧数据现场派生），但不写回存储——
  /// id 是纯派生值，落盘只会多一个可能过期的字段。
  static SemesterConfig? loadCurrent() {
    try {
      final SemesterConfig? config = SemesterConfig.tryDecode(
        StorageService.settingsBox.get(kSemesterConfigKey),
      );
      return config?.ensureId();
    } catch (error) {
      debugPrint('[SemesterArchive] 读当前学期失败：$error');
      return null;
    }
  }

  /// 已归档的学期，按**开学日期倒序**（最近的学期在前）。
  static List<SemesterArchiveEntry> loadArchived() {
    try {
      final List<SemesterArchiveEntry> entries =
          SemesterArchiveEntry.decodeList(
        StorageService.settingsBox.get(kSemesterArchiveKey),
      );
      final List<SemesterArchiveEntry> sorted =
          entries.map((SemesterArchiveEntry e) {
        return SemesterArchiveEntry(
          config: e.config.ensureId(),
          archivedAt: e.archivedAt,
        );
      }).toList();
      sorted.sort((SemesterArchiveEntry a, SemesterArchiveEntry b) =>
          b.config.startDate.compareTo(a.config.startDate));
      return sorted;
    } catch (error) {
      debugPrint('[SemesterArchive] 读归档失败：$error');
      return const <SemesterArchiveEntry>[];
    }
  }

  /// 全部学期（当前 + 归档），按开学日期倒序。
  ///
  /// 同 id 只留一条（当前学期可能同时存在于归档里，例如用户先归档又手动
  /// 恢复回来）——去重时**当前学期优先**。
  static List<SemesterConfig> listSemesters() {
    final SemesterConfig? current = loadCurrent();
    final Map<String, SemesterConfig> byId = <String, SemesterConfig>{};
    if (current != null) byId[current.id] = current;
    for (final SemesterArchiveEntry entry in loadArchived()) {
      byId.putIfAbsent(entry.config.id, () => entry.config);
    }
    final List<SemesterConfig> all = byId.values.toList();
    all.sort((SemesterConfig a, SemesterConfig b) =>
        b.startDate.compareTo(a.startDate));
    return all;
  }

  // ───────────────────── 写 ─────────────────────

  /// 只写当前学期（不归档旧的）。给"首次设置学期"这类场景用。
  static Future<void> saveCurrent(SemesterConfig config) async {
    await StorageService.settingsBox
        .put(kSemesterConfigKey, jsonEncode(config.ensureId().toJson()));
  }

  /// 把当前学期挪进归档并清空"当前"。
  ///
  /// 清空前会先给**无归属课程**打上这个学期的 id——否则它们会变成
  /// "属于当前学期"，而当前学期已经没了，等于凭空消失。
  static Future<SemesterSwitchResult> archiveCurrent() async {
    final SemesterConfig? current = loadCurrent();
    if (current == null) {
      return const SemesterSwitchResult(
        ok: false,
        message: '还没有设置学期，没有可归档的内容',
      );
    }
    return _archiveAndSwitch(current, null);
  }

  /// 切换到学期 [target]：归档当前学期 → 写入新当前学期 → 补课程归属。
  ///
  /// [target] 若已在归档里（从归档里恢复），会先把它从归档里移出，
  /// 避免同一学期同时出现在"当前"和"归档"两处。
  static Future<SemesterSwitchResult> switchTo(SemesterConfig target) async {
    final SemesterConfig next = target.ensureId();
    final SemesterConfig? current = loadCurrent();

    if (current != null && current.id == next.id) {
      // 已经是这个学期：不重复归档，但顺手把旧课程归属补上（幂等）。
      final int stamped = await stampUnassignedCourses(next.id);
      return SemesterSwitchResult(
        ok: true,
        message: '当前已经是「${next.name}」',
        current: next,
        stampedCourses: stamped,
        archivedCount: loadArchived().length,
      );
    }
    return _archiveAndSwitch(current, next);
  }

  /// 从归档里恢复某个学期（等于 `switchTo` + 从归档移除）。
  static Future<SemesterSwitchResult> restoreArchived(String semesterId) async {
    SemesterArchiveEntry? found;
    for (final SemesterArchiveEntry entry in loadArchived()) {
      if (entry.config.id == semesterId) {
        found = entry;
        break;
      }
    }
    if (found == null) {
      return const SemesterSwitchResult(
        ok: false,
        message: '归档里没有这个学期',
      );
    }
    return switchTo(found.config);
  }

  /// 删除一条归档（不影响当前学期、不删课程）。
  static Future<bool> removeArchived(String semesterId) async {
    try {
      final List<SemesterArchiveEntry> entries = loadArchived()
          .where((SemesterArchiveEntry e) => e.config.id != semesterId)
          .toList();
      await _writeArchive(entries);
      return true;
    } catch (error, stack) {
      debugPrint('[SemesterArchive] 删除归档失败：$error');
      AppLog.e('semester_archive', '删除归档学期失败',
          error: error, stack: stack);
      return false;
    }
  }

  // ───────────────────── 课程归属 ─────────────────────

  /// 从 [all] 里挑出属于学期 [semesterId] 的课程。
  ///
  /// [currentSemesterId] 必须传当前学期 id：空串（旧数据）只归当前学期。
  static List<Course> coursesOf(
    List<Course> all, {
    required String semesterId,
    required String currentSemesterId,
  }) {
    return all
        .where((Course c) => c.belongsToSemester(
              semesterId,
              currentSemesterId: currentSemesterId,
            ))
        .toList(growable: false);
  }

  /// 给**还没有归属**的课程打上 [semesterId]，返回改动条数。
  ///
  /// 直接改 `courses` Box 里的原始 JSON（而不是走 `Course` 模型）：
  /// 这样能保留 Box 里可能存在、但当前模型还不认识的键，
  /// 也避免把 `userOverride` 从覆盖层 Box 里"顺手复制"进课程 JSON
  /// （`CourseProvider` 落盘时是 `clearUserOverride` 的，覆盖层以
  /// `overrides` Box 为权威来源）。
  static Future<int> stampUnassignedCourses(String semesterId) =>
      _stampCourses(semesterId: semesterId, onlyUnassigned: true);

  /// 把指定课程强制改到 [semesterId]（未来"把课程挪到别的学期"用）。
  static Future<int> assignCoursesToSemester(
    Iterable<String> courseIds,
    String semesterId,
  ) =>
      _stampCourses(
        semesterId: semesterId,
        onlyUnassigned: false,
        courseIds: courseIds.toSet(),
      );

  static Future<int> _stampCourses({
    required String semesterId,
    required bool onlyUnassigned,
    Set<String>? courseIds,
  }) async {
    if (semesterId.isEmpty) return 0;
    int changed = 0;
    try {
      final Map<dynamic, String> raw = StorageService.coursesBox.toMap();
      for (final MapEntry<dynamic, String> entry in raw.entries) {
        final String key = '${entry.key}';
        if (courseIds != null && !courseIds.contains(key)) continue;

        final Object? decoded = _tryDecode(entry.value);
        if (decoded is! Map) continue;
        final Map<String, dynamic> json = <String, dynamic>{};
        decoded.forEach((dynamic k, dynamic v) {
          if (k != null) json[k.toString()] = v;
        });

        final Object? existing = json['semesterId'];
        final String existingId = existing is String ? existing : '';
        if (onlyUnassigned && existingId.isNotEmpty) continue;
        if (existingId == semesterId) continue;

        json['semesterId'] = semesterId;
        await StorageService.coursesBox.put(key, jsonEncode(json));
        changed++;
      }
    } catch (error, stack) {
      debugPrint('[SemesterArchive] 课程归属改写失败：$error');
      AppLog.e('semester_archive', '课程归属改写失败',
          error: error, stack: stack);
    }
    return changed;
  }

  // ───────────────────── 内部 ─────────────────────

  /// 归档 [current]、写入 [next]（可为 `null` = 只归档不设新学期）。
  static Future<SemesterSwitchResult> _archiveAndSwitch(
    SemesterConfig? current,
    SemesterConfig? next,
  ) async {
    int stamped = 0;
    int archivedCount = 0;
    try {
      // 1. 先补归属：此刻"当前学期"还是 current，空串课程该归它。
      if (current != null) {
        stamped = await stampUnassignedCourses(current.id);
      }

      // 2. 归档 current，并确保 next 不在归档里重复出现。
      final List<SemesterArchiveEntry> entries = loadArchived()
          .where((SemesterArchiveEntry e) =>
              next == null || e.config.id != next.id)
          .toList();
      if (current != null) {
        entries.removeWhere(
          (SemesterArchiveEntry e) => e.config.id == current.id,
        );
        entries.add(SemesterArchiveEntry(
          config: current,
          archivedAt: DateTime.now(),
        ));
      }
      entries.sort((SemesterArchiveEntry a, SemesterArchiveEntry b) =>
          b.config.startDate.compareTo(a.config.startDate));
      // 超出上限时丢最早的（列表已按开学日期倒序）。
      final List<SemesterArchiveEntry> kept =
          entries.take(kMaxArchivedSemesters).toList();
      await _writeArchive(kept);
      archivedCount = kept.length;

      // 3. 写当前学期（`null` = 清空）。
      if (next == null) {
        await StorageService.settingsBox.delete(kSemesterConfigKey);
      } else {
        await saveCurrent(next);
      }
    } catch (error, stack) {
      debugPrint('[SemesterArchive] 归档 / 切换失败：$error');
      AppLog.e('semester_archive', '归档 / 切换学期失败',
          error: error, stack: stack);
      return SemesterSwitchResult(
        ok: false,
        message: '保存失败：$error',
        current: loadCurrent(),
        stampedCourses: stamped,
        archivedCount: archivedCount,
      );
    }

    AppLog.action('semester_switch', <String, Object?>{
      'from': current?.name ?? '',
      'to': next?.name ?? '',
      'stampedCourses': stamped,
      'archivedCount': archivedCount,
    });

    final String message = next == null
        ? '已归档「${current?.name ?? ''}」'
        : current == null
            ? '已设为「${next.name}」'
            : '已切换到「${next.name}」';
    return SemesterSwitchResult(
      ok: true,
      message: message,
      current: next,
      stampedCourses: stamped,
      archivedCount: archivedCount,
    );
  }

  static Future<void> _writeArchive(List<SemesterArchiveEntry> entries) async {
    await StorageService.settingsBox.put(
      kSemesterArchiveKey,
      SemesterArchiveEntry.encodeList(entries),
    );
  }

  static Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
