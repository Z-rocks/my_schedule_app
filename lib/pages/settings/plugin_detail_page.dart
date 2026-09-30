// 插件详情页：展示单个插件的元信息、运行时状态与操作入口
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plugin_meta.dart';
import '../../models/sync_report.dart';
import '../../providers/course_provider.dart';
import '../../providers/plugin_provider.dart';
import '../../runtime/plugin_handle.dart';
import '../../runtime/plugin_manifest.dart';
import '../../services/cookie_service.dart';
import '../../services/course_sync_service.dart';
import '../../services/plugin_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../login/webview_login_page.dart';
import 'plugin_manage_page.dart'
    show
        PluginUiStatus,
        pluginUiStatusColor,
        pluginUiStatusLabel,
        pluginUiStatusOf;

/// 同步进度最多展示的警告条数。
///
/// 插件可能回传很多条警告（例如每个学院各一条），全铺在页面上会把
/// 操作区淹掉；剩下的引导用户去看日志（`debugPrint` 已完整输出）。
const int kMaxVisibleSyncWarnings = 3;

/// 插件详情页。
///
/// 数据全部来自 `PluginProvider`（`context.watch` 保证启停 / 加载结果实时反映）。
/// 安装路径是**异步**读的（`PluginStorageService.getPluginJsPath`），
/// 用 `FutureBuilder` 展示。
///
/// **Phase 4.3 起是 `StatefulWidget`**：因为同步需要页内状态
/// （进行中 / 进度文案 / 上一次的 [SyncReport]）。4.2 时为了一个防重入闩锁
/// 用的是 `static bool`，那样有两个问题：跨实例泄漏状态、且没法显示结果。
class PluginDetailPage extends StatefulWidget {
  const PluginDetailPage({super.key, required this.pluginId});

  /// 要展示的插件 id。插件被卸载后本页会显示"插件不存在"。
  final String pluginId;

  @override
  State<PluginDetailPage> createState() => _PluginDetailPageState();
}

class _PluginDetailPageState extends State<PluginDetailPage> {
  /// 当前插件 id（卸载后 [widget.pluginId] 不变，但可能已不存在）。
  String get pluginId => widget.pluginId;

  /// 是否正在同步（防重入）。
  bool _syncing = false;

  /// 当前进度文案（`null` 表示没有进行中的同步）。
  String? _progressMessage;

  /// 上一次同步的报告（`null` 表示本次进入页面后还没同步过）。
  SyncReport? _lastReport;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final PluginProvider provider = context.watch<PluginProvider>();
    final PluginMeta? meta = provider.getById(pluginId);

