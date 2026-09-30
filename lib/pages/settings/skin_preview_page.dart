// 皮肤预览页（Phase 6）：用皮肤令牌渲染一小段"假 UI"，确认效果后再应用。
//
// 为什么单独一页而不是在列表里直接应用：配色是"看一眼才知道好不好"的东西，
// 而应用后要改回来需要再进一次设置。预览页把"试"和"定"分开，
// 并在页内提供「应用」按钮，避免用户来回跳。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/skin_pack.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';

/// 皮肤预览页。
///
/// **不修改全局主题**：整页用 `Theme(data: ...)` 局部套用候选皮肤的
/// `ThemeData`，所以退出页面即恢复原样，不会"看个预览把主题改了"。
class SkinPreviewPage extends StatelessWidget {
  const SkinPreviewPage({super.key, required this.skin});

  /// 要预览的皮肤。
  final SkinPack skin;

  @override
  Widget build(BuildContext context) {
    final ThemeProvider provider = context.watch<ThemeProvider>();
    // 用候选皮肤合成一份主题（不改变 provider 的状态），
    // 明暗取用户当前的实际偏好，这样预览与"应用后看到的样子"一致。
    final AppTheme themed =
        provider.previewSkin(skin).withBrightness(provider.brightness);

    return Theme(
      data: _themeData(themed, provider.brightness),
      child: Builder(
        builder: (BuildContext inner) {
          final AppTheme t = AppThemeExtension.of(inner);
          return Scaffold(
            backgroundColor: t.background,
            appBar: AppBar(
              title: Text('预览：${skin.name}'),
              centerTitle: true,
            ),
            body: ListView(
              padding: EdgeInsets.all(t.cardPadding),
              children: <Widget>[
                _SectionTitle(theme: t, text: '皮肤信息'),
                _Card(
                  theme: t,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Row(theme: t, label: '名称', value: skin.name),
                      _Row(theme: t, label: '作者', value: skin.author),
                      _Row(theme: t, label: '版本', value: skin.version),
                      _Row(
                        theme: t,
                        label: '色表',
                        value: skin.supportsDarkMode ? '亮色 + 暗色' : '仅亮色',
                      ),
                      if (skin.description.isNotEmpty)
                        _Row(theme: t, label: '说明', value: skin.description),
                    ],
                  ),
                ),
                SizedBox(height: t.sectionGap),

                _SectionTitle(theme: t, text: '课表效果'),
                // 用几门假课程拼出真实课表的样子——这是用户最常看的一屏。
                _Card(
                  theme: t,
                  padding: EdgeInsets.all(t.gridGap),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          _TimeCell(theme: t, text: '1\n08:30\n09:15'),
                          _DemoCourse(
                            theme: t,
                            name: '高等数学',
                            room: 'HE-405',
                            color: _courseColor(t, 0),
                          ),
                          _DemoCourse(
                            theme: t,
                            name: '大学英语',
                            room: 'HA-201',
                            color: _courseColor(t, 1),
                          ),
                          _DemoCourse(
                            theme: t,
                            name: '软件工程',
                            room: 'HA-416',
                            color: _courseColor(t, 2),
                          ),
                        ],
                      ),
                      SizedBox(height: t.gridGap),
                      Row(
                        children: <Widget>[
                          _TimeCell(theme: t, text: '2\n09:20\n10:05'),
                          _DemoCourse(
                            theme: t,
                            name: '线性代数',
                            room: 'HB-108',
                            color: _courseColor(t, 3),
                          ),
                          const Spacer(),
                          _DemoCourse(
                            theme: t,
                            name: '体育',
                            room: '操场',
                            color: _courseColor(t, 4),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: t.sectionGap),

                _SectionTitle(theme: t, text: '组件效果'),
                _Card(
                  theme: t,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '标题文字（titleSize ${t.titleSize.toStringAsFixed(0)}）',
                        style: TextStyle(
                          fontSize: t.titleSize,
                          fontWeight: t.titleFontWeight,
                          color: t.onBackground,
                        ),
                      ),
                      SizedBox(height: t.gridGap),
                      Text(
                        '正文文字（bodySize ${t.bodySize.toStringAsFixed(0)}）',
                        style: TextStyle(
                          fontSize: t.bodySize,
                          color: t.onBackground,
                        ),
                      ),
                      SizedBox(height: t.gridGap),
                      Text(
                        '辅助说明（captionSize ${t.captionSize.toStringAsFixed(0)}）',
                        style: TextStyle(
                          fontSize: t.captionSize,
                          color: t.onBackground.withValues(alpha: 0.6),
                        ),
                      ),
                      SizedBox(height: t.sectionGap),
                      Wrap(
                        spacing: t.gridGap * 2,
                        runSpacing: t.gridGap * 2,
                        children: <Widget>[
                          FilledButton(
                            onPressed: () {},
                            style: FilledButton.styleFrom(
                              backgroundColor: t.primary,
                              foregroundColor: t.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(t.buttonRadius),
                              ),
                            ),
                            child: const Text('主要按钮'),
                          ),
                          OutlinedButton(
                            onPressed: () {},
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.primary,
                              side: BorderSide(color: t.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(t.buttonRadius),
                              ),
                            ),
                            child: const Text('次要按钮'),
                          ),
                          Chip(
                            label: const Text('标签'),
                            backgroundColor:
                                t.primary.withValues(alpha: 0.12),
                            labelStyle: TextStyle(
                              fontSize: t.captionSize,
                              color: t.primary,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(t.chipRadius),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: t.sectionGap),
                      Row(
                        children: <Widget>[
                          _StatusDot(theme: t, color: t.success, label: '成功'),
                          SizedBox(width: t.sectionGap),
                          _StatusDot(theme: t, color: t.warning, label: '警告'),
                          SizedBox(width: t.sectionGap),
                          _StatusDot(theme: t, color: t.error, label: '错误'),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: t.sectionGap * 1.5),

                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    SizedBox(width: t.gridGap * 2),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _apply(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: t.primary,
                          foregroundColor: t.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                        child: const Text('应用这套皮肤'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 用**候选皮肤**构造 `ThemeData`（与 `MyApp._themeData` 同思路）。
  ThemeData _themeData(AppTheme t, Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: t.primary,
        brightness: brightness,
      ),
      useMaterial3: true,
      fontFamily: t.fontFamily.isEmpty ? null : t.fontFamily,
      scaffoldBackgroundColor: t.background,
      extensions: <ThemeExtension<dynamic>>[
        AppThemeExtension(theme: t),
      ],
    );
  }

  /// 课程卡片配色：优先用皮肤的配色池，没有则回落到主题的。
  static Color _courseColor(AppTheme theme, int index) {
    if (theme.courseCardColors.isEmpty) return theme.surface;
    return theme.courseCardColors[index % theme.courseCardColors.length];
  }

  Future<void> _apply(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ThemeProvider provider = context.read<ThemeProvider>();
    await provider.applySkin(skin);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('已应用皮肤「${skin.name}」')),
    );
  }
}

/// 时间列单元格（与真实课表同款的上下两行时间）。
class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.theme, required this.text});

  final AppTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: theme.timetableTimeColumnWidth,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: theme.captionSize * 0.9,
          color: theme.onBackground.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// 演示用课程卡片。
class _DemoCourse extends StatelessWidget {
  const _DemoCourse({
    required this.theme,
    required this.name,
    required this.room,
    required this.color,
  });

  final AppTheme theme;
  final String name;
  final String room;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: theme.timetableCellHeight,
        margin: EdgeInsets.symmetric(horizontal: theme.gridGap / 2),
        padding: EdgeInsets.symmetric(
          horizontal: 3,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(theme.cardRadius / 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: theme.bodySize,
                fontWeight: theme.titleFontWeight,
                // 课程卡片的文字色由**卡片底色**决定，不能用 onBackground：
                // 暗色模式下 onBackground 是浅色，而卡片底色也被推导成深色，
                // 两者对比度刚好够；但亮色皮肤下卡片是浅色，必须用深字。
                color: _textOn(color, theme),
              ),
            ),
            Text(
              room,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: _textOn(color, theme).withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片底色上可读的文字色。
  static Color _textOn(Color background, AppTheme theme) =>
      background.computeLuminance() > 0.5
          ? const Color(0xFF1A1A1A)
          : const Color(0xFFEDEDED);
}

/// 状态圆点 + 文字。
class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.theme,
    required this.color,
    required this.label,
  });

  final AppTheme theme;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: theme.captionSize,
          height: theme.captionSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: theme.gridGap),
        Text(
          label,
          style: TextStyle(fontSize: theme.captionSize, color: theme.onBackground),
        ),
      ],
    );
  }
}

/// 分区标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.theme, required this.text});

  final AppTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: theme.cardPadding / 2,
        bottom: theme.gridGap * 2,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: theme.captionSize,
          fontWeight: theme.titleFontWeight,
          color: theme.primary,
        ),
      ),
    );
  }
}

/// 一张卡片（用候选皮肤的 surface / 圆角 / 阴影）。
class _Card extends StatelessWidget {
  const _Card({
    required this.theme,
    required this.child,
    this.padding,
  });

  final AppTheme theme;
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? EdgeInsets.all(theme.cardPadding),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.cardShadowColor,
            blurRadius: theme.cardShadowBlur,
            offset: Offset(0, theme.cardShadowOffsetY),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 「标签 : 值」一行。
class _Row extends StatelessWidget {
  const _Row({required this.theme, required this.label, required this.value});

  final AppTheme theme;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.gridGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: theme.timetableTimeColumnWidth * 1.5,
            child: Text(
              label,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.55),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '（未填写）' : value,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
