// 主页：按 ModuleProvider.visibleModules 动态构建底部导航栏与页面
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/module.dart';
import '../providers/module_provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_extension.dart';
import '../widgets/empty_state.dart';
import '../widgets/module_icon.dart';
import 'course_list/course_list_view.dart';
import 'exam/exam_view.dart';
import 'homework/homework_view.dart';
import 'message/message_view.dart';
import 'settings/settings_page.dart';
import 'timetable/timetable_view.dart';

/// 主页外壳：底部导航栏的模块与顺序完全由 [ModuleProvider] 决定。
///
/// 用户在"设置 → 导航栏配置"里勾选 / 取消模块后，本页会立即重建
/// （CONTEXT.md 3.4"用户改动后导航栏立即刷新"）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 当前选中的导航栏下标（对应 `visibleModules` 的下标，不是 `allModules` 的）。
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final ModuleProvider moduleProvider = context.watch<ModuleProvider>();
    final List<ModuleInfo> modules = moduleProvider.visibleModules;

    // 极端兜底：课表与设置是常驻模块，理论上 visibleModules 不会为空。
    if (modules.isEmpty) {
      return Scaffold(
        backgroundColor: theme.background,
        body: const EmptyState(
          icon: Icons.settings_outlined,
          title: '没有可显示的模块',
          subtitle: '请到设置中开启',
        ),
      );
    }

    // 越界保护：模块被关闭后 visibleModules 会变短，此时旧下标可能越界。
    // 越界时**重置为 0**（回到课表，它是常驻的首个模块），而不是钳到最后一个，
    // 否则用户会莫名其妙地停在别的页面上。
    // 这里先算出本帧可用的下标（保证渲染不崩），再把真实状态推迟到
    // 帧结束后归一化——避免在 build 中 setState。
    final int safeIndex = _currentIndex < modules.length ? _currentIndex : 0;
    if (safeIndex != _currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted || _currentIndex == safeIndex) return;
        setState(() => _currentIndex = safeIndex);
      });
    }

    return Scaffold(
      // 用 IndexedStack 保活各页面，切回标签时保留滚动位置与内部状态
      // （例如课表页选中的周次）。
      body: IndexedStack(
        index: safeIndex,
        children: modules
            .map((ModuleInfo module) => _buildPage(context, module))
            .toList(growable: false),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (int index) =>
            setState(() => _currentIndex = index),
        destinations: modules
            .map(
              (ModuleInfo module) => NavigationDestination(
                icon: Icon(iconFromName(module.iconName)),
                label: module.title,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  /// 模块 → 页面。
  ///
  /// `settings` 与插件模块的页面分别属于 Phase 1.6 与 Phase 3，
  /// 目前用 [_pendingPage] 给出空态外壳。
  Widget _buildPage(BuildContext context, ModuleInfo module) {
    switch (module.type) {
      case ModuleType.timetable:
        return const TimetableView();
      case ModuleType.courseList:
        return const CourseListView();
      case ModuleType.exam:
        return const ExamView();
      case ModuleType.homework:
        return const HomeworkView();
      case ModuleType.message:
        return const MessageView();
      case ModuleType.settings:
        return const SettingsPage();
      case null:
        // 插件贡献的自定义模块（ModuleInfo.type == null），Phase 3 实现。
        return _pendingPage(context, module, '插件模块页面待实现（Phase 3）');
    }
  }

  /// 尚未实现的页面的临时外壳：统一用 [EmptyState] 呈现，不再单写占位类。
  Widget _pendingPage(BuildContext context, ModuleInfo module, String subtitle) {
    final AppTheme theme = AppThemeExtension.of(context);
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(module.title),
        centerTitle: true,
      ),
      body: EmptyState(
        icon: iconFromName(module.iconName),
        title: module.title,
        subtitle: subtitle,
      ),
    );
  }
}