// 已隐藏的课程页（Phase 5）：查看并恢复被隐藏的课程。
//
// 为什么需要这一页：CONTEXT 3.3 规定教务课程**只能隐藏、不能真删**，
// 而"隐藏"如果没有恢复入口，在用户看来就和删除没有区别——
// 数据还在，但用户找不回来。所以隐藏功能必须配一个恢复入口才算完整。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../models/time_place.dart';
import '../../providers/course_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';

/// 已隐藏的课程列表页。
///
/// 入口：设置 → 课表设置 → 已隐藏的课程。
class HiddenCoursesPage extends StatelessWidget {
  const HiddenCoursesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final List<Course> hidden = context.watch<CourseProvider>().hiddenCourses;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('已隐藏的课程'),
        centerTitle: true,
      ),
      body: hidden.isEmpty
          ? const EmptyState(
              icon: Icons.visibility_outlined,
              title: '没有隐藏的课程',
              subtitle: '在课程详情里可以隐藏不需要的课程',
            )
          : ListView.builder(
              padding: EdgeInsets.all(theme.cardPadding),
              itemCount: hidden.length,
              itemBuilder: (BuildContext context, int index) =>
                  _HiddenCourseCard(course: hidden[index]),
            ),
    );
  }
}

/// 单张已隐藏课程卡片：课程名 + 教师 + 安排摘要 + "恢复"按钮。
class _HiddenCourseCard extends StatelessWidget {
  const _HiddenCourseCard({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final List<TimePlace> places = course.displayTimePlaces;

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
              course.displayName,
              style: TextStyle(
                fontSize: theme.titleSize,
                fontWeight: theme.titleFontWeight,
                color: theme.onBackground,
              ),
            ),
            SizedBox(height: theme.gridGap),
            Text(
              _subtitle(places),
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

  /// 副标题：`教师 · 3 个时间段`（教师为空时只显示段数）。
  String _subtitle(List<TimePlace> places) {
    final String teacher = course.displayTeacher;
    final String count = places.isEmpty ? '暂无安排' : '${places.length} 个时间段';
    return teacher.isEmpty ? count : '$teacher · $count';
  }

  Future<void> _restore(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final CourseProvider courses = context.read<CourseProvider>();
    // 用 `setHidden(false)` 而不是重建覆盖层：它会保留用户的颜色 / 备注 / 改名。
    final bool ok = await courses.setHidden(course.id, false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? '「${course.displayName}」已恢复显示' : '恢复失败：找不到该课程'),
      ),
    );
  }
}
