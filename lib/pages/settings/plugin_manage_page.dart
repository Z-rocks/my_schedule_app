// 插件管理页：展示已安装插件列表，支持启停、查看详情与（占位）导入
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plugin_catalog.dart';
import '../../models/plugin_meta.dart';
import '../../providers/plugin_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/module_icon.dart';
import 'plugin_detail_page.dart';
import 'workshop_page.dart';

/// 状态徽章的四种状态（Phase 3.5）。
///
/// 抽成公开枚举 + [pluginUiStatusOf] 纯函数，是为了让"四态判定"能被**单独测试**，
/// 不必去 widget 树里找那个小圆点（与 `semester_config_page.dart` 导出
/// `dateOnly` / `mondayOfWeek` 等纯函数同一思路）。
enum PluginUiStatus {
  /// 已加载且沙箱可用 —— 一切正常。
  loaded,

  /// 加载失败（`loadErrors` 里有原因）。
  failed,

  /// 已启用但尚未加载成功（正在加载，或降级了但没记录原因）。
  enabledNotLoaded,

  /// 已停用。
  disabled,
}

/// 判定某个插件该显示哪种状态徽章。
///
/// **优先级**：加载失败 > 已加载 > 已启用未加载 > 已停用。
/// 失败优先于成功，是因为"失败原因"对用户最有价值，不该被其他状态盖掉。
PluginUiStatus pluginUiStatusOf({
  required bool enabled,
  required bool isLoaded,
  required bool hasError,
}) {
  if (hasError) return PluginUiStatus.failed;
  if (isLoaded) return PluginUiStatus.loaded;
  if (enabled) return PluginUiStatus.enabledNotLoaded;
  return PluginUiStatus.disabled;
}

/// 状态徽章的颜色。颜色一律取自 [AppTheme]，不硬编码。
Color pluginUiStatusColor(PluginUiStatus status, AppTheme theme) {
  switch (status) {
    case PluginUiStatus.loaded:
      return theme.success;
    case PluginUiStatus.failed:
      return theme.error;
    case PluginUiStatus.enabledNotLoaded:
      return theme.warning;
    case PluginUiStatus.disabled:
      // 灰：正文色的低透明度版本，明暗主题下都合适。
      return theme.onBackground.withValues(alpha: 0.3);
  }
}

/// 状态徽章的提示文案（tooltip / 无障碍）。
String pluginUiStatusLabel(PluginUiStatus status) {
  switch (status) {
    case PluginUiStatus.loaded:
      return '已加载';
    case PluginUiStatus.failed:
      return '加载失败';
    case PluginUiStatus.enabledNotLoaded:
      return '已启用，尚未加载';
    case PluginUiStatus.disabled:
      return '已停用';
  }
}

/// 徽章圆点直径（逻辑像素）。
///
/// [AppTheme] 没有图标 / 徽章尺寸令牌，故按 `empty_state.dart` 的先例
/// 定义组件级常量（CONTEXT 4.1 的 `k` 前缀小驼峰）。
const double kPluginStatusDotSize = 10;

/// 插件管理页。
///
/// **Phase 1.6 曾是空态占位，Phase 3.5 接入真实数据**：列表来自
/// `PluginProvider.plugins`，启停走 `PluginProvider.togglePlugin`，
/// 状态徽章综合 `loadErrors` 与 `loadedHandles` 判定。
///
/// `context.watch` 保证"插件从 0 个变 N 个（或反向）"时自动重建，
/// 空态与列表之间自动切换。
class PluginManagePage extends StatelessWidget {
  const PluginManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final PluginProvider provider = context.watch<PluginProvider>();
    final List<PluginMeta> plugins = provider.plugins;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('插件管理'),
        centerTitle: true,
        // 刻意**不放** `+` 安装菜单（P1 修正）：安装入口统一在创意工坊的
        // 插件市场。此前这里有一个 `+`，与市场是同一件事的两个入口，必然漂移
        // （市场上了新插件，菜单不会自动同步）；而且第三项"从文件导入"是纯占位，
        // 属于"看起来能用其实不能用"。本页只负责**管理已安装的插件**。
      ),
      body: plugins.isEmpty
          ? EmptyState(
              icon: Icons.extension,
              title: '还没有安装插件',
              // 引导目标必须是**能真正装上的地方**：创意工坊的插件市场
              // （其默认 Tab 就是插件市场，直接 push 即可）。
              //
              // P0 修正：此前这里写"从文件导入或从创意工坊下载"并跳创意工坊，
              // 而创意工坊的插件 Tab 又引导回本页，两页互跳、谁都没有安装动作。
              subtitle: '去创意工坊的插件市场挑一个装上',
              actionLabel: '去创意工坊安装',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const WorkshopPage(),
                ),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(theme.cardPadding),
              itemCount: plugins.length,
              itemBuilder: (BuildContext context, int index) {
                final PluginMeta meta = plugins[index];
                return _PluginCard(meta: meta, provider: provider);
              },
            ),
    );
  }
}

