// 主页：按 ModuleProvider.visibleModules 动态构建底部导航栏与页面
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/module.dart';
import '../providers/module_provider.dart';
import '../services/app_log.dart';
import '../services/widget_bridge.dart';
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
  void initState() {
    super.initState();
    // 小组件 / 通知点击跳转（Phase W1）：Kotlin 把目标经 WidgetNav 递过来，
    // 这里消费并切到对应 tab；目标模块被用户关了就停在原来的页面。
    WidgetNav.pendingTarget.addListener(_onWidgetTarget);
    // **必须补这一下**：冷启动（进程被拉起）或 Activity 重建时，目标在
    // HomePage 构建之前就已经写进 pendingTarget 了，只靠监听会漏掉
    // （ValueNotifier 不会为"注册前发生的变更"补发通知）。
    // 放到帧后执行：initState 里直接 setState 会在首帧前触发多余重建。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onWidgetTarget();
    });
  }

  @override
  void dispose() {
    WidgetNav.pendingTarget.removeListener(_onWidgetTarget);
    super.dispose();
  }

  void _onWidgetTarget() {
    final WidgetTarget? target = WidgetNav.pendingTarget.value;
    if (target == null) return;
    WidgetNav.pendingTarget.value = null; // 消费掉，避免重复触发
    if (!mounted) return;

    final ModuleType want = switch (target) {
      WidgetTarget.home => ModuleType.timetable,
      WidgetTarget.homework => ModuleType.homework,
      WidgetTarget.exam => ModuleType.exam,
    };
    final List<ModuleInfo> modules = context.read<ModuleProvider>().visibleModules;
    final int index = modules.indexWhere((ModuleInfo m) => m.type == want);
    debugPrint('[WidgetNav] 切 tab：target=$target index=$index');
    // 先退回到标签页根节点：点击来自"外部"（桌面卡片 / 通知栏），
    // 用户上次可能停在设置、作业提醒之类的二级页面上，不退栈的话
    // 切好的 tab 会被那层页面盖住，看起来像"没跳转"。
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    if (index >= 0) setState(() => _currentIndex = index);
    // index < 0：模块被隐藏/关闭，什么都不做，停在当前页。
  }

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
        onDestinationSelected: (int index) {
          // 行为埋点：标签切换是最高频的操作，日志里能看到
          // "用户在哪个模块之间来回跳"——很多"数据没刷新"的反馈
          // 其实是切走又切回，靠这条就能看出来。
          if (index >= 0 && index < modules.length) {
            AppLog.action('tab_switch', <String, Object?>{
              // 插件模块的 `type` 是 null（它不是内置类型），退回能力 id。
              'to': modules[index].type?.name ?? modules[index].capabilityId,
              'index': index,
            });
          }
          setState(() => _currentIndex = index);
        },
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