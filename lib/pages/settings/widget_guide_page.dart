// 桌面小组件引导页（Phase W5）：
// 1) 使用说明 —— 怎么加卡片、四张卡各看什么、刷新逻辑；
// 2) 省电引导 —— 为什么小组件可能不更新，按厂商给操作步骤 + 一键跳系统设置。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/system_bridge.dart';
import '../../services/widget_bridge.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';

/// 默认展示哪一节。
enum WidgetGuideSection { usage, battery }

/// 小组件引导页。
class WidgetGuidePage extends StatefulWidget {
  const WidgetGuidePage({super.key, this.initialSection = WidgetGuideSection.usage});

  final WidgetGuideSection initialSection;

  @override
  State<WidgetGuidePage> createState() => _WidgetGuidePageState();
}

class _WidgetGuidePageState extends State<WidgetGuidePage>
    with WidgetsBindingObserver {
  String _manufacturer = '';
  bool _loadingVendor = true;

  /// 桌面上已经有实例的卡片（用 `getAppWidgetIds` 查到的真实状态）。
  final Set<WidgetKind> _added = <WidgetKind>{};

  /// pin 结果订阅。
  StreamSubscription<WidgetPinEvent>? _pinSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetPinEvents.hook();
    _pinSub = WidgetPinEvents.stream.listen(_onPinResult);
    _loadManufacturer();
    _refreshAddedState();
  }

  @override
  void dispose() {
    _pinSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 回到前台时重查一次：用户去桌面确认添加、或手动加了卡片后回到 App，
  /// 状态要立刻反映出来（pin 回调在进程被杀时会丢，这里是兜底）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAddedState();
  }

  Future<void> _refreshAddedState() async {
    final Set<WidgetKind> next = <WidgetKind>{};
    for (final WidgetKind kind in WidgetKind.values) {
      if (await isWidgetAdded(kind)) next.add(kind);
    }
    if (!mounted) return;
    if (next.length == _added.length && next.containsAll(_added)) return;
    setState(() {
      _added
        ..clear()
        ..addAll(next);
    });
  }

  /// pin 结果回调：只用来**立刻刷新**状态。
  ///
  /// 成功/失败的具体提示由 [_requestAdd] 在等桌面绑定完成后统一给（它查询的是
  /// 真实状态 [isWidgetAdded]）——这里再弹一次会重复打扰用户。
  void _onPinResult(WidgetPinEvent event) {
    if (!mounted) return;
    debugPrint(
      '[Widget] pin 回调：${event.kind.name} accepted=${event.accepted} '
      'id=${event.appWidgetId}',
    );
    _refreshAddedState();
  }

  /// 卡片中文名（提示文案用）。
  static String _cardName(WidgetKind kind) {
    switch (kind) {
      case WidgetKind.today:
        return '今天课表';
      case WidgetKind.week:
        return '本周课表';
      case WidgetKind.homework:
        return '待交作业';
      case WidgetKind.exam:
        return '近期考试';
    }
  }

  Future<void> _loadManufacturer() async {
    final String value = await SystemBridge.manufacturer();
    if (!mounted) return;
    setState(() {
      _manufacturer = value;
      _loadingVendor = false;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSettings(Future<bool> Function() action, String hint) async {
    final bool ok = await action();
    if (!mounted) return;
    if (!ok) _snack(hint);
  }

  /// 添加某张卡片到桌面。
  ///
  /// 只走系统原生"固定小部件"请求（见 [requestPinWidget]）：桌面自己弹确认框，
  /// 确认后卡片直接落桌面。**不依赖厂商小部件中心目录**——HyperOS 的小部件中心
  /// 是云端审核目录，未上架的应用在那里永远是空页面（这是 2026-10-17 反编译
  /// 桌面代码确认的，见 docs/widget_task_breakdown.md 6.3）。
  Future<void> _requestAdd(WidgetKind kind, String cardName) async {
    final bool ok = await requestPinWidget(kind);
    if (!mounted) return;
    if (!ok) {
      _snack('当前桌面不支持直接添加，请长按桌面空白处 → 添加小部件 → '
          '在全部应用里找到「校园助手」→ 选择「$cardName」');
      return;
    }
    // "系统接单"不等于"加进桌面"：等桌面走完绑定（或拦下）再查真实结果。
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final bool added = await isWidgetAdded(kind);
    await _refreshAddedState();
    if (!mounted) return;
    if (added) {
      _snack('「$cardName」已添加到桌面');
      return;
    }
    await _showAddBlockedDialog(cardName);
  }

  /// 请求被桌面接单、但卡片没出现时的解释与补救。
  ///
  /// 小米 / HyperOS：桌面在落桌面之前检查 MIUIOP(10017)「桌面快捷方式」，
  /// 默认"拒绝"，会**静默**拦掉（没有报错、没有 toast）——这就是用户
  /// 之前"点了没反应、桌面找不到小组件"的直接原因。允许一次即可。
  Future<void> _showAddBlockedDialog(String cardName) async {
    final String m = _manufacturer.toLowerCase();
    final bool miuiLike =
        m.contains('xiaomi') || m.contains('redmi') || m.contains('poco');
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('没能添加成功'),
        content: Text(
          miuiLike
              ? 'HyperOS 需要先允许「桌面快捷方式」权限，才会把「$cardName」'
                  '放到桌面上：\n\n'
                  '权限管理 → 其他权限 → 桌面快捷方式 → 始终允许\n\n'
                  '允许后回到这里，再点一次「添加到桌面 · $cardName」。'
              : '可以改用手动方式：\n\n'
                  '长按桌面空白处 → 添加小部件 → 在全部应用里找到'
                  '「校园助手」→ 选择「$cardName」。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('知道了'),
          ),
          if (miuiLike)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('去开启权限'),
            ),
        ],
      ),
    );
    if (go == true) await SystemBridge.openPermissionEditor();
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('桌面小组件'),
        centerTitle: true,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: theme.sectionGap),
        children: <Widget>[
          if (widget.initialSection == WidgetGuideSection.battery) ...<Widget>[
            _buildBatterySection(theme),
          ] else ...<Widget>[
            _buildUsageSection(theme),
            _buildCardsSection(theme),
            _buildBatterySection(theme),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 使用说明

  Widget _buildUsageSection(AppTheme theme) {
    return _GuideCard(
      theme: theme,
      title: '如何添加',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _bullet(theme, '最省事：点下方「四张卡片」里的「添加到桌面」按钮，'
              '桌面会弹出确认框，点「添加」后卡片直接出现在桌面上。'),
          _bullet(theme, '也可以长按桌面空白处 → 添加小部件，在「全部应用」里'
              '找到「校园助手」再选卡片（部分系统的这个列表是厂商自己维护的，'
              '里面没有本应用时，用上面的按钮添加）。'),
          _bullet(theme, '拖到桌面后，点击卡片可直达课表 / 作业 / 考试页。'),
          _bullet(theme, '小米 / 红米（HyperOS）第一次添加前，需要允许「桌面快捷方式」'
              '权限（应用信息 → 权限管理 → 其他权限 → 桌面快捷方式 → 始终允许），'
              '否则桌面会静默拦掉添加。没加成功时会弹出入口，直接点「去开启权限」。'),
          _bullet(theme, '卡片数据随 App 内的操作自动更新；没显示时打开 App 刷新一次即可。'),
        ],
      ),
    );
  }

  Widget _buildCardsSection(AppTheme theme) {
    final List<String> addedNames = <String>[
      for (final WidgetKind kind in WidgetKind.values)
        if (_added.contains(kind)) _cardName(kind),
    ];
    return _GuideCard(
      theme: theme,
      title: '四张卡片',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _bullet(theme, '今天课表：当天从第几节到第几节、课程、教室，今天没课会提示。'),
          _bullet(theme, '本周课表：周几 × 节次的色块网格，今天的列高亮。'),
          _bullet(theme, '待交作业：待交数量、逾期数量，以及最近的几条作业。'),
          _bullet(theme, '近期考试：最近一场考试倒计时和其余考试安排。'),
          SizedBox(height: theme.gridGap),
          Text(
            addedNames.isEmpty
                ? '桌面上还没有卡片'
                : '桌面上已有：${addedNames.join('、')}',
            style: TextStyle(
              fontSize: theme.captionSize,
              color: theme.onBackground.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: theme.gridGap * 2),
          Wrap(
            spacing: theme.gridGap,
            runSpacing: theme.gridGap,
            children: <Widget>[
              _addButton(theme, WidgetKind.today, '今天课表'),
              _addButton(theme, WidgetKind.week, '本周课表'),
              _addButton(theme, WidgetKind.homework, '待交作业'),
              _addButton(theme, WidgetKind.exam, '近期考试'),
            ],
          ),
          SizedBox(height: theme.gridGap * 2),
          Text(
            '卡片可按住边缘拉伸改变大小，系统每 30 分钟也会兜底刷新一次。',
            style: TextStyle(
              fontSize: theme.captionSize,
              color: theme.onBackground.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// 「添加到桌面」按钮：应用内直接请求固定小部件（见 [requestPinWidget]）。
  ///
  /// 已经加过的卡片在按钮上带「已添加」；仍可继续点（同一张卡允许加多份）。
  Widget _addButton(AppTheme theme, WidgetKind kind, String cardName) {
    final bool added = _added.contains(kind);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.primary,
        side: BorderSide(color: theme.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.buttonRadius),
        ),
      ),
      onPressed: () => _requestAdd(kind, cardName),
      child: Text(added ? '已添加 · $cardName' : '添加到桌面 · $cardName'),
    );
  }

  // ---------------------------------------------------------------- 省电引导

  Widget _buildBatterySection(AppTheme theme) {
    final _VendorGuide guide = _guideFor(_manufacturer);
    return _GuideCard(
      theme: theme,
      title: '让卡片保持更新',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '课表 / 作业有变化时，App 会主动把新数据推给小组件。'
            '如果系统的省电策略限制了校园助手的后台活动，'
            '卡片就可能要等系统兜底刷新（最多 30 分钟）。'
            '按下面的步骤放开限制即可。',
            style: TextStyle(
              fontSize: theme.captionSize,
              height: 1.6,
              color: theme.onBackground.withValues(alpha: 0.8),
            ),
          ),
          SizedBox(height: theme.gridGap * 2),
          if (_loadingVendor)
            Text(
              '正在识别机型…',
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.6),
              ),
            )
          else ...<Widget>[
            Text(
              '识别到：${guide.label}',
              style: TextStyle(
                fontSize: theme.bodySize,
                fontWeight: theme.titleFontWeight,
                color: theme.primary,
              ),
            ),
            SizedBox(height: theme.gridGap),
            for (final String step in guide.steps)
              _numberedStep(theme, guide.steps.indexOf(step) + 1, step),
          ],
          SizedBox(height: theme.gridGap * 2),
          Wrap(
            spacing: theme.gridGap,
            runSpacing: theme.gridGap,
            children: <Widget>[
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.primary,
                  side: BorderSide(color: theme.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.buttonRadius),
                  ),
                ),
                onPressed: () => _openSettings(
                  SystemBridge.openAppDetails,
                  '未能打开应用信息页，请手动前往：设置 → 应用 → 校园助手',
                ),
                child: const Text('打开应用信息'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.primary,
                  side: BorderSide(color: theme.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.buttonRadius),
                  ),
                ),
                onPressed: () => _openSettings(
                  SystemBridge.openBatterySettings,
                  '未能打开电池优化页，请手动前往：设置 → 电池 → 校园助手 → 不受限制',
                ),
                child: const Text('打开电池优化'),
              ),
            ],
          ),
          SizedBox(height: theme.gridGap),
          Text(
            '识别不准或列表里没有本机？按下方通用路径操作：'
            '设置 → 应用 → 校园助手 → 电池 → 不受限制。',
            style: TextStyle(
              fontSize: theme.captionSize,
              color: theme.onBackground.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 小组件

  Widget _bullet(AppTheme theme, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: theme.gridGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: theme.bodySize / 2, right: theme.gridGap),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: theme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: theme.captionSize,
                height: 1.6,
                color: theme.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberedStep(AppTheme theme, int index, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: theme.gridGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: theme.bodySize + 8,
            height: theme.bodySize + 8,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: theme.captionSize,
                fontWeight: theme.titleFontWeight,
                color: theme.primary,
              ),
            ),
          ),
          SizedBox(width: theme.gridGap),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: theme.captionSize,
                height: 1.6,
                color: theme.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一块分组卡片（标题 + 内容），样式与设置页分组一致。
