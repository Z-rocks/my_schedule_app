// Phase 8：按课程勾选后抓取（作业 / 考试共用）。
//
// ## 为什么是"先列课程、再勾选、再抓"
//
// 学习通有反爬：实测 12 秒内 136 个请求会触发
// `【9010】操作异常，请输入图片中的验证码`。因此**绝不能默认全量抓取**
// （本账号就有 68 门课，全抓必然被拦，且用户多半只关心其中几门）。
// 本页把选择权交给用户，并主动限制"一次最多几门"。
//
// ## 与具体实体解耦
//
// 本页不认识"作业"或"考试"：能力 ID、标题、量词、以及"怎么执行同步"
// 全部由调用方通过构造函数传入（[EntitySyncRunner]）。因此作业页与考试页
// 复用同一个页面，将来加"成绩"也只需再写一个调用方。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/message.dart';
import '../../models/plugin_course_ref.dart';
import '../../models/plugin_meta.dart';
import '../../models/sync_report.dart';
import '../../providers/message_provider.dart';
import '../../providers/plugin_provider.dart';
import '../../runtime/plugin_handle.dart';
import '../../services/plugin_entity_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';

/// 单次抓取建议的课程数上限。
///
/// 不是硬限制（不阻止用户），而是**超过就显式警告**：请求数约为 `4 × 课程数`，
/// 越多越容易撞风控，撞上之后整批都会失败，反而更慢。
const int kRecommendedMaxCoursesPerSync = 5;

/// 结果卡片最多展示的警告条数。
const int kMaxVisibleEntityWarnings = 3;

/// "执行一次抓取"的闭包类型。
///
/// 由调用方（作业页 / 考试页）提供——它们各自持有对应的 Provider，
/// 用它去调 [PluginEntitySyncService.sync]。
typedef EntitySyncRunner = Future<SyncReport> Function({
  required String pluginId,
  required PluginHandle? handle,
  required List<PluginCourseRef> refs,
  required bool withContent,
  void Function(String stage, String message)? onProgress,
});

/// 按课程勾选后抓取的页面。
class PluginEntitySyncPage extends StatefulWidget {
  const PluginEntitySyncPage({
    super.key,
    required this.capability,
    required this.title,
    required this.itemLabel,
    required this.itemUnit,
    required this.run,
    this.showContentToggle = false,
    this.contentToggleLabel = '同时抓取正文',
    this.contentToggleHint = '',
  });

  /// 插件能力 ID（`homework` / `exam`），用于定位提供数据的插件。
  final String capability;

  /// 页面标题，如 `抓取作业`。
  final String title;

  /// 条目名词，如 `作业`。
  final String itemLabel;

  /// 量词，如 `份`。
  final String itemUnit;

  /// 执行同步的闭包（见 [EntitySyncRunner]）。
  final EntitySyncRunner run;

  /// 是否显示"同时抓取正文"开关（作业为 `true`，考试为 `false`）。
  final bool showContentToggle;

  /// 开关的标题。
  final String contentToggleLabel;

  /// 开关下方的说明（副作用提示等）。
  final String contentToggleHint;

  @override
  State<PluginEntitySyncPage> createState() => _PluginEntitySyncPageState();
}

class _PluginEntitySyncPageState extends State<PluginEntitySyncPage> {
  /// 已解析出的课程引用（`null` 表示还没加载成功）。
  List<PluginCourseRef>? _refs;

  /// 加载课程列表时的错误（空串表示没有错误）。
  String _loadError = '';

  /// 是否正在加载课程列表。
  bool _loadingCourses = false;

  /// 被勾选的课程 id 集合。
  final Set<String> _selected = <String>{};

  /// 课程过滤关键字（68 门课时靠它找课）。
  final TextEditingController _filter = TextEditingController();

  /// 是否正在抓取（防重入）。
  bool _syncing = false;

  /// 当前进度文案（`null` 表示没有进行中的抓取）。
  String? _progress;

  /// 上一次抓取的报告（`null` 表示本次进入页面后还没抓过）。
  SyncReport? _report;

