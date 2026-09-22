// 插件管理页（Phase 1.6 空态占位，Phase 3 接入真实插件列表）
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';
import 'workshop_page.dart';

/// 插件管理页。
///
/// **Phase 1.6 只做空态**：真实插件列表与安装流程在 Phase 3（插件运行时）。
class PluginManagePage extends StatelessWidget {
  const PluginManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('插件管理'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '安装插件',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('安装插件（待实现）')),
            ),
          ),
        ],
      ),
      body: EmptyState(
        icon: Icons.extension,
        title: '还没有安装插件',
        subtitle: '插件可以从创意工坊下载，或从本地文件导入',
        actionLabel: '去创意工坊',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) => const WorkshopPage(),
          ),
        ),
      ),
    );
  }
}