// 插件详情页：展示单个插件的元信息、运行时状态与操作入口
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plugin_meta.dart';
import '../../providers/plugin_provider.dart';
import '../../runtime/plugin_handle.dart';
import '../../services/plugin_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import 'plugin_manage_page.dart'
    show
        PluginUiStatus,
        pluginUiStatusColor,
        pluginUiStatusLabel,
        pluginUiStatusOf;

/// 插件详情页。
///
/// 数据全部来自 `PluginProvider`（`context.watch` 保证启停 / 加载结果实时反映）。
/// 安装路径是**异步**读的（`PluginStorageService.getPluginJsPath`），
/// 用 `FutureBuilder` 展示。
class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({super.key, required this.pluginId});

  /// 要展示的插件 id。插件被卸载后本页会显示"插件不存在"。
  final String pluginId;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final PluginProvider provider = context.watch<PluginProvider>();
    final PluginMeta? meta = provider.getById(pluginId);

    if (meta == null) {
      // 卸载后（或 id 失效）的兜底，避免空指针。
      return Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(title: const Text('插件详情'), centerTitle: true),
        body: Center(
          child: Text(
            '插件不存在或已卸载',
            style: TextStyle(
              fontSize: theme.bodySize,
              color: theme.onBackground.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    final PluginHandle? handle = provider.getHandle(pluginId);
    final String? error = provider.loadErrorOf(pluginId);
    final PluginUiStatus status = pluginUiStatusOf(
      enabled: meta.enabled,
      isLoaded: handle?.isUsable ?? false,
      hasError: error != null,
    );

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(meta.name, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        actions: <Widget>[
          // 只有**不可卸载**的插件才隐藏入口（`isRemovable == false`，
          // 留给硬编码的系统级插件）。来源为 builtin 的插件照样能卸载——
          // 例如从 assets 安装的示例插件（Phase 3.5.1 修正）。
          if (meta.isRemovable)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '卸载',
              onPressed: () => _confirmUninstall(context, provider, meta),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(theme.cardPadding),
        children: <Widget>[
          _InfoCard(
            title: '基本信息',
            children: <Widget>[
              _InfoRow(label: '插件 ID', value: meta.id),
              _InfoRow(label: '版本', value: meta.version),
              _InfoRow(
                label: '作者',
                value: meta.author.trim().isEmpty ? '未知作者' : meta.author,
              ),
              _InfoRow(
                label: '描述',
                value: meta.description.trim().isEmpty
                    ? '（无描述）'
                    : meta.description,
              ),
              _InfoRow(
                label: '能力',
                value: meta.effectiveCapabilities.isEmpty
                    ? '（未声明）'
                    : meta.effectiveCapabilities.join(' · '),
              ),
              _InfoRow(
                label: '来源',
                value: _sourceLabel(meta.source),
              ),
              _InstallPathRow(pluginId: pluginId),
              _InfoRow(
                label: '加载状态',
                value: '${pluginUiStatusLabel(status)}'
                    '${error == null ? '' : '：$error'}',
                valueColor: pluginUiStatusColor(status, theme),
              ),
            ],
          ),
          SizedBox(height: theme.cardPadding),
          _InfoCard(
            title: '运行时',
            children: <Widget>[
              _InfoRow(
                label: '沙箱',
                value: handle == null
                    ? '未创建'
                    : (handle.isUsable ? '可用' : '不可用'),
              ),
              _InfoRow(
                label: '入口函数',
                value: (handle?.entries.isEmpty ?? true)
                    ? '（无）'
                    : handle!.entries.join(' · '),
              ),
              if (handle != null && !handle.isUsable)
                _InfoRow(
                  label: '降级原因',
                  value: handle.reason ?? '（未记录）',
                  valueColor: theme.error,
                ),
            ],
          ),
          SizedBox(height: theme.cardPadding),
          _InfoCard(
            title: '操作',
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '启用',
                  style: TextStyle(
                    fontSize: theme.bodySize,
                    color: theme.onBackground,
                  ),
                ),
                value: meta.enabled,
                onChanged: (bool value) =>
                    provider.togglePlugin(meta.id, value),
              ),
              // 以下三项留给后续阶段，先占位（CONTEXT 要求用户可见错误用 SnackBar）。
              _ActionRow(
                icon: Icons.login,
                label: '登录',
                onTap: () => _snack(context, '登录（Phase 4 实现）'),
              ),
              _ActionRow(
                icon: Icons.sync,
                label: '立即同步',
                onTap: () => _snack(context, '立即同步（Phase 4 实现）'),
              ),
              _ActionRow(
                icon: Icons.article_outlined,
                label: '查看日志',
                onTap: () => _snack(context, '查看日志（Phase 3 后实现）'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 卸载：先确认，再移除（会销毁运行时沙箱并删存储），最后退回列表页。
  Future<void> _confirmUninstall(
    BuildContext context,
    PluginProvider provider,
    PluginMeta meta,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text('确定要卸载插件「${meta.name}」吗？这会删除插件文件与本地数据。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await provider.removePlugin(meta.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 安装来源的中文标签。
  static String _sourceLabel(String source) {
    switch (source) {
      case 'builtin':
        return '内置';
      case 'workshop':
        return '创意工坊';
      case 'local':
        return '本地导入';
      default:
        return source;
    }
  }
}

/// 分区卡片（标题 + 若干行）。
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return Card(
      color: theme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                fontSize: theme.bodySize,
                fontWeight: theme.titleFontWeight,
                color: theme.onBackground,
              ),
            ),
            SizedBox(height: theme.gridGap * 2),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 一行"标签 : 值"。值可换行（描述、错误详情可能很长）。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final Color labelColor = theme.onBackground.withValues(alpha: 0.55);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.gridGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: theme.captionSize, color: labelColor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: valueColor ?? theme.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "安装路径"行：异步读文件系统，读到之前显示"读取中…"。
class _InstallPathRow extends StatelessWidget {
  const _InstallPathRow({required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: PluginStorageService.getPluginJsPath(pluginId),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        final String value;
        if (snapshot.connectionState != ConnectionState.done) {
          value = '读取中…';
        } else if (snapshot.hasError) {
          value = '读取失败';
        } else {
          value = snapshot.data ?? '未安装（插件目录中找不到 .js 文件）';
        }
        return _InfoRow(label: '安装路径', value: value);
      },
    );
  }
}

/// 一行可点击的操作项。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.primary),
      title: Text(
        label,
        style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.onBackground.withValues(alpha: 0.3),
      ),
      onTap: onTap,
    );
  }
}