  /// 是否同时抓取正文（仅作业使用）。
  bool _withContent = true;

  /// 定位到的插件（`null` 表示没找到可用的）。
  PluginMeta? _plugin;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  // ─────────────────────── 加载课程列表 ───────────────────────

  /// 找出插件并拉取它的课程列表（不落盘，仅供本页勾选）。
  Future<void> _loadCourses() async {
    if (_loadingCourses) return;
    setState(() {
      _loadingCourses = true;
      _loadError = '';
      _report = null;
    });

    final PluginProvider plugins = context.read<PluginProvider>();
    final PluginMeta? meta =
        plugins.firstUsableWithCapability(widget.capability);

    if (meta == null) {
      // 区分"没装 / 没启用"与"启用了但没加载成功"，让用户知道该去做什么。
      final PluginMeta? enabled =
          plugins.firstEnabledWithCapability(widget.capability);
      final String reason = enabled == null
          ? '还没有可用的插件。请先到「设置 → 插件管理」安装并启用一个支持'
              '${widget.itemLabel}的插件（如学习通），然后回来重试。'
          : '插件「${enabled.name}」已启用但运行时不可用'
              '（${plugins.loadErrorOf(enabled.id) ?? '原因未知'}），'
              '请到插件详情页检查后重试。';
      if (!mounted) return;
      setState(() {
        _loadingCourses = false;
        _loadError = reason;
      });
      return;
    }

    final CourseRefFetchResult result =
        await PluginEntitySyncService.fetchCourseRefs(
      pluginId: meta.id,
      handle: plugins.getHandle(meta.id),
      onProgress: (String stage, String message) {
        if (!mounted) return;
        setState(() => _progress = message);
      },
    );

    if (!mounted) return;
    setState(() {
      _loadingCourses = false;
      _progress = null;
      _plugin = meta;
      if (result.isSuccess) {
        _refs = result.refs;
        // **默认不勾选**：全量抓取会撞风控，且用户通常只关心少数几门。
        _selected.clear();
      } else {
        _loadError = result.error;
      }
    });
  }

  // ─────────────────────── 抓取 ───────────────────────

  Future<void> _startSync() async {
    final PluginMeta? meta = _plugin;
    final List<PluginCourseRef>? refs = _refs;
    if (_syncing || meta == null || refs == null) return;

    final List<PluginCourseRef> chosen = refs
        .where((PluginCourseRef r) => _selected.contains(r.id))
        .toList(growable: false);
    if (chosen.isEmpty) {
      _snack('请先勾选要抓取的课程');
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final MessageProvider messages = context.read<MessageProvider>();
    final PluginHandle? handle = context.read<PluginProvider>().getHandle(meta.id);

    setState(() {
      _syncing = true;
      _progress = null;
      _report = null;
    });

    // `late final` 表达"下面 try / catch 两条路径各赋一次，且只赋一次"。
    late final SyncReport report;
    try {
      report = await widget.run(
        pluginId: meta.id,
        handle: handle,
        refs: chosen,
        withContent: _withContent,
        onProgress: (String stage, String message) {
          if (!mounted) return;
          setState(() => _progress = message);
        },
      );
    } catch (e) {
      // 服务层契约是"不抛异常"；真抛了也要给用户一个交代，
      // 否则页面会永远停在转圈状态。
      debugPrint('[PluginEntitySyncPage] 抓取抛出未预期异常：$e');
      report = SyncReport.failure(
        pluginId: meta.id,
        outcome: SyncOutcome.failed,
        reason: '抓取异常：$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _progress = null;
        });
      } else {
        _syncing = false;
        _progress = null;
      }
    }

