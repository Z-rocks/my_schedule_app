// 主题状态：包装 ThemeEngine，向 UI 暴露当前主题与明暗模式偏好
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/skin_pack.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_engine.dart';

/// 主题状态。
///
/// 内部持有 [ThemeEngine]（Phase 1.2 已完成"皮肤 → AppTheme"的转换与合并），
/// 本类只负责把它包装成 UI 可用的 Provider：对外暴露 [currentTheme] /
/// [brightness]，并在状态变化后 `notifyListeners`。
///
/// 皮肤 ID 的持久化（Hive `settings`）留到 Phase 2；本类不引用其他 Provider。
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({ThemeEngine? engine}) : _engine = engine ?? ThemeEngine();

  final ThemeEngine _engine;

  /// 用户的明暗模式偏好。
  ///
  /// Phase 1 只有亮 / 暗两态（默认亮色），"跟随系统"留到 Phase 6
  /// 与暗色配色一起实现。
  Brightness _brightness = Brightness.light;
  bool _disposed = false;

  /// 当前生效的主题令牌集合（供 `AppThemeExtension` 使用）。
  AppTheme get currentTheme => _engine.current;

  /// 当前皮肤 ID；空字符串表示使用内置默认主题。
  String get currentSkinId => _engine.currentSkinId;

  /// 用户的明暗模式偏好。
  Brightness get brightness => _brightness;

  /// 按当前偏好取主题。
  ///
  /// Phase 1 的 `withBrightness` 是简化实现（返回 `this`），
  /// 因此这里等价于 [currentTheme]；接口先固定下来，Phase 6 自动生效。
  AppTheme get themedForBrightness =>
      _engine.current.withBrightness(_brightness);

  /// 应用一份皮肤。
  ///
  /// 调用 [ThemeEngine.loadSkin] 解析并合并皮肤，然后通知 UI 重建。
  /// 皮肤解析失败时引擎会保持原主题（内部已 try-catch），本方法不会抛出。
  Future<void> applySkin(SkinPack skin) async {
    await _engine.loadSkin(skin);
    _notify();
  }

  /// 恢复内置默认主题。
  Future<void> resetTheme() async {
    await _engine.reset();
    _notify();
  }

  /// 设置明暗模式偏好。
  ///
  /// 变更后自动落盘（见 [saveToStorage]），杀进程重开仍保留。
  void setBrightness(Brightness b) {
    if (_brightness == b) return;
    _brightness = b;
    _notify();
    // 不 await：同步接口，落盘失败只记日志。
    unawaited(saveToStorage());
  }

  /// 预览皮肤效果，**不改变**当前状态、不通知 UI。
  AppTheme previewSkin(SkinPack skin) => _engine.preview(skin);

  // ————————————————— 持久化（settings Box） —————————————————

  /// 从 `settings` Box 恢复明暗模式偏好。
  ///
  /// 没存过、空串或值无法识别时保持当前值（默认 `Brightness.light`），不崩溃。
  Future<void> loadFromStorage() async {
    try {
      final String? raw = StorageService.settingsBox.get(kThemeBrightnessKey);
      final Brightness? stored = decodeBrightness(raw);
      if (stored == null || stored == _brightness) return;
      _brightness = stored;
      _notify();
    } catch (error, stackTrace) {
      debugPrint('ThemeProvider.loadFromStorage 失败（保持默认偏好）: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 把明暗模式偏好写入 `settings` Box（值取 `Brightness.name`：`light` / `dark`）。
  Future<void> saveToStorage() async {
    try {
      await StorageService.settingsBox
          .put(kThemeBrightnessKey, _brightness.name);
    } catch (error, stackTrace) {
      debugPrint('ThemeProvider.saveToStorage 失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 解析存储里的明暗偏好；无法识别返回 `null`（调用方保持默认）。
  static Brightness? decodeBrightness(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    switch (raw.trim().toLowerCase()) {
      case 'light':
        return Brightness.light;
      case 'dark':
        return Brightness.dark;
      default:
        debugPrint('ThemeProvider: 无法识别的明暗偏好 "$raw"，改用默认值');
        return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _engine.dispose();
    super.dispose();
  }

  /// 已释放则不再通知：`applySkin` / `resetTheme` 是异步的，
  /// 若在 await 期间 Provider 被 dispose，直接 `notifyListeners` 会触发 assert。
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}