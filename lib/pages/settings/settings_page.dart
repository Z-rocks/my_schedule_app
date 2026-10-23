// 设置主页：分组列出扩展 / 外观 / 布局 / 数据 / 关于入口
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/course_provider.dart';
import '../../providers/exam_provider.dart';
import '../../providers/homework_provider.dart';
import '../../providers/message_provider.dart';
import '../../providers/module_provider.dart';
import '../../providers/plugin_provider.dart';
import '../../providers/semester_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/app_version.dart';
import '../../services/data_backup_service.dart';
import '../../services/reminder_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/system_bridge.dart';
import '../../services/update_service.dart';
import '../../services/widget_bridge.dart';
import '../../theme/default_skins.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import 'module_config_page.dart';
import 'log_viewer_page.dart';
import 'plugin_manage_page.dart';
import 'timetable_settings_page.dart';
import 'widget_guide_page.dart';
import 'workshop_page.dart';
import 'class_reminder_page.dart';
import 'homework_reminder_page.dart';

/// 设置主页。
///
/// Phase 1.6 只搭结构：除"导航栏配置"外，其余条目都是占位（点击弹 SnackBar
/// 或跳转到占位页），不读写任何持久化数据。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// 弹一条 SnackBar。
  ///
  /// [replace] 为 `true` 时**先顶掉当前那条**再显示。数据导出/导入会先弹
  /// "正在处理…"、再弹结果，不顶掉的话用户得等前一条自然消失才能看到结果，
  /// 中间那几秒很像"卡住了"。
  void _showSnack(
    BuildContext context,
    String message, {
    bool replace = false,
  }) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (replace) messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// 「当前主题」的展示值（**Phase 6**）。
  ///
  /// 只在内置皮肤里查名字：asset 皮肤的名字要异步读 bundle，
  /// 而这是同步的 `trailingText`。查不到就显示"自定义皮肤"——
  /// 比显示一串 id 友好。
  static String _currentThemeLabel(BuildContext context) {
    final String id = context.watch<ThemeProvider>().currentSkinId;
    if (id.isEmpty) return '默认蓝';
    for (final skin in builtinSkins()) {
      if (skin.id == id) return skin.name;
    }
    return '自定义皮肤';
  }

  /// 选择明暗模式（**Phase 6**）：亮色 / 暗色 / 跟随系统。
  ///
  /// 用底部弹层而不是三态循环点击：三态循环要用户记住"点几下到哪一档"，
  /// 而三选一的语义直接列出来更清楚。
  Future<void> _pickBrightnessMode(BuildContext context) async {
    final ThemeProvider provider = context.read<ThemeProvider>();
    final AppTheme theme = AppThemeExtension.of(context);
    final ThemeBrightnessMode current = provider.mode;

    final ThemeBrightnessMode? picked =
        await showModalBottomSheet<ThemeBrightnessMode>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(theme.cardPadding),
              child: Text(
                '深色模式',
                style: TextStyle(
                  fontSize: theme.titleSize,
                  fontWeight: theme.titleFontWeight,
                  color: theme.onBackground,
                ),
              ),
            ),
            for (final ThemeBrightnessMode mode
                in ThemeBrightnessMode.values)
              ListTile(
                title: Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: theme.bodySize,
                    color: theme.onBackground,
                  ),
                ),
                subtitle: mode == ThemeBrightnessMode.system
                    ? Text(
                        '当前系统为'
                        '${provider.systemBrightness == Brightness.dark ? '暗色' : '亮色'}',
                        style: TextStyle(
                          fontSize: theme.captionSize,
                          color: theme.onBackground.withValues(alpha: 0.6),
                        ),
                      )
                    : null,
                trailing: mode == current
                    ? Icon(Icons.check, color: theme.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(mode),
              ),
          ],
        ),
      ),
    );

    if (picked == null || !context.mounted) return;
    provider.setMode(picked);
    _showSnack(context, '已切换为「${picked.label}」');
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => page),
    );
  }

  // ───────────────────── 数据：导出 / 导入 / 清理 ─────────────────────

  /// 导出全部数据并拉起系统分享面板。
  ///
  /// 刻意**不做导出前确认**：这是个只读操作，问一遍只会多一次点击。
  /// 但结果文案必须说清"备份里有什么、没有什么"——"不含登录凭据"这一点
  /// 用户最容易误解（以为导完就能直接同步）。
  Future<void> _exportData(BuildContext context) async {
    _showSnack(context, '正在生成备份…');
    final BackupResult result = await DataBackupService.export();
    if (!context.mounted) return;

    if (!result.ok) {
      _showSnack(context, result.message);
      return;
    }
    final String summary = _summarizeCounts(result.counts);
    if (result.shared) {
      _showSnack(context, '已生成备份（$summary）。备份不含登录信息，换机后需重新登录');
    } else {
      _showSnack(
        context,
        '已生成备份（$summary），但系统分享不可用：${result.file?.path}',
      );
    }
  }

  /// 选一个备份文件并覆盖导入。
  ///
  /// 校验放在**确认框之前**：校验不过就不该让用户看到"将覆盖 N 门课程"
  /// 这种吓人的文案，更不该让他点了确认才发现文件不对。
  Future<void> _importData(BuildContext context) async {
    final PickedFile picked = await SystemBridge.pickFile();
    if (!context.mounted) return;
    // 用户点了取消：正常操作，不打扰。
    if (picked.isCancelled) return;
    if (!picked.ok) {
      _showSnack(context, picked.error);
      return;
    }

    final String text = picked.content!;
    final String? invalid = DataBackupService.validate(text);
    if (invalid != null) {
      _showSnack(context, invalid);
      return;
    }

    final Map<String, int> counts = DataBackupService.summarize(text);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('导入数据'),
        content: Text(
          '备份内容：${_summarizeCounts(counts)}\n\n'
          '导入会「覆盖」当前全部数据。覆盖前会自动保存一份当前数据的'
          '回滚点，万一导错了还能找回。\n\n'
          '登录状态不在备份里，导入后需要重新登录插件。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('覆盖导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final RestoreResult result = await DataBackupService.import(text);
    if (!context.mounted) return;
    if (!result.ok) {
      _showSnack(context, result.message);
      return;
    }

    await _reloadAll(context);
    if (!context.mounted) return;
    final String plugins =
        result.pluginCount > 0 ? ' · 插件 ${result.pluginCount} 个' : '';
    _showSnack(context, '导入完成：${_summarizeCounts(result.counts)}$plugins');
  }

  /// 清理缓存（临时文件 + 图片缓存）。
  Future<void> _clearCache(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text(
          '将清除临时文件与图片缓存，不会删除课程数据。'
          '已导出的备份文件也会保留。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    // showDialog 是异步的，回来时页面可能已被销毁。
    if (confirmed != true || !context.mounted) return;

    final ClearCacheResult result = await DataBackupService.clearCache();
    if (!context.mounted) return;
    if (!result.ok) {
      _showSnack(context, result.message);
      return;
    }
    // 文件删了，内存里的图片缓存还在——不清掉的话，用户感受不到"释放"。
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    _showSnack(
      context,
      result.freedBytes == 0
          ? '缓存已经很干净了'
          : '已清理 ${_formatBytes(result.freedBytes)}',
    );
  }

  /// 清空本机的课表业务数据（保留设置、插件、皮肤）。
  Future<void> _clearAllData(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('清空课表数据'),
        content: const Text(
          '将删除本机上的全部课程、考试、作业、消息，以及你对课程做过的修改。\n\n'
          '设置、已装插件、皮肤不受影响。此操作不可撤销——'
          '建议先「导出数据」留一份备份。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final int total = await DataBackupService.clearBusinessData();
    if (!context.mounted) return;
    await _reloadAll(context);
    if (!context.mounted) return;
    _showSnack(context, total == 0 ? '本来就没有数据' : '已清空 $total 条数据');
  }

  /// 导入 / 清空之后让内存里的 Provider 重新读盘。
  ///
  /// 不重启 App：重启体验太差，用户会以为崩了。但必须**按依赖顺序**来——
  /// 插件能力决定模块可用性，所以插件先于模块。
  Future<void> _reloadAll(BuildContext context) async {
    if (!context.mounted) return;
    final CourseProvider courses = context.read<CourseProvider>();
    final ExamProvider exams = context.read<ExamProvider>();
    final HomeworkProvider homeworks = context.read<HomeworkProvider>();
    final MessageProvider messages = context.read<MessageProvider>();
    final SemesterProvider semester = context.read<SemesterProvider>();
    final SettingsProvider settings = context.read<SettingsProvider>();
    final ThemeProvider theme = context.read<ThemeProvider>();
    final PluginProvider plugins = context.read<PluginProvider>();
    final ModuleProvider modules = context.read<ModuleProvider>();

    await Future.wait(<Future<void>>[
      courses.loadFromStorage(),
      exams.loadFromStorage(),
      homeworks.loadFromStorage(),
      messages.loadFromStorage(),
      semester.loadFromStorage(),
      settings.loadFromStorage(),
      plugins.loadFromStorage(),
    ]);
    await theme.loadFromStorage();
    await theme.restoreStoredSkin();
    await modules.loadFromStorage();
    // 插件 js 可能刚被恢复：重载要起沙箱，慢，不阻塞提示文案。
    unawaited(plugins.loadAllEnabledPlugins());
  }

  /// 把各 Box 的条目数拼成一句人话，如「课表 32 · 考试 5 · 作业 12」。
  static String _summarizeCounts(Map<String, int> counts) {
    const Map<String, String> labels = <String, String>{
      kCoursesBoxName: '课表',
      kExamsBoxName: '考试',
      kHomeworksBoxName: '作业',
      kMessagesBoxName: '消息',
      kOverridesBoxName: '自定义',
    };
    final List<String> parts = <String>[];
    for (final MapEntry<String, String> entry in labels.entries) {
      final int count = counts[entry.key] ?? 0;
      if (count > 0) parts.add('${entry.value} $count');
    }
    return parts.isEmpty ? '没有可备份的数据' : parts.join(' · ');
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: theme.sectionGap),
        children: <Widget>[
          _SettingsGroup(
            title: '扩展',
            children: <Widget>[
              _SettingsTile(
                title: '插件管理',
                showChevron: true,
                onTap: () => _push(context, const PluginManagePage()),
              ),
              _SettingsTile(
                title: '创意工坊',
                showChevron: true,
                onTap: () => _push(context, const WorkshopPage()),
              ),
            ],
          ),
          _SettingsGroup(
            title: '外观',
            children: <Widget>[
              _SettingsTile(
                title: '深色模式',
                // Phase 6：显示当前偏好（亮色 / 暗色 / 跟随系统）
                trailingText: context.watch<ThemeProvider>().mode.label,
                showChevron: true,
                onTap: () => _pickBrightnessMode(context),
              ),
              _SettingsTile(
                title: '当前主题',
                trailingText: _currentThemeLabel(context),
                showChevron: true,
                // 从"当前主题"进来显然是想换皮肤：直接落在皮肤 Tab，
                // 而不是创意工坊的默认页（插件市场）。
                onTap: () => _push(
                  context,
                  const WorkshopPage(initialTab: WorkshopTab.skins),
                ),
              ),
            ],
          ),
          _SettingsGroup(
            title: '布局',
            children: <Widget>[
              _SettingsTile(
                title: '导航栏配置',
                showChevron: true,
                onTap: () => _push(context, const ModuleConfigPage()),
              ),
              _SettingsTile(
                title: '课表设置',
                showChevron: true,
                onTap: () => _push(context, const TimetableSettingsPage()),
              ),
            ],
          ),
          _SettingsGroup(
            title: '提醒',
            children: <Widget>[
              _SettingsTile(
                title: '上课提醒',
                subtitleText: '快到上课时间时提醒，按课表自动排期',
                showChevron: true,
                onTap: () => _push(context, const ClassReminderPage()),
              ),
              _SettingsTile(
                title: '作业提醒',
                subtitleText: ReminderBridge.isBackgroundCheckSupported
                    ? '截止前按档位提醒，发通知前先查作业状态'
                    : '截止前按档位提醒',
                showChevron: true,
                onTap: () => _push(context, const HomeworkReminderPage()),
              ),
            ],
          ),
          // 小组件目前只有 Android 实现；iOS 发行版不显示该分组。
          if (isWidgetPlatformSupported)
            _SettingsGroup(
              title: '桌面小组件',
              children: <Widget>[
                _SettingsTile(
                  title: '添加与使用',
                  showChevron: true,
                  onTap: () => _push(context, const WidgetGuidePage()),
                ),
                _SettingsTile(
                  title: '后台刷新设置',
                  subtitleText: '让卡片随数据变化即时更新',
                  showChevron: true,
                  onTap: () => _push(
                    context,
                    const WidgetGuidePage(
                      initialSection: WidgetGuideSection.battery,
                    ),
                  ),
                ),
              ],
            ),
          // 数据：全 App 唯一的数据安全网。没有后端、没有云同步，
          // 换手机 / 清应用数据 / 卸载重装全靠这里的导出导入。
          _SettingsGroup(
            title: '数据',
            children: <Widget>[
              _SettingsTile(
                title: '导出数据',
                subtitleText: '课表、考试、作业、插件备份成一个文件',
                onTap: () => _exportData(context),
              ),
              _SettingsTile(
                title: '导入数据',
                subtitleText: '从备份文件恢复，会覆盖当前数据',
                onTap: () => _importData(context),
              ),
              _SettingsTile(
                title: '清理缓存',
                onTap: () => _clearCache(context),
              ),
              _SettingsTile(
                title: '清空课表数据',
                subtitleText: '保留设置与插件，删除全部课程与作业',
                isDestructive: true,
                onTap: () => _clearAllData(context),
              ),
            ],
          ),
          // 诊断：这个 App 没有后端，出问题时开发者唯一的线索就是设备日志，
          // 所以入口必须显眼、文案必须说清"什么时候该点它"。
          _SettingsGroup(
            title: '诊断',
            children: <Widget>[
              _SettingsTile(
                title: '运行日志',
                subtitleText: '记录最近 24 小时的操作与报错，可导出反馈',
                showChevron: true,
                onTap: () => _push(context, const LogViewerPage()),
              ),
            ],
          ),
          _SettingsGroup(
            title: '关于',
            children: <Widget>[
              // 版本号不可点击：值来自系统包信息（`AppVersion` 经平台通道读取），
              // 不再写死常量——写死的那个曾经是 v0.1.0，与实际包 0.2.0+2 不符。
              FutureBuilder<String>(
                future: AppVersion.load(),
                builder: (
                  BuildContext context,
                  AsyncSnapshot<String> snapshot,
                ) =>
                    _SettingsTile(
                  title: '版本号',
                  trailingText:
                      snapshot.hasData ? 'v${snapshot.data}' : '读取中…',
                ),
              ),
              const _CheckUpdateTile(),
              _SettingsTile(
                title: '反馈',
                onTap: () => _showSnack(context, '反馈（待实现）'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一个设置分组：小标题 + 一张卡片。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

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
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// 「检查更新」条目：点一次查一次远端 Release（Gitee 镜像优先，GitHub 兜底）。
///
/// 抽成独立的 StatefulWidget，是因为"检查中"这个瞬时状态只需要重建这一行，
/// 不该让整个设置页跟着重建。
class _CheckUpdateTile extends StatefulWidget {
  const _CheckUpdateTile();

  @override
  State<_CheckUpdateTile> createState() => _CheckUpdateTileState();
}

class _CheckUpdateTileState extends State<_CheckUpdateTile> {
  /// 是否正在请求远端（防重入 + 行尾提示）。
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);

    // 桌面 / 未知平台：没有对应的安装包，别引导用户去下 APK。
    if (!SystemBridge.supported) {
      setState(() => _checking = false);
      _snack('当前平台不支持自动更新');
      return;
    }

    final String current = await AppVersion.load();
    final UpdateCheckResult result =
        await UpdateService.check(currentVersion: current);

    if (!mounted) return;
    setState(() => _checking = false);

    if (result.status == UpdateStatus.upToDate) {
      // 带上来源：用户能看出是走 Gitee 镜像还是 GitHub 查到的。
      final String via = result.source.isEmpty ? '' : '（${result.source}）';
      _snack('已是最新版本 v$current$via');
    } else if (result.status == UpdateStatus.failed) {
      _snack(result.reason);
    } else {
      await _showUpdateDialog(result);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showUpdateDialog(UpdateCheckResult result) async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('发现新版本 v${result.latestVersion}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('当前版本 v${result.currentVersion}'),
              if (result.source.isNotEmpty)
                Text(
                  '下载源：${result.source}',
                  style: const TextStyle(fontSize: 12),
                ),
              if (result.changelog.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                // Release 正文是纯文本（可能带 Markdown 标记），这里原样展示：
                // 为了它引入一个 Markdown 渲染器不值得，用户关心的是"改了什么"。
                Text(result.changelog),
              ],
              // 本平台这次没传安装包（iOS 还没打包 / Release 漏传）：
              // 说清楚去哪装，别让用户以为"点了没反应"。
              if (result.apkUrl.isEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  Platform.isIOS
                      ? 'iOS 版请用 TestFlight 安装；下面的按钮会打开 Release 页面。'
                      : '这个 Release 没有本平台的安装包，'
                          '下面的按钮会打开 Release 页面。',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(result.apkUrl.isEmpty ? '前往查看' : '前往下载'),
          ),
        ],
      ),
    );

    if (go != true || !mounted) return;

    final String url = result.downloadUrl;
    if (url.isEmpty) {
      _snack('这个 Release 没有可下载的文件');
      return;
    }

    final bool opened = await SystemBridge.openUrl(url);
    if (opened) return;

    // 兜底：非 Android 平台 / 没有浏览器可打开 → 复制链接，用户自己粘。
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _snack('已复制下载链接到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      title: '检查更新',
      trailingText: _checking ? '检查中…' : null,
      showChevron: !_checking,
      onTap: _checking ? null : _check,
    );
  }
}

/// 分组内的一行。
///
/// [onTap] 为 `null` 时该行不可点击（如"版本号"）。
/// [showChevron] 用于可跳转的条目，[trailingText] 用于展示只读值。
/// [isDestructive] 让标题用错误色——**不可撤销的操作必须看起来就不一样**，
/// 不能和"清理缓存"这种随时能重做的操作长一个样。
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.onTap,
    this.showChevron = false,
    this.trailingText,
    this.subtitleText,
    this.isDestructive = false,
  });

  final String title;
  final VoidCallback? onTap;
  final bool showChevron;
  final String? trailingText;
  final String? subtitleText;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final String? trailingText = this.trailingText;
    final String? subtitleText = this.subtitleText;

    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: theme.bodySize,
          color: isDestructive ? theme.error : theme.onBackground,
        ),
      ),
      subtitle: subtitleText == null
          ? null
          : Text(
              subtitleText,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.6),
              ),
            ),
      onTap: onTap,
      trailing: (trailingText == null && !showChevron)
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (trailingText != null)
                  Text(
                    trailingText,
                    style: TextStyle(
                      fontSize: theme.bodySize,
                      color: theme.onBackground.withValues(alpha: 0.6),
                    ),
                  ),
                if (showChevron)
                  Icon(
                    Icons.chevron_right,
                    color: theme.onBackground.withValues(alpha: 0.4),
                  ),
              ],
            ),
    );
  }
}