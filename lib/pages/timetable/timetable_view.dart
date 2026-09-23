// 课表页：顶部日期栏 + 课程网格 + 三种状态（未配学期 / 无课程 / 有数据）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../models/semester_config.dart';
import '../../providers/course_provider.dart';
import '../../providers/semester_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/timetable_logic.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/timetable_grid.dart';
import '../settings/semester_config_page.dart';
import 'course_detail_sheet.dart';

/// 顶部日期栏的高度。
const double kTopBarHeight = 48;

/// 默认节次时间表（节次 → 上课时间段）。
///
/// 暂时硬编码：`AppTheme` 只有 `timeFormat`，没有节次时间数据。
/// **Phase 4 插件接入后改为从插件的 `sectionTime` 数据读取**
/// （不同学校的作息不同，不能长期写死在客户端）。
const Map<int, String> kDefaultSectionTimes = <int, String>{
  1: '08:30-09:15',
  2: '09:20-10:05',
  3: '10:25-11:10',
  4: '11:15-12:00',
  5: '14:00-14:45',
  6: '14:50-15:35',
  7: '15:55-16:40',
  8: '16:45-17:30',
  9: '19:00-19:45',
  10: '19:50-20:35',
  11: '20:40-21:25',
  12: '21:30-22:15',
};

/// 把日期格式化成 `yyyy/M/d`（如 `2026/9/23`，不补零）。
String formatDateYmd(DateTime date) =>
    '${date.year}/${date.month}/${date.day}';

/// 某周周一的日期：`startDate + (week - 1) * 7` 天。
DateTime weekStartDateOf(SemesterConfig config, int week) {
  final DateTime start = DateTime(
    config.startDate.year,
    config.startDate.month,
    config.startDate.day,
  );
  return start.add(Duration(days: (week - 1) * kDaysPerWeek));
}

/// 课表页。
///
/// 数据来源（全部经 Provider，本页不直接访问 Hive）：
/// - [SemesterProvider]：学期起止与总周数，决定"当前周"与每周日期
/// - [CourseProvider]：课程列表（用 `visibleCourses`，已过滤隐藏课程）
/// - [SettingsProvider]：`gestureSwitchWeek` 决定是否启用左右滑动切周
/// - `TimetableLogic`：周次解析与网格构建（纯函数）
///
/// 顶部是**一行日期栏**（视觉稿要求，不再有常驻的周次 chips 行）：
/// `[今天日期]  [第 N 周]  (学期已结束)            [+]`。
/// 点击"第 N 周"弹出周次选择面板。
class TimetableView extends StatefulWidget {
  const TimetableView({super.key});