class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.theme, required this.title, required this.child});

  final AppTheme theme;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: theme.cardPadding,
        right: theme.cardPadding,
        bottom: theme.sectionGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(
              left: theme.cardPadding / 2,
              bottom: theme.gridGap * 2,
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: theme.captionSize,
                fontWeight: theme.titleFontWeight,
                color: theme.primary,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            color: theme.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.cardRadius),
            ),
            child: Padding(
              padding: EdgeInsets.all(theme.cardPadding),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个厂商的引导文案。
class _VendorGuide {
  const _VendorGuide(this.label, this.steps);

  final String label;
  final List<String> steps;
}

/// 按 `Build.MANUFACTURER` 给引导步骤；识别不了走通用路径。
_VendorGuide _guideFor(String manufacturer) {
  final String m = manufacturer.toLowerCase();
  if (m.contains('xiaomi') || m.contains('redmi')) {
    return const _VendorGuide('小米 / 红米（HyperOS）', <String>[
      '设置 → 应用设置 → 应用管理 → 校园助手 → 省电策略 → 选择「无限制」',
      '打开最近任务，下拉校园助手卡片上锁，防止被一键清理',
      '设置 → 应用设置 → 权限管理 → 自启动管理 → 允许校园助手自启动',
    ]);
  }
  if (m.contains('huawei')) {
    return const _VendorGuide('华为（HarmonyOS）', <String>[
      '设置 → 应用和服务 → 应用启动管理 → 关闭「校园助手」的自动管理',
      '在弹出的手动管理里，允许自启动、关联启动和后台活动',
      '最近任务界面下拉锁定校园助手',
    ]);
  }
  if (m.contains('honor')) {
    return const _VendorGuide('荣耀（MagicOS）', <String>[
      '设置 → 应用 → 应用启动管理 → 关闭「校园助手」的自动管理',
      '手动允许自启动与后台活动',
      '最近任务界面下拉锁定校园助手',
    ]);
  }
  if (m.contains('oppo') || m.contains('oneplus') || m.contains('realme')) {
    return const _VendorGuide('OPPO / 一加 / realme（ColorOS）', <String>[
      '设置 → 电池 → 耗电详情 → 校园助手 → 允许后台运行、允许自启动',
      '最近任务界面下拉锁定校园助手',
      '仍不刷新时：设置 → 应用 → 校园助手 → 省电策略 → 允许后台运行',
    ]);
  }
  if (m.contains('vivo') || m.contains('iqoo')) {
    return const _VendorGuide('vivo / iQOO（OriginOS）', <String>[
      '设置 → 电池 → 后台高耗电 → 允许校园助手后台运行',
      'i管家 → 应用管理 → 自启动 → 允许校园助手',
      '最近任务界面下拉锁定校园助手',
    ]);
  }
  if (m.contains('samsung')) {
    return const _VendorGuide('三星（One UI）', <String>[
      '设置 → 应用程序 → 校园助手 → 电池 → 选择「不受限制」',
      '设置 → 电池 → 后台使用限制 → 不要限制校园助手',
      '或将校园助手加入「从未休眠的应用」',
    ]);
  }
  if (m.contains('meizu')) {
    return const _VendorGuide('魅族（Flyme）', <String>[
      '设置 → 应用管理 → 校园助手 → 省电策略 → 选择「不受限制」',
      '手机管家 → 权限管理 → 自启动 → 允许校园助手',
      '最近任务界面下拉锁定校园助手',
    ]);
  }
  return const _VendorGuide('本机', <String>[
    '设置 → 应用 → 校园助手 → 电池 → 选择「不受限制」',
    '若系统有休眠 / 深度睡眠策略，把校园助手加入例外',
    '最近任务界面下拉锁定校园助手',
  ]);
}