/// 单个插件卡片。
class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.meta, required this.provider});

  final PluginMeta meta;
  final PluginProvider provider;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final String? error = provider.loadErrorOf(meta.id);
    final PluginUiStatus status = pluginUiStatusOf(
      enabled: meta.enabled,
      isLoaded: provider.getHandle(meta.id)?.isUsable ?? false,
      hasError: error != null,
    );

    final String author = meta.author.trim().isEmpty ? '未知作者' : meta.author;
    final List<String> capabilities = meta.effectiveCapabilities.toList();

    return Card(
      color: theme.surface,
      elevation: 0,
      margin: EdgeInsets.only(bottom: theme.cardPadding),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      child: ListTile(
        // 图标由第一个能力映射而来；映射不到则兜底 Icons.extension。
        leading: Icon(
          iconFromName(pluginIconNameForCapability(
            capabilities.isEmpty ? '' : capabilities.first,
          )),
          color: theme.primary,
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                meta.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: theme.bodySize,
                  fontWeight: theme.titleFontWeight,
                  color: theme.onBackground,
                ),
              ),
            ),
            _StatusBadge(
              // 便于测试与调试定位：每个插件的徽章有稳定 Key。
              key: ValueKey<String>('plugin-status-${meta.id}'),
              status: status,
              error: error,
            ),
          ],
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: theme.gridGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '版本 ${meta.version} · $author',
                style: TextStyle(
                  fontSize: theme.captionSize,
                  color: theme.onBackground.withValues(alpha: 0.6),
                ),
              ),
              if (capabilities.isNotEmpty) ...<Widget>[
                SizedBox(height: theme.gridGap),
                Text(
                  capabilities.map(pluginCapabilityLabel).join(' · '),
                  style: TextStyle(
                    fontSize: theme.captionSize,
                    color: theme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: Switch(
          value: meta.enabled,
          onChanged: (bool value) => provider.togglePlugin(meta.id, value),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) => PluginDetailPage(pluginId: meta.id),
          ),
        ),
      ),
    );
  }
}

/// 状态徽章：一个彩色小圆点，hover / 长按显示状态与错误详情。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({super.key, required this.status, this.error});

  final PluginUiStatus status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final String label = pluginUiStatusLabel(status);
    final String tooltip = error == null ? label : '$label：$error';

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: EdgeInsets.only(left: theme.gridGap),
        child: Semantics(
          label: tooltip,
          child: Container(
            width: kPluginStatusDotSize,
            height: kPluginStatusDotSize,
            decoration: BoxDecoration(
              color: pluginUiStatusColor(status, theme),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// 能力 id → 图标名。
///
/// 内置能力直接复用导航栏模块的图标名（`ModuleProvider._initialModules`
/// 用的是同一批名字），插件自定义能力（如 `ncst.grade`）查不到时返回空串，
/// 由 `iconFromName` 兜底成 `Icons.extension`。
///
/// 公开而非私有：创意工坊的插件市场卡片也要用同一套图标，
/// 两处各写一份必然漂移（与 `PluginUiStatus` 的导出理由相同）。
String pluginIconNameForCapability(String capability) {
  switch (capability) {
    case 'timetable':
      return 'calendar_month';
    case 'courseList':
      return 'book_outlined';
    case 'exam':
      return 'assignment_outlined';
    case 'homework':
      return 'edit_note';
    case 'message':
      return 'notifications_outlined';
    case 'settings':
      return 'settings_outlined';
    default:
      return '';
  }
}

/// 能力 id → 中文短标签的映射已移到 `models/plugin_catalog.dart`
/// （[pluginCapabilityLabel]），市场卡片与本页共用同一份说法。