    if (meta == null) {
      // 卸载后（或 id 失效）的兜底，避免空指针。
      return Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(title: const Text('插件详情'), centerTitle: true),
        body: Center(
          child: Text(
            '插件不存在或已卸载',
            style: TextStyle(
              fontSize: theme.bodySize,
              color: theme.onBackground.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    final PluginHandle? handle = provider.getHandle(pluginId);
    final String? error = provider.loadErrorOf(pluginId);
    final PluginUiStatus status = pluginUiStatusOf(
      enabled: meta.enabled,
      isLoaded: handle?.isUsable ?? false,
      hasError: error != null,
    );

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(meta.name, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        actions: <Widget>[
          // 只有**不可卸载**的插件才隐藏入口（`isRemovable == false`，
          // 留给硬编码的系统级插件）。来源为 builtin 的插件照样能卸载——
          // 例如从 assets 安装的示例插件（Phase 3.5.1 修正）。
          if (meta.isRemovable)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '卸载',
              onPressed: () => _confirmUninstall(context, provider, meta),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(theme.cardPadding),
        children: <Widget>[
          _InfoCard(
            title: '基本信息',
            children: <Widget>[
              _InfoRow(label: '插件 ID', value: meta.id),
              _InfoRow(label: '版本', value: meta.version),
              _InfoRow(
                label: '作者',
                value: meta.author.trim().isEmpty ? '未知作者' : meta.author,
              ),
              _InfoRow(
                label: '描述',
                value: meta.description.trim().isEmpty
                    ? '（无描述）'
                    : meta.description,
              ),
              _InfoRow(
                label: '能力',
                value: meta.effectiveCapabilities.isEmpty
                    ? '（未声明）'
                    : meta.effectiveCapabilities.join(' · '),
              ),
              _InfoRow(
                label: '来源',
                value: _sourceLabel(meta.source),
              ),
              _InstallPathRow(pluginId: pluginId),
              _InfoRow(
                label: '加载状态',
                value: '${pluginUiStatusLabel(status)}'
                    '${error == null ? '' : '：$error'}',
                valueColor: pluginUiStatusColor(status, theme),
              ),
            ],
          ),
          SizedBox(height: theme.cardPadding),
          _InfoCard(
            title: '运行时',
            children: <Widget>[
              _InfoRow(
                label: '沙箱',
                value: handle == null
                    ? '未创建'
                    : (handle.isUsable ? '可用' : '不可用'),
              ),
              _InfoRow(
                label: '入口函数',
                value: (handle?.entries.isEmpty ?? true)
                    ? '（无）'
                    : handle!.entries.join(' · '),
              ),
              if (handle != null && !handle.isUsable)
                _InfoRow(
                  label: '降级原因',
                  value: handle.reason ?? '（未记录）',
                  valueColor: theme.error,
                ),
            ],
          ),
          SizedBox(height: theme.cardPadding),
          _InfoCard(
            title: '操作',
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '启用',
                  style: TextStyle(
                    fontSize: theme.bodySize,
                    color: theme.onBackground,
                  ),
                ),
                value: meta.enabled,
                onChanged: (bool value) =>
                    provider.togglePlugin(meta.id, value),
              ),
              // "登录" Phase 4.1 起接真实 WebView 登录（见 _openLogin）。
              _ActionRow(
                icon: Icons.login,
                label: '登录',
                onTap: () => _openLogin(context, provider, meta, handle),
              ),
              // "立即同步" Phase 4.3 起走 CourseSyncService（增量 + 重试 + 进度）。
              _ActionRow(
                icon: Icons.sync,
                label: _syncing ? '正在同步…' : '立即同步',
                // 同步中禁用入口，避免连点（原先是 static 闩锁静默丢弃点击）。
                onTap: _syncing
                    ? null
                    : () => _syncNow(context, provider, meta, handle),
              ),
              _ActionRow(
                icon: Icons.article_outlined,
                label: '查看日志',
                onTap: () => _snack(context, '查看日志（Phase 3 后实现）'),
              ),
              if (_syncing) _SyncProgressTile(message: _progressMessage),
              if (!_syncing && _lastReport != null)
                _SyncResultTile(report: _lastReport!),
            ],
          ),
        ],
      ),
    );
  }

