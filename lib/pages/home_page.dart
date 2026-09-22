// 主页：按 ModuleProvider.visibleModules 动态构建底部导航栏与页面
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/module.dart';
import '../providers/module_provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_extension.dart';

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
    final ModuleProvider moduleProvider = context.watch<ModuleProvider>();
    final List<ModuleInfo> modules = moduleProvider.visibleModules;

    // 极端兜底：课表与设置是常驻模块，理论上 visibleModules 不会为空。
    if (modules.isEmpty) {
      return const _NoModuleScaffold();
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
      // 用 IndexedStack 保活各页面，切回标签时保留滚动位置与内部状态。
      body: IndexedStack(
        index: safeIndex,
        children: modules
            .map((ModuleInfo module) => _buildPage(module))
            .toList(growable: false),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (int index) =>
            setState(() => _currentIndex = index),
        destinations: modules
            .map(
              (ModuleInfo module) => NavigationDestination(
                icon: Icon(_iconFromName(module.iconName)),
                label: module.title,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  /// 模块 → 页面。
  ///
  /// Phase 1.5 会把每个 `_ModulePlaceholder` 换成对应的真实页面
  /// （见每个 case 后的注释），本方法的签名保持不变。
  Widget _buildPage(ModuleInfo module) {
    switch (module.type) {
      case ModuleType.timetable:
        return _ModulePlaceholder(module: module); // Phase 1.5: TimetableView()
      case ModuleType.courseList:
        return _ModulePlaceholder(module: module); // Phase 1.5: CourseListView()
      case ModuleType.exam:
        return _ModulePlaceholder(module: module); // Phase 1.5: ExamView()
      case ModuleType.homework:
        return _ModulePlaceholder(module: module); // Phase 1.5: HomeworkView()
      case ModuleType.message:
        return _ModulePlaceholder(module: module); // Phase 1.5: MessageView()
      case ModuleType.settings:
        return _ModulePlaceholder(module: module); // Phase 1.5: SettingsPage()
      case null:
        // 插件贡献的自定义模块（ModuleInfo.type == null）。
        return _ModulePlaceholder(module: module);
    }
  }
}

/// Material 图标名 → [IconData] 映射。
///
/// 模型层的 [ModuleInfo.iconName] 是字符串（模型不依赖 Flutter），
/// 由本表在 UI 层转成 [IconData]。内置模块的图标名见
/// `ModuleProvider._initialModules`；插件可在 `.js` 里用同样的名字声明图标。
const Map<String, IconData> _kIconByName = <String, IconData>{
  // —— 内置模块 ——
  'calendar_month': Icons.calendar_month,
  'book_outlined': Icons.book_outlined,
  'assignment_outlined': Icons.assignment_outlined,
  'edit_note': Icons.edit_note,
  'notifications_outlined': Icons.notifications_outlined,
  'settings_outlined': Icons.settings_outlined,
  // —— 预留：插件常用图标 ——
  'grade_outlined': Icons.grade_outlined,
  'school_outlined': Icons.school_outlined,
  'task_outlined': Icons.task_outlined,
  'message_outlined': Icons.message_outlined,
};

/// 把图标名转成 [IconData]。
///
/// 查不到（含空字符串、插件未声明 `iconName` 的情况）时兜底为
/// [Icons.extension]——"扩展/插件"的通用图标。
IconData _iconFromName(String name) =>
    _kIconByName[name] ?? Icons.extension;

/// 把 [AppTheme.fontWeightTitle]（int，如 600）转成 [FontWeight]。
FontWeight _fontWeightOf(int value) {
  final int index = (value ~/ 100) - 1;
  if (index < 0 || index >= FontWeight.values.length) return FontWeight.w400;
  return FontWeight.values[index];
}

/// 模块页面的临时占位（Phase 1.5 由真实页面替换，届时删除本类）。
class _ModulePlaceholder extends StatelessWidget {
  const _ModulePlaceholder({required this.module});

  final ModuleInfo module;

  @override
  Widget build(BuildContext context) {
    // 样式一律从 AppTheme 读，不硬编码颜色 / 尺寸（CONTEXT.md 3.2）。
    final AppTheme theme = AppThemeExtension.of(context);
    final Color hintColor = theme.onBackground.withValues(alpha: 0.35);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(module.title),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(theme.cardPadding * 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(_iconFromName(module.iconName), size: 80, color: hintColor),
              SizedBox(height: theme.sectionGap),
              Text(
                module.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: theme.titleSize,
                  fontWeight: _fontWeightOf(theme.fontWeightTitle),
                  color: theme.onBackground,
                ),
              ),
              SizedBox(height: theme.gridGap * 2),
              Text(
                '页面待实现（Phase 1.5）',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: theme.captionSize,
                  color: hintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 没有任何可见模块时的兜底页面（正常流程不会出现）。
class _NoModuleScaffold extends StatelessWidget {
  const _NoModuleScaffold();

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return Scaffold(
      backgroundColor: theme.background,
      body: Center(
        child: Text(
          '没有可显示的模块\n请到设置中开启',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
        ),
      ),
    );
  }
}