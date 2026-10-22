// 课表页：顶部日期栏 + 课程网格 + 三种状态（未配学期 / 无课程 / 有数据）
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../models/message.dart';
import '../../models/plugin_meta.dart';
import '../../models/semester_config.dart';
import '../../models/sync_report.dart';
import '../../providers/course_provider.dart';
import '../../providers/message_provider.dart';
import '../../providers/plugin_provider.dart';
import '../../providers/semester_provider.dart';
import '../../providers/settings_provider.dart';
import '../../runtime/plugin_handle.dart';
import '../../services/cookie_service.dart';
import '../../services/course_sync_service.dart';
import '../../services/section_time_service.dart';
import '../../services/timetable_logic.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/timetable_grid.dart';
import '../edit/course_edit_page.dart';
import '../settings/semester_config_page.dart';
import 'course_detail_sheet.dart';

/// 顶部日期栏的高度。
const double kTopBarHeight = 48;

/// **兜底**节次时间表（节次 → 上课时间段）。
///
/// **Phase 4.4 起这只是一份兜底值**：正常路径是用插件同步下来的真实作息
/// （`SectionTimeService` 从 Hive `plugin_data.section_times` 读，
/// 见 `_TimetableViewState._sectionTimes`）。只有当"没有任何插件提供作息"时
/// 才用这份硬编码——它不可能对每一所学校都正确。
///
/// 保留它的另一个原因：新用户还没装插件时，课表时间列得显示点东西，
/// 而不是一片空白。
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

  /// 插件同步下来的真实作息（Phase 4.4）；`null` 表示没有插件提供 →
  /// 课表回退到内置默认 [kDefaultSectionTimes]。
  SectionTimes? _sectionTimes;

  /// 上次解析作息时用的"插件状态签名"。
  ///
  /// 用途：作息存在 Hive `plugin_data` 里，**不是** Flutter 的可监听状态。
  /// 用签名避免每帧都去查一次 Box：只有"插件列表 / 启用态 / 能力声明"变了
  /// 才重新解析。
  ///
  /// **同步完成后会自动刷新**，不需要用户手动操作：同步会写课程，
  /// 而写课程走 `CourseProvider.saveCourse` → `notifyListeners`，
  /// 本页 `watch` 了 `CourseProvider`，于是重建 → [didChangeDependencies]
  /// → 本方法。课表页的同步按钮另外会显式把签名置空再刷新一次（更直接）。
  String? _sectionTimesSignature;

  /// 是否正在同步（Phase 4.4 顶部栏按钮的防重入闩锁）。
  bool _syncing = false;

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

    // 插件状态可能变了（启用/禁用/新装）→ 重新解析作息。
    _refreshSectionTimesIfChanged();
  }

  /// 重新解析插件作息（仅在插件状态签名变化时真正读盘）。
  ///
  /// 数据流：插件同步时 `ctx.storage.set('section_times', ...)` →
  /// 宿主落 Hive `plugin_data` 的 `<pluginId>:section_times` →
  /// [SectionTimeService] 读出 → 传给 `TimetableGrid.sectionTimes`。
  ///
  /// **不需要手动刷新**：同步会走 `CourseProvider.saveCourse` → `notifyListeners`，
  /// 而课表页 `watch` 了 `CourseProvider`，于是本页重建 → 本方法被再次调用。
  void _refreshSectionTimesIfChanged() {
    final List<PluginMeta> plugins = context.read<PluginProvider>().plugins;
    final String signature = plugins
        .map((PluginMeta p) => '${p.id}:${p.enabled}:'
            '${(p.effectiveCapabilities.toList()..sort()).join(",")}')
        .join('|');
    if (signature == _sectionTimesSignature) return;
    _sectionTimesSignature = signature;
    _sectionTimes = SectionTimeService.fromPlugins(plugins);
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

  /// 打开课程编辑页；**必须先配置学期**（周次范围依赖总周数）。
  ///
  /// 没有学期时提示并提供"去配置"入口，而不是直接跳转。
  ///
  /// [course] 为 `null` 表示新增，非空表示编辑该课程（Phase 5）。
  Future<void> _openCourseEdit([Course? course]) async {
    if (!context.read<SemesterProvider>().hasConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先配置学期'),
          action: SnackBarAction(
            label: '去配置',
            onPressed: _openSemesterConfig,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) => CourseEditPage(course: course),
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
            // Phase 4.4：有可同步的插件时，课表页也能直接同步
            // （原来只能进「设置 → 插件管理 → 详情」才能点同步）。
            if (_syncablePlugins.isNotEmpty)
              IconButton(
                icon: _syncing
                    ? SizedBox(
                        width: theme.bodySize,
                        height: theme.bodySize,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.primary,
                          ),
                        ),
                      )
                    : const Icon(Icons.sync),
                tooltip: _syncing ? '正在同步…' : '从教务系统同步课程',
                color: theme.primary,
                // 同步中置灰，避免连点
                onPressed: _syncing ? null : _syncNow,
              ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '添加课程',
              color: theme.primary,
              onPressed: _openCourseEdit,
            ),
          ],
        ),
      ),
    );
  }

  /// 课表页可用的同步插件（空列表 = 不显示同步按钮）。
  ///
  /// **Phase 9 起允许多个**：大物实验插件与教务插件都声明 `timetable`，
  /// 原来"只在恰好一个候选时给按钮"的做法会让两个插件同时启用时
  /// 同步按钮直接消失（用户会以为功能坏了）。现在多个候选时点按钮弹一个
  /// 选择器，让用户决定同步哪一个数据源。
  List<PluginMeta> get _syncablePlugins {
    final PluginProvider provider = context.read<PluginProvider>();
    return provider.enabledPlugins.where((PluginMeta p) {
      if (!p.effectiveCapabilities.contains('timetable')) return false;
      final PluginHandle? handle = provider.getHandle(p.id);
      if (handle == null || !handle.isUsable) return false;
      return handle.entries.contains('fetchCourses');
    }).toList(growable: false);
  }

  /// 课表页的「同步」入口：复用 [CourseSyncService]（与插件详情页同一套逻辑）。
  ///
  /// 与详情页的差别只有两点：没有 Cookie 时引导去插件详情页登录
  /// （课表页没有登录入口），以及结果只用 SnackBar 呈现
  /// （课表页顶部放不下结果卡片，详细信息去详情页看）。
  Future<void> _syncNow() async {
    if (_syncing) return;
    final List<PluginMeta> candidates = _syncablePlugins;
    if (candidates.isEmpty) return;

    final PluginMeta? meta = candidates.length == 1
        ? candidates.first
        : await _pickSyncPlugin(candidates);
    // 选择器是异步的：用户可能在这期间离开课表页，之后碰 context 会报错。
    if (meta == null || !mounted) return;

    final PluginProvider pluginProvider = context.read<PluginProvider>();
    final CourseProvider courseProvider = context.read<CourseProvider>();
    // 学期配置在下面 `await CookieService.loadCookie` 之前取好，
    // 否则会被判定为"跨 async gap 使用 BuildContext"。
    final SemesterConfig? semester = context.read<SemesterProvider>().config;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final String cookie = await CookieService.loadCookie(meta.id);
    if (cookie.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('「${meta.name}」还没有登录，请到插件详情页登录'),
        ),
      );
      return;
    }

    setState(() => _syncing = true);
    SyncReport report;
    try {
      report = await CourseSyncService.sync(
        pluginId: meta.id,
        handle: pluginProvider.getHandle(meta.id),
        courses: courseProvider,
        // 与插件详情页一致：把学期配置给插件，供"日期 → 周次"换算用。
        semester: semester,
        // Phase 7：与插件详情页一致，把结果沉淀成站内消息。
        onReport: (SyncReport r) => unawaited(
          context.read<MessageProvider>().addMessagePersisted(
                Message.fromSyncReport(report: r, pluginName: meta.name),
              ),
        ),
      );
    } catch (e) {
      debugPrint('[TimetableView] 同步抛出未预期异常：$e');
      report = SyncReport.failure(
        pluginId: meta.id,
        outcome: SyncOutcome.failed,
        reason: '同步异常：$e',
      );
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      } else {
        _syncing = false;
      }
    }

    if (!mounted) return;

    // 作息可能在本次同步里更新了（插件会写 `section_times`），重新读一次。
    _sectionTimesSignature = null;
    _refreshSectionTimesIfChanged();
    setState(() {});

    messenger.showSnackBar(SnackBar(content: Text(_reportText(report))));
  }

  /// 多个插件都能同步课表时，让用户选同步哪一个数据源。
  ///
  /// 返回 `null` 表示用户取消了（点遮罩 / 返回键），调用方直接收手。
  Future<PluginMeta?> _pickSyncPlugin(List<PluginMeta> candidates) async {
    final AppTheme theme = AppThemeExtension.of(context);
    return showModalBottomSheet<PluginMeta>(
      context: context,
      backgroundColor: theme.surface,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(theme.cardPadding),
                child: Text(
                  '从哪个系统同步课程？',
                  style: TextStyle(
                    fontSize: theme.titleSize,
                    fontWeight: theme.titleFontWeight,
                    color: theme.onBackground,
                  ),
                ),
              ),
              for (final PluginMeta meta in candidates)
                ListTile(
                  leading: Icon(Icons.sync, color: theme.primary),
                  title: Text(
                    meta.name,
                    style: TextStyle(color: theme.onBackground),
                  ),
                  subtitle: meta.description.isEmpty
                      ? null
                      : Text(
                          meta.description,
                          style: TextStyle(fontSize: theme.captionSize),
                        ),
                  onTap: () => Navigator.of(sheetContext).pop(meta),
                ),
              SizedBox(height: theme.gridGap),
            ],
          ),
        );
      },
    );
  }

  /// 把同步报告压成一句课表页能说清的文案。
  static String _reportText(SyncReport report) {
    if (!report.isSuccess) return '同步失败：${report.reason}';
    if (!report.hasChanges) {
      return report.totalCourses == 0
          ? '同步完成：这学期没有课程'
          : '同步完成：${report.totalCourses} 门课程已是最新';
    }
    return '已同步 ${report.totalCourses} 门课程'
        '（新增 ${report.added}、更新 ${report.updated}）';
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
        onAction: _openCourseEdit,
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
  ///
  /// **本周没课时不是给一片空白**：课程可能是 `4,6-14周` 这类"跳过某几周"的安排，
  /// 那时网格本来就该是空的。但空白网格与"一门课都没有"长得一模一样，
  /// 用户会以为同步失败——所以在网格上方给一条说明 + 跳到最近有课周的入口。
  Widget _buildWeekGrid(
    AppTheme theme,
    SemesterConfig config,
    List<Course> courses,
    int week,
  ) {
    final int totalWeeks = config.totalWeeks < 1 ? 1 : config.totalWeeks;
    final bool weekIsEmpty = !TimetableLogic.hasAnyClassInWeek(courses, week);

    final Widget grid = TimetableGrid(
      // 一块 = 一张卡片：跨节合并、重叠并排（同一时间两门课各占半宽）
      // 全部在 layoutBlocks 里算好，组件只做像素换算。
      blocks: TimetableLogic.layoutBlocks(courses, week),
      // Phase 4.4：优先用插件同步下来的**真实作息**；没有插件提供时
      // 回退到内置默认值（各校作息不同，硬编码只是最后兜底）。
      sectionTimes: _sectionTimes?.times ?? kDefaultSectionTimes,
      currentWeek: week,
      weekStartDate: weekStartDateOf(config, week),
      onTapCourse: (Course course) => showCourseDetailSheet(context, course),
      // Phase 5：长按直接进编辑页（原来只弹一句"待实现"）。
      onLongPressCourse: _openCourseEdit,
    );

    if (!weekIsEmpty) return grid;

    // 本周空：列表只在"当前页"算一次（PageView 的每一页都会调到这里，
    // 但只有空周才需要它，非空周直接早退，不影响滑动性能）。
    final List<int> weeks = TimetableLogic.weeksWithClass(
      courses,
      totalWeeks: totalWeeks,
    );
    final int? nearest = TimetableLogic.nearestWeekWithClass(
      courses,
      week: week,
      totalWeeks: totalWeeks,
    );

    return Column(
      children: <Widget>[
        _EmptyWeekNotice(
          theme: theme,
          week: week,
          weeksWithClass: weeks,
          nearestWeek: nearest,
          onJump: nearest == null
              ? null
              : () => _setWeek(nearest, totalWeeks: totalWeeks),
        ),
        Expanded(child: grid),
      ],
    );
  }
}

