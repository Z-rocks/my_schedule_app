// 作业提醒设置页（Phase 9）。
//
// 三块内容：
// 1. 开关 + 档位编辑（"提醒几次、每次提前多少分钟"就靠这个列表表达）；
// 2. 权限状态（Android 13+ 通知权限 / Android 12+ 精确闹钟）——缺权限时
//    提醒会静默失效，所以必须在这里可见、可一键去授权；
// 3. 测试通知 + 当前排期条数，让用户能当场验证"到底会不会响"。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/homework_reminder_plan.dart';
import '../../models/homework_reminder_settings.dart';
import '../../providers/homework_provider.dart';
import '../../providers/plugin_provider.dart';
import '../../services/homework_reminder_service.dart';
import '../../services/reminder_bridge.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';

/// 作业提醒设置页。
class HomeworkReminderPage extends StatefulWidget {
  const HomeworkReminderPage({super.key});

  @override
  State<HomeworkReminderPage> createState() => _HomeworkReminderPageState();
}

class _HomeworkReminderPageState extends State<HomeworkReminderPage>
    with WidgetsBindingObserver {
  HomeworkReminderSettings _settings = const HomeworkReminderSettings();
  bool _loading = true;
  bool _saving = false;
  bool _testingChain = false;
  bool _notificationAllowed = false;
  bool _exactAlarmAllowed = true;
  int _planCount = 0;

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

  /// 从系统设置页回来时重查权限（用户可能刚去授权/撤销）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      _refreshPermissions();
    }
  }

  Future<void> _load() async {
    final HomeworkReminderSettings loaded = HomeworkReminderService.loadSettings();
    setState(() {
      _settings = loaded;
      _loading = false;
    });
    await _refreshPermissions();
    // 进页面时按当前设置重排一次：保证"排期条数"显示的是真实值，
    // 也顺手修掉"改了作业但还没触发刷新"的情况。
    await _applySettings(showSnack: false);
  }

  Future<void> _refreshPermissions() async {
    if (!ReminderBridge.isSupported) return;
    final bool notif = await ReminderBridge.hasNotificationPermission();
    final bool exact = await ReminderBridge.canScheduleExactAlarms();
    if (!mounted) return;
    setState(() {
      _notificationAllowed = notif;
      _exactAlarmAllowed = exact;
    });
  }

  /// 保存设置并按新设置重排提醒。
  Future<void> _applySettings({bool showSnack = true}) async {
    final HomeworkProvider homeworkProvider = context.read<HomeworkProvider>();
    final PluginProvider pluginProvider = context.read<PluginProvider>();
    setState(() => _saving = true);
    final int count = await HomeworkReminderService.saveSettings(
      _settings,
      homeworks: homeworkProvider.homeworks,
      pluginIds: pluginProvider.plugins.map((dynamic p) => '${p.id}'),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _planCount = count;
    });
    if (showSnack) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !_settings.isEffective
                ? '已关闭作业提醒'
                : count == 0
                    ? '已保存，但当前没有即将截止的作业'
                    : '已保存，排好了 $count 次提醒',
          ),
        ),
      );
    }
  }

  void _setEnabled(bool value) {
    setState(() => _settings = _settings.copyWith(enabled: value));
    if (value && !_notificationAllowed) {
      // 打开开关的同一动作里申请通知权限，用户不用再去找一遍。
      unawaited(_requestNotificationPermission());
    }
    unawaited(_applySettings());
  }

  Future<void> _requestNotificationPermission() async {
    await ReminderBridge.requestNotificationPermission();
    // 系统弹窗异步，稍等再查真实状态。
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshPermissions();
  }

  Future<void> _addOffset() async {
    if (_settings.offsetsMinutes.length >= kMaxReminderOffsets) {
      _snack('最多 $kMaxReminderOffsets 档');
      return;
    }
    final int? minutes = await _askOffsetMinutes();
    if (minutes == null) return;
    setState(() {
      _settings = _settings.copyWith(
        offsetsMinutes: <int>[..._settings.offsetsMinutes, minutes],
      );
    });
    unawaited(_applySettings());
  }

  /// 弹输入框问"提前多少分钟"。返回 null 表示取消。
  Future<int?> _askOffsetMinutes() async {
    final TextEditingController controller = TextEditingController(text: '15');
    final int? result = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('添加一档提醒'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: const InputDecoration(
            labelText: '截止前多少分钟',
            helperText: '60 = 提前 1 小时，1440 = 提前 1 天',
          ),
          onSubmitted: (String value) {
            final int? parsed = int.tryParse(value);
            if (parsed != null) Navigator.of(dialogContext).pop(parsed);
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(int.tryParse(controller.text)),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return null;
    if (result < kMinReminderOffset || result > kMaxReminderOffset) {
      _snack('请输入 $kMinReminderOffset ~ $kMaxReminderOffset 之间的分钟数');
      return null;
    }
    return result;
  }

  void _removeOffset(int minutes) {
    setState(() {
      _settings = _settings.copyWith(
        offsetsMinutes: _settings.offsetsMinutes
            .where((int m) => m != minutes)
            .toList(),
      );
    });
    unawaited(_applySettings());
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 「立即走一遍完整校验」：拿最近截止的未完成作业，走真实的服务链路。
  ///
  /// 原生侧会起临时引擎、加载插件、调一次 API 查状态，然后按结果决定
  /// 发不发通知——与闹钟到点时的行为完全一致，只是不等时间。
  Future<void> _runFullCheck() async {
    final HomeworkReminderItem? item = HomeworkReminderService.buildProbeItem(
      homeworks: context.read<HomeworkProvider>().homeworks,
    );
    if (item == null) {
      _snack('没有待完成的作业，无法测试完整链路');
      return;
    }
    setState(() => _testingChain = true);
    final bool ok = await ReminderBridge.runCheckNow(
      jsonEncode(item.toJson()),
    );
    if (!mounted) return;
    setState(() => _testingChain = false);
    _snack(
      ok
          ? '已触发校验（用「${item.title}」测试），稍后看通知栏结果'
          : '触发失败，请检查通知权限',
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    if (_loading) {
      return Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(title: const Text('作业提醒'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(title: const Text('作业提醒'), centerTitle: true),
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
                title: Text('开启作业提醒', style: _titleStyle(theme)),
                subtitle: Text(
                  ReminderBridge.isBackgroundCheckSupported
                      ? '作业快到截止时间时发系统通知；每次提醒前会先查一次'
                          '作业状态，已经提交的不打扰。'
                      : '作业快到截止时间时发系统通知。'
                          '（iOS 版提醒时不查状态，已提交也可能提醒）',
                  style: _captionStyle(theme),
                ),
              ),
            ],
          ),
          SizedBox(height: theme.sectionGap),
          _card(
            theme,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('提醒档位', style: _titleStyle(theme)),
                  ),
                  Text(
                    '共 ${_settings.offsetsMinutes.length} 次',
                    style: _captionStyle(theme),
                  ),
                ],
              ),
              SizedBox(height: theme.cardPadding / 2),
              if (_settings.offsetsMinutes.isEmpty)
                Text(
                  '还没有档位。加一档，比如"截止前 30 分钟"。',
                  style: _captionStyle(theme),
                )
              else
                Wrap(
                  spacing: theme.gridGap / 2,
                  runSpacing: theme.gridGap / 2,
                  children: <Widget>[
                    for (final int minutes in _settings.offsetsMinutes)
                      InputChip(
                        label: Text(HomeworkReminderSettings.describeOffset(minutes)),
                        onDeleted: () => _removeOffset(minutes),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        backgroundColor: theme.primary.withValues(alpha: 0.10),
                        side: BorderSide(
                          color: theme.primary.withValues(alpha: 0.35),
                        ),
                        labelStyle: TextStyle(
                          fontSize: theme.captionSize,
                          color: theme.onBackground,
                        ),
                      ),
                  ],
                ),
              SizedBox(height: theme.cardPadding / 2),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed:
                      _settings.offsetsMinutes.length >= kMaxReminderOffsets
                          ? null
                          : _addOffset,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加一档'),
                ),
              ),
              Text(
                '按"离截止从远到近"排列，例如 60 / 30 / 10 = 提前 1 小时、'
                '半小时、10 分钟各提醒一次。',
                style: _captionStyle(theme),
              ),
            ],
          ),
          SizedBox(height: theme.sectionGap),
          // 「查不到状态仍然提醒」只作用于 Android 的到点后台校验；
          // iOS 到点直接提醒、不查状态，该开关无效，不显示。
          if (ReminderBridge.isBackgroundCheckSupported)
            _card(
              theme,
              children: <Widget>[
                SwitchListTile(
                  value: _settings.notifyWhenCheckFails,
                  onChanged: (bool value) {
                    setState(() {
                      _settings =
                          _settings.copyWith(notifyWhenCheckFails: value);
                    });
                    unawaited(_applySettings());
                  },
                  contentPadding: EdgeInsets.zero,
                  title: Text('查不到状态时仍然提醒', style: _titleStyle(theme)),
                  subtitle: Text(
                    '断网、未登录、插件不可用时会查不出作业状态。'
                    '开着更稳妥（宁可多提醒一次，也不漏截止）；'
                    '关掉则只在确认未提交时才提醒。',
                    style: _captionStyle(theme),
                  ),
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
              // "精确闹钟"是 Android 12+ 的独立授权，iOS 不存在该概念。
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
                _settings.isEffective
                    ? '当前已排 $_planCount 次提醒（只统计还没到点的）。'
                    : '提醒已关闭，不会发通知。',
                style: _captionStyle(theme),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: _saving
                        ? null
                        : () async {
                            final bool ok =
                                await ReminderBridge.showTestNotification(
                              title: '作业提醒 · 测试',
                              body: '通知能用，作业快截止时就会这样提醒你。',
                            );
                            if (!mounted) return;
                            _snack(ok ? '已发送测试通知' : '发送失败，请检查通知权限');
                            await _refreshPermissions();
                          },
                    icon: const Icon(Icons.notifications_active_outlined,
                        size: 18),
                    label: const Text('发一条测试通知'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 「完整校验」走的是 Android 原生的"起临时引擎 → 查状态"链路，
              // iOS 没有这条链路（到点直接提醒），不显示该入口。
              if (ReminderBridge.isBackgroundCheckSupported) ...<Widget>[
                Row(
                  children: <Widget>[
                    TextButton.icon(
                      onPressed:
                          _saving || _testingChain ? null : _runFullCheck,
                      icon: _testingChain
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_circle_outline, size: 18),
                      label: Text(_testingChain ? '正在校验…' : '立即走一遍完整校验'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '完整校验会像闹钟到点那样：起一次后台引擎 → 查一次作业状态 → '
                  '已提交则不打扰。用它可以在不等到截止的情况下确认整条链路通不通。',
                  style: _captionStyle(theme),
                ),
              ],
            ],
          ),
          SizedBox(height: theme.sectionGap),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: theme.cardPadding / 2),
            child: Text(
              ReminderBridge.isBackgroundCheckSupported
                  ? '说明：提醒由系统闹钟触发，App 没打开也会响。触发时会临时检查'
                      '一次作业状态（需要网络）；检查结果只用于决定"这次要不要打扰你"，'
                      '不会修改你的作业数据。\n'
                      '部分厂商的省电策略可能清掉闹钟，建议在系统设置里允许本应用'
                      '"自启动 / 后台运行"。'
                  : '说明：提醒由系统本地通知触发，App 没打开也会响。\n'
                      'iOS 版暂不支持到点前检查作业状态：提醒内容以排期时的快照为准，'
                      '已提前交了的作业也可能收到提醒，请以作业列表为准。',
              style: _captionStyle(theme),
            ),
          ),
        ],
      ),
    );
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
