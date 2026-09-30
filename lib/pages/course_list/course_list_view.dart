// 课程列表页：显示 CourseProvider 里的真实课程（Phase 4.3 接入）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../models/time_place.dart';
import '../../providers/course_provider.dart';
import '../../services/timetable_logic.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/timetable_grid.dart';
import '../timetable/course_detail_sheet.dart';

/// 课程列表页。
///
/// 数据来源：[CourseProvider.visibleCourses]（已过滤 `userOverride.hidden`），
/// 与课表页共用同一个数据源，因此"同步后课表有课、列表没课"这种不一致不会再出现。
///
/// - 空列表 → [EmptyState]（保留 Phase 1.5 的空态样式）
/// - 有数据 → `ListView.builder`，每张卡片：课程名 / 教师 / 学分 + 类别 / 时间地点
/// - 点卡片 → 复用课表页的 [showCourseDetailSheet]（只读详情）
class CourseListView extends StatelessWidget {
  const CourseListView({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final List<Course> courses = context.watch<CourseProvider>().visibleCourses;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('课程'),
        centerTitle: true,
      ),
      body: courses.isEmpty
          ? const EmptyState(
              icon: Icons.book_outlined,
              title: '暂无课程',
              subtitle: '在课表页点右上角 + 添加，或安装插件从教务系统导入',
            )
          : ListView.builder(
              padding: EdgeInsets.all(theme.cardPadding),
              itemCount: courses.length,
              itemBuilder: (BuildContext context, int index) =>
                  _CourseListCard(course: courses[index]),
            ),
    );
  }
}

/// 单张课程卡片（只读展示；编辑在 Phase 5）。
class _CourseListCard extends StatelessWidget {
  const _CourseListCard({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final List<TimePlace> places = course.displayTimePlaces;
    final String teacher = course.displayTeacher;

    // 学分为 0（插件没给 / 用户没填）时不显示，避免"0 学分"这种噪声
    final List<String> meta = <String>[
      if (course.unit > 0) '${_formatUnit(course.unit)} 学分',
      if (course.category.isNotEmpty) course.category,
    ];

    return Card(
      margin: EdgeInsets.only(bottom: theme.sectionGap),
      color: theme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showCourseDetailSheet(context, course),
        child: Padding(
          padding: EdgeInsets.all(theme.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 课程名
              Text(
                course.displayName,
                style: TextStyle(
                  fontSize: theme.titleSize,
                  fontWeight: theme.titleFontWeight,
                  color: theme.onBackground,
                ),
              ),
              SizedBox(height: theme.gridGap),
              // 教师
              Row(
                children: <Widget>[
                  Icon(
                    Icons.person_outline,
                    size: theme.captionSize,
                    color: theme.onBackground.withValues(alpha: 0.6),
                  ),
                  SizedBox(width: theme.gridGap),
                  Expanded(
                    child: Text(
                      teacher.isEmpty ? '未知教师' : teacher,
                      style: TextStyle(
                        fontSize: theme.captionSize,
                        color: theme.onBackground.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
              // 学分 + 类别（都为空则不占位）
              if (meta.isNotEmpty) ...<Widget>[
                SizedBox(height: theme.gridGap),
                Text(
                  meta.join(' · '),
                  style: TextStyle(
                    fontSize: theme.captionSize,
                    color: theme.onBackground.withValues(alpha: 0.6),
                  ),
                ),
              ],
              // 时间地点
              if (places.isNotEmpty) ...<Widget>[
                SizedBox(height: theme.sectionGap),
                for (final TimePlace tp in places)
                  Padding(
                    padding: EdgeInsets.only(top: theme.gridGap),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.schedule_outlined,
                          size: theme.captionSize,
                          color: theme.primary,
                        ),
                        SizedBox(width: theme.gridGap),
                        Expanded(
                          child: Text(
                            _timePlaceText(tp),
                            style: TextStyle(
                              fontSize: theme.captionSize,
                              color: theme.onBackground.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 一条时间地点的文本：`周一 第3-4节 4,6-14周 HE-405`。
///
/// 与详情弹层的写法一致（`course_detail_sheet.dart` 的 `_TimePlaceTile`），
/// 但**刻意不复用**：那个函数是私有的，为它改成公开会动到 Phase 2.2b 已交付的页面。
/// 教室为空时不留多余空格。
String _timePlaceText(TimePlace tp) {
  final List<String> parts = <String>[
    _dayLabel(tp.day),
    tp.length <= 1
        ? '第${tp.startSession}节'
        : '第${tp.startSession}-${tp.endSession}节',
    _weeksLabel(tp),
    if (tp.room.isNotEmpty) tp.room,
  ];
  return parts.join(' ');
}

/// `1` → `周一`；越界返回 `第N天`（不抛异常）。
String _dayLabel(int day) {
  if (day >= 1 && day <= kDaysPerWeek) return kWeekdayLabels[day - 1];
  return '第$day天';
}

/// 周次文本：优先用原始文本；缺单双周标记时补上。
String _weeksLabel(TimePlace tp) {
  final String base = tp.rawWeeksText.isNotEmpty
      ? tp.rawWeeksText
      : '${TimetableLogic.formatWeeks(tp.weeks)}周';
  switch (tp.weekType) {
    case WeekType.all:
      return base;
    case WeekType.odd:
      return base.contains('单') ? base : '$base(单)';
    case WeekType.even:
      return base.contains('双') ? base : '$base(双)';
  }
}

/// 学分文本：`2` → `2`，`2.5` → `2.5`（去掉多余的 `.0`）。
String _formatUnit(double unit) {
  if (unit == unit.roundToDouble()) return '${unit.toInt()}';
  return '$unit';
}
