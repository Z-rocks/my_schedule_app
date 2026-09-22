// 覆盖层引擎：读写用户对课程原始数据的修改（独立于原始数据的存储）
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user_override.dart';
import 'storage_service.dart';

/// 用户覆盖层的读写入口。
///
/// 覆盖层与原始数据**分离存储**（CONTEXT.md 3.3 / 3.5）：
/// 原始课程在 `courses` Box，用户修改在 `overrides` Box，
/// 两边都以**课程 ID** 为 key，因此同步教务数据时覆盖层不会被冲掉。
///
/// 所有方法都不会抛异常：读取失败返回 `null` / 空 Map，写入失败只记日志。
class OverrideEngine {
  /// 纯静态工具类，禁止实例化。
  OverrideEngine._();

  /// 读取某门课程的覆盖层；没有或解析失败返回 `null`。
  static UserOverride? getOverride(String courseId) {
    try {
      return decodeOverride(StorageService.overridesBox.get(courseId));
    } catch (error, stackTrace) {
      debugPrint('OverrideEngine.getOverride($courseId) 失败: $error');
      debugPrint('$stackTrace');
      return null;
    }
  }

  /// 写入 / 覆盖某门课程的覆盖层。
  static Future<void> saveOverride(
    String courseId,
    UserOverride override,
  ) async {
    try {
      await StorageService.overridesBox
          .put(courseId, jsonEncode(override.toJson()));
    } catch (error, stackTrace) {
      debugPrint('OverrideEngine.saveOverride($courseId) 失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 删除某门课程的覆盖层（例如恢复原始数据、或课程被真正删除时）。
  static Future<void> removeOverride(String courseId) async {
    try {
      await StorageService.overridesBox.delete(courseId);
    } catch (error, stackTrace) {
      debugPrint('OverrideEngine.removeOverride($courseId) 失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 一次性读出全部覆盖层，返回 `课程 ID → UserOverride`。
  ///
  /// 用 `box.toMap()` 一次取完，而不是"先列课程再逐个 `getOverride`"：
  /// Hive 的 `get` 虽然快，但逐条调用会把 N 门课变成 N 次 Box 访问，
  /// 且每次都各自 try-catch。整表读取只有一次访问、一次解析循环，
  /// 加载 N 门课的复杂度从 O(N) 次 IO 降为 1 次。
  static Map<String, UserOverride> getAllOverrides() {
    try {
      final Map<String, UserOverride> result = <String, UserOverride>{};
      final Map<dynamic, String> raw = StorageService.overridesBox.toMap();
      for (final MapEntry<dynamic, String> entry in raw.entries) {
        final Object? key = entry.key;
        if (key == null) continue;
        final UserOverride? override = decodeOverride(entry.value);
        if (override != null) result[key.toString()] = override;
      }
      return result;
    } catch (error, stackTrace) {
      debugPrint('OverrideEngine.getAllOverrides 失败: $error');
      debugPrint('$stackTrace');
      return <String, UserOverride>{};
    }
  }

  /// 已保存的覆盖层条数。
  static int get count {
    try {
      return StorageService.overridesBox.length;
    } catch (error) {
      debugPrint('OverrideEngine.count 失败: $error');
      return 0;
    }
  }

  /// 把存进 Box 的 JSON 字符串解析成 [UserOverride]。
  ///
  /// 对空值、非 JSON、非对象等情况一律返回 `null`（跳过该条），不抛异常——
  /// 一条坏数据不应该让整个课程列表加载失败。
  static UserOverride? decodeOverride(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> json = <String, dynamic>{};
      decoded.forEach((dynamic key, dynamic value) {
        if (key != null) json[key.toString()] = value;
      });
      return UserOverride.fromJson(json);
    } catch (error) {
      debugPrint('OverrideEngine: 跳过无法解析的覆盖层数据: $error');
      return null;
    }
  }
}