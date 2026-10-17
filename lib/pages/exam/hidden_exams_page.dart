// 已隐藏的考试页：查看并恢复被隐藏的考试安排。
//
// 与 `hidden_homeworks_page.dart` 同源：考试详情里的「隐藏这场考试」会把
// 记录从 `displayExams` 过滤掉，没有恢复入口就等于删除。
// 课程侧早有 `hidden_courses_page.dart`，作业 / 考试这两处都曾漏掉。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/exam.dart';
import '../../providers/exam_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';

/// 已隐藏的考试列表页。
///
/// 入口：考试页右上角「已隐藏」按钮（仅在 [ExamProvider.hiddenCount] > 0 时出现）。
class HiddenExamsPage extends StatelessWidget {
  const HiddenExamsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final List<Exam> hidden = context.watch<ExamProvider>().hiddenExams;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('已隐藏的考试'),
        centerTitle: true,
      ),
      body: hidden.isEmpty
          ? const EmptyState(
              icon: Icons.visibility_outlined,
              title: '没有隐藏的考试',
              subtitle: '在考试详情里可以隐藏不需要的考试安排',
            )
          : ListView.builder(
              padding: EdgeInsets.all(theme.cardPadding),
              itemCount: hidden.length,
              itemBuilder: (BuildContext context, int index) =>
                  _HiddenExamCard(exam: hidden[index]),
            ),
    );
  }
}

/// 单张已隐藏考试卡片：考试名 + 课程 / 时间 / 地点 + 「恢复显示」。
class _HiddenExamCard extends StatelessWidget {
  const _HiddenExamCard({required this.exam});

  final Exam exam;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

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
            Text(
              exam.displayName,
              style: TextStyle(
                fontSize: theme.titleSize,
                fontWeight: theme.titleFontWeight,
                color: theme.onBackground,
              ),
            ),
            SizedBox(height: theme.gridGap),
            Text(
              _subtitle(),
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.7),
              ),
            ),
            SizedBox(height: theme.gridGap),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.visibility),
                label: const Text('恢复显示'),
                style: TextButton.styleFrom(foregroundColor: theme.primary),
                onPressed: () => _restore(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 副标题：`课程名 · 2026-10-20 09:00 · 教学楼A101`（空项自动跳过）。
  String _subtitle() {
    final List<String> parts = <String>[
      if (exam.courseName.trim().isNotEmpty) exam.courseName.trim(),
      _formatDateTime(exam.displayStartTime),
      if (exam.displayLocation.trim().isNotEmpty) exam.displayLocation.trim(),
    ];
    return parts.join(' · ');
  }

  Future<void> _restore(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ExamProvider provider = context.read<ExamProvider>();
    // `setHidden(false)` 保留用户改过的名称 / 时间 / 地点。
    final bool ok = await provider.setHidden(exam.id, false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? '「${exam.displayName}」已恢复显示' : '恢复失败：找不到该考试',
        ),
      ),
    );
  }
}

/// `2026-10-20 09:00`。手写而不引 `intl`：只此一处需要，格式固定。
String _formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
