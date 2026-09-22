// 学期状态：管理唯一的学期配置，并与 Hive settings Box 同步
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/semester_config.dart';
import '../services/storage_service.dart';

/// 学期配置状态（单学期）。
///
/// 用户已确认只保留**一份**学期配置，存在 `settings` Box 的
/// [kSemesterConfigKey] 下。没有配置时 [config] 为 `null`，[hasConfig] 为 `false`，
/// 课表页应据此提示用户先设置学期。
///
/// 本类不引用任何其他 Provider。
class SemesterProvider extends ChangeNotifier {
  SemesterConfig? _config;
  bool _disposed = false;
  bool _loaded = false;

  /// 当前学期配置；`null` 表示还没设置。
  SemesterConfig? get config => _config;

  /// 是否已设置学期。
  bool get hasConfig => _config != null;

  /// 是否已尝试从存储载入过（UI 可区分"没设置学期"与"尚未加载"）。
  bool get isLoaded => _loaded;

  /// 从 `settings` Box 载入学期配置。
  ///
  /// 坏数据（坏 JSON / 非对象 / 缺 `startDate` / 缺 `totalWeeks`）一律视为
  /// "没有配置"（保持 `null`），而不是用兜底值伪造一个学期。
  Future<void> loadFromStorage() async {
    try {
      final String? raw = StorageService.settingsBox.get(kSemesterConfigKey);
      final SemesterConfig? decoded = SemesterConfig.tryDecode(raw);
      if (raw != null && raw.isNotEmpty && decoded == null) {
        debugPrint('SemesterProvider: 学期配置无法解析，按"未设置"处理');
      }
      _loaded = true;
      if (decoded == null) {
        if (_config != null) {
          _config = null;
          _notify();
        }
        return;
      }
      _config = decoded;
      _notify();
    } catch (error, stackTrace) {
      _loaded = true;
      debugPrint('SemesterProvider.loadFromStorage 失败（按"未设置"处理）: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 保存学期配置。
  ///
  /// 内存与通知是**同步**完成的（调用方无需 await 即可看到 UI 更新）；
  /// 返回的 Future 对应落盘，`await` 它可以确保已持久化，忽略它则等价于
  /// fire-and-forget（与 `ModuleProvider.toggle` 的用法一致）。
  /// 落盘失败只记日志，不回滚内存状态。
  Future<void> save(SemesterConfig config) async {
    _config = config;
    _loaded = true;
    _notify();

    try {
      await StorageService.settingsBox
          .put(kSemesterConfigKey, jsonEncode(config.toJson()));
    } catch (error, stackTrace) {
      debugPrint('SemesterProvider.save 落盘失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 清除学期配置（内存 + 存储）。
  Future<void> clear() async {
    final bool had = _config != null;
    _config = null;
    _loaded = true;
    if (had) _notify();

    try {
      await StorageService.settingsBox.delete(kSemesterConfigKey);
    } catch (error, stackTrace) {
      debugPrint('SemesterProvider.clear 落盘失败: $error');
      debugPrint('$stackTrace');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 已释放则不再通知，避免异步回调触发 `ChangeNotifier` 的 assert。
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}