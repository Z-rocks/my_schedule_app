// 已隐藏的作业页：查看并恢复被隐藏的作业。
//
// 为什么需要这一页：作业的「隐藏」写在 `UserOverride.hidden` 里，
// `displayHomeworks` 会把它过滤掉。如果只做隐藏不做恢复入口，
// 在用户看来就和删除没有区别——数据还在，但找不回来。
// （课程侧早有 `hidden_courses_page.dart`，作业侧一直漏了这一环。）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/homework.dart';
import '../../providers/homework_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';

/// 已隐藏的作业列表页。
///
/// 入口：作业页右上角「已隐藏」按钮（仅在 [HomeworkProvider.hiddenCount] > 0 时出现）。
class HiddenHomeworksPage extends StatelessWidget {
  const HiddenHomeworksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final List<Homework> hidden =
        context.watch<HomeworkProvider>().hiddenHomeworks;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('已隐藏的作业'),
        centerTitle: true,
      ),
      body: hidden.isEmpty
          ? const EmptyState(
              icon: Icons.visibility_outlined,
              title: '没有隐藏的作业',
              subtitle: '在作业详情里可以隐藏不需要的作业',
            )
          : ListView.builder(
              padding: EdgeInsets.all(theme.cardPadding),
              itemCount: hidden.length,
              itemBuilder: (BuildContext context, int index) =>
                  _HiddenHomeworkCard(homework: hidden[index]),
            ),
    );
  }
}

/// 单张已隐藏作业卡片：标题 + 课程 + 截止日期 + 「恢复显示」。
class _HiddenHomeworkCard extends StatelessWidget {
  const _HiddenHomeworkCard({required this.homework});

  final Homework homework;

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
              homework.displayTitle,
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

  /// 副标题：`课程名 · 截止 2026-10-18`（课程为空时只显示截止）。
  String _subtitle() {
    final DateTime? deadline = homework.displayDeadline;
    final String deadlineText =
        deadline == null ? '无截止时间' : '截止 ${_formatDate(deadline)}';
    final String course = homework.courseName.trim();
    return course.isEmpty ? deadlineText : '$course · $deadlineText';
  }

  Future<void> _restore(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final HomeworkProvider provider = context.read<HomeworkProvider>();
    // 用 `setHidden(false)` 而不是重建覆盖层：它会保留用户的完成勾选 / 改名 / 改期。
    final bool ok = await provider.setHidden(homework.id, false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? '「${homework.displayTitle}」已恢复显示' : '恢复失败：找不到该作业',
        ),
      ),
    );
  }
}

/// `2026-10-18`。
///
/// 只到日期：这一页是"找回误隐藏的作业"，精确到分钟没有意义，
/// 且主列表已经给了完整时间。
String _formatDate(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
