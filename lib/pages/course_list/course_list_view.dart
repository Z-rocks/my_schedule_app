// 课程列表页：显示 CourseProvider 里的真实课程（Phase 4.3 接入）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../models/time_place.dart';
import '../../providers/course_provider.dart';
import '../../services/course_filter.dart';
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
/// - 有数据 → 搜索框 + 类别筛选 + 课程卡片列表
/// - 点卡片 → 复用课表页的 [showCourseDetailSheet]（只读详情）
class CourseListView extends StatefulWidget {
  const CourseListView({super.key});

  @override
  State<CourseListView> createState() => _CourseListViewState();
}

class _CourseListViewState extends State<CourseListView> {
  final TextEditingController _controller = TextEditingController();

  /// 当前搜索词（原样保留，匹配时由 [filterCourses] 处理大小写与空格）。
  String _query = '';

  /// 当前选中的类别；空串表示"全部"。
  String _category = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    if (value == _query) return;
    setState(() => _query = value);
  }

  void _clearQuery() {
    _controller.clear();
    _onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final List<Course> all = context.watch<CourseProvider>().visibleCourses;

    // 数据变了（同步 / 删除）之后，原来选中的类别可能已经不存在——
    // 不清理的话会出现"筛选了一个不存在的类别 → 永远空列表"。
    final List<String> categories = collectCategories(all);
    if (_category.isNotEmpty && !categories.contains(_category)) {
      _category = '';
    }

    final List<Course> courses =
        filterCourses(all, _query, category: _category);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('课程'),
        centerTitle: true,
      ),
      body: all.isEmpty
          ? const EmptyState(
              icon: Icons.book_outlined,
              title: '暂无课程',
              subtitle: '在课表页点右上角 + 添加，或安装插件从教务系统导入',
            )
          : Column(
              children: <Widget>[
                _SearchField(
                  controller: _controller,
                  onChanged: _onQueryChanged,
                  onClear: _clearQuery,
                ),
                if (categories.length > 1)
                  _CategoryBar(
                    categories: categories,
                    selected: _category,
                    onSelect: (String value) =>
                        setState(() => _category = value),
                  ),
                Expanded(
                  child: courses.isEmpty
                      ? const EmptyState(
                          icon: Icons.search_off,
                          title: '没有匹配的课程',
                          subtitle: '换个关键词试试，或点「全部」看所有课程',
                        )
                      : ListView.builder(
                          padding: EdgeInsets.all(theme.cardPadding),
                          itemCount: courses.length,
                          itemBuilder: (BuildContext context, int index) =>
                              _CourseListCard(course: courses[index]),
                        ),
                ),
              ],
            ),
    );
  }
}

/// 搜索输入框。
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        theme.cardPadding,
        theme.gridGap,
        theme.cardPadding,
        0,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
        decoration: InputDecoration(
          hintText: '搜索课程名 / 教师 / 教室',
          hintStyle: TextStyle(
            fontSize: theme.bodySize,
            color: theme.onBackground.withValues(alpha: 0.4),
          ),
          prefixIcon: Icon(
            Icons.search,
            size: theme.titleSize,
            color: theme.onBackground.withValues(alpha: 0.5),
          ),
          // 有内容才显示清除按钮：空框上挂一个 ✕ 会让人误以为能点出什么。
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, size: theme.titleSize),
                  color: theme.onBackground.withValues(alpha: 0.5),
                  onPressed: onClear,
                  tooltip: '清除',
                ),
          filled: true,
          fillColor: theme.surface,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: theme.gridGap * 1.6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(theme.cardRadius),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// 类别筛选条：`全部` + 各课程类别。
///
/// 只有一种类别时整条不显示（筛选一个选项没有意义）。
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return SizedBox(
      height: theme.titleSize * 2.6,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: theme.cardPadding,
          vertical: theme.gridGap,
        ),
        children: <Widget>[
          _FilterChip(
            label: '全部',
            selected: selected.isEmpty,
            // 再点一次"全部"不该变成未选中（列表会变成空），保持选中即可。
            onTap: () => onSelect(''),
          ),
          for (final String category in categories)
            _FilterChip(
              label: category,
              selected: selected == category,
              // 再点一次已选中的类别 = 取消筛选，回到全部。
              onTap: () => onSelect(selected == category ? '' : category),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Padding(
      padding: EdgeInsets.only(right: theme.gridGap),
      child: Material(
        color: selected ? theme.primary : theme.surface,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(theme.cardRadius),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: theme.cardPadding,
              vertical: theme.gridGap,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: theme.captionSize,
                  fontWeight:
                      selected ? FontWeight.w500 : FontWeight.normal,
                  color: selected ? theme.onPrimary : theme.onBackground,
                ),
              ),
            ),
          ),
        ),
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
