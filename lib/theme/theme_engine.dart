// 主题引擎：把皮肤包（SkinPack）解析成 AppTheme 并管理"当前主题"状态
import 'package:flutter/foundation.dart';

import '../models/skin_pack.dart';
import 'app_theme.dart';

/// 皮肤令牌名 → AppTheme 字段名的别名表。
///
/// 皮肤作者写的是通用令牌（`card` / `textPrimary`），
/// AppTheme 用的是语义化字段名（`surface` / `onBackground`）。
/// 不在表中的令牌按同名直接映射；表里没有且字段也不存在的令牌会被忽略。
const Map<String, String> _kSkinTokenAliases = <String, String>{
  'card': 'surface',
  'textPrimary': 'onBackground',
  'textSecondary': 'onBackground',
  'courseColors': 'courseCardColors',
};

/// 主题引擎：持有当前生效的 [AppTheme]，皮肤切换后通知 UI 重建。
///
/// 职责边界：本类只做"皮肤 → 主题"的转换与状态管理，
/// 不做持久化（Phase 2 接 Hive `settings`）也不碰 UI。
class ThemeEngine extends ChangeNotifier {
  AppTheme _current = AppTheme.defaultTheme();
  String _currentSkinId = '';
  bool _disposed = false;

  /// 当前生效的主题。
  AppTheme get current => _current;

  /// 当前生效的皮肤 ID，空字符串表示使用内置默认主题。
  ///
  /// Phase 2 会把它写入 Hive `settings`（见 CONTEXT.md 3.5）。
  String get currentSkinId => _currentSkinId;

  /// 加载并应用一份皮肤。
  ///
  /// 流程：`SkinPack` → 主题 JSON → [AppTheme.fromJson] → merge 到默认主题 → 通知。
  /// 任何解析异常都被吞掉并 `debugPrint`，保证皮肤有问题时 App 仍能用默认主题运行。
  Future<void> loadSkin(SkinPack skin) async {
    try {
      final AppTheme merged = AppTheme.defaultTheme().merge(_themeOf(skin));
      _current = merged;
      _currentSkinId = skin.id;
      _notify();
    } catch (error, stackTrace) {
      debugPrint('ThemeEngine.loadSkin 失败（已保持原主题）: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 预览一份皮肤的效果，**不改变**当前状态。
  ///
  /// 返回值与 [loadSkin] 应用后的结果一致（同样以默认主题为基线）。
  AppTheme preview(SkinPack skin) {
    try {
      return AppTheme.defaultTheme().merge(_themeOf(skin));
    } catch (error) {
      debugPrint('ThemeEngine.preview 失败（已回退默认主题）: $error');
      return AppTheme.defaultTheme();
    }
  }

  /// 恢复内置默认主题。
  Future<void> reset() async {
    _current = AppTheme.defaultTheme();
    _currentSkinId = '';
    _notify();
  }

  /// 直接应用一个已构造好的主题（用户自定义微调 / 主题编辑器用）。
  void applyTheme(AppTheme theme) {
    _current = theme;
    _currentSkinId = '';
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 已释放则不再通知：[loadSkin] / [reset] 是异步的，
  /// 若在 await 期间被 dispose（例如宿主 Provider 先释放），
  /// 直接 `notifyListeners` 会触发 `ChangeNotifier` 的 assert。
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 把皮肤包转换成"主题 JSON"，交给 [AppTheme.fromJson] 解析。
  ///
  /// 颜色直接用 ARGB 整数传入（`AppTheme.fromJson` 兼容整数与 hex 字符串）。
  AppTheme _themeOf(SkinPack skin) {
    final Map<String, dynamic> json = <String, dynamic>{};

    // 按皮肤声明的模式选色表；暗色表缺失时回落亮色表。
    final bool preferDark = skin.mode.trim().toLowerCase() == 'dark';
    final Map<String, int> palette =
        preferDark && skin.supportsDarkMode ? skin.darkColors : skin.lightColors;

    palette.forEach((String token, int argb) {
      final String key = _kSkinTokenAliases[token] ?? token;
      json[key] = argb;
    });

    if (skin.courseColors.isNotEmpty) {
      json['courseCardColors'] = skin.courseColors;
    }
    if (skin.borderRadius > 0) {
      json['cardRadius'] = skin.borderRadius;
    }
    if (skin.fontFamily.isNotEmpty) {
      json['fontFamily'] = skin.fontFamily;
    }
    // 皮肤的 elevation 语义上是"卡片抬升高度"，映射到阴影垂直偏移。
    if (skin.elevation > 0) {
      json['cardShadowOffsetY'] = skin.elevation;
    }

    return AppTheme.fromJson(json);
  }
}