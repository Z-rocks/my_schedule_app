// 设置状态：管理 UI 偏好（目前只有"左右滑动切换周次"）
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/storage_service.dart';

/// UI 偏好设置。
///
/// 为什么单独建一个 Provider 而不是塞进 [SemesterProvider]：
/// - `SemesterProvider` 建模的是**学期这个领域对象**（起止日期、总周数），
///   存的是 `semester_config` 这一条业务数据；而"左右滑动切换周次"是
///   **纯交互偏好**，与学期内容无关，混在一起会让那个类说不清"我到底管什么"。
/// - `TimetableSettingsPage` 里还有"显示周末""显示节次时间""每节高度"三个
///   目前只存在内存、重启即丢的偏好，它们需要同一个归宿；先建好
///   `SettingsProvider`，后续把它们搬进来即可（Phase 6 的皮肤 / 明暗偏好同理）。
///
/// 本类不引用任何其他 Provider。
class SettingsProvider extends ChangeNotifier {
  /// [initialGestureSwitchWeek] 是构造时的初值（测试可注入），
  /// 正常流程由 [loadFromStorage] 从存储覆盖。
  SettingsProvider({bool initialGestureSwitchWeek = true})
      : _gestureSwitchWeek = initialGestureSwitchWeek;

  /// 是否允许在课表页左右滑动切换周次。默认开启。
  bool _gestureSwitchWeek;
  bool _disposed = false;
  bool _loaded = false;

  /// 是否允许左右滑动切换周次。
  bool get gestureSwitchWeek => _gestureSwitchWeek;

  /// 是否已尝试从存储载入过。
  bool get isLoaded => _loaded;

  /// 从 `settings` Box 恢复 UI 偏好。
  ///
  /// 坏数据（空值 / 非法 JSON / 类型不符）一律**回落默认值 `true`**，不崩溃。
  Future<void> loadFromStorage() async {
    try {
      final String? raw = StorageService.settingsBox.get(kGestureSwitchWeekKey);
      _loaded = true;
      final bool? decoded = decodeBool(raw);
      if (decoded == null || decoded == _gestureSwitchWeek) return;
      _gestureSwitchWeek = decoded;
      _notify();
    } catch (error, stackTrace) {
      _loaded = true;
      debugPrint('SettingsProvider.loadFromStorage 失败（用默认值）: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 设置"左右滑动切换周次"。
  ///
  /// 内存与通知**同步**完成（调用方无需 await 即可看到 UI 更新）；
  /// 返回的 Future 对应落盘，`await` 它可确保已持久化，忽略则等价
  /// fire-and-forget（与 `SemesterProvider.save` 一致）。落盘失败只记日志。
  Future<void> setGestureSwitchWeek(bool value) async {
    if (_gestureSwitchWeek == value) return;
    _gestureSwitchWeek = value;
    _notify();

    try {
      await StorageService.settingsBox
          .put(kGestureSwitchWeekKey, jsonEncode(value));
    } catch (error, stackTrace) {
      debugPrint('SettingsProvider.setGestureSwitchWeek 落盘失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 解析存进 Box 的布尔值；无法识别返回 `null`（调用方回落默认值）。
  ///
  /// 写入时用 `jsonEncode`，所以正常存的是带引号的 `"true"` / `"false"`；
  /// 这里同时兼容裸字符串 `true` / `false`、数字 `0` / `1` 以及已解析的 bool，
  /// 避免早期手写数据或手工改库导致读不出来。
  static bool? decodeBool(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is bool) return decoded;
      if (decoded is num) return decoded != 0;
      if (decoded is String) return _parseBoolText(decoded);
    } catch (_) {
      // 不是合法 JSON，按裸字符串继续尝试
    }
    return _parseBoolText(raw);
  }

  static bool? _parseBoolText(String text) {
    switch (text.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
      default:
        return null;
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