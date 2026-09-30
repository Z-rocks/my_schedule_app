// 课程详情弹层：只读展示一门课程的全部信息，并提供「编辑」入口（Phase 5）
import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/time_place.dart';
import '../../services/timetable_logic.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../edit/course_edit_page.dart';

/// 星期标签（索引 0 = 周一），与 `TimetableGrid` 共用同一份定义。
const List<String> _kWeekdayLabels = <String>[
  '周一', '周二', '周三', '周四', '周五', '周六', '周日',
];

/// 弹出课程详情底部弹层（只读）。
///
/// 用 `showModalBottomSheet` 打开，内容全部取自 `displayXxx` 系列
/// （即已叠加用户覆盖层），因此用户改过的名称 / 教师 / 时间地点会如实展示。
Future<void> showCourseDetailSheet(BuildContext context, Course course) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => _CourseDetailSheet(course: course),
  );
}

class _CourseDetailSheet extends StatelessWidget {
  const _CourseDetailSheet({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final String? note = course.userOverride?.note;
    final List<TimePlace> timePlaces = course.displayTimePlaces;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(theme.cardRadius),
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(theme.cardPadding * 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 顶部拖动条
                Center(
                  child: Container(
                    width: theme.timetableTimeColumnWidth,
                    height: theme.gridGap,
                    decoration: BoxDecoration(
                      color: theme.onBackground.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(theme.gridGap),
                    ),
                  ),
                ),
                SizedBox(height: theme.sectionGap),

                // 课程名
                Text(
                  course.displayName,
                  style: TextStyle(
                    fontSize: theme.titleSize,
                    fontWeight: theme.titleFontWeight,
                    color: theme.onBackground,
                  ),
                ),
                SizedBox(height: theme.gridGap * 2),

                // 教师
                _DetailRow(
                  theme: theme,
                  icon: Icons.person_outline,
                  text: course.displayTeacher.isEmpty
                      ? '未知教师'
                      : course.displayTeacher,
                ),
                // 学分 / 类别
                _DetailRow(
                  theme: theme,
                  icon: Icons.school_outlined,
                  text: '${_formatUnit(course.unit)} 学分'
                      '${course.category.isEmpty ? '' : ' · ${course.category}'}',
                ),

                SizedBox(height: theme.sectionGap),
                _SectionTitle(theme: theme, text: '上课时间地点'),

                if (timePlaces.isEmpty)
                  _DetailRow(
                    theme: theme,
                    icon: Icons.event_busy_outlined,
                    text: '暂无安排',
                  )
                else
                  ...timePlaces.map((TimePlace tp) => _TimePlaceTile(
                        theme: theme,
                        timePlace: tp,
                      )),

                if (note != null && note.isNotEmpty) ...<Widget>[
                  SizedBox(height: theme.sectionGap),
                  _SectionTitle(theme: theme, text: '备注'),
                  _DetailRow(
                    theme: theme,
                    icon: Icons.sticky_note_2_outlined,
                    text: note,
                  ),
                ],

                SizedBox(height: theme.sectionGap * 1.5),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        // Phase 5：接真实编辑页。
                        //
                        // 先取 Navigator 再 pop：pop 之后本 widget 就失效了，
                        // 那时再 `Navigator.of(context)` 会拿不到（且弹层自己的
                        // Navigator 与页面的可能是同一个，必须用同一个才能保证
                        // 编辑页盖在**页面**上而不是弹层上）。
                        onPressed: () {
                          final NavigatorState navigator =
                              Navigator.of(context);
                          navigator.pop();
                          navigator.push(
                            MaterialPageRoute<bool>(
                              builder: (BuildContext _) =>
                                  CourseEditPage(course: course),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(theme.buttonRadius),
                          ),
                        ),
                        child: const Text('编辑'),
                      ),
                    ),
                    SizedBox(width: theme.gridGap * 2),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.primary,
                          foregroundColor: theme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(theme.buttonRadius),
                          ),
                        ),
                        child: const Text('关闭'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 学分展示：整数去掉小数点（`3.0` → `3`）。
String _formatUnit(double unit) {
  if (unit == unit.roundToDouble()) return unit.round().toString();
  return unit.toString();
}

/// 一条"图标 + 文字"信息行。
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.theme,
    required this.icon,
    required this.text,
  });

  final AppTheme theme;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.gridGap / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: theme.bodySize, color: theme.primary),
          SizedBox(width: theme.gridGap * 2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: theme.bodySize,
                color: theme.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 小标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.theme, required this.text});

  final AppTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: theme.gridGap),
      child: Text(
        text,
        style: TextStyle(
          fontSize: theme.captionSize,
          fontWeight: theme.titleFontWeight,
          color: theme.primary,
        ),
      ),
    );
  }
}

/// 一条时间地点：「周一 第3-4节 4,6-14周」+「HE-405」。
class _TimePlaceTile extends StatelessWidget {
  const _TimePlaceTile({required this.theme, required this.timePlace});

  final AppTheme theme;
  final TimePlace timePlace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.gridGap / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.schedule_outlined, size: theme.bodySize, color: theme.primary),
          SizedBox(width: theme.gridGap * 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${_dayLabel(timePlace.day)} '
                  '${_sessionLabel(timePlace)} '
                  '${_weeksLabel(timePlace)}',
                  style: TextStyle(
                    fontSize: theme.bodySize,
                    color: theme.onBackground,
                  ),
                ),
                if (timePlace.room.isNotEmpty)
                  Text(
                    timePlace.room,
                    style: TextStyle(
                      fontSize: theme.captionSize,
                      color: theme.onBackground.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `1` → `周一`；越界返回 `第N天`（不抛异常）。
String _dayLabel(int day) {
  if (day >= 1 && day <= _kWeekdayLabels.length) {
    return _kWeekdayLabels[day - 1];
  }
  return '第$day天';
}

/// 节次文本：单节 `第3节`，连堂 `第3-4节`。
String _sessionLabel(TimePlace tp) => tp.length <= 1
    ? '第${tp.startSession}节'
    : '第${tp.startSession}-${tp.endSession}节';

/// 周次文本：优先用原始文本，缺单双周标记时补上。
String _weeksLabel(TimePlace tp) {
  final String base = tp.rawWeeksText.isNotEmpty
      ? tp.rawWeeksText
      : '${TimetableLogic.formatWeeks(tp.weeks)}周';
  switch (tp.weekType) {
    case WeekType.all:
      return base;
    case WeekType.odd:
      // 原始文本里已带"(单)"就不再重复追加
      return base.contains('单') ? base : '$base(单)';
    case WeekType.even:
      return base.contains('双') ? base : '$base(双)';
  }
}