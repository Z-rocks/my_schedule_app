// 课表网格：用 Stack + Positioned 绝对定位渲染课程卡片（纯展示组件）
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/time_place.dart';
import '../services/timetable_logic.dart';
import '../theme/app_theme.dart';
import '../theme/theme_extension.dart';

/// 表头（星期 + 日期那一行）的高度。
///
/// [AppTheme] 没有表头高度的令牌，故定义组件级常量
/// （CONTEXT.md 4.1 的 `k` 前缀小驼峰）。
const double kGridHeaderHeight = 34;

/// 卡片相对格子的外缩进（每边）。
///
/// 取 `theme.gridGap / 2`（默认 2）——卡片基本"占满格子"，
/// 只留一条细缝把相邻两节课分开。
const double kCardInset = 2;

/// 卡片内边距：左右 3、上下 4（Phase 2.2b.3 视觉稿指定）。
///
/// 列宽只有约 46px，内边距必须很小才放得下课程名。
const double kCardPaddingH = 3;
const double kCardPaddingV = 4;

/// 星期短标签（索引 0 = 周一），用于表头。
const List<String> kWeekdayShortLabels = <String>[
  '一', '二', '三', '四', '五', '六', '日',
];

/// 星期标签（索引 0 = 周一），用于详情弹层等需要全称的地方。
const List<String> kWeekdayLabels = <String>[
  '周一', '周二', '周三', '周四', '周五', '周六', '周日',
];

