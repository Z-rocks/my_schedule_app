// 课表页（空态骨架）：周次选择器 + 空态提示
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';

/// 周次选择器的高度（逻辑像素）。
///
/// 水平 `ListView` 在纵向需要确定高度，`ChoiceChip` 需要约 40px + 上下留白，
/// 故定义组件级常量（CONTEXT.md 4.1 的 `k` 前缀小驼峰）。
const double kWeekSelectorHeight = 48;

/// 课表页。
///
/// **Phase 1.5 只做 UI 骨架**：周次选择器只改内部 state，不读任何业务数据
/// （不接 Provider、不渲染课程网格）。课表网格在 Phase 5 实现。
class TimetableView extends StatefulWidget {
  const TimetableView({super.key, this.totalWeeks = 20, this.initialWeek = 1});

  /// 学期总周数。
  final int totalWeeks;

  /// 初始选中的周次。
  ///
  /// Phase 2 接入学期配置后，由调用方传入真实的"当前周"；
  /// 目前没有学期起始日期，因此默认第 1 周。
  final int initialWeek;

  @override
  State<TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends State<TimetableView> {
  late int _currentWeek;

  @override
  void initState() {
    super.initState();
    _currentWeek = _clampWeek(widget.initialWeek);
  }

  /// 把周次限制在 `1..totalWeeks` 之间，避免外部传入越界值。
  int _clampWeek(int week) {
    if (week < 1) return 1;
    if (week > widget.totalWeeks) return widget.totalWeeks;
    return week;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('课表'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加课程',
            onPressed: () => _showSnack('添加课程（待实现）'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildWeekSelector(theme),
          Expanded(
            child: EmptyState(
              icon: Icons.calendar_today,
              title: '还没有课表数据',
              subtitle: '点击右上角 + 添加课程，或安装插件从教务系统导入',
              actionLabel: '去设置安装插件',
              onAction: () => _showSnack('请前往设置 → 插件管理'),
            ),
          ),
        ],
      ),
    );
  }

  /// 周次选择器：1..totalWeeks 的水平滚动数字列表。
  Widget _buildWeekSelector(AppTheme theme) {
    return SizedBox(
      height: kWeekSelectorHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: theme.cardPadding),
        itemCount: widget.totalWeeks,
        itemBuilder: (BuildContext context, int index) {
          final int week = index + 1;
          final bool selected = week == _currentWeek;
          return Padding(
            padding: EdgeInsets.only(right: theme.gridGap * 2),
            child: Center(
              child: ChoiceChip(
                label: Text('$week'),
                selected: selected,
                onSelected: (bool _) => setState(() => _currentWeek = week),
                labelStyle: TextStyle(
                  fontSize: theme.bodySize,
                  color: selected ? theme.onPrimary : theme.onBackground,
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