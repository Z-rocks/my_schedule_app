// 课表网格：用 Stack + Positioned 绝对定位渲染课程卡片（纯展示组件）
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/time_place.dart';
import '../services/timetable_logic.dart';
import '../theme/app_theme.dart';
import '../theme/theme_extension.dart';

/// 表头（星期几那一行）的高度。
///
/// [AppTheme] 没有表头高度的令牌，故定义组件级常量
/// （CONTEXT.md 4.1 的 `k` 前缀小驼峰）。
const double kGridHeaderHeight = 34;

/// 课表网格。
///
/// **纯展示组件**：不读 Provider、不访问存储，只把 [grid] 画出来。
/// 网格由 `TimetableLogic.buildGrid` 生成，尺寸 `(7+1) × (12+1)`，
/// 索引 1-7（星期）与 1-12（节次）有效，索引 0 为占位。
///
/// 用 `Stack` + `Positioned` 而不是 `Table`：`Table` 不支持跨行合并
/// （rowspan），而一门连上 3 节的课需要占满 3 格高度。
class TimetableGrid extends StatelessWidget {
  /// 课程网格，`grid[day][session] = Course?`。
  final List<List<Course?>> grid;

  /// 节次 → 时间文本，如 `{1: "08:30-09:15"}`。
  final Map<int, String> sectionTimes;

  /// 当前显示第几周。
  ///
  /// 网格本身已由调用方按周过滤过（`buildGrid(courses, week)`）；
  /// 这里保留它是为了让卡片 `Key` 随周次变化，切周时能正确重建。
  final int currentWeek;

  /// 点击课程卡片。
  final void Function(Course course)? onTapCourse;

  /// 长按课程卡片。
  final void Function(Course course)? onLongPressCourse;

  const TimetableGrid({
    super.key,
    required this.grid,
    required this.sectionTimes,
    required this.currentWeek,
    this.onTapCourse,
    this.onLongPressCourse,
  });

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final int dayCount = theme.showWeekend ? kDaysPerWeek : 5;
    final double cellHeight = theme.timetableCellHeight;
    final double timeColumnWidth = theme.timetableTimeColumnWidth;
    final double bodyHeight = cellHeight * kMaxSessions;
    final List<_PlacedCourse> placements = _collectPlacements(dayCount);

