// 插件详情页：展示单个插件的元信息、运行时状态与操作入口
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../models/plugin_meta.dart';
import '../../providers/course_provider.dart';
import '../../providers/plugin_provider.dart';
import '../../runtime/js_sandbox.dart';
import '../../runtime/plugin_handle.dart';
import '../../runtime/plugin_manifest.dart';
import '../../services/cookie_service.dart';
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

/// 同步时单次 JS 执行的墙钟上限。
///
/// 比默认的 1s 宽：一次同步要解析整学期课表（几十门课 + 上百条时间地点），
/// 而 HTTP 请求本身发生在宿主侧（dio），**不受这个超时约束**。
const Duration kSyncJsTimeout = Duration(seconds: 5);

/// 插件详情页。
///
/// 数据全部来自 `PluginProvider`（`context.watch` 保证启停 / 加载结果实时反映）。
/// 安装路径是**异步**读的（`PluginStorageService.getPluginJsPath`），
/// 用 `FutureBuilder` 展示。
class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({super.key, required this.pluginId});

  /// 要展示的插件 id。插件被卸载后本页会显示"插件不存在"。
  final String pluginId;

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
              // "立即同步" Phase 4.2 起接真实同步（见 _syncNow）。
              _ActionRow(
                icon: Icons.sync,
                label: '立即同步',
                onTap: () => _syncNow(context, provider, meta, handle),
              ),
              _ActionRow(
                icon: Icons.article_outlined,
                label: '查看日志',
                onTap: () => _snack(context, '查看日志（Phase 3 后实现）'),
              ),
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

  /// 把同步请求收窄成一次（防重复点击的简单闩锁）。
  ///
  /// 本页是 `StatelessWidget`（Phase 4.1 起就没引状态），为一次防抖而改造成
  /// StatefulWidget 不划算；用一个 `try/finally` 保证必被复位的静态闩锁即可。
  /// Phase 4.4 做同步进度 UI 时再改成页内状态。
  static bool _syncing = false;

  /// 「立即同步」：读 Cookie → 调插件 `fetchCourses` → 解析 → 落盘（Phase 4.2）。
  ///
  /// **关键点**：
  /// - 插件负责"拉数据 + 转成内核的 Course JSON"（各校字段不同，内核不认识，见 CONTEXT 3.1）；
  /// - Dart 侧只做**容错解析 + 落盘**：单条课程字段缺失/类型不符就跳过并 `debugPrint`，
  ///   不让一条坏数据毁掉整次同步；
  /// - `fetchCourses` 可能被执行多次（`ctx.http` 重放，见 CONTEXT 3.6），
  ///   但插件是幂等的、宿主只在最终轮提交副作用，所以这里不需要去重。
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
    if (handle == null || !handle.isUsable) {
      messenger.showSnackBar(
        SnackBar(content: Text('插件未加载，无法同步：${handle?.reason ?? '未加载'}')),
      );
      return;
    }

    _syncing = true;
    messenger.showSnackBar(const SnackBar(content: Text('正在同步，请稍候…')));
    try {
      final JsSandboxResult result = await handle.execute(
        'fetchCourses',
        timeout: kSyncJsTimeout,
      );

      if (result.status == JsSandboxStatus.timeout) {
        messenger.showSnackBar(
          const SnackBar(content: Text('同步超时（插件执行过久）')),
        );
        return;
      }
      if (result.status == JsSandboxStatus.unavailable) {
        messenger.showSnackBar(
          SnackBar(content: Text('同步失败：${result.message ?? '插件不可用'}')),
        );
        return;
      }
      if (!result.isSuccess || result.value == null) {
        messenger.showSnackBar(
          SnackBar(content: Text('同步失败：${result.message ?? '插件返回异常'}')),
        );
        return;
      }

      final Object? decoded = _tryDecode(result.value!);
      if (decoded is! Map) {
        messenger.showSnackBar(
          const SnackBar(content: Text('同步失败：插件返回值不是 JSON 对象')),
        );
        return;
      }

      // 插件约定：失败返回 {error: '...'}，成功返回 {courses: [...]}
      final String? pluginError = decoded['error']?.toString();
      if (pluginError != null && pluginError.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text('同步失败：$pluginError')));
        return;
      }

      final List<Course> parsed = _parseCourses(decoded['courses']);
      if (parsed.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('同步完成，但没有解析到任何课程')),
        );
        return;
      }

      for (final Course course in parsed) {
        await courses.saveCourse(course);
      }

      final List<String> warnings = _stringList(decoded['warnings']);
      debugPrint('[PluginDetailPage] 同步完成：写入 ${parsed.length} 门课程'
          '${warnings.isEmpty ? '' : '，警告：${warnings.join('；')}'}');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已同步 ${parsed.length} 门课程'
            '${warnings.isEmpty ? '' : '（${warnings.length} 条警告，详见日志）'}',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[PluginDetailPage] 同步异常：$e');
      messenger.showSnackBar(SnackBar(content: Text('同步异常：$e')));
    } finally {
      _syncing = false;
    }
  }

  /// 逐条把插件返回的课程 JSON 解析成 [Course]；坏数据跳过，不抛异常。
  static List<Course> _parseCourses(Object? raw) {
    if (raw is! List) return const <Course>[];
    final List<Course> result = <Course>[];
    for (int i = 0; i < raw.length; i++) {
      final Object? item = raw[i];
      if (item is! Map) {
        debugPrint('[PluginDetailPage] 第 $i 条课程不是对象，已跳过');
        continue;
      }
      final Map<String, dynamic> json = <String, dynamic>{};
      item.forEach((dynamic k, dynamic v) {
        if (k != null) json['$k'] = v;
      });
      try {
        final Course course = Course.fromJson(json);
        if (course.id.isEmpty) {
          debugPrint('[PluginDetailPage] 第 $i 条课程缺少 id，已跳过');
          continue;
        }
        result.add(course);
      } catch (e) {
        // Course.fromJson 本身已经很宽容，这里只是最后一道保险。
        debugPrint('[PluginDetailPage] 第 $i 条课程解析失败，已跳过：$e');
      }
    }
    return result;
  }

  static Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (e) {
      debugPrint('[PluginDetailPage] 解析插件返回值失败：$e');
      return null;
    }
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw.whereType<Object?>().map((Object? e) => '$e').toList();
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
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.primary),
      title: Text(
        label,
        style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.onBackground.withValues(alpha: 0.3),
      ),
      onTap: onTap,
    );
  }
}
