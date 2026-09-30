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

  /// 当前皮肤（`null` = 内置默认主题）。
  ///
  /// Phase 6 需要它：切换明暗模式时要**用同一份皮肤**重新合成主题，
  /// 不能只把已合成的结果再推导一遍（那会丢掉皮肤的原始色表）。
  SkinPack? _skin;

  /// 当前生效的明暗模式（Phase 6）。
  Brightness _brightness = Brightness.light;

  /// 当前生效的主题。
  AppTheme get current => _current;

  /// 当前生效的皮肤 ID，空字符串表示使用内置默认主题。
  String get currentSkinId => _currentSkinId;

  /// 当前皮肤；`null` 表示内置默认主题。
  SkinPack? get skin => _skin;

  /// 当前生效的明暗模式。
  Brightness get brightness => _brightness;

  /// 加载并应用一份皮肤。
  ///
  /// 流程：`SkinPack` → 主题 JSON → [AppTheme.fromJson] → merge 到默认主题 → 通知。
  /// 任何解析异常都被吞掉并 `debugPrint`，保证皮肤有问题时 App 仍能用默认主题运行。
  ///
  /// **Phase 6**：`skin.mode == 'system'` 时按 [brightness] 选色表——
  /// 这让"同一个皮肤在明暗两种模式下都好看"成为可能（皮肤给了两套色表时）。
  Future<void> loadSkin(SkinPack skin, {Brightness? brightness}) async {
    try {
      _skin = skin;
      final Brightness target = brightness ?? _brightness;
      _brightness = target;
      _current = _compose(skin, target);
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
  AppTheme preview(SkinPack skin, {Brightness? brightness}) {
    try {
      return _compose(skin, brightness ?? _brightness);
    } catch (error, stackTrace) {
      debugPrint('ThemeEngine.preview 失败（已回退默认主题）: $error');
      debugPrint('$stackTrace');
      return AppTheme.defaultTheme();
    }
  }

  /// 切换明暗模式（**Phase 6**）。
  ///
  /// 有皮肤时**用同一份皮肤重新合成**（而不是把已合成的主题再推导一次）；
  /// 没有皮肤时对内置默认主题做推导。两种情况都会重算并通知。
  void setBrightness(Brightness brightness) {
    if (_brightness == brightness) return;
    _brightness = brightness;
    final SkinPack? skin = _skin;
    _current = skin == null
        ? AppTheme.defaultTheme().withBrightness(brightness)
        : _compose(skin, brightness);
    _notify();
  }

  /// 恢复内置默认主题。
  Future<void> reset() async {
    _skin = null;
    _current = AppTheme.defaultTheme().withBrightness(_brightness);
    _currentSkinId = '';
    _notify();
  }

  /// 直接应用一个已构造好的主题（用户自定义微调 / 主题编辑器用）。
  void applyTheme(AppTheme theme) {
    _current = theme;
    _currentSkinId = '';
    _skin = null;
    _notify();
  }

  /// 皮肤 + 明暗模式 → 最终主题。
  ///
  /// 两步（顺序很重要）：
  /// 1. 按 [brightness] 选皮肤的色表并 merge 到默认主题 —— 得到"皮肤原始配色"；
  /// 2. `withBrightness(brightness)` 校正明暗关系 —— 皮肤只给了一套亮色表时，
  ///    这一步保证暗色模式下背景深、文字浅、卡片分层。
  AppTheme _compose(SkinPack skin, Brightness brightness) {
    final AppTheme merged = AppTheme.defaultTheme().merge(_themeOf(skin, brightness));
    return merged.withBrightness(brightness);
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
  ///
  /// [brightness] 决定优先用哪张色表（**Phase 6**）：
  /// - 皮肤 `mode == 'dark'` → 暗色表；
  /// - 皮肤 `mode == 'system'` → 按 [brightness] 选，**这才让同一个皮肤在
  ///   明暗两种模式下都好看**（皮肤给了两套色表时）；
  /// - 皮肤 `mode == 'light'` → 强制亮色表（皮肤作者的明确意图，不随系统变）。
  ///
  /// 所选色表缺 `darkColors` 时回落亮色表，再由
  /// [AppTheme.withBrightness] 推导出可用的暗色取值。
  AppTheme _themeOf(SkinPack skin, [Brightness brightness = Brightness.light]) {
    final Map<String, dynamic> json = <String, dynamic>{};

    final String mode = skin.mode.trim().toLowerCase();
    final bool preferDark = mode == 'dark' ||
        (mode != 'light' &&
            brightness == Brightness.dark &&
            skin.supportsDarkMode);
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