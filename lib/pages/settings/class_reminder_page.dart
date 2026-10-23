// 上课提醒设置页。
//
// 与作业提醒设置页（`homework_reminder_page.dart`）结构对齐，但**故意更简单**：
// 上课提醒没有"多档叠加"（一节课提醒两次太吵）、没有"到点查状态"（数据全在
// 本地）、没有后台引擎。所以这里只有四块：开关 / 提前量 / 权限 / 验证。
//
// 为什么必须显示"当前排了 N 次"：排期只覆盖未来 7 天，且完全依赖系统闹钟。
// 用户看不到任何反馈时，一旦厂商 ROM 清掉闹钟就会觉得"这功能是坏的"——
// 把条数摆出来，至少能自己判断"是没排上，还是排上了没响"。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/class_reminder_settings.dart';
import '../../models/semester_config.dart';
import '../../providers/course_provider.dart';
import '../../providers/plugin_provider.dart';
import '../../providers/semester_provider.dart';
import '../../services/class_reminder_service.dart';
import '../../services/reminder_bridge.dart';
import '../../services/section_time_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';

/// 上课提醒设置页。
class ClassReminderPage extends StatefulWidget {
  const ClassReminderPage({super.key});

  @override
  State<ClassReminderPage> createState() => _ClassReminderPageState();
}

