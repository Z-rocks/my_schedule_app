// 主题扩展：把 AppTheme 挂到 Flutter ThemeData 上，供 UI 通过 context 读取
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 把 [AppTheme] 注册进 `ThemeData.extensions`，让任意组件都能读到主题令牌。
///
/// UI 侧统一这样取样式（CONTEXT.md 3.2 要求，禁止硬编码颜色/圆角/间距/字体）：
/// ```dart
/// final AppTheme theme = AppThemeExtension.of(context);
/// Container(decoration: BoxDecoration(color: theme.surface, ...))
/// ```
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  /// 被托管的主题令牌集合。
  final AppTheme theme;

  const AppThemeExtension({required this.theme});

  /// 读取当前主题；没有注册扩展时回退到内置默认主题，保证不会崩。
  static AppTheme of(BuildContext context) =>
      maybeOf(context) ?? AppTheme.defaultTheme();

  /// 读取当前主题；未注册扩展时返回 `null`。
  static AppTheme? maybeOf(BuildContext context) =>
      Theme.of(context).extension<AppThemeExtension>()?.theme;

  @override
  AppThemeExtension copyWith({AppTheme? theme}) =>
      AppThemeExtension(theme: theme ?? this.theme);

  /// **Phase 1 简化实现**：直接返回 `this`，不做颜色/尺寸插值。
  ///
  /// 主题切换是瞬时的（皮肤切换后整棵子树直接读新令牌），
  /// 渐变过渡留到 Phase 6 与暗色模式一起处理。
  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) =>
      this;

  @override
  String toString() => 'AppThemeExtension(theme: $theme)';
}