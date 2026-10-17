// 创意工坊页：插件市场（默认）+ 皮肤商店
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plugin_catalog.dart';
import '../../models/plugin_meta.dart';
import '../../models/skin_pack.dart';
import '../../providers/plugin_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/default_skins.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/module_icon.dart';
import 'plugin_detail_page.dart';
import 'plugin_manage_page.dart' show pluginIconNameForCapability;
import 'skin_preview_page.dart';

/// 创意工坊的两个 Tab。
///
/// 顺序即 Tab 顺序，`index` 直接用作 `DefaultTabController.initialIndex`。
enum WorkshopTab {
  /// 插件市场（默认）。
  plugins,

  /// 皮肤商店。
  skins,
}

/// 创意工坊页：**插件市场 / 皮肤** 两个 Tab。
///
/// **默认停在插件**（P0 修正）：用户进"创意工坊"的主要目的是获取能力
/// （装插件），皮肤是次要的装饰性需求。此前默认停在皮肤 Tab，导致
/// "想装插件的人先看到一堆配色"。
///
/// 但入口语境要保留：从「设置 → 当前主题」进来的用户显然想看皮肤，
/// 所以调用方可用 [initialTab] 指定落地页。
///
/// 插件 Tab 就是**插件市场**：可安装列表 + 已安装列表，卡片内直接安装。
/// 此前这里只有"已安装概览 + 去插件管理安装"——而插件管理那边又引导回
/// 创意工坊，两个空页面互相弹，用户永远装不上插件。
class WorkshopPage extends StatelessWidget {
  const WorkshopPage({super.key, this.initialTab = WorkshopTab.plugins});

  /// 打开时落在哪个 Tab。
  final WorkshopTab initialTab;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.index,
      child: Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          title: const Text('创意工坊'),
          centerTitle: true,
          bottom: TabBar(
            labelColor: theme.primary,
            unselectedLabelColor: theme.onBackground.withValues(alpha: 0.6),
            indicatorColor: theme.primary,
            labelStyle: TextStyle(
              fontSize: theme.bodySize,
              fontWeight: theme.titleFontWeight,
            ),
            unselectedLabelStyle: TextStyle(fontSize: theme.bodySize),
            tabs: const <Widget>[
              Tab(text: '插件'),
              Tab(text: '皮肤'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _PluginsTab(),
            _SkinsTab(),
          ],
        ),
      ),
    );
  }
}

/// 皮肤 Tab：内置皮肤列表 + 当前生效标记 + 恢复默认。
///
/// **Stateful**：asset 皮肤要从 bundle 异步读（`rootBundle.loadString`），
/// 读之前先只显示代码内置的那几套——不阻塞首屏。
class _SkinsTab extends StatefulWidget {
  const _SkinsTab();

  @override
  State<_SkinsTab> createState() => _SkinsTabState();
}

class _SkinsTabState extends State<_SkinsTab> {
  /// 全部可用皮肤（代码内置 + assets），读取完成前只有内置的。
  late List<SkinPack> _skins = builtinSkins();

  @override
  void initState() {
    super.initState();
    _loadAssetSkins();
  }

