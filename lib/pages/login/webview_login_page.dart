// Phase 4.1：通用 WebView 登录页（登录 + Cookie 提取）。
//
// **本页是通用组件**：不硬编码任何学校 URL、不依赖任何学校页面结构
// （CONTEXT 3.1：内核不知道任何具体学校的 URL / 字段名）。
// 登录地址与成功判定条件都由调用方（Phase 4.2 起是插件的 manifest）传入。
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/cookie_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';

/// 判定"当前 URL 是否表示登录成功"。
///
/// 这是**主方案**（Phase 4.1 决策 1 的方案 A：URL 前缀匹配）：
/// 通用、不需要知道任何学校的页面结构、失败模式可预期。
///
/// 纯函数，便于单测（不需要真的起一个 WebView）。
/// 空前缀（未声明）时返回 `false` —— 表示"不靠 URL 判定"，
/// 由调用方退化为"拿到任意 Cookie 即视为成功"的兜底策略。
bool isLoginSuccessUrl(String currentUrl, String successUrlPrefix) {
  final String prefix = successUrlPrefix.trim();
  if (prefix.isEmpty) return false;
  return currentUrl.trim().startsWith(prefix);
}

/// 通用 WebView 登录页。
///
/// 打开 [loginUrl]；当 WebView 的当前 URL 命中 [successUrlPrefix] **且拿到 Cookie**
/// 时判定登录成功，pop 返回 Cookie 字符串（HTTP 头格式，见 `CookieService.formatCookies`）。
///
/// - **用户手动返回** → `pop(null)`，不写任何东西（决策 4）
/// - [pluginId] 非空时，本页会在返回前把 Cookie 存进 `flutter_secure_storage`
///   （key = `<pluginId>:cookie`）；为空则只返回，由调用方自己保存
/// - [successUrlPrefix] 为空 → 退化为"拿到任意 Cookie 即视为成功"（兜底策略）
class WebViewLoginPage extends StatefulWidget {
  const WebViewLoginPage({
    super.key,
    required this.loginUrl,
    required this.successUrlPrefix,
    this.title,
    this.pluginId,
  });

  /// 登录页地址。
  final String loginUrl;

  /// 登录成功判定的 URL 前缀；空串表示未声明（走 Cookie 兜底）。
  final String successUrlPrefix;

  /// AppBar 标题，默认"登录"。
  final String? title;

  /// 插件 id；非空时本页负责把 Cookie 落盘。
  final String? pluginId;

  @override
  State<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends State<WebViewLoginPage> {
  late final WebViewController _controller;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();

  bool _loading = true;
  String? _error;

  /// 是否已经判定成功过——防止"多次 onPageFinished"导致重复 pop。
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: _onPageStarted,
          onPageFinished: _onPageFinished,
          onWebResourceError: _onWebResourceError,
        ),
      );
    _load();
  }

  /// 加载登录页；URL 非法时不崩，直接显示错误。
  void _load() {
    final Uri? uri = Uri.tryParse(widget.loginUrl.trim());
    final bool valid = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!valid) {
      setState(() {
        _loading = false;
        _error = '登录地址无效：${widget.loginUrl}';
      });
      return;
    }
    _controller.loadRequest(uri);
  }

  void _onPageStarted(String url) {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
  }

  Future<void> _onPageFinished(String url) async {
    if (!mounted) return;
    setState(() => _loading = false);
    await _maybeFinish(url);
  }

  void _onWebResourceError(WebResourceError error) {
    // 子资源（图片 / CSS）失败不该当成整页失败。
    if (error.isForMainFrame == false) return;
    if (!mounted) return;
    debugPrint('[WebViewLoginPage] 加载失败：${error.errorCode} ${error.description}');
    setState(() {
      _loading = false;
      _error = '页面加载失败（${error.errorCode}）：${error.description}';
    });
  }

  /// 判断是否登录成功；成功则提取 Cookie 并返回。
  Future<void> _maybeFinish(String url) async {
    if (_finished) return;

    final bool byUrl = isLoginSuccessUrl(url, widget.successUrlPrefix);
    // 未声明成功前缀 → 兜底策略：拿到任意 Cookie 即视为成功。
    final bool cookieFallback = widget.successUrlPrefix.trim().isEmpty;
    if (!byUrl && !cookieFallback) return;

    final String cookie = await _collectCookieString(url);

    if (byUrl) {
      if (cookie.isEmpty) {
        // URL 命中了却没拿到凭证 —— 这种"成功"没有意义，继续等下一页。
        debugPrint('[WebViewLoginPage] URL 已匹配前缀但未拿到 Cookie，继续等待：$url');
        return;
      }
      await _finish(cookie);
      return;
    }

    if (cookie.isNotEmpty) {
      debugPrint('[WebViewLoginPage] 未声明成功前缀，按"拿到 Cookie"判定成功');
      await _finish(cookie);
    }
  }

  /// 提取并落盘（可选）Cookie，然后带着它 pop。
  Future<void> _finish(String cookie) async {
    _finished = true;
    final String? pluginId = widget.pluginId;
    if (pluginId != null && pluginId.isNotEmpty) {
      await CookieService.saveCookie(pluginId, cookie);
      debugPrint('[WebViewLoginPage] 已保存 $pluginId 的 Cookie（${cookie.length} 字符）');
    }
    if (!mounted) return;
    Navigator.of(context).pop(cookie);
  }

  /// 收集 Cookie 并拼成 HTTP 头格式。
  ///
  /// 同时查**登录页域名**与**当前页域名**：会话 Cookie 通常落在登录页那个域上，
  /// 但登录成功后可能跳到同域的另一个路径（甚至另一台主机），两边都查更稳。
  /// 同名 Cookie 以"后查到的"为准（顺序：登录页 → 当前页）。
  Future<String> _collectCookieString(String currentUrl) async {
    final Map<String, WebViewCookie> byName = <String, WebViewCookie>{};
    for (final String candidate in <String>[widget.loginUrl, currentUrl]) {
      final Uri? uri = Uri.tryParse(candidate.trim());
      if (uri == null || uri.host.isEmpty) continue;
      try {
        for (final WebViewCookie cookie
            in await _cookieManager.getCookies(domain: uri)) {
          byName[cookie.name] = cookie;
        }
      } catch (e) {
        // 读不到就跳过：某些平台对 domain 参数有要求，不该因此崩掉登录流程。
        debugPrint('[WebViewLoginPage] 读取 $uri 的 Cookie 失败：$e');
      }
    }
    final String formatted = CookieService.formatCookies(byName.values.toList());
    debugPrint('[WebViewLoginPage] 提取到 ${byName.length} 个 Cookie，'
        '拼接后 ${formatted.length} 字符');
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(widget.title ?? '登录'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              setState(() {
                _error = null;
                _loading = true;
              });
              _controller.reload();
            },
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(AppTheme theme) {
    final String? error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(theme.cardPadding * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: theme.titleSize * 3,
                color: theme.error,
              ),
              SizedBox(height: theme.sectionGap),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: theme.bodySize,
                  color: theme.onBackground,
                ),
              ),
              SizedBox(height: theme.sectionGap),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _loading = true;
                  });
                  _load();
                },
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

    return Stack(
      children: <Widget>[
        WebViewWidget(controller: _controller),
        if (_loading)
          LinearProgressIndicator(
            minHeight: theme.gridGap,
            backgroundColor: theme.surface,
            color: theme.primary,
          ),
      ],
    );
  }
}
