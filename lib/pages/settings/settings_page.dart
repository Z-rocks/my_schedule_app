// 设置主页：分组列出账号 / 扩展 / 外观 / 布局 / 数据 / 关于入口
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../theme/default_skins.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import 'module_config_page.dart';
import 'plugin_manage_page.dart';
import 'timetable_settings_page.dart';
import 'widget_guide_page.dart';
import 'workshop_page.dart';

/// 应用版本号。
///
/// 修改版本号时需同步 `pubspec.yaml` 的 `version` 字段（两处目前各自维护）。
/// Phase 9 打包后改用 `package_info_plus` 运行时读取。
///
/// 这里用常量而不是 `package_info_plus`：项目技术栈（CONTEXT.md 第 2 节）
/// 未声明该依赖，Phase 9 打包时再改为运行时读取。
const String kAppVersion = 'v0.1.0';

/// 设置主页。
///
/// Phase 1.6 只搭结构：除"导航栏配置"外，其余条目都是占位（点击弹 SnackBar
/// 或跳转到占位页），不读写任何持久化数据。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 「当前主题」的展示值（**Phase 6**）。
  ///
  /// 只在内置皮肤里查名字：asset 皮肤的名字要异步读 bundle，
  /// 而这是同步的 `trailingText`。查不到就显示"自定义皮肤"——
  /// 比显示一串 id 友好。
  static String _currentThemeLabel(BuildContext context) {
    final String id = context.watch<ThemeProvider>().currentSkinId;
    if (id.isEmpty) return '默认蓝';
    for (final skin in builtinSkins()) {
      if (skin.id == id) return skin.name;
    }
    return '自定义皮肤';
  }

  /// 选择明暗模式（**Phase 6**）：亮色 / 暗色 / 跟随系统。
  ///
  /// 用底部弹层而不是三态循环点击：三态循环要用户记住"点几下到哪一档"，
  /// 而三选一的语义直接列出来更清楚。
  Future<void> _pickBrightnessMode(BuildContext context) async {
    final ThemeProvider provider = context.read<ThemeProvider>();
    final AppTheme theme = AppThemeExtension.of(context);
    final ThemeBrightnessMode current = provider.mode;

    final ThemeBrightnessMode? picked =
        await showModalBottomSheet<ThemeBrightnessMode>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(theme.cardPadding),
              child: Text(
                '深色模式',
                style: TextStyle(
                  fontSize: theme.titleSize,
                  fontWeight: theme.titleFontWeight,
                  color: theme.onBackground,
                ),
              ),
            ),
            for (final ThemeBrightnessMode mode
                in ThemeBrightnessMode.values)
              ListTile(
                title: Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: theme.bodySize,
                    color: theme.onBackground,
                  ),
                ),
                subtitle: mode == ThemeBrightnessMode.system
                    ? Text(
                        '当前系统为'
                        '${provider.systemBrightness == Brightness.dark ? '暗色' : '亮色'}',
                        style: TextStyle(
                          fontSize: theme.captionSize,
                          color: theme.onBackground.withValues(alpha: 0.6),
                        ),
                      )
                    : null,
                trailing: mode == current
                    ? Icon(Icons.check, color: theme.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(mode),
              ),
          ],
        ),
      ),
    );

    if (picked == null || !context.mounted) return;
    provider.setMode(picked);
    _showSnack(context, '已切换为「${picked.label}」');
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => page),
    );
  }

  /// "清理缓存"：先弹确认框，确认后才提示（Phase 2 接真实清理）。
  Future<void> _confirmClearCache(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('将清除临时文件与图片缓存，不会删除课程数据。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    // showDialog 是异步的，回来时页面可能已被销毁。
    if (confirmed != true || !context.mounted) return;
    _showSnack(context, '已清理（待实现）');
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: theme.sectionGap),
        children: <Widget>[
          _SettingsGroup(
            title: '账号',
            children: <Widget>[
              _SettingsTile(
                title: '登录管理',
                showChevron: true,
                onTap: () => _showSnack(context, '登录管理（待实现）'),
              ),
            ],
          ),
          _SettingsGroup(
            title: '扩展',
            children: <Widget>[
              _SettingsTile(
                title: '插件管理',
                showChevron: true,
                onTap: () => _push(context, const PluginManagePage()),
              ),
              _SettingsTile(
                title: '创意工坊',
                showChevron: true,
                onTap: () => _push(context, const WorkshopPage()),
              ),
            ],
          ),
          _SettingsGroup(
            title: '外观',
            children: <Widget>[
              _SettingsTile(
                title: '深色模式',
                // Phase 6：显示当前偏好（亮色 / 暗色 / 跟随系统）
                trailingText: context.watch<ThemeProvider>().mode.label,
                showChevron: true,
                onTap: () => _pickBrightnessMode(context),
              ),
              _SettingsTile(
                title: '当前主题',
                trailingText: _currentThemeLabel(context),
                showChevron: true,
                onTap: () => _push(context, const WorkshopPage()),
              ),
            ],
          ),
          _SettingsGroup(
            title: '布局',
            children: <Widget>[
              _SettingsTile(
                title: '导航栏配置',
                showChevron: true,
                onTap: () => _push(context, const ModuleConfigPage()),
              ),
              _SettingsTile(
                title: '课表设置',
                showChevron: true,
                onTap: () => _push(context, const TimetableSettingsPage()),
              ),
            ],
          ),
          _SettingsGroup(
            title: '桌面小组件',
            children: <Widget>[
              _SettingsTile(
                title: '添加与使用',
                showChevron: true,
                onTap: () => _push(context, const WidgetGuidePage()),
              ),
              _SettingsTile(
                title: '后台刷新设置',
                subtitleText: '让卡片随数据变化即时更新',
                showChevron: true,
                onTap: () => _push(
                  context,
                  const WidgetGuidePage(
                    initialSection: WidgetGuideSection.battery,
                  ),
                ),
              ),
            ],
          ),
          _SettingsGroup(
            title: '数据',
            children: <Widget>[
              _SettingsTile(
                title: '导出数据',
                onTap: () => _showSnack(context, '导出（待实现）'),
              ),
              _SettingsTile(
                title: '导入数据',
                onTap: () => _showSnack(context, '导入（待实现）'),
              ),
              _SettingsTile(
                title: '清理缓存',
                onTap: () => _confirmClearCache(context),
              ),
            ],
          ),
          _SettingsGroup(
            title: '关于',
            children: <Widget>[
              // 版本号不可点击。
              _SettingsTile(title: '版本号', trailingText: kAppVersion),
              _SettingsTile(
                title: '反馈',
                onTap: () => _showSnack(context, '反馈（待实现）'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一个设置分组：小标题 + 一张卡片。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: theme.cardPadding,
        right: theme.cardPadding,
        bottom: theme.sectionGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(
              left: theme.cardPadding / 2,
              bottom: theme.gridGap * 2,
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: theme.captionSize,
                fontWeight: theme.titleFontWeight,
                color: theme.primary,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            color: theme.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.cardRadius),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// 分组内的一行。
///
/// [onTap] 为 `null` 时该行不可点击（如"版本号"）。
/// [showChevron] 用于可跳转的条目，[trailingText] 用于展示只读值。
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.onTap,
    this.showChevron = false,
    this.trailingText,
    this.subtitleText,
  });

  final String title;
  final VoidCallback? onTap;
  final bool showChevron;
  final String? trailingText;
  final String? subtitleText;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final String? trailingText = this.trailingText;
    final String? subtitleText = this.subtitleText;

    return ListTile(
      title: Text(
        title,
        style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
      ),
      subtitle: subtitleText == null
          ? null
          : Text(
              subtitleText,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.6),
              ),
            ),
      onTap: onTap,
      trailing: (trailingText == null && !showChevron)
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (trailingText != null)
                  Text(
                    trailingText,
                    style: TextStyle(
                      fontSize: theme.bodySize,
                      color: theme.onBackground.withValues(alpha: 0.6),
                    ),
                  ),
                if (showChevron)
                  Icon(
                    Icons.chevron_right,
                    color: theme.onBackground.withValues(alpha: 0.4),
                  ),
              ],
            ),
    );
  }
}