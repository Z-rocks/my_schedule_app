// 运行日志查看页：分级筛选、展开详情、导出给开发者。
//
// ## 为什么要有这个页面
//
// 这个 App 没有后端，开发者拿不到任何运行时信息。用户报"同步失败"时，
// 唯一的线索就是设备上的日志——所以这个页面不是给开发者用的调试面板，
// 而是**用户把问题交出去的出口**：
//
//   出问题 → 打开设置 → 运行日志 → 导出并发送 → 发给我
//
// 因此文案全部面向用户（不是 `Level.DEBUG` 而是"调试"），
// 并且要能一眼看出"有没有错误"。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_log.dart';
import '../../services/log_export_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';

/// 运行日志页。
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  /// 当前筛选级别（`null` = 全部）。
  LogLevel? _filter;

  /// 导出中（防重入 + 按钮 loading）。
  bool _exporting = false;

  /// 上次渲染时的条数：只有条数变化才重建，避免每秒白刷 3000 行。
  int _lastCount = -1;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    AppLog.action('log_view_open');
    // 日志会持续产生（用户可能一边复现问题一边看），每秒对一次条数。
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (!mounted) return;
      if (AppLog.snapshot().length != _lastCount) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  List<LogEntry> get _visible {
    final List<LogEntry> all = AppLog.snapshot();
    final List<LogEntry> filtered = _filter == null
        ? all
        : all.where((LogEntry e) => e.level.index >= _filter!.index).toList();
    // 新的在上面：用户关心的是"刚刚发生了什么"。
    return filtered.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final List<LogEntry> entries = _visible;
    _lastCount = AppLog.snapshot().length;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('运行日志'),
        centerTitle: true,
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenu,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'copy',
                child: Text('复制当前内容'),
              ),
              const PopupMenuItem<String>(
                value: 'clear',
                child: Text('清空日志'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildSummary(theme),
          _buildFilters(theme),
          Divider(
            height: 1,
            color: theme.onBackground.withValues(alpha: 0.08),
          ),
          Expanded(
            child: entries.isEmpty
                ? _buildEmpty(theme)
                : ListView.separated(
                    padding: EdgeInsets.symmetric(vertical: theme.gridGap * 2),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: theme.cardPadding,
                      endIndent: theme.cardPadding,
                      color: theme.onBackground.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (BuildContext context, int index) =>
                        _buildEntry(theme, entries[index]),
                  ),
          ),
          _buildExportBar(theme),
        ],
      ),
    );
  }

  // ───────────────────── 顶部统计 ─────────────────────

  Widget _buildSummary(AppTheme theme) {
    final DateTime? first = AppLog.firstTime;
    final DateTime? last = AppLog.lastTime;
    final int total = AppLog.snapshot().length;
    final int errors = AppLog.countAtLeast(LogLevel.error);
    final int warns = AppLog.countAtLeast(LogLevel.warn);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        theme.cardPadding,
        theme.gridGap * 2,
        theme.cardPadding,
        theme.gridGap,
      ),
      padding: EdgeInsets.all(theme.cardPadding),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            AppLog.isReady ? '近 24 小时共 $total 条记录' : '日志系统不可用',
            style: TextStyle(
              fontSize: theme.bodySize,
              fontWeight: theme.titleFontWeight,
              color: theme.onBackground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLog.isReady
                ? '${errors > 0 ? '错误 $errors 条' : '无错误'}'
                    '${warns > 0 ? '，警告 $warns 条' : ''}'
                : (AppLog.initError.isEmpty ? '未知原因' : AppLog.initError),
            style: TextStyle(
              fontSize: theme.captionSize,
              color: errors > 0
                  ? _levelColor(theme, LogLevel.error)
                  : theme.onBackground.withValues(alpha: 0.6),
            ),
          ),
          if (first != null && last != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              '${_formatDate(first)} ~ ${_formatTime(last)}',
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.45),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilters(AppTheme theme) {
    // 「全部」+ 三个级别；点已选中的项取消筛选。
    final List<({String label, LogLevel? level})> options =
        <({String label, LogLevel? level})>[
      (label: '全部', level: null),
      (label: '错误', level: LogLevel.error),
      (label: '警告及以上', level: LogLevel.warn),
      (label: '信息及以上', level: LogLevel.info),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: theme.cardPadding),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final ({String label, LogLevel? level}) option = options[index];
          final bool selected = _filter == option.level;
          return Center(
            child: ChoiceChip(
              label: Text(option.label),
              selected: selected,
              onSelected: (_) => setState(() => _filter = option.level),
              labelStyle: TextStyle(
                fontSize: theme.captionSize,
                color: selected ? theme.background : theme.onBackground,
              ),
              selectedColor: theme.primary,
              backgroundColor: theme.surface,
              side: BorderSide(
                color: theme.onBackground.withValues(alpha: 0.12),
              ),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(AppTheme theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.receipt_long_outlined,
            size: 40,
            color: theme.onBackground.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 12),
          Text(
            _filter == null ? '还没有日志' : '没有符合条件的日志',
            style: TextStyle(
              fontSize: theme.bodySize,
              color: theme.onBackground.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────── 单条 ─────────────────────

  Widget _buildEntry(AppTheme theme, LogEntry entry) {
    final Color color = _levelColor(theme, entry.level);
    final bool isToday = _isToday(entry.time);

    return InkWell(
      onTap: () => _showDetail(entry),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.cardPadding,
          vertical: theme.gridGap,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 时间列：今天只显示时分秒，跨天带上日期。
            SizedBox(
              width: isToday ? 62 : 96,
              child: Text(
                isToday
                    ? _formatTime(entry.time)
                    : '${_formatDate(entry.time)} ${_formatTime(entry.time)}',
                style: TextStyle(
                  fontSize: theme.captionSize - 1,
                  height: 1.4,
                  fontFamily: 'monospace',
                  color: theme.onBackground.withValues(alpha: 0.45),
                ),
              ),
            ),
            // 级别色条：扫一眼就能找到红色那几条。
            Container(
              width: 3,
              height: 16,
              margin: const EdgeInsets.only(right: 8, top: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: '[${entry.tag}] ',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: entry.message),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: theme.captionSize,
                      height: 1.4,
                      color: theme.onBackground,
                    ),
                  ),
                  if (entry.hasDetail)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        entry.error != null ? '点开看错误详情' : '点开看附加信息',
                        style: TextStyle(
                          fontSize: theme.captionSize - 2,
                          color: theme.onBackground.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetail(LogEntry entry) async {
    final AppTheme theme = AppThemeExtension.of(context);
    final StringBuffer buffer = StringBuffer()
      ..writeln(entry.toLine());
    if (entry.stack != null && entry.stack!.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln(entry.stack);
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.3,
        builder: (BuildContext context, ScrollController controller) {
          return Column(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  theme.cardPadding,
                  theme.cardPadding,
                  theme.cardPadding,
                  theme.gridGap,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _levelColor(theme, entry.level),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.level.label} · ${entry.tag}',
                      style: TextStyle(
                        fontSize: theme.bodySize,
                        fontWeight: theme.titleFontWeight,
                        color: theme.onBackground,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_formatDate(entry.time)} ${_formatTime(entry.time)}',
                      style: TextStyle(
                        fontSize: theme.captionSize,
                        color: theme.onBackground.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: EdgeInsets.fromLTRB(
                    theme.cardPadding,
                    0,
                    theme.cardPadding,
                    theme.cardPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _detailBlock(
                        theme,
                        '内容',
                        entry.message,
                      ),
                      if (entry.data.isNotEmpty)
                        _detailBlock(
                          theme,
                          '附加信息',
                          const JsonEncoder.withIndent('  ').convert(entry.data),
                        ),
                      if (entry.error != null)
                        _detailBlock(theme, '错误', entry.error!),
                      if (entry.stack != null && entry.stack!.trim().isNotEmpty)
                        _detailBlock(theme, '堆栈', entry.stack!),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.all(theme.cardPadding),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_all, size: 18),
                      label: const Text('复制这条日志'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: buffer.toString()),
                        );
                        if (!sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop();
                        _snack('已复制');
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailBlock(AppTheme theme, String title, String content) {
    return Padding(
      padding: EdgeInsets.only(bottom: theme.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: theme.captionSize,
              fontWeight: theme.titleFontWeight,
              color: theme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              content,
              style: TextStyle(
                fontSize: theme.captionSize,
                height: 1.5,
                fontFamily: 'monospace',
                color: theme.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────── 导出 ─────────────────────

  Widget _buildExportBar(AppTheme theme) {
    final int problems = AppLog.countAtLeast(LogLevel.warn);

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.all(theme.cardPadding),
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border(
            top: BorderSide(
              color: theme.onBackground.withValues(alpha: 0.08),
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: _exporting ? null : () => _export(problemsOnly: false),
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share, size: 18),
                label: Text(_exporting ? '正在生成…' : '导出并发送'),
              ),
            ),
            const SizedBox(width: 8),
            // 日志量大时（几千条）用户只想发"出问题那部分"。
            if (problems > 0)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _exporting ? null : () => _export(problemsOnly: true),
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: Text('仅问题($problems)'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _export({required bool problemsOnly}) async {
    if (_exporting) return;
    setState(() => _exporting = true);

    final LogExportResult result =
        await LogExportService.share(problemsOnly: problemsOnly);

    if (!mounted) return;
    setState(() => _exporting = false);

    if (!result.ok) {
      _snack(result.message);
      return;
    }
    if (result.shared) {
      _snack('已生成日志，选择微信 / QQ / 邮件发给我即可');
      return;
    }
    // 分享面板拉不起来：把路径给用户，至少还有办法自己取。
    await _showFallbackDialog(result);
  }

  Future<void> _showFallbackDialog(LogExportResult result) async {
    final String path = result.file?.path ?? '';
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('已生成日志文件'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('这台设备上没有可用的分享应用。文件已保存到：'),
            const SizedBox(height: 8),
            SelectableText(
              path,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            const Text(
              '可以把这个路径发给我，或者先用文件管理器把它拷出来。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('复制路径'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ───────────────────── 菜单 ─────────────────────

  Future<void> _onMenu(String value) async {
    if (value == 'clear') {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('清空日志'),
          content: const Text('将删除设备上的全部运行日志，不影响课程与设置数据。'),
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
      if (confirmed != true || !mounted) return;
      await AppLog.clear();
      if (!mounted) return;
      setState(() {});
      _snack('日志已清空');
      return;
    }

    if (value == 'copy') {
      final String text = AppLog.buildExportText(
        header: '（复制自 App 运行日志页）',
      );
      // 剪贴板对超大文本不友好，且部分输入法会卡；超长就截断并说明。
      const int limit = 200000;
      final String clipped = text.length > limit
          ? '${text.substring(0, limit)}\n…（已截断，完整日志请用「导出并发送」）'
          : text;
      await Clipboard.setData(ClipboardData(text: clipped));
      if (!mounted) return;
      _snack('已复制到剪贴板');
    }
  }

  // ───────────────────── 工具 ─────────────────────

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static Color _levelColor(AppTheme theme, LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return const Color(0xFFE5484D);
      case LogLevel.warn:
        return const Color(0xFFF5A524);
      case LogLevel.info:
        return theme.primary;
      case LogLevel.debug:
        return theme.onBackground.withValues(alpha: 0.35);
    }
  }

  static bool _isToday(DateTime t) {
    final DateTime now = DateTime.now();
    return t.year == now.year && t.month == now.month && t.day == now.day;
  }

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  static String _formatDate(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)}';
  }
}