  /// 打开通用 WebView 登录页（Phase 4.1）。
  ///
  /// 登录地址与成功判定前缀都来自**插件自己的声明**（`PluginManifest.loginUrl` /
  /// `checkUrl`，由插件 JS 的 `__plugin` 或 `.manifest.json` 提供）——内核**不硬编码**
  /// 任何学校 URL（CONTEXT 3.1）。插件没声明时给 SnackBar 提示，不跳转。
  Future<void> _openLogin(
    BuildContext context,
    PluginProvider provider,
    PluginMeta meta,
    PluginHandle? handle,
  ) async {
    final PluginManifest? manifest = handle?.manifest;
    final String loginUrl = manifest?.loginUrl.trim() ?? '';
    if (loginUrl.isEmpty) {
      _snack(context, '该插件未声明登录地址（loginUrl）');
      return;
    }

    final String? cookie = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext _) => WebViewLoginPage(
          loginUrl: loginUrl,
          // 未声明 checkUrl 时传空串 → 登录页退化为"拿到 Cookie 即成功"
          successUrlPrefix: manifest?.checkUrl.trim() ?? '',
          title: '登录 ${meta.name}',
          // 传入 pluginId → 由登录页负责落盘，避免调用方忘记保存
          pluginId: meta.id,
        ),
      ),
    );

    if (!context.mounted) return;
    if (cookie == null || cookie.isEmpty) {
      // 用户主动返回（或没拿到凭证）：不做任何破坏性操作（决策 4）。
      _snack(context, '已取消登录');
      return;
    }
    _snack(context, '登录成功（已保存 ${cookie.length} 字符的 Cookie）');
  }

  /// 「立即同步」（Phase 4.3 起走 [CourseSyncService]）。
  ///
  /// 本方法只负责**编排与展示**：查登录态 → 调服务 → 把 [SyncReport] 变成
  /// 人话。重试、增量落盘、覆盖层保留、结果分类全部在服务里完成，
  /// 这样 Phase 4.4 的课表页同步入口能复用同一套行为。
  ///
  /// 为什么仍然先查 Cookie：没有凭证时插件会**立刻**返回"未登录"，
  /// 提前拦掉可以省掉一次沙箱执行与一次重试退避等待。
  Future<void> _syncNow(
    BuildContext context,
    PluginProvider provider,
    PluginMeta meta,
    PluginHandle? handle,
  ) async {
    if (_syncing) return;
    final CourseProvider courses = context.read<CourseProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // 1) 先看登录态：没有 Cookie 就别白跑一趟网络
    final String cookie = await CookieService.loadCookie(meta.id);
    if (cookie.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('请先登录，再点「立即同步」')),
      );
      return;
    }

    setState(() {
      _syncing = true;
      _progressMessage = null;
      _lastReport = null;
    });

    // `late final` 表达"下面 try / catch 两条路径各赋一次，且只赋一次"这个不变量
    // —— 用类型表达出来，就不需要事后判空（分析器也能据此确认非空）。
    //
    // 注意 catch 块不是多余的：`CourseSyncService.sync` 的契约是"不抛异常"，
    // 但万一它真的抛了，没有 catch 就会跳过 `finally` 之后的收尾，
    // 页面会**永远停在转圈状态**。
    late final SyncReport report;
    try {
      report = await CourseSyncService.sync(
        pluginId: meta.id,
        handle: handle,
        courses: courses,
        onProgress: (String stage, String message) {
          // 回调发生在 await 之间，此时 State 一定还挂着；
          // 但仍按规范查 mounted，避免页面被 pop 后 setState 报错。
          if (!mounted) return;
          setState(() => _progressMessage = message);
        },
      );
    } catch (e) {
      // 最后一道保险：服务层的契约是"不抛"，真抛了也要给用户一个交代。
      debugPrint('[PluginDetailPage] 同步抛出未预期异常：$e');
      report = SyncReport.failure(
        pluginId: meta.id,
        outcome: SyncOutcome.failed,
        reason: '同步异常：$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _progressMessage = null;
        });
      } else {
        // 页面已销毁：没有 State 可更新，但字段复位仍是有意义的
        // （State 对象可能被复用前的最后一次写入）。
        _syncing = false;
        _progressMessage = null;
      }
    }

    if (!mounted) return;
    setState(() => _lastReport = report);

    messenger.showSnackBar(
      SnackBar(content: Text(_snackTextFor(report))),
    );
  }

  /// 把报告压成一句 SnackBar 文案。
  ///
  /// 详细结果交给 [_SyncResultTile]（那里有地方换行、也能常驻），
  /// SnackBar 只给最关键的结论。
  static String _snackTextFor(SyncReport report) {
    if (!report.isSuccess) {
      return '同步失败：${report.reason}';
    }
    if (!report.hasChanges) {
      return report.totalCourses == 0
          ? '同步完成：这学期没有课程'
          : '同步完成：${report.totalCourses} 门课程已是最新';
    }
    final List<String> parts = <String>[];
    if (report.added > 0) parts.add('新增 ${report.added}');
    if (report.updated > 0) parts.add('更新 ${report.updated}');
    return '已同步 ${report.totalCourses} 门课程（${parts.join('、')}）';
  }

  /// 卸载：先确认，再移除（会销毁运行时沙箱并删存储），最后退回列表页。
  Future<void> _confirmUninstall(
    BuildContext context,
    PluginProvider provider,
    PluginMeta meta,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text('确定要卸载插件「${meta.name}」吗？这会删除插件文件与本地数据。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await provider.removePlugin(meta.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 安装来源的中文标签。
  static String _sourceLabel(String source) {
    switch (source) {
      case 'builtin':
        return '内置';
      case 'workshop':
        return '创意工坊';
      case 'local':
        return '本地导入';
      default:
        return source;
    }
  }
}

/// 分区卡片（标题 + 若干行）。
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return Card(
      color: theme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.cardPadding),
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
            SizedBox(height: theme.gridGap * 2),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 一行"标签 : 值"。值可换行（描述、错误详情可能很长）。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final Color labelColor = theme.onBackground.withValues(alpha: 0.55);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.gridGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: theme.captionSize, color: labelColor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: valueColor ?? theme.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "安装路径"行：异步读文件系统，读到之前显示"读取中…"。
class _InstallPathRow extends StatelessWidget {
  const _InstallPathRow({required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: PluginStorageService.getPluginJsPath(pluginId),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        final String value;
        if (snapshot.connectionState != ConnectionState.done) {
          value = '读取中…';
        } else if (snapshot.hasError) {
          value = '读取失败';
        } else {
          value = snapshot.data ?? '未安装（插件目录中找不到 .js 文件）';
        }
        return _InfoRow(label: '安装路径', value: value);
      },
    );
  }
}