    // 把结果沉淀成一条站内消息：SnackBar 一闪而过，
    // 而"上次抓到了什么"是用户回头会想看的信息。
    unawaited(
      messages.addMessagePersisted(
        Message.fromSyncReport(
          report: report,
          pluginName: meta.name,
          itemLabel: widget.itemLabel,
          itemUnit: widget.itemUnit,
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _report = report);
    messenger.showSnackBar(SnackBar(content: Text(_snackText(report))));
  }

  /// 把报告压成一句 SnackBar 文案（细节交给结果卡片）。
  String _snackText(SyncReport report) {
    if (!report.isSuccess) return '抓取失败：${report.reason}';
    if (!report.hasChanges) {
      return report.totalCourses == 0
          ? '抓取完成：没有找到${widget.itemLabel}'
          : '抓取完成：${report.totalCourses}${widget.itemUnit}${widget.itemLabel}已是最新';
    }
    final List<String> parts = <String>[];
    if (report.added > 0) parts.add('新增 ${report.added}');
    if (report.updated > 0) parts.add('更新 ${report.updated}');
    return '已抓取 ${report.totalCourses}${widget.itemUnit}${widget.itemLabel}'
        '（${parts.join('、')}）';
  }

  /// 弹一条提示。**只在 `mounted` 为 true 时调用**（调用点都在同步回调里，
  /// 已逐个查过 `mounted`）。
  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
  // ─────────────────────── 构建 ───────────────────────

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final List<PluginCourseRef>? refs = _refs;
    final String keyword = _filter.text.trim().toLowerCase();
    final List<PluginCourseRef> visible = refs == null
        ? const <PluginCourseRef>[]
        : refs
            .where((PluginCourseRef r) =>
                keyword.isEmpty ||
                r.displayName.toLowerCase().contains(keyword) ||
                r.subtitle.toLowerCase().contains(keyword))
            .toList(growable: false);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新获取课程列表',
            onPressed: _syncing || _loadingCourses ? null : _loadCourses,
          ),
        ],
      ),
      body: _buildBody(context, theme, refs, visible),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppTheme theme,
    List<PluginCourseRef>? refs,
    List<PluginCourseRef> visible,
  ) {
    if (_loadError.isNotEmpty) {
      return _ErrorState(
        message: _loadError,
        onRetry: _loadingCourses ? null : _loadCourses,
      );
    }
    if (_loadingCourses && refs == null) {
      return _CenteredProgress(message: _progress ?? '正在获取课程列表…');
    }
    if (refs == null || refs.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(theme.cardPadding * 2),
          child: Text(
            '该账号下没有可抓取的课程。',
            style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        _buildHeader(theme, refs.length),
        _buildFilterField(theme),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配「${_filter.text.trim()}」的课程',
                    style: TextStyle(
                      fontSize: theme.captionSize,
                      color: theme.onBackground.withValues(alpha: 0.6),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: theme.cardPadding),
                  itemCount: visible.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _buildCourseTile(theme, visible[index]),
                ),
        ),
        if (widget.showContentToggle) _buildContentToggle(theme),
        if (_syncing)
          _ProgressTile(message: _progress)
        else if (_report != null)
          _ResultTile(
            report: _report!,
            itemLabel: widget.itemLabel,
            itemUnit: widget.itemUnit,
          ),
        _buildActionBar(theme),
      ],
    );
  }

  /// 顶部信息条：已选数量 + 全选 / 清空 + 风控提醒。
  Widget _buildHeader(AppTheme theme, int total) {
    final int count = _selected.length;
    final bool tooMany = count > kRecommendedMaxCoursesPerSync;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: theme.cardPadding,
        vertical: theme.gridGap * 2,
      ),
      color: theme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '共 $total 门课程，已选 $count 门',
                  style: TextStyle(
                    fontSize: theme.bodySize,
                    fontWeight: theme.titleFontWeight,
                    color: theme.onBackground,
                  ),
                ),
              ),
              TextButton(
                onPressed: _syncing
                    ? null
                    : () => setState(() {
                          // 只全选**当前筛选出的**课程，避免"筛了 3 门却选上 68 门"。
                          _selected.addAll(
                            _refs!
                                .where(_matchFilter)
                                .map((PluginCourseRef r) => r.id),
                          );
                        }),
                child: const Text('全选'),
              ),
              TextButton(
                onPressed:
                    _syncing ? null : () => setState(() => _selected.clear()),
                child: const Text('清空'),
              ),
            ],
          ),
          if (tooMany)
            Padding(
              padding: EdgeInsets.only(top: theme.gridGap),
              child: Text(
                '一次抓取建议不超过 $kRecommendedMaxCoursesPerSync 门课：'
                '学习通有反爬，请求太多会被要求输入验证码，整批都会失败。',
                style: TextStyle(fontSize: theme.captionSize, color: theme.warning),
              ),
            ),
          // 刷新课程列表时（列表已有内容、所以不走全屏转圈）在这里给个提示。
          if (_loadingCourses)
            Padding(
              padding: EdgeInsets.only(top: theme.gridGap),
              child: Text(
                _progress ?? '正在重新获取课程列表…',
                style: TextStyle(fontSize: theme.captionSize, color: theme.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterField(AppTheme theme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        theme.cardPadding,
        theme.gridGap * 2,
        theme.cardPadding,
        theme.gridGap,
      ),
      child: TextField(
        controller: _filter,
        onChanged: (String _) => setState(() {}),
        style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
        decoration: InputDecoration(
          isDense: true,
          hintText: '筛选课程（名称 / 教师 / 班级）',
          prefixIcon: Icon(Icons.search, size: theme.captionSize * 1.4),
          suffixIcon: _filter.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, size: theme.captionSize * 1.25),
                  onPressed: () => setState(_filter.clear),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(theme.buttonRadius),
          ),
        ),
      ),
    );
  }

  bool _matchFilter(PluginCourseRef ref) {
    final String keyword = _filter.text.trim().toLowerCase();
    if (keyword.isEmpty) return true;
    return ref.displayName.toLowerCase().contains(keyword) ||
        ref.subtitle.toLowerCase().contains(keyword);
  }

  Widget _buildCourseTile(AppTheme theme, PluginCourseRef ref) {
    final bool checked = _selected.contains(ref.id);
    return CheckboxListTile(
      value: checked,
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: theme.primary,
      onChanged: _syncing
          ? null
          : (bool? value) => setState(() {
                if (value == true) {
                  _selected.add(ref.id);
                } else {
                  _selected.remove(ref.id);
                }
              }),
      title: Text(
        ref.displayName,
        style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
      ),
      subtitle: ref.subtitle.isEmpty
          ? null
          : Text(
              ref.subtitle,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.65),
              ),
            ),
    );
  }

  Widget _buildContentToggle(AppTheme theme) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.cardPadding,
        vertical: theme.gridGap,
      ),
      color: theme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _withContent,
            onChanged: _syncing
                ? null
                : (bool value) => setState(() => _withContent = value),
            title: Text(
              widget.contentToggleLabel,
              style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
            ),
          ),
          if (widget.contentToggleHint.isNotEmpty)
            Text(
              widget.contentToggleHint,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar(AppTheme theme) {
    final int count = _selected.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(theme.cardPadding),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _syncing || count == 0 ? null : _startSync,
            style: FilledButton.styleFrom(
              backgroundColor: theme.primary,
              foregroundColor: theme.onPrimary,
              padding: EdgeInsets.symmetric(vertical: theme.gridGap * 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(theme.buttonRadius),
              ),
            ),
            child: Text(
              _syncing
                  ? '正在抓取…'
                  : '开始抓取（$count 门课）',
              style: TextStyle(fontSize: theme.bodySize),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 小组件 ─────────────────────────

/// 居中转圈 + 文案。
class _CenteredProgress extends StatelessWidget {
  const _CenteredProgress({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: theme.captionSize * 1.6,
            height: theme.captionSize * 1.6,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
            ),
          ),
          SizedBox(height: theme.sectionGap),
          Text(
            message,
            style: TextStyle(
              fontSize: theme.captionSize,
              color: theme.onBackground.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// 错误态：文案 + 重试按钮。
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(theme.cardPadding * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: theme.captionSize * 3.2,
              color: theme.error.withValues(alpha: 0.8),
            ),
            SizedBox(height: theme.sectionGap),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
            ),
            SizedBox(height: theme.sectionGap),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: theme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.buttonRadius),
                ),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 抓取进行中的进度行。
class _ProgressTile extends StatelessWidget {
  const _ProgressTile({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: theme.cardPadding,
        vertical: theme.gridGap * 2,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: theme.captionSize * 1.4,
            height: theme.captionSize * 1.4,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
            ),
          ),
          SizedBox(width: theme.cardPadding),
          Expanded(
            child: Text(
              message ?? '正在抓取，请稍候…',
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 抓取结果卡片（常驻，比 SnackBar 更适合看细节）。
class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.report,
    required this.itemLabel,
    required this.itemUnit,
  });

  final SyncReport report;
  final String itemLabel;
  final String itemUnit;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final Color accent = report.isSuccess
        ? (report.hasChanges
            ? theme.success
            : theme.onBackground.withValues(alpha: 0.6))
        : (report.isRetryable ? theme.warning : theme.error);

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: theme.cardPadding,
        vertical: theme.gridGap,
      ),
      padding: EdgeInsets.all(theme.cardPadding),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(theme.buttonRadius),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                report.isSuccess
                    ? (report.hasChanges
                        ? Icons.check_circle_outline
                        : Icons.info_outline)
                    : Icons.error_outline,
                size: theme.captionSize * 1.4,
                color: accent,
              ),
              SizedBox(width: theme.gridGap * 2),
              Expanded(
                child: Text(
                  _title(),
                  style: TextStyle(
                    fontSize: theme.captionSize,
                    fontWeight: theme.titleFontWeight,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          if (!report.isSuccess && report.reason.isNotEmpty) ...<Widget>[
            SizedBox(height: theme.gridGap * 2),
            Text(
              report.reason,
              style: TextStyle(fontSize: theme.captionSize, color: theme.onBackground),
            ),
          ],
          if (report.isSuccess) ...<Widget>[
            SizedBox(height: theme.gridGap * 2),
            _line(theme, '新增 ${report.added} · 更新 ${report.updated} '
                '· 未变 ${report.unchanged}'),
            if (report.skipped > 0)
              _line(theme, '跳过 ${report.skipped} 条（数据不完整）'),
            if (report.userEdited > 0)
              _line(theme, '其中 ${report.userEdited}$itemUnit$itemLabel保留了你的修改'),
          ],
          if (report.attempts > 1) _line(theme, '共尝试 ${report.attempts} 次'),
          if (report.warnings.isNotEmpty) ...<Widget>[
            SizedBox(height: theme.gridGap * 2),
            for (final String warning
                in report.warnings.take(kMaxVisibleEntityWarnings))
              Text(
                '· $warning',
                style: TextStyle(fontSize: theme.captionSize, color: theme.warning),
              ),
            if (report.warnings.length > kMaxVisibleEntityWarnings)
              Text(
                '· 另有 ${report.warnings.length - kMaxVisibleEntityWarnings} 条警告，详见日志',
                style: TextStyle(
                  fontSize: theme.captionSize,
                  color: theme.onBackground.withValues(alpha: 0.6),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _title() {
    if (!report.isSuccess) {
      switch (report.outcome) {
        case SyncOutcome.authRequired:
          return '需要先登录';
        case SyncOutcome.networkError:
          return '网络失败（可重试）';
        case SyncOutcome.timeout:
          return '抓取超时';
        case SyncOutcome.unavailable:
          return '插件不可用';
        case SyncOutcome.unsupported:
          return '该插件不支持此能力';
        case SyncOutcome.protocolError:
          return '数据无法识别';
        case SyncOutcome.failed:
        case SyncOutcome.success:
          return '抓取失败';
      }
    }
    if (!report.hasChanges) {
      return report.totalCourses == 0 ? '没有找到$itemLabel' : '已是最新';
    }
    return '抓取成功';
  }

  Widget _line(AppTheme theme, String text) {
    return Padding(
      padding: EdgeInsets.only(top: theme.gridGap / 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: theme.captionSize,
          color: theme.onBackground.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
