// 创意工坊页（Phase 1.6 双 Tab 空态占位，Phase 6 接入皮肤 / 插件商店）
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';

/// 创意工坊页：皮肤 / 插件两个 Tab。
///
/// **Phase 1.6 只做空态**：真实的皮肤下载与应用在 Phase 6
/// （`ThemeEngine` 已具备 `loadSkin` / `preview` 能力）。
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
            EmptyState(
              icon: Icons.palette_outlined,
              title: '暂无皮肤',
              subtitle: '敬请期待',
            ),
            EmptyState(
              icon: Icons.extension_outlined,
              title: '暂无插件',
              subtitle: '敬请期待',
            ),
          ],
        ),
      ),
    );
  }
}