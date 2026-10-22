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

/// 并排卡片之间的细缝（只在时间重叠、一列拆成多份时生效）。
///
/// 取 1 而不是 `kCardInset`：列宽本来就只有 50 上下，分成两份后
/// 每份 24 左右，再各让出 2px 就等于把课程名全挤掉了。
const double kOverlapGap = 1;

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
/// **纯展示组件**：不读 Provider、不访问存储，只把 [blocks] 画出来。
/// 布局（跨节合并 + 重叠并排）全部由 `TimetableLogic.layoutBlocks` 算好，
/// 这里只负责把每块的左上角、宽高换算成像素。
///
/// **一屏 7 天**：每列宽度 = `(可用宽度 - 时间列宽) / 可见天数`，
/// 整体只做纵向滚动，**不横向滚动**（Phase 2.2b.3 视觉稿要求）。
///
/// 用 `Stack` + `Positioned` 而不是 `Table`：`Table` 不支持跨行合并
/// （rowspan），而一门连上 3 节的课需要占满 3 格高度。
class TimetableGrid extends StatelessWidget {
  /// 已排好槽位的课程块（`TimetableLogic.layoutBlocks` 产出）。
  ///
  /// 一块 = 一张卡片：跨节的课只有一块（不是每节一块），
  /// 同一时间重叠的课各有各的块，靠 [TimetableBlock.slotIndex] /
  /// [TimetableBlock.slotCount] 分成并排的窄卡。
  final List<TimetableBlock> blocks;

  /// 节次 → 时间文本，如 `{1: "08:30-09:15"}`。
  final Map<int, String> sectionTimes;

  /// 当前显示第几周。
  ///
  /// 块本身已由调用方按周过滤过（`layoutBlocks(courses, week)`）；
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
    required this.blocks,
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
    final List<TimetableBlock> placements = blocks;

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
    List<TimetableBlock> placements,
    double timeColumnWidth,
    double columnWidth,
    double cellHeight,
  ) {
    return placements.map((TimetableBlock placed) {
      final Course course = placed.course;
      const double inset = kCardInset;
      // 并排：把整列宽度均分给同一时间块的课程。
      // slotCount == 1 时结果与改动前完全一致（整列宽 - 两侧 inset）。
      final double usableWidth = columnWidth - inset * 2;
      final double slotWidth = usableWidth / placed.slotCount;
      final double slotGap = placed.slotCount > 1 ? kOverlapGap : 0;
      return Positioned(
        key: ValueKey<String>(
          '${course.id}-${placed.day}-${placed.startSession}-'
          '${placed.slotIndex}-$currentWeek',
        ),
        left: timeColumnWidth +
            (placed.day - 1) * columnWidth +
            inset +
            placed.slotIndex * slotWidth,
        top: kGridHeaderHeight +
            (placed.startSession - 1) * cellHeight +
            inset,
        width: slotWidth - slotGap,
        // 跨节：卡片高度 = 节数 × 单元格高度（减去外缩进）
        height: placed.length * cellHeight - inset * 2,
        child: _CourseCard(
          course: course,
          timePlace: placed.timePlace,
          color: _colorForCourse(course, theme),
          length: placed.length,
          // 并排时列宽只剩一半，内边距必须收紧，否则一个字都放不下
          dense: placed.slotCount > 1,
          onTap: onTapCourse == null ? null : () => onTapCourse!(course),
          onLongPress: onLongPressCourse == null
              ? null
              : () => onLongPressCourse!(course),
        ),
      );
    }).toList(growable: false);
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

// `splitCampusAndRoom` 已下沉到模型层（`models/time_place.dart`），
// 小组件快照要复用同一套"校区 + 教室"拆分规则。本文件通过上面的
// `import '../models/time_place.dart'` 直接使用，不再重复定义。

/// 单个课程卡片：课程名 + 教室。
///
/// 内容按**节数**逐级显示（Phase 2.2b.4）：
/// - `length >= 2` → 课程名 + 教室
/// - `length == 1` → 只显示课程名（格子太小，放不下教室）
///
/// **不显示教师**（只在详情弹层里），**不显示 `@校区`**
/// （真机反馈：窄列宽下教室与校区互相挤到看不清）。
class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.timePlace,
    required this.color,
    required this.length,
    this.dense = false,
    this.onTap,
    this.onLongPress,
  });

  final Course course;
  final TimePlace? timePlace;
  final Color color;

  /// 该课程块占几节（用于计算可用高度）。
  final int length;

  /// 紧凑模式：卡片被并排压到半宽时打开，收紧左右内边距。
  final bool dense;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 行高倍数（与 `TextStyle.height` 保持一致，用于估算能放几行）。
  static const double _lineFactor = 1.2;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final Color textColor = theme.onBackground;

    final String name = course.displayName;
    // 只取教室部分：`"曹妃甸校区 HE-405"` → `"HE-405"`。
    // 校区不再显示（Phase 2.2b.4：窄列宽下教室与 @校区 会互相挤到看不清）。
    final ({String campus, String room}) place =
        splitCampusAndRoom(timePlace?.room ?? '');
    final String room = place.room;

    // 卡片块高度 = 节数 × 单元格高度
    final double blockHeight = length * theme.timetableCellHeight;
    // 1 节课的格子放不下教室，只显示课程名；2 节及以上才有位置
    final bool showRoom = length >= 2 && room.isNotEmpty;

    // 课程名能占几行：按可用高度算，最多 3 行。
    // 课程名优先——教室排在后面，真放不下时由外层裁掉（不抢课程名的空间）。
    final double innerHeight = blockHeight - kCardPaddingV * 2;
    final double nameLineHeight = theme.bodySize * _lineFactor;
    int nameMaxLines = nameLineHeight <= 0
        ? 1
        : (innerHeight / nameLineHeight).floor();
    if (nameMaxLines < 1) nameMaxLines = 1;
    if (nameMaxLines > 3) nameMaxLines = 3;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(theme.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 1 : kCardPaddingH,
            vertical: kCardPaddingV,
          ),
          // 内容按自然高度排布，超出卡片高度的部分**裁掉**（不用省略号）：
          // OverflowBox 让 Column 拿到无界高度、按内容自然排布，
          // 外层 ClipRect 把溢出部分裁掉——这样既允许教室换行，
          // 又不会触发 RenderFlex 溢出报错。
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
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
                  if (showRoom)
                    Text(
                      room,
                      // 允许换行、最多 2 行；超出部分直接裁掉，不加省略号
                      maxLines: 2,
                      overflow: TextOverflow.clip,
                      softWrap: true,
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
        ),
      ),
    );
  }
}