class _ClassReminderPageState extends State<ClassReminderPage>
    with WidgetsBindingObserver {
  ClassReminderSettings _settings = const ClassReminderSettings();
  bool _loading = true;
  bool _saving = false;
  bool _notificationAllowed = false;
  bool _exactAlarmAllowed = true;
  int _planCount = 0;

  /// 排期时的"没有课 / 没有学期"提示，避免用户以为排期坏了。
  String _emptyReason = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置页回来时重查权限（用户可能刚去授权 / 撤销）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      unawaited(_refreshPermissions());
    }
  }

  Future<void> _load() async {
    final ClassReminderSettings loaded = ClassReminderService.loadSettings();
    setState(() {
      _settings = loaded;
      _loading = false;
    });
    await _refreshPermissions();
    // 进页面就按当前设置重排一次：让"已排 N 次"显示真实值，也顺手修掉
    // "改了课表但 controller 还没防抖到"的情况。
    await _applySettings(showSnack: false);
  }

  Future<void> _refreshPermissions() async {
    if (!ReminderBridge.isSupported) return;
    final bool notif = await ReminderBridge.hasClassNotificationPermission();
    final bool exact = await ReminderBridge.canScheduleExactAlarms();
    if (!mounted) return;
    setState(() {
      _notificationAllowed = notif;
      _exactAlarmAllowed = exact;
    });
  }

  /// 保存设置并按新设置重排。
  Future<void> _applySettings({bool showSnack = true}) async {
    final CourseProvider courses = context.read<CourseProvider>();
    final SemesterProvider semester = context.read<SemesterProvider>();
    final PluginProvider plugins = context.read<PluginProvider>();

    setState(() => _saving = true);
    await ClassReminderService.saveSettings(_settings);
    final int count = await ClassReminderService.refresh(
      courses: courses.visibleCourses,
      config: semester.config,
      sectionTimes: _resolveSectionTimes(plugins),
    );
    if (!mounted) return;

    setState(() {
      _saving = false;
      _planCount = count;
      _emptyReason = _describeEmptyReason(
        courses: courses.visibleCourses.length,
        config: semester.config,
      );
    });

    if (showSnack) {
      _snack(
        !_settings.isEffective
            ? '已关闭上课提醒'
            : count == 0
                ? '已保存，但未来 7 天没有可提醒的课'
                : '已保存，未来 7 天排好了 $count 次提醒',
      );
    }
  }

  /// 为什么排期是 0 条——把"用户能自己修的原因"说清楚。
  ///
  /// 只说"没有课"会让人以为同步失败；实际常见原因是没配学期（算不出周次）。
  static String _describeEmptyReason({
    required int courses,
    required SemesterConfig? config,
  }) {
    if (config == null) return '还没有设置学期开学日期，无法计算周次';
    if (courses == 0) return '课表里还没有课程';
    return '';
  }

  /// 作息优先用插件同步下来的真实值，没有就回落到内置默认表。
  static Map<int, String> _resolveSectionTimes(PluginProvider plugins) {
    final SectionTimes? times =
        SectionTimeService.fromPlugins(plugins.plugins);
    if (times == null || times.isEmpty) return kDefaultSectionTimes;
    return times.times;
  }

  void _setEnabled(bool value) {
    setState(() => _settings = _settings.copyWith(enabled: value));
    if (value && !_notificationAllowed) {
      // 打开开关的同一动作里申请通知权限，用户不用再去找一遍。
      unawaited(_requestNotificationPermission());
    }
    unawaited(_applySettings());
  }

  void _setOffset(int minutes) {
    if (minutes == _settings.offsetMinutes) return;
    setState(() => _settings = _settings.copyWith(offsetMinutes: minutes));
    unawaited(_applySettings());
  }

  Future<void> _requestNotificationPermission() async {
    await ReminderBridge.requestNotificationPermission();
    // 系统弹窗异步，稍等再查真实状态。
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshPermissions();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    if (_loading) {
      return Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(title: const Text('上课提醒'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(title: const Text('上课提醒'), centerTitle: true),
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: theme.cardPadding,
          vertical: theme.sectionGap,
        ),
        children: <Widget>[
          _card(
            theme,
            children: <Widget>[
              SwitchListTile(
                value: _settings.enabled,
                onChanged: _setEnabled,
                contentPadding: EdgeInsets.zero,
                title: Text('开启上课提醒', style: _titleStyle(theme)),
                subtitle: Text(
                  '快到上课时间时发系统通知，App 没打开也会响。'
                  '数据都在本机，提醒时不联网、不查任何接口。',
                  style: _captionStyle(theme),
                ),
              ),
            ],
          ),
          SizedBox(height: theme.sectionGap),
          _card(
            theme,
            children: <Widget>[
              Text('提前多久提醒', style: _titleStyle(theme)),
              SizedBox(height: theme.cardPadding / 2),
              Wrap(
                spacing: theme.gridGap / 2,
                runSpacing: theme.gridGap / 2,
                children: <Widget>[
                  for (final int minutes in kClassReminderOffsetOptions)
                    ChoiceChip(
                      label: Text(_describeOffset(minutes)),
                      selected: _settings.offsetMinutes == minutes,
                      onSelected: (bool _) => _setOffset(minutes),
                      selectedColor: theme.primary.withValues(alpha: 0.18),
                      backgroundColor: theme.background,
                      side: BorderSide(
                        color: theme.primary.withValues(
                          alpha: _settings.offsetMinutes == minutes
                              ? 0.55
                              : 0.18,
                        ),
                      ),
                      labelStyle: TextStyle(
                        fontSize: theme.captionSize,
                        color: theme.onBackground,
                      ),
                    ),
                ],
              ),
              SizedBox(height: theme.cardPadding / 2),
              Text(
                '只提醒一次，不叠加档位——一节课响两遍反而吵。'
                '课间只有几分钟时建议选 5 或 10 分钟。',
                style: _captionStyle(theme),
              ),
            ],
          ),
          SizedBox(height: theme.sectionGap),
          _card(
            theme,
            children: <Widget>[
              Text('权限', style: _titleStyle(theme)),
              const SizedBox(height: 4),
              _permissionRow(
                theme,
                title: '通知权限',
                ok: _notificationAllowed,
                okText: '已允许',
                badText: '未允许（提醒不会显示）',
                onTap: _notificationAllowed
                    ? () => ReminderBridge.openNotificationSettings()
                    : _requestNotificationPermission,
              ),
              // "精确闹钟"是 Android 12+ 的独立授权；iOS 的本地通知本来就准时。
              if (ReminderBridge.isExactAlarmSupported)
                _permissionRow(
                  theme,
                  title: '精确闹钟',
                  ok: _exactAlarmAllowed,
                  okText: '已允许',
                  badText: '未允许（提醒可能晚几分钟）',
                  onTap: () => ReminderBridge.openExactAlarmSettings(),
                ),
            ],
          ),
          SizedBox(height: theme.sectionGap),
          _card(
            theme,
            children: <Widget>[
              Text('验证', style: _titleStyle(theme)),
              const SizedBox(height: 4),
              Text(
                !_settings.isEffective
                    ? '提醒已关闭，不会发通知。'
                    : _planCount > 0
                        ? '未来 7 天已排 $_planCount 次提醒（只统计还没到点的）。'
                        : '当前排期为 0 条。${_emptyReason.isEmpty ? '' : '$_emptyReason。'}',
                style: _captionStyle(theme),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _saving
                    ? null
                    : () async {
                        final bool ok =
                            await ReminderBridge.showClassTestNotification();
                        if (!mounted) return;
                        _snack(ok ? '已发送测试通知' : '发送失败，请检查通知权限');
                        await _refreshPermissions();
                      },
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('发一条测试通知'),
              ),
            ],
          ),
          SizedBox(height: theme.sectionGap),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: theme.cardPadding / 2),
            child: Text(
              '说明：只排未来 7 天的课，每次打开 App 会自动往后补。'
              '超过一周没打开过 App 就不会收到提醒。\n'
              '部分厂商的省电策略会清掉闹钟，建议在系统设置里允许本应用'
              '"自启动 / 后台运行"。',
              style: _captionStyle(theme),
            ),
          ),
        ],
      ),
    );
  }

  /// `5` → `5 分钟`；`60` → `1 小时`。
  static String _describeOffset(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
  }

  Widget _card(AppTheme theme, {required List<Widget> children}) {
    return Container(
      padding: EdgeInsets.all(theme.cardPadding),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _permissionRow(
    AppTheme theme, {
    required String title,
    required bool ok,
    required String okText,
    required String badText,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      onTap: () => unawaited(onTap()),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 18,
              color: ok ? theme.success : theme.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: theme.bodySize,
                  color: theme.onBackground,
                ),
              ),
            ),
            Text(
              ok ? okText : badText,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: ok
                    ? theme.onBackground.withValues(alpha: 0.6)
                    : theme.warning,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.onBackground.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _titleStyle(AppTheme theme) => TextStyle(
        fontSize: theme.bodySize,
        fontWeight: FontWeight.w600,
        color: theme.onBackground,
      );

  TextStyle _captionStyle(AppTheme theme) => TextStyle(
        fontSize: theme.captionSize,
        height: 1.45,
        color: theme.onBackground.withValues(alpha: 0.65),
      );
}