/// 一行可点击的操作项。
///
/// [onTap] 为 `null` 时是**禁用态**（Phase 4.3：同步进行中禁用"立即同步"，
/// 避免连点；`ListTile` 收到 `null` 会自动置灰并拦截点击）。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final bool enabled = onTap != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(
        icon,
        color: enabled ? theme.primary : theme.onBackground.withValues(alpha: 0.38),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: theme.bodySize,
          color: enabled ? theme.onBackground : theme.onBackground.withValues(alpha: 0.38),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.onBackground.withValues(alpha: 0.3),
      ),
      onTap: onTap,
    );
  }
}

/// 同步进行中的进度行（转圈 + 当前阶段文案）。
///
/// 所有样式取自 [AppTheme]（CONTEXT 3.2，禁止硬编码颜色/字号）。
class _SyncProgressTile extends StatelessWidget {
  const _SyncProgressTile({required this.message});

  /// 当前进度文案；为 `null` 时显示一个通用文案。
  final String? message;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.gridGap * 2),
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
              message ?? '正在同步，请稍候…',
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

/// 上一次同步的结果卡片（常驻显示，比 SnackBar 更适合看细节）。
///
/// 颜色只用主题里的语义令牌：`success` / `warning` / `error`
/// （CONTEXT 3.2 明确禁止 UI 硬编码绿 / 黄 / 红）。
class _SyncResultTile extends StatelessWidget {
  const _SyncResultTile({required this.report});

  final SyncReport report;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final Color accent = report.isSuccess
        ? (report.hasChanges ? theme.success : theme.onBackground.withValues(alpha: 0.6))
        : (report.isRetryable ? theme.warning : theme.error);

    return Container(
      margin: EdgeInsets.only(top: theme.gridGap * 2),
      padding: EdgeInsets.all(theme.cardPadding),
      decoration: BoxDecoration(
        // 极浅的强调色底：让结果区与上面的操作行区分开，又不抢眼。
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
                    ? (report.hasChanges ? Icons.check_circle_outline : Icons.info_outline)
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
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground,
              ),
            ),
          ],
          if (report.isSuccess) ...<Widget>[
            SizedBox(height: theme.gridGap * 2),
            _detailLine(context, '新增 ${report.added} · 更新 ${report.updated} · '
                '未变 ${report.unchanged}'),
            if (report.skipped > 0)
              _detailLine(context, '跳过 ${report.skipped} 条（数据不完整）'),
            // 这一行是"用户改动没有被同步冲掉"的可见证据。
            if (report.userEdited > 0)
              _detailLine(context, '其中 ${report.userEdited} 门保留了你的修改'),
            if (report.sectionTimes > 0)
              _detailLine(context, '节次时间 ${report.sectionTimes} 条'),
            if (report.allUnits != null)
              _detailLine(context, '总学分 ${report.allUnits}'),
          ],
          if (report.attempts > 1)
            _detailLine(context, '共尝试 ${report.attempts} 次'),
          if (report.warnings.isNotEmpty) ...<Widget>[
            SizedBox(height: theme.gridGap * 2),
            for (final String warning
                in report.warnings.take(kMaxVisibleSyncWarnings))
              Text(
                '· $warning',
                style: TextStyle(
                  fontSize: theme.captionSize,
                  color: theme.warning,
                ),
              ),
            if (report.warnings.length > kMaxVisibleSyncWarnings)
              Text(
                '· 另有 ${report.warnings.length - kMaxVisibleSyncWarnings} 条警告，详见日志',
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
          return '插件执行超时';
        case SyncOutcome.unavailable:
          return '插件不可用';
        case SyncOutcome.unsupported:
          return '该插件不支持课程同步';
        case SyncOutcome.protocolError:
          return '数据无法识别';
        case SyncOutcome.failed:
        case SyncOutcome.success:
          return '同步失败';
      }
    }
    if (!report.hasChanges) {
      return report.totalCourses == 0 ? '这学期没有课程' : '已是最新';
    }
    return '同步成功';
  }

  Widget _detailLine(BuildContext context, String text) {
    final AppTheme theme = AppThemeExtension.of(context);
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
