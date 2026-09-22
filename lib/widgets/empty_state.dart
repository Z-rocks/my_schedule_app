// 通用空态组件：图标 + 主文案 + 可选副文案 + 可选操作按钮
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/theme_extension.dart';

/// 空态图标尺寸（逻辑像素）。
///
/// [AppTheme] 没有图标尺寸令牌，而空态图标需要一个统一的大尺寸，
/// 因此在这里定义组件级常量（按 CONTEXT.md 4.1 的 `k` 前缀小驼峰命名）。
const double kEmptyStateIconSize = 80;

/// 通用空态占位：所有模块页面在没有数据时都使用本组件。
///
/// 样式全部来自 [AppThemeExtension]，不在页面里硬编码颜色 / 字号 / 圆角。
class EmptyState extends StatelessWidget {
  /// 空态图标。
  final IconData icon;

  /// 主文案（必填）。
  final String title;

  /// 副文案，`null` 表示不显示。
  final String? subtitle;

  /// 操作按钮文字，`null` 表示不显示按钮。
  final String? actionLabel;

  /// 操作按钮回调。与 [actionLabel] 同时提供才会显示按钮。
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    // 图标与副文案用正文色的低透明度版本，保证在亮 / 暗背景下都柔和可读。
    final Color hintColor = theme.onBackground.withValues(alpha: 0.35);
    final String? subtitle = this.subtitle;
    final String? actionLabel = this.actionLabel;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(theme.cardPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: kEmptyStateIconSize, color: hintColor),
            SizedBox(height: theme.sectionGap),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: theme.titleSize,
                fontWeight: theme.titleFontWeight,
                color: theme.onBackground,
              ),
            ),
            if (subtitle != null) ...<Widget>[
              SizedBox(height: theme.gridGap * 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: theme.captionSize,
                  color: hintColor,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              SizedBox(height: theme.sectionGap),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: theme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.buttonRadius),
                  ),
                ),
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}