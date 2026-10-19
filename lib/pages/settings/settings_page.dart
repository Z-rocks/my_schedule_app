// 设置主页：分组列出扩展 / 外观 / 布局 / 数据 / 关于入口
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../services/app_version.dart';
import '../../services/system_bridge.dart';
import '../../services/update_service.dart';
import '../../theme/default_skins.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import 'module_config_page.dart';
import 'plugin_manage_page.dart';
import 'timetable_settings_page.dart';
import 'widget_guide_page.dart';
import 'workshop_page.dart';
import 'homework_reminder_page.dart';

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
                // 从"当前主题"进来显然是想换皮肤：直接落在皮肤 Tab，
                // 而不是创意工坊的默认页（插件市场）。
                onTap: () => _push(
                  context,
                  const WorkshopPage(initialTab: WorkshopTab.skins),
                ),
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
            title: '提醒',
            children: <Widget>[
              _SettingsTile(
                title: '作业提醒',
                subtitleText: '截止前按档位提醒，发通知前先查作业状态',
                showChevron: true,
                onTap: () => _push(context, const HomeworkReminderPage()),
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
              // 版本号不可点击：值来自系统包信息（`AppVersion` 经平台通道读取），
              // 不再写死常量——写死的那个曾经是 v0.1.0，与实际包 0.2.0+2 不符。
              FutureBuilder<String>(
                future: AppVersion.load(),
                builder: (
                  BuildContext context,
                  AsyncSnapshot<String> snapshot,
                ) =>
                    _SettingsTile(
                  title: '版本号',
                  trailingText:
                      snapshot.hasData ? 'v${snapshot.data}' : '读取中…',
                ),
              ),
              const _CheckUpdateTile(),
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

/// 「检查更新」条目：点一次查一次远端 Release（Gitee 镜像优先，GitHub 兜底）。
///
/// 抽成独立的 StatefulWidget，是因为"检查中"这个瞬时状态只需要重建这一行，
/// 不该让整个设置页跟着重建。
class _CheckUpdateTile extends StatefulWidget {
  const _CheckUpdateTile();

  @override
  State<_CheckUpdateTile> createState() => _CheckUpdateTileState();
}

class _CheckUpdateTileState extends State<_CheckUpdateTile> {
  /// 是否正在请求远端（防重入 + 行尾提示）。
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);

    final String current = await AppVersion.load();
    final UpdateCheckResult result =
        await UpdateService.check(currentVersion: current);

    if (!mounted) return;
    setState(() => _checking = false);

    if (result.status == UpdateStatus.upToDate) {
      // 带上来源：用户能看出是走 Gitee 镜像还是 GitHub 查到的。
      final String via = result.source.isEmpty ? '' : '（${result.source}）';
      _snack('已是最新版本 v$current$via');
    } else if (result.status == UpdateStatus.failed) {
      _snack(result.reason);
    } else {
      await _showUpdateDialog(result);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showUpdateDialog(UpdateCheckResult result) async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('发现新版本 v${result.latestVersion}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('当前版本 v${result.currentVersion}'),
              if (result.source.isNotEmpty)
                Text(
                  '下载源：${result.source}',
                  style: const TextStyle(fontSize: 12),
                ),
              if (result.changelog.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                // Release 正文是纯文本（可能带 Markdown 标记），这里原样展示：
                // 为了它引入一个 Markdown 渲染器不值得，用户关心的是"改了什么"。
                Text(result.changelog),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('前往下载'),
          ),
        ],
      ),
    );

    if (go != true || !mounted) return;

    final String url = result.downloadUrl;
    if (url.isEmpty) {
      _snack('这个 Release 没有可下载的文件');
      return;
    }

    final bool opened = await SystemBridge.openUrl(url);
    if (opened) return;

    // 兜底：非 Android 平台 / 没有浏览器可打开 → 复制链接，用户自己粘。
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _snack('已复制下载链接到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      title: '检查更新',
      trailingText: _checking ? '检查中…' : null,
      showChevron: !_checking,
      onTap: _checking ? null : _check,
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