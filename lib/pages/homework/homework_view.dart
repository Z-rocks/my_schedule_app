// 作业页（空态骨架）
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';

/// 作业页。
///
/// **Phase 1.5 只做空态骨架**：不接任何 Provider。
/// 作业数据必须来自插件（`homework` 能力），由 Phase 8 的学习通插件提供。
class HomeworkView extends StatelessWidget {
  const HomeworkView({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('作业'),
        centerTitle: true,
      ),
      body: const EmptyState(
        icon: Icons.edit_note,
        title: '暂无作业',
        subtitle: '安装学习通等插件后可查看',
      ),
    );
  }
}