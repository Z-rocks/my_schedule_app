// 创意工坊页：皮肤商店 + 插件 Tab（Phase 6 起皮肤列表是真实内容）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plugin_meta.dart';
import '../../models/skin_pack.dart';
import '../../providers/plugin_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/default_skins.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';
import 'plugin_detail_page.dart';
import 'plugin_manage_page.dart';
import 'skin_preview_page.dart';

/// 创意工坊页：皮肤 / 插件两个 Tab。
///
/// **Phase 1.6 是双 Tab 空态；Phase 6 起皮肤 Tab 有真实内容**：
/// 内置皮肤（`builtinSkins()`）+ 「应用 / 预览 / 恢复默认」。
///
/// 插件 Tab 不重复实现商店逻辑，只做"已装插件概览 + 跳插件管理"——
/// 插件的安装/启停/详情已经有专门的页面，在这里再写一套必然会漂移。
class WorkshopPage extends StatelessWidget {
  const WorkshopPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return DefaultTabController(
      length: 2,
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
              Tab(text: '皮肤'),
              Tab(text: '插件'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _SkinsTab(),
            _PluginsTab(),
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

/// 插件 Tab：已装插件概览 + 跳插件管理。
///
/// **刻意不复刻**插件商店/安装流程：那套逻辑已经在
/// `PluginManagePage` / `PluginDetailPage` 里，这里再写一份必然漂移。
class _PluginsTab extends StatelessWidget {
  const _PluginsTab();

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final PluginProvider provider = context.watch<PluginProvider>();
    final List<PluginMeta> plugins = provider.plugins;

    if (plugins.isEmpty) {
      return Column(
        children: <Widget>[
          const Expanded(
            child: EmptyState(
              icon: Icons.extension_outlined,
              title: '还没有安装插件',
              subtitle: '插件为 App 提供教务数据能力',
            ),
          ),
          Padding(
            padding: EdgeInsets.all(theme.cardPadding),
            child: FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('去插件管理安装'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: theme.onPrimary,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.buttonRadius),
                ),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (BuildContext _) => const PluginManagePage(),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.all(theme.cardPadding),
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            left: theme.cardPadding / 2,
            bottom: theme.gridGap * 2,
          ),
          child: Text(
            '已安装 ${plugins.length} 个插件',
            style: TextStyle(
              fontSize: theme.captionSize,
              fontWeight: theme.titleFontWeight,
              color: theme.primary,
            ),
          ),
        ),
        for (final PluginMeta plugin in plugins)
          _PluginSummaryCard(plugin: plugin),
        SizedBox(height: theme.sectionGap),
        OutlinedButton.icon(
          icon: const Icon(Icons.settings_outlined),
          label: const Text('去插件管理'),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.primary,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.buttonRadius),
            ),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<bool>(
              builder: (BuildContext _) => const PluginManagePage(),
            ),
          ),
        ),
      ],
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
