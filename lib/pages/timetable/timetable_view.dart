// 课表页：周次选择器 + 课程网格 + 三种状态（未配学期 / 无课程 / 有数据）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../models/semester_config.dart';
import '../../providers/course_provider.dart';
import '../../providers/semester_provider.dart';
import '../../services/timetable_logic.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/timetable_grid.dart';
import 'course_detail_sheet.dart';

/// 周次选择器的高度（逻辑像素）。
///
/// 水平 `ListView` 在纵向需要确定高度，`ChoiceChip` 需要约 40px + 上下留白，
/// 故定义组件级常量（CONTEXT.md 4.1 的 `k` 前缀小驼峰）。
const double kWeekSelectorHeight = 48;

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

/// 课表页。
///
/// 数据来源（全部经 Provider，本页不直接访问 Hive）：
/// - [SemesterProvider]：学期起止与总周数，决定"当前周"与周次选择器长度
/// - [CourseProvider]：课程列表（用 `visibleCourses`，已过滤隐藏课程）
/// - `TimetableLogic`：周次解析与网格构建（纯函数）
class TimetableView extends StatefulWidget {
  const TimetableView({super.key});

  @override
  State<TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends State<TimetableView> {
  /// 当前选中的周次。
  int _week = 1;

  /// [_week] 是基于哪个学期算出来的（学期变了就重新落到"当前周"）。
  String _weekBasis = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // build 里 watch 了 SemesterProvider，学期变化会先触发本回调，
    // 因此这里能及时把选中周同步到新学期的"当前周"。
    _syncWeekWithSemester(context.read<SemesterProvider>().config);
  }

  /// 学期变化时把选中周重置为"当前周"；同一个学期内保留用户的选择。
  void _syncWeekWithSemester(SemesterConfig? config) {
    final String basis = config == null
        ? ''
        : '${config.startDate.toIso8601String()}|${config.totalWeeks}';
    if (basis == _weekBasis) return;
    _weekBasis = basis;
    _week = config == null ? 1 : TimetableLogic.currentWeek(config);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final SemesterProvider semester = context.watch<SemesterProvider>();
    final CourseProvider courses = context.watch<CourseProvider>();
    final SemesterConfig? config = semester.config;
    final List<Course> visible = courses.visibleCourses;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('课表'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加课程',
            onPressed: () => _showSnack('添加课程页待实现（Phase 2.2c）'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 没有学期时周次无意义，隐藏选择器
          if (config != null) _buildWeekSelector(theme, config),
          Expanded(child: _buildBody(theme, config, visible)),
        ],
      ),
    );
  }

  /// 三种状态：
  /// a. 未配置学期 → 提示去配置
  /// b. 已配置学期但没有课程 → 提示添加课程
  /// c. 有课程 → 渲染网格
  Widget _buildBody(
    AppTheme theme,
    SemesterConfig? config,
    List<Course> courses,
  ) {
    if (config == null) {
      return EmptyState(
        icon: Icons.calendar_today,
        title: '还没有配置学期',
        subtitle: '配置学期后才能看到课表',
        actionLabel: '去配置学期',
        onAction: () => _showSnack('学期配置页待实现（Phase 2.2c）'),
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

    final List<List<Course?>> grid =
        TimetableLogic.buildGrid(courses, _week);
    return TimetableGrid(
      grid: grid,
      sectionTimes: kDefaultSectionTimes,
      currentWeek: _week,
      onTapCourse: (Course course) => showCourseDetailSheet(context, course),
      onLongPressCourse: (Course _) =>
          _showSnack('编辑功能待实现（Phase 5）'),
    );
  }

  /// 周次选择器：1..totalWeeks 的水平滚动数字列表。
  Widget _buildWeekSelector(AppTheme theme, SemesterConfig config) {
    final int totalWeeks = config.totalWeeks < 1 ? 1 : config.totalWeeks;
    final int selected = _week.clamp(1, totalWeeks);

    return SizedBox(
      height: kWeekSelectorHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: theme.cardPadding),
        itemCount: totalWeeks,
        itemBuilder: (BuildContext context, int index) {
          final int week = index + 1;
          final bool isSelected = week == selected;
          return Padding(
            padding: EdgeInsets.only(right: theme.gridGap * 2),
            child: Center(
              child: ChoiceChip(
                label: Text('$week'),
                selected: isSelected,
                onSelected: (bool _) => setState(() => _week = week),
                labelStyle: TextStyle(
                  fontSize: theme.bodySize,
                  color: isSelected ? theme.onPrimary : theme.onBackground,
                ),
                selectedColor: theme.primary,
                backgroundColor: theme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.chipRadius),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}