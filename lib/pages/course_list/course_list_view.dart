// 课程列表页（空态骨架）
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';

/// 课程列表页。
///
/// **Phase 1.5 只做空态骨架**：不接 `CourseProvider`，不渲染课程卡片。
/// 真实列表在 Phase 2（接入 Hive）与 Phase 5（编辑）之后实现。
class CourseListView extends StatelessWidget {
  const CourseListView({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('课程'),
        centerTitle: true,
      ),
      body: const EmptyState(
        icon: Icons.book_outlined,
        title: '暂无课程',
      ),
    );
  }
}