/// 本周没有课时显示在网格上方的说明条。
///
/// 三种情况分别说清楚（都不留空白）：
/// - 课程有周次信息但都不含本周 → 列出全部有课周 + 跳最近一周；
/// - 课程**完全没有**周次信息（教务没给 / 解析不出）→ 提示去课程页检查；
/// - 兜底（有课但本周没排）→ 一句话说明。
class _EmptyWeekNotice extends StatelessWidget {
  const _EmptyWeekNotice({
    required this.theme,
    required this.week,
    required this.weeksWithClass,
    required this.nearestWeek,
    required this.onJump,
  });

  final AppTheme theme;
  final int week;
  final List<int> weeksWithClass;
  final int? nearestWeek;
  final VoidCallback? onJump;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String detail;

    if (weeksWithClass.isEmpty) {
      // 有课程，但没有任何一条安排带周次信息 —— 网格永远是空的。
      title = '第 $week 周没有课';
      detail = '课程缺少周次信息，无法判断它们在第几周上课。'
          '请到「课程」页检查这些课程的上课周次。';
    } else {
      title = '第 $week 周没有课';
      detail = '本学期有课的周次：第 ${TimetableLogic.formatWeeks(weeksWithClass)} 周'
          '${nearestWeek == null ? '' : '（最近有课：第 $nearestWeek 周）'}';
    }

    return Container(
      margin: EdgeInsets.only(bottom: theme.gridGap * 2),
      padding: EdgeInsets.all(theme.cardPadding),
      decoration: BoxDecoration(
        // 用 warning 令牌而不是硬编码黄色（CONTEXT 3.2）。
        color: theme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(theme.buttonRadius),
        border: Border.all(color: theme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.event_busy_outlined,
              size: theme.captionSize * 1.4, color: theme.warning),
          SizedBox(width: theme.gridGap * 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: theme.bodySize,
                    fontWeight: theme.titleFontWeight,
                    color: theme.onBackground,
                  ),
                ),
                SizedBox(height: theme.gridGap),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: theme.captionSize,
                    color: theme.onBackground.withValues(alpha: 0.75),
                  ),
                ),
                if (onJump != null && weeksWithClass.isNotEmpty) ...<Widget>[
                  SizedBox(height: theme.gridGap),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: Text('跳到第 $nearestWeek 周'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.primary,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: onJump,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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