/// 课表网格。
///
/// **纯展示组件**：不读 Provider、不访问存储，只把 [grid] 画出来。
/// 网格由 `TimetableLogic.buildGrid` 生成，尺寸 `(7+1) × (12+1)`，
/// 索引 1-7（星期）与 1-12（节次）有效，索引 0 为占位。
///
/// **一屏 7 天**：每列宽度 = `(可用宽度 - 时间列宽) / 可见天数`，
/// 整体只做纵向滚动，**不横向滚动**（Phase 2.2b.3 视觉稿要求）。
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

  /// 当前周的**周一**（`null` 时不显示日期）。
  ///
  /// 表头据此算出每列日期（`weekStartDate + (dayIndex - 1)` 天），
  /// 并在时间列表头显示该周的月份。
  final DateTime? weekStartDate;

  /// 点击课程卡片。
  final void Function(Course course)? onTapCourse;

  /// 长按课程卡片。
  final void Function(Course course)? onLongPressCourse;

  const TimetableGrid({
    super.key,
    required this.grid,
    required this.sectionTimes,
    required this.currentWeek,
    this.weekStartDate,
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
            // 每列宽度 = (可用宽度 - 时间列) / 可见天数 —— 一屏正好放下全部天数
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

  /// 表头：时间列格显示当前周的**月份**，其余格显示"星期 + 日期"。
  List<Widget> _buildHeader(
    AppTheme theme,
    int dayCount,
    double timeColumnWidth,
    double columnWidth,
  ) {
    final DateTime? weekStart = weekStartDate;
    final List<Widget> children = <Widget>[
      // 左上角：该周的月份（如 "9月"）；没有周起始日则留空
      Positioned(
        left: 0,
        top: 0,
        width: timeColumnWidth,
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
            weekStart == null ? '' : '${weekStart.month}月',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: theme.bodySize,
              fontWeight: theme.titleFontWeight,
              color: theme.onBackground,
            ),
          ),
        ),
      ),
    ];

    for (int day = 1; day <= dayCount; day++) {
      // 该列日期 = 该周周一 + (dayIndex - 1) 天
      final DateTime? columnDate =
          weekStart?.add(Duration(days: day - 1));
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
              columnDate == null
                  ? kWeekdayShortLabels[day - 1]
                  : '${kWeekdayShortLabels[day - 1]} '
                      '${_headerDayLabel(columnDate)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
            padding: EdgeInsets.symmetric(horizontal: theme.gridGap / 2),
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
            // （这是**时间列**的兜底，与课程卡片无关。）
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
      const double inset = kCardInset;
      return Positioned(
        key: ValueKey<String>(
          '${course.id}-${placed.day}-${placed.startSession}-$currentWeek',
        ),
        left: timeColumnWidth + (placed.day - 1) * columnWidth + inset,
        top: kGridHeaderHeight +
            (placed.startSession - 1) * cellHeight +
            inset,
        width: columnWidth - inset * 2,
        // 跨节：卡片高度 = 节数 × 单元格高度（减去外缩进）
        height: placed.length * cellHeight - inset * 2,
        child: _CourseCard(
          course: course,
          timePlace: placed.timePlace,
          color: _colorForCourse(course, theme),
          length: placed.length,
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

  /// 找出该课程在 (day, startSession) 对应的 [TimePlace]，用于取教室 / 校区。
  ///
  /// 网格里只有 [Course]，没有 [TimePlace]，而卡片要显示教室，
  /// 所以按"星期 + 起始节次"回查；查不到返回 `null`（卡片只显示课程名）。
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

/// 表头里的日期标签：1 号显示 `M/1`（跨月时能看出换月），其余显示日号。
String _headerDayLabel(DateTime date) =>
    date.day == 1 ? '${date.month}/1' : '${date.day}';

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

/// 把 `TimePlace.room`（如 `"曹妃甸校区 HE-405"`）拆成"校区 + 教室"。
///
/// 模型层目前只有 `room` 一个字段，而视觉稿要分两行显示教室与 `@校区`，
/// 所以按**首个空白**拆分：第一段是校区，其余是教室。
/// 没有空白时整串都算教室，校区为空。
///
/// 这是展示层的权宜做法——Phase 4 定下插件的数据契约后，
/// 应给 `TimePlace` 加一个独立的 `campus` 字段（那时要按 CONTEXT 4.2.1 写迁移）。
({String campus, String room}) splitCampusAndRoom(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) return (campus: '', room: '');

  final int space = text.indexOf(RegExp(r'\s'));
  if (space < 0) return (campus: '', room: text);

  final String campus = text.substring(0, space).trim();
  final String room = text.substring(space).trim();
  if (room.isEmpty) return (campus: '', room: campus);
  return (campus: campus, room: room);
}

/// 单个课程卡片：课程名（最多 3 行）+ 教室 + `@校区`。
///
/// 内容按**卡片可用高度**逐级显示（视觉稿规则）：
/// - 高度 ≥ 2.5 格 → 课程名 + 教室 + @校区
/// - 高度 ≥ 1.5 格 → 课程名 + 教室
/// - 否则 → 只显示课程名
///
/// **不显示教师**（视觉稿要求，教师移到详情弹层）。
class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.timePlace,
    required this.color,
    required this.length,
    this.onTap,
    this.onLongPress,
  });

  final Course course;
  final TimePlace? timePlace;
  final Color color;

  /// 该课程块占几节（用于计算可用高度）。
  final int length;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 行高倍数（与 `TextStyle.height` 保持一致，用于估算能放几行）。
  static const double _lineFactor = 1.2;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final Color textColor = theme.onBackground;

    final String name = course.displayName;
    final ({String campus, String room}) place =
        splitCampusAndRoom(timePlace?.room ?? '');

    // 卡片块高度 = 节数 × 单元格高度
    final double blockHeight = length * theme.timetableCellHeight;
    final bool showRoom = blockHeight >= 1.5 * theme.timetableCellHeight;
    final bool showCampus = blockHeight >= 2.5 * theme.timetableCellHeight;

    // 课程名能占几行：扣掉内边距与 meta 行占用的高度，最多 3 行。
    // 这一步保证按目标字号渲染也不会溢出（不依赖 FittedBox 缩放）。
    final double innerHeight = blockHeight - kCardPaddingV * 2;
    final int metaLines =
        (showRoom && place.room.isNotEmpty ? 1 : 0) +
            (showCampus && place.campus.isNotEmpty ? 1 : 0);
    final double metaHeight = metaLines * theme.captionSize * _lineFactor;
    final double nameLineHeight = theme.bodySize * _lineFactor;
    int nameMaxLines = nameLineHeight <= 0
        ? 1
        : ((innerHeight - metaHeight) / nameLineHeight).floor();
    if (nameMaxLines < 1) nameMaxLines = 1;
    if (nameMaxLines > 3) nameMaxLines = 3;

    final List<String> metaTexts = <String>[
      if (showRoom && place.room.isNotEmpty) place.room,
      if (showCampus && place.campus.isNotEmpty) '@${place.campus}',
    ];

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(theme.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kCardPaddingH,
            vertical: kCardPaddingV,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                name,
                maxLines: nameMaxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: theme.bodySize,
                  fontWeight: theme.titleFontWeight,
                  color: textColor,
                  height: _lineFactor,
                ),
              ),
              for (final String meta in metaTexts)
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: theme.captionSize,
                    color: textColor.withValues(alpha: 0.75),
                    height: _lineFactor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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