// 考试安排页（空态骨架）
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';

/// 考试安排页。
///
/// **Phase 1.5 只做空态骨架**：不接任何 Provider。
/// 考试数据需要插件声明 `exam` 能力后由 Phase 4 导入。
class ExamView extends StatelessWidget {
  const ExamView({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('考试'),
        centerTitle: true,
      ),
      body: const EmptyState(
        icon: Icons.assignment_outlined,
        title: '暂无考试安排',
        subtitle: '安装支持考试能力的插件后可导入',
      ),
    );
  }
}