  /// 异步补上 assets 皮肤；失败就保持"只有内置皮肤"（完全可用的状态）。
  Future<void> _loadAssetSkins() async {
    final List<SkinPack> fromAssets =
        await ThemeProvider.loadAssetSkins();
    if (!mounted || fromAssets.isEmpty) return;
    setState(() {
      // assets 皮肤排在内置之前：它们是"用户自己放进来的"，更可能是想找的
      // 那一套；同时去重（万一有人把内置皮肤也复制进 assets）。
      final Set<String> seen = <String>{
        for (final SkinPack s in fromAssets) s.id,
      };
      _skins = <SkinPack>[
        ...fromAssets,
        for (final SkinPack s in builtinSkins())
          if (!seen.contains(s.id)) s,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    final String currentId = themeProvider.currentSkinId;

    return ListView(
      padding: EdgeInsets.all(theme.cardPadding),
      children: <Widget>[
        // 当前状态 + 恢复默认
        Container(
          padding: EdgeInsets.all(theme.cardPadding),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(theme.cardRadius),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.palette_outlined, color: theme.primary),
              SizedBox(width: theme.cardPadding),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '当前皮肤',
                      style: TextStyle(
                        fontSize: theme.captionSize,
                        color: theme.onBackground.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(
                      _currentSkinName(_skins, currentId),
                      style: TextStyle(
                        fontSize: theme.bodySize,
                        fontWeight: theme.titleFontWeight,
                        color: theme.onBackground,
                      ),
                    ),
                    Text(
                      '明暗模式：${themeProvider.mode.label}'
                      '${themeProvider.mode.name == 'system' ? '（当前${themeProvider.brightness == Brightness.dark ? '暗色' : '亮色'}）' : ''}',
                      style: TextStyle(
                        fontSize: theme.captionSize,
                        color: theme.onBackground.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (currentId.isNotEmpty)
                TextButton(
                  onPressed: () => _reset(context, themeProvider),
                  style: TextButton.styleFrom(foregroundColor: theme.primary),
                  child: const Text('恢复默认'),
                ),
            ],
          ),
        ),
        SizedBox(height: theme.sectionGap),
        Padding(
          padding: EdgeInsets.only(
            left: theme.cardPadding / 2,
            bottom: theme.gridGap * 2,
          ),
          child: Text(
            '可用皮肤（${_skins.length}）',
            style: TextStyle(
              fontSize: theme.captionSize,
              fontWeight: theme.titleFontWeight,
              color: theme.primary,
            ),
          ),
        ),
        for (final SkinPack skin in _skins)
          _SkinCard(
            skin: skin,
            isCurrent: skin.id == currentId,
          ),
      ],
    );
  }

  /// 当前皮肤名；没选皮肤时显示"内置默认主题"。
  static String _currentSkinName(List<SkinPack> skins, String id) {
    if (id.isEmpty) return '内置默认主题';
    for (final SkinPack skin in skins) {
      if (skin.id == id) return skin.name;
    }
    // 皮肤被删掉后 `ThemeProvider.restoreSkin` 会清空 id，
    // 正常走不到这里；留个兜底以免显示空白。
    return id;
  }

  Future<void> _reset(
    BuildContext context,
    ThemeProvider provider,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await provider.resetTheme();
    messenger.showSnackBar(
      const SnackBar(content: Text('已恢复内置默认主题')),
    );
  }
}

/// 一张皮肤卡片：色板预览 + 名称/作者/说明 + 应用、预览按钮。
class _SkinCard extends StatelessWidget {
  const _SkinCard({required this.skin, required this.isCurrent});

  final SkinPack skin;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Card(
      margin: EdgeInsets.only(bottom: theme.sectionGap),
      color: theme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
        // 当前生效的皮肤描一圈主色边，一眼能认出来
        side: isCurrent
            ? BorderSide(color: theme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    skin.name,
                    style: TextStyle(
                      fontSize: theme.titleSize,
                      fontWeight: theme.titleFontWeight,
                      color: theme.onBackground,
                    ),
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: theme.gridGap * 2,
                      vertical: theme.gridGap / 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(theme.chipRadius),
                    ),
                    child: Text(
                      '使用中',
                      style: TextStyle(
                        fontSize: theme.captionSize,
                        color: theme.success,
                        fontWeight: theme.titleFontWeight,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: theme.gridGap),
            Text(
              '${skin.author} · v${skin.version}'
              '${skin.supportsDarkMode ? ' · 亮/暗双色表' : ''}',
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.6),
              ),
            ),
            if (skin.description.isNotEmpty) ...<Widget>[
              SizedBox(height: theme.gridGap),
              Text(
                skin.description,
                style: TextStyle(
                  fontSize: theme.captionSize,
                  color: theme.onBackground.withValues(alpha: 0.8),
                ),
              ),
            ],
            SizedBox(height: theme.cardPadding),
            // 色板：主色 / 次色 / 背景 / 卡片 + 前 4 个课程色
            _SwatchRow(theme: theme, skin: skin),
            SizedBox(height: theme.cardPadding),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: ValueKey<String>('skin-preview-${skin.id}'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<bool>(
                        builder: (BuildContext _) =>
                            SkinPreviewPage(skin: skin),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(theme.buttonRadius),
                      ),
                    ),
                    child: const Text('预览'),
                  ),
                ),
                SizedBox(width: theme.gridGap * 2),
                Expanded(
                  child: FilledButton(
                    key: ValueKey<String>('skin-apply-${skin.id}'),
                    // 已在使用中就不必再应用一次
                    onPressed: isCurrent ? null : () => _apply(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: theme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(theme.buttonRadius),
                      ),
                    ),
                    child: Text(isCurrent ? '正在使用' : '应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apply(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ThemeProvider provider = context.read<ThemeProvider>();
    await provider.applySkin(skin);
    messenger.showSnackBar(
      SnackBar(content: Text('已应用皮肤「${skin.name}」')),
    );
  }
}

/// 一排色块：让用户不进预览页也能大致看出这套皮肤长什么样。
class _SwatchRow extends StatelessWidget {
  const _SwatchRow({required this.theme, required this.skin});

  final AppTheme theme;
  final SkinPack skin;

  @override
  Widget build(BuildContext context) {
    // 按用户**当前**的明暗偏好挑色表，色板才与实际效果一致。
    final bool preferDark =
        context.watch<ThemeProvider>().brightness == Brightness.dark;
    final Map<String, int> palette =
        preferDark && skin.supportsDarkMode ? skin.darkColors : skin.lightColors;

    // 令牌名与 `default_skins.dart` 的常量一致；
    // 缺失的令牌直接跳过（皮肤允许只声明一部分）。
    final List<MapEntry<String, int>> entries = <MapEntry<String, int>>[
      for (final String token in <String>[
        'primary',
        'secondary',
        'background',
        'surface',
      ])
        if (palette[token] != null) MapEntry<String, int>(token, palette[token]!),
    ];

    return SizedBox(
      height: theme.timetableCellHeight * 0.5,
      child: Row(
        children: <Widget>[
          for (final MapEntry<String, int> e in entries)
            Expanded(
              child: Tooltip(
                message: _tokenLabel(e.key),
                child: Container(
                  margin: EdgeInsets.only(right: theme.gridGap),
                  decoration: BoxDecoration(
                    color: Color(e.value),
                    borderRadius: BorderRadius.circular(theme.gridGap),
                    border: Border.all(
                      color: theme.onBackground.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
            ),
          if (skin.courseColors.isNotEmpty)
            Expanded(
              flex: 2,
              child: Row(
                children: <Widget>[
                  for (final int argb in skin.courseColors.take(4))
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: theme.gridGap / 2),
                        decoration: BoxDecoration(
                          color: Color(argb),
                          borderRadius: BorderRadius.circular(theme.gridGap),
                          border: Border.all(
                            color: theme.onBackground.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 令牌名 → 中文（Tooltip 用，帮皮肤作者对上号）。
  static String _tokenLabel(String token) {
    switch (token) {
      case 'primary':
        return '主色';
      case 'secondary':
        return '次要色';
      case 'background':
        return '页面背景';
      case 'surface':
        return '卡片背景';
      default:
        return token;
    }
  }
}

/// 插件 Tab = **插件市场**。
///
/// 分两段：**可安装**（目录里还没装的）+ **已安装**。
/// 安装动作直接在卡片里完成，不再跳转到插件管理页——
/// 此前这里只有"已装概览 + 去插件管理安装"，而插件管理空态又引导回创意工坊，
/// 两个页面互相弹、谁都不提供安装动作，用户永远装不上插件（P0-1）。
class _PluginsTab extends StatefulWidget {
  const _PluginsTab();

  @override
  State<_PluginsTab> createState() => _PluginsTabState();
}

class _PluginsTabState extends State<_PluginsTab> {
  /// 正在安装的插件 id：用于按钮转圈 + 防重复点击。
  final Set<String> _installing = <String>{};

  Future<void> _install(PluginCatalogEntry entry) async {
    if (_installing.contains(entry.id)) return;
    setState(() => _installing.add(entry.id));

    final PluginProvider provider = context.read<PluginProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    bool ok = false;
    try {
      ok = await provider.installCatalogPlugin(entry);
    } catch (e) {
      // 服务层契约是"失败返回 false"，真抛了也要让用户知道，不能静默。
      debugPrint('[WorkshopPage] 安装 ${entry.id} 抛出异常：$e');
    } finally {
      if (mounted) setState(() => _installing.remove(entry.id));
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '已安装「${entry.name}」，进详情页完成登录即可使用'
              : '安装「${entry.name}」失败，详见日志',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final PluginProvider provider = context.watch<PluginProvider>();
    final List<PluginMeta> installed = provider.plugins;
    final Set<String> installedIds =
        installed.map((PluginMeta p) => p.id).toSet();
    final List<PluginCatalogEntry> available = kPluginCatalog
        .where((PluginCatalogEntry e) => !installedIds.contains(e.id))
        .toList(growable: false);

    if (available.isEmpty && installed.isEmpty) {
      // 目录被清空时的兜底（正常不会走到：kPluginCatalog 恒非空）。
      return const EmptyState(
        icon: Icons.extension_outlined,
        title: '暂无可安装的插件',
        subtitle: '插件市场正在准备中',
      );
    }

    return ListView(
      padding: EdgeInsets.all(theme.cardPadding),
      children: <Widget>[
        if (available.isNotEmpty) ...<Widget>[
          _SectionLabel(text: '可安装（${available.length}）'),
          for (final PluginCatalogEntry entry in available)
            _MarketCard(
              entry: entry,
              installing: _installing.contains(entry.id),
              onInstall: () => _install(entry),
            ),
        ],
        if (installed.isNotEmpty) ...<Widget>[
          _SectionLabel(text: '已安装（${installed.length}）'),
          for (final PluginMeta plugin in installed)
            _PluginSummaryCard(plugin: plugin),
        ],
      ],
    );
  }
}

/// 分组小标题（"可安装（2）" / "已安装（1）"）。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
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

/// 市场里的一张**可安装**插件卡片。
///
/// 与 [_PluginSummaryCard]（已安装、只读、点击进详情）分开：
/// 这张卡的主要动作是"安装"，整卡点击不应跳转，避免误触。
class _MarketCard extends StatelessWidget {
  const _MarketCard({
    required this.entry,
    required this.installing,
    required this.onInstall,
  });

  final PluginCatalogEntry entry;

  /// 安装进行中：按钮转圈并禁用。
  final bool installing;

  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final String iconName = pluginIconNameForCapability(
      entry.capabilities.isEmpty ? '' : entry.capabilities.first,
    );

    return Card(
      margin: EdgeInsets.only(bottom: theme.sectionGap),
      color: theme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(iconFromName(iconName), color: theme.primary),
                SizedBox(width: theme.cardPadding),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: theme.bodySize,
                          fontWeight: theme.titleFontWeight,
                          color: theme.onBackground,
                        ),
                      ),
                      Text(
                        entry.school,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: theme.captionSize,
                          color: theme.onBackground.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: theme.gridGap * 2),
            Text(
              entry.description,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.8),
              ),
            ),
            SizedBox(height: theme.cardPadding),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Wrap(
                    spacing: theme.gridGap,
                    runSpacing: theme.gridGap,
                    children: <Widget>[
                      for (final String label in entry.capabilityLabels)
                        _CapabilityChip(label: label),
                    ],
                  ),
                ),
                SizedBox(width: theme.gridGap * 2),
                FilledButton(
                  key: ValueKey<String>('plugin-install-${entry.id}'),
                  onPressed: installing ? null : onInstall,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: theme.onPrimary,
                    padding: EdgeInsets.symmetric(
                      horizontal: theme.cardPadding,
                      vertical: theme.gridGap * 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(theme.buttonRadius),
                    ),
                  ),
                  child: installing
                      ? SizedBox(
                          width: theme.captionSize,
                          height: theme.captionSize,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(theme.onPrimary),
                          ),
                        )
                      : const Text('安装'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 能力标签（"课表" / "作业" / "考试"）。
class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.gridGap * 2,
        vertical: theme.gridGap / 2,
      ),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.chipRadius),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: theme.captionSize, color: theme.primary),
      ),
    );
  }
}

/// 插件概览卡片（只读，点击进详情）。
class _PluginSummaryCard extends StatelessWidget {
  const _PluginSummaryCard({required this.plugin});

  final PluginMeta plugin;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final bool usable =
        context.watch<PluginProvider>().getHandle(plugin.id)?.isUsable ?? false;

    return Card(
      margin: EdgeInsets.only(bottom: theme.sectionGap),
      color: theme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: theme.cardPadding),
        leading: Icon(
          usable ? Icons.extension : Icons.extension_off_outlined,
          color: usable ? theme.success : theme.onBackground.withValues(alpha: 0.4),
        ),
        title: Text(
          plugin.name,
          style: TextStyle(
            fontSize: theme.bodySize,
            fontWeight: theme.titleFontWeight,
            color: theme.onBackground,
          ),
        ),
        subtitle: Text(
          plugin.school.isEmpty
              ? (plugin.enabled ? '已启用' : '未启用')
              : '${plugin.school} · ${plugin.enabled ? '已启用' : '未启用'}',
          style: TextStyle(
            fontSize: theme.captionSize,
            color: theme.onBackground.withValues(alpha: 0.6),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: theme.onBackground.withValues(alpha: 0.4),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<bool>(
            builder: (BuildContext _) => PluginDetailPage(pluginId: plugin.id),
          ),
        ),
      ),
    );
  }
}