    return SingleChildScrollView(
      child: SizedBox(
        height: kGridHeaderHeight + bodyHeight,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // 每列宽度 = (可用宽度 - 时间列) / 可见天数
            final double available = constraints.maxWidth - timeColumnWidth;
            final double columnWidth =
                available > 0 ? available / dayCount : 0;
            if (columnWidth <= 0) return const SizedBox.shrink();

            return Stack(
              children: <Widget>[
                ..._buildHeader(theme, dayCount, timeColumnWidth, columnWidth),
                ..._buildCells(theme, dayCount, timeColumnWidth, columnWidth,
                    cellHeight),
                ..._buildCards(theme, placements, timeColumnWidth, columnWidth,
                    cellHeight),
              ],
            );
          },
        ),
      ),
    );
  }

  // ————————————————————— 表头 —————————————————————

  List<Widget> _buildHeader(
    AppTheme theme,
    int dayCount,
    double timeColumnWidth,
    double columnWidth,
  ) {
    final List<Widget> children = <Widget>[
      // 左上角空单元格
      Positioned(
        left: 0,
        top: 0,
        width: timeColumnWidth,
        height: kGridHeaderHeight,
        child: Container(
          decoration: BoxDecoration(
            color: theme.surface,
            border: Border(
              right: BorderSide(color: theme.background),
              bottom: BorderSide(color: theme.background),
            ),
          ),
        ),
      ),
    ];

    for (int day = 1; day <= dayCount; day++) {
      children.add(
        Positioned(
          left: timeColumnWidth + (day - 1) * columnWidth,
          top: 0,
          width: columnWidth,
          height: kGridHeaderHeight,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.surface,
              border: Border(
                right: BorderSide(color: theme.background),
                bottom: BorderSide(color: theme.background),
              ),
            ),
            child: Text(
              kWeekdayLabels[day - 1],
              style: TextStyle(
                fontSize: theme.captionSize,
                fontWeight: theme.titleFontWeight,
                color: theme.onBackground,
              ),
            ),
          ),
        ),
      );
    }
    return children;
  }

  // —————————————————— 时间列 + 空单元格 ——————————————————

  List<Widget> _buildCells(
    AppTheme theme,
    int dayCount,
    double timeColumnWidth,
    double columnWidth,
    double cellHeight,
  ) {
    final List<Widget> children = <Widget>[];

    for (int session = 1; session <= kMaxSessions; session++) {
      final double top = kGridHeaderHeight + (session - 1) * cellHeight;
      final String? time = sectionTimes[session];

      // 左侧时间列：第 N 节 + 具体时间
      children.add(
        Positioned(
          left: 0,
          top: top,
          width: timeColumnWidth,
          height: cellHeight,
          child: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: theme.gridGap),
            decoration: BoxDecoration(
              color: theme.surface,
              border: Border(
                right: BorderSide(color: theme.background),
                bottom: BorderSide(color: theme.background),
              ),
            ),
            // 时间列很窄（timetableTimeColumnWidth，默认 40px），
            // "08:30-09:15" 放一行会换行撑破单元格，所以拆成上下两行；
            // 外面再套 FittedBox 兜底，避免主题把字号调大后溢出。
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    '第$session节',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: theme.captionSize,
                      color: theme.onBackground,
                    ),
                  ),
                  if (time != null)
                    Text(
                      _startOfTimeRange(time),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: theme.captionSize * 0.8,
                        color: theme.onBackground.withValues(alpha: 0.55),
                      ),
                    ),
                  if (time != null && _endOfTimeRange(time).isNotEmpty)
                    Text(
                      _endOfTimeRange(time),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: theme.captionSize * 0.8,
                        color: theme.onBackground.withValues(alpha: 0.55),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      // 右侧空单元格（课程卡片会盖在上面）
      for (int day = 1; day <= dayCount; day++) {
        children.add(
          Positioned(
            left: timeColumnWidth + (day - 1) * columnWidth,
            top: top,
            width: columnWidth,
            height: cellHeight,
            child: Container(
              decoration: BoxDecoration(
                color: theme.surface,
                border: Border(
                  right: BorderSide(color: theme.background),
                  bottom: BorderSide(color: theme.background),
                ),
              ),
            ),
          ),
        );
      }
    }
    return children;
  }

  // ———————————————————— 课程卡片 ————————————————————

  List<Widget> _buildCards(
    AppTheme theme,
    List<_PlacedCourse> placements,
    double timeColumnWidth,
    double columnWidth,
    double cellHeight,
  ) {
    return placements.map((_PlacedCourse placed) {
      final Course course = placed.course;
      final double gap = theme.gridGap;
      return Positioned(
        key: ValueKey<String>(
          '${course.id}-${placed.day}-${placed.startSession}-$currentWeek',
        ),
        left: timeColumnWidth + (placed.day - 1) * columnWidth + gap,
        top: kGridHeaderHeight + (placed.startSession - 1) * cellHeight + gap,
        width: columnWidth - gap * 2,
        // 跨节：卡片高度 = 节数 * 单元格高度（减去上下留白）
        height: placed.length * cellHeight - gap * 2,
        child: _CourseCard(
          course: course,
          timePlace: placed.timePlace,
          color: _colorForCourse(course, theme),
          onTap: onTapCourse == null ? null : () => onTapCourse!(course),
          onLongPress: onLongPressCourse == null
              ? null
              : () => onLongPressCourse!(course),
        ),
      );
    }).toList(growable: false);
  }

  /// 扫描网格，找出每个"课程块"的左上角与其高度。
  ///
  /// `buildGrid` 会把同一门课的实例填进跨节涉及的每一格，因此
  /// "上一格不是同一实例"就是块的起点；再向下数连续的同实例格数得到节数。
  /// 用 `identical` 而非 `==`：同一门课的不同实例不该被合并。
  List<_PlacedCourse> _collectPlacements(int dayCount) {
    final List<_PlacedCourse> result = <_PlacedCourse>[];
    for (int day = 1; day <= dayCount; day++) {
      if (day >= grid.length) break;
      final List<Course?> column = grid[day];
      for (int session = 1; session <= kMaxSessions; session++) {
        if (session >= column.length) break;
        final Course? course = column[session];
        if (course == null) continue;
        // 只处理块顶部
        if (session > 1 && identical(column[session - 1], course)) continue;

        int length = 1;
        while (session + length < column.length &&
            identical(column[session + length], course)) {
          length++;
        }
        result.add(_PlacedCourse(
          course: course,
          day: day,
          startSession: session,
          length: length,
          timePlace: _timePlaceFor(course, day, session),
        ));
      }
    }
    return result;
  }

  /// 找出该课程在 (day, startSession) 对应的 [TimePlace]，用于取教室等信息。
  ///
  /// 网格里只有 [Course]，没有 [TimePlace]，而卡片要显示教室，
  /// 所以按"星期 + 起始节次"回查；查不到返回 `null`（卡片只显示课程名与教师）。
  TimePlace? _timePlaceFor(Course course, int day, int session) {
    for (final TimePlace tp in course.displayTimePlaces) {
      if (tp.day == day && tp.startSession == session) return tp;
    }
    return null;
  }

  /// 课程卡片颜色。
  ///
  /// 优先用户自定义色（`userOverride.customColor`），
  /// 否则按 `course.id` 的哈希从主题配色池里取——
  /// 同一门课每次渲染都得到同样的颜色，且不同课程尽量分散。
  Color _colorForCourse(Course course, AppTheme theme) {
    final int? custom = course.displayColor;
    if (custom != null) return Color(custom);
    if (theme.courseCardColors.isEmpty) return theme.surface;
    final int index =
        course.id.hashCode.abs() % theme.courseCardColors.length;
    return theme.courseCardColors[index];
  }
}

