// 导航栏配置页：勾选 / 取消底部导航栏模块，并处理 5 个上限
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/module.dart';
import '../../providers/module_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/module_icon.dart';

/// 导航栏配置页。
///
/// 直接操作 [ModuleProvider]（`context.watch` 监听变化，勾选后立即刷新），
/// 并在模块数量触到 [kMaxModules] 时给出提示。
class ModuleConfigPage extends StatelessWidget {
  const ModuleConfigPage({super.key});

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 处理一次开关切换。
  ///
  /// 关于上限的处理逻辑（重要）：
  /// [ModuleProvider.visibleModules] **永远不会超过 [kMaxModules]**——它在内部
  /// 就按"常驻优先 + 列表顺序"截断了。所以"切换后判断 `length > 5` 再回滚"
  /// 是永远不成立的死代码。真实需要处理的是两种情形：
  /// 1. 新模块**挤不进去**（5 个位置已被占满且它排在更后面）→ 拦下并提示
  /// 2. 新模块挤进去了，但**顶掉了另一个已显示的模块** → 放行，但告知顶掉了谁
  ///
  /// 这里采取"先应用、再看结果、必要时回滚"的做法：直接复用 Provider 里
  /// 那套唯一的截断算法，避免在本页复制一份顺序 / 优先级规则。
  void _onToggle(
    BuildContext context,
    ModuleProvider provider,
    ModuleInfo module,
    bool value,
  ) {
    final ModuleType? type = module.type;
    if (type == null) return; // 插件模块暂不支持在此配置

    // 关闭总是允许的。
    if (!value) {
      provider.toggle(type, value);
      return;
    }

    final String capabilityId = module.capabilityId;
    final Set<String> beforeIds = provider.visibleModules
        .map((ModuleInfo m) => m.capabilityId)
        .toSet();

    provider.toggle(type, value);

    final List<ModuleInfo> after = provider.visibleModules;
    final Set<String> afterIds =
        after.map((ModuleInfo m) => m.capabilityId).toSet();

    // 情形 1：开是开了，但它没出现在导航栏上 → 回滚，等于"不允许开启"。
    if (!afterIds.contains(capabilityId)) {
      provider.toggle(type, !value);
      _showSnack(context, '最多显示 $kMaxModules 个模块，请先关闭其他模块');
      return;
    }

    // 情形 2：开启了，但顶掉了别的模块 → 放行并告知（PROGRESS 阻塞表要求）。
    final List<String> evicted = provider.allModules
        .where((ModuleInfo m) =>
            beforeIds.contains(m.capabilityId) &&
            !afterIds.contains(m.capabilityId))
        .map((ModuleInfo m) => m.title)
        .toList();
    if (evicted.isNotEmpty) {
      _showSnack(
        context,
        '最多显示 $kMaxModules 个模块，"${evicted.join('、')}" 已被移出导航栏',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    // watch：勾选 / 取消后本页立即重建，开关状态与导航栏保持一致。
    final ModuleProvider provider = context.watch<ModuleProvider>();
    final List<ModuleInfo> modules = provider.allModules;
    final int visibleCount = provider.visibleModules.length;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('导航栏配置'),
        centerTitle: true,
      ),
      body: Column(
        children: <Widget>[
          _buildHint(theme, visibleCount),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: theme.sectionGap),
              itemCount: modules.length,
              itemBuilder: (BuildContext context, int index) =>
                  _buildTile(context, theme, provider, modules[index]),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部提示：规则说明 + 当前用量。
  Widget _buildHint(AppTheme theme, int visibleCount) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.all(theme.cardPadding),
      padding: EdgeInsets.all(theme.cardPadding),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '最多显示 $kMaxModules 个模块，课表和设置不可关闭',
            style: TextStyle(
              fontSize: theme.bodySize,
              fontWeight: theme.titleFontWeight,
              color: theme.onBackground,
            ),
          ),
          SizedBox(height: theme.gridGap * 2),
          Text(
            '当前已显示 $visibleCount/$kMaxModules 个',
            style: TextStyle(
              fontSize: theme.captionSize,
              color: visibleCount >= kMaxModules
                  ? theme.error
                  : theme.onBackground.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    AppTheme theme,
    ModuleProvider provider,
    ModuleInfo module,
  ) {
    // 常驻模块（课表 / 设置）：开关固定打开且禁用。
    final bool isRequired = module.alwaysOn;
    // 能力未提供的模块（如未装插件时的作业）：开关固定关闭且禁用。
    final bool isUnavailable = !module.available;

    final String? badge = isRequired
        ? '必需'
        : (isUnavailable ? '未激活' : null);

    return ListTile(
      leading: Icon(
        iconFromName(module.iconName),
        color: isUnavailable
            ? theme.onBackground.withValues(alpha: 0.3)
            : theme.primary,
      ),
      title: Text(
        module.title,
        style: TextStyle(
          fontSize: theme.bodySize,
          color: isUnavailable
              ? theme.onBackground.withValues(alpha: 0.5)
              : theme.onBackground,
        ),
      ),
      subtitle: isUnavailable
          ? Text(
              '需要插件提供该能力',
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.5),
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (badge != null) ...<Widget>[
            Text(
              badge,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: isRequired
                    ? theme.primary
                    : theme.onBackground.withValues(alpha: 0.5),
              ),
            ),
            SizedBox(width: theme.gridGap * 2),
          ],
          Switch(
            value: isRequired ? true : (isUnavailable ? false : module.enabled),
            // 常驻 / 未激活的模块不可切换（onChanged 为 null 即禁用）。
            onChanged: (isRequired || isUnavailable)
                ? null
                : (bool value) => _onToggle(context, provider, module, value),
          ),
        ],
      ),
    );
  }
}