  @override
  State<TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends State<TimetableView> {
  /// 当前选中的周次。**它是唯一真相源**：滑动与选择面板都只改它。
  int _week = 1;

  /// [_week] 是基于哪个学期算出来的（学期变了就重新落到"当前周"）。
  String _weekBasis = '';

  /// 左右滑动切周用的控制器；懒建，仅 `gestureSwitchWeek == true` 时使用。
  PageController? _pageController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // build 里 watch 了 SemesterProvider，学期变化会先触发本回调，
    // 因此这里能及时把选中周同步到新学期的"当前周"。
    if (_syncWeekWithSemester(context.read<SemesterProvider>().config)) {
      // 学期变了：PageView 需要跟着跳到新周次，但它可能还没挂载，
      // 所以推迟到帧结束后再跳（那时 hasClients 才为 true）。
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted) return;
        _jumpPageToWeek(_week);
      });
    }
  }

  /// 学期变化时把选中周重置为"当前周"；同一学期内保留用户的选择。
  ///
  /// 返回是否发生了变化（调用方据此决定要不要同步 PageView）。
  bool _syncWeekWithSemester(SemesterConfig? config) {
    final String basis = config == null
        ? ''
        : '${config.startDate.toIso8601String()}|${config.totalWeeks}';
    if (basis == _weekBasis) return false;
    _weekBasis = basis;
    _week = config == null ? 1 : TimetableLogic.currentWeek(config);
    return true;
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 切换周次的统一入口：更新 `_week`，并把 PageView 对齐。
  ///
  /// 这是**双向同步**的关键：`_week` 是唯一真相源，
  /// PageView 的 `onPageChanged` 与周次面板的选择都只改 `_week`，
  /// 再由本方法把另一侧对齐，因此两侧不会互相触发形成循环。
  void _setWeek(int week, {required int totalWeeks, bool animate = true}) {
    final int clamped = week.clamp(1, totalWeeks);
    if (clamped == _week) return;
    setState(() => _week = clamped);
    if (animate) {
      _animatePageToWeek(clamped);
    } else {
      // 页面已经滑到位，不要再动，否则会和手势抢位置
      _jumpPageToWeek(clamped);
    }
  }

  void _jumpPageToWeek(int week) {
    final PageController? controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final int target = week - 1;
    if (controller.page?.round() == target) return; // 已在目标页，不必动
    controller.jumpToPage(target);
  }

  void _animatePageToWeek(int week) {
    final PageController? controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final int target = week - 1;
    if (controller.page?.round() == target) return;
    controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// 打开学期配置页（三处入口共用）。
  Future<void> _openSemesterConfig() async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) => const SemesterConfigPage(),
      ),
    );
  }

  /// 弹出周次选择面板；选中周次则跳周，选"编辑学期"则打开学期配置页。
  Future<void> _showWeekPicker(SemesterConfig config) async {
    final int totalWeeks = config.totalWeeks < 1 ? 1 : config.totalWeeks;
    final Object? result = await showModalBottomSheet<Object>(
      context: context,
      builder: (BuildContext sheetContext) => _WeekPickerSheet(
        totalWeeks: totalWeeks,
        currentWeek: _week.clamp(1, totalWeeks),
      ),
    );
    if (result == null || !mounted) return;

    if (result is int) {
      _setWeek(result, totalWeeks: totalWeeks);
      return;
    }
    if (result == _WeekPickerResult.editSemester) {
      await _openSemesterConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final SemesterProvider semester = context.watch<SemesterProvider>();
    final CourseProvider courses = context.watch<CourseProvider>();
    final bool gestureSwitchWeek =
        context.watch<SettingsProvider>().gestureSwitchWeek;
    final SemesterConfig? config = semester.config;
    final List<Course> visible = courses.visibleCourses;

    return Scaffold(
      backgroundColor: theme.background,
      // 顶部是一行日期栏，不再用 AppBar（视觉稿的顶栏就这一行）
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildTopBar(theme, config),
            Expanded(
              child: _buildBody(theme, config, visible, gestureSwitchWeek),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部日期栏：`[今天日期]  [第 N 周]  (学期已结束)   [+]`。
  Widget _buildTopBar(AppTheme theme, SemesterConfig? config) {
    final DateTime today = DateTime.now();
    final bool semesterEnded = _isSemesterEnded(config, today);

    return SizedBox(
      height: kTopBarHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: theme.cardPadding),
        child: Row(
          children: <Widget>[
            // 今天日期
            Text(
              formatDateYmd(today),
              style: TextStyle(
                fontSize: theme.bodySize,
                fontWeight: theme.titleFontWeight,
                color: theme.onBackground,
              ),
            ),
            SizedBox(width: theme.sectionGap),
            if (config != null)
              // 当前周次，可点击选择
              InkWell(
                onTap: () => _showWeekPicker(config),
                borderRadius: BorderRadius.circular(theme.chipRadius),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: theme.gridGap * 2,
                    vertical: theme.gridGap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '第 $_week 周',
                        style: TextStyle(
                          fontSize: theme.bodySize,
                          color: theme.primary,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: theme.bodySize + 4,
                        color: theme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            if (semesterEnded)
              Text(
                '学期已结束',
                style: TextStyle(
                  fontSize: theme.captionSize,
                  color: theme.onBackground.withValues(alpha: 0.45),
                ),
              ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '添加课程',
              color: theme.primary,
              onPressed: () => _showSnack('添加课程页待实现（Phase 2.2c）'),
            ),
          ],
        ),
      ),
    );
  }

  /// 学期是否已结束：当前周已是最后一周，且今天已过学期结束日。
  bool _isSemesterEnded(SemesterConfig? config, DateTime today) {
    if (config == null || config.totalWeeks < 1) return false;
    final DateTime end = config.endDate;
    final DateTime todayDate = DateTime(today.year, today.month, today.day);
    final DateTime endDate = DateTime(end.year, end.month, end.day);
    return TimetableLogic.currentWeek(config) == config.totalWeeks &&
        todayDate.isAfter(endDate);
  }

  /// 三种状态：
  /// a. 未配置学期 → 提示去配置
  /// b. 已配置学期但没有课程 → 提示添加课程
  /// c. 有课程 → 渲染网格（可按偏好用 PageView 左右滑周）
  Widget _buildBody(
    AppTheme theme,
    SemesterConfig? config,
    List<Course> courses,
    bool gestureSwitchWeek,
  ) {
    if (config == null) {
      return EmptyState(
        icon: Icons.calendar_today,
        title: '还没有配置学期',
        subtitle: '配置学期后才能看到课表',
        actionLabel: '去配置学期',
        onAction: _openSemesterConfig,
      );
    }

    if (courses.isEmpty) {
      return EmptyState(
        icon: Icons.add_circle_outline,
        title: '还没有课程',
        subtitle: '点击下方按钮添加第一门课',
        actionLabel: '添加课程',
        onAction: () => _showSnack('添加课程页待实现（Phase 2.2c）'),
      );
    }

    if (!gestureSwitchWeek) {
      // 关闭滑动切周：只能通过顶部"第 N 周"面板切换
      return _buildWeekGrid(theme, config, courses, _week);
    }

    final int totalWeeks = config.totalWeeks < 1 ? 1 : config.totalWeeks;
    _pageController ??= PageController(initialPage: _week - 1);

    return PageView.builder(
      controller: _pageController,
      itemCount: totalWeeks,
      // 滑动结束后才回调，避免拖动过程中反复 setState
      onPageChanged: (int index) => _setWeek(
        index + 1,
        totalWeeks: totalWeeks,
        animate: false,
      ),
      itemBuilder: (BuildContext context, int index) =>
          _buildWeekGrid(theme, config, courses, index + 1),
    );
  }

  /// 某一周的网格（PageView 的每一页 / 无滑动模式下的唯一一页）。
  Widget _buildWeekGrid(
    AppTheme theme,
    SemesterConfig config,
    List<Course> courses,
    int week,
  ) {
    return TimetableGrid(
      grid: TimetableLogic.buildGrid(courses, week),
      sectionTimes: kDefaultSectionTimes,
      currentWeek: week,
      weekStartDate: weekStartDateOf(config, week),
      onTapCourse: (Course course) => showCourseDetailSheet(context, course),
      onLongPressCourse: (Course _) => _showSnack('编辑功能待实现（Phase 5）'),
    );
  }
}

/// 周次面板的返回结果：面板可以返回一个周次（`int`），
/// 也可以返回本枚举表示"用户点了编辑学期"。
enum _WeekPickerResult { editSemester }

/// 周次选择面板：1..totalWeeks 的 chips，点选后返回该周次；
/// 底部另有"编辑学期"入口，返回 [_WeekPickerResult.editSemester]。
class _WeekPickerSheet extends StatelessWidget {
  const _WeekPickerSheet({required this.totalWeeks, required this.currentWeek});

  final int totalWeeks;
  final int currentWeek;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

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
                Text(
                  '选择周次',
                  style: TextStyle(
                    fontSize: theme.titleSize,
                    fontWeight: theme.titleFontWeight,
                    color: theme.onBackground,
                  ),
                ),
                SizedBox(height: theme.sectionGap),
                Wrap(
                  spacing: theme.gridGap * 2,
                  runSpacing: theme.gridGap * 2,
                  children: <Widget>[
                    for (int week = 1; week <= totalWeeks; week++)
                      ChoiceChip(
                        label: Text('$week'),
                        selected: week == currentWeek,
                        onSelected: (bool _) =>
                            Navigator.of(context).pop(week),
                        labelStyle: TextStyle(
                          fontSize: theme.bodySize,
                          color: week == currentWeek
                              ? theme.onPrimary
                              : theme.onBackground,
                        ),
                        selectedColor: theme.primary,
                        backgroundColor: theme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(theme.chipRadius),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: theme.sectionGap),
                // 学期配置入口（改学期起止/总周数）
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pop(_WeekPickerResult.editSemester),
                    icon: Icon(Icons.edit_calendar_outlined,
                        size: theme.bodySize),
                    label: Text(
                      '编辑学期',
                      style: TextStyle(fontSize: theme.bodySize),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.primary,
                    ),
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