/// 星期标签（索引 0 = 周一）。
const List<String> kWeekdayLabels = <String>[
  '周一', '周二', '周三', '周四', '周五', '周六', '周日',
];

/// `"08:30-09:15"` → `"08:30"`；没有连字符时原样返回。
String _startOfTimeRange(String time) {
  final int dash = time.indexOf('-');
  return dash < 0 ? time : time.substring(0, dash);
}

/// `"08:30-09:15"` → `"09:15"`；没有连字符时返回空串。
String _endOfTimeRange(String time) {
  final int dash = time.indexOf('-');
  return dash < 0 ? '' : time.substring(dash + 1);
}

/// 一个待渲染的课程块（网格里的左上角 + 高度）。
class _PlacedCourse {
  const _PlacedCourse({
    required this.course,
    required this.day,
    required this.startSession,
    required this.length,
    required this.timePlace,
  });

  final Course course;
  final int day;
  final int startSession;
  final int length;
  final TimePlace? timePlace;
}

/// 单个课程卡片：课程名（最多 2 行）+ 教师 + 教室。
class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.timePlace,
    required this.color,
    this.onTap,
    this.onLongPress,
  });

  final Course course;
  final TimePlace? timePlace;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final String teacher = course.displayTeacher;
    final String room = timePlace?.room ?? '';
    // 卡片底色来自主题配色池（浅色），文字用正文色保证对比度。
    final Color textColor = theme.onBackground;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(theme.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.all(theme.gridGap),
          // 单元格高度固定（timetableCellHeight），课程名 2 行 + 教师 + 教室
          // 在单节卡片里可能放不下。用 FittedBox 等比缩小兜底，
          // 保证任何主题字号 / 卡片高度组合都不溢出。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  course.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: theme.captionSize,
                    fontWeight: theme.titleFontWeight,
                    color: textColor,
                  ),
                ),
                if (teacher.isNotEmpty)
                  Text(
                    teacher,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: theme.captionSize * 0.85,
                      color: textColor.withValues(alpha: 0.75),
                    ),
                  ),
                if (room.isNotEmpty)
                  Text(
                    room,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: theme.captionSize * 0.85,
                      color: textColor.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}