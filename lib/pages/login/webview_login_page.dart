// Phase 4.1：通用 WebView 登录页（登录 + Cookie 提取）。
// Phase 4.2.1：新增 SSL 证书错误处理（**只放行登录 URL 的 host**）+ 诊断日志。
//
// **本页是通用组件**：不硬编码任何学校 URL、不依赖任何学校页面结构
// （CONTEXT 3.1：内核不知道任何具体学校的 URL / 字段名）。
// 登录地址与成功判定条件都由调用方（Phase 4.2 起是插件的 manifest）传入。
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/cookie_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';

/// 去掉 URL 的 scheme（`http://` / `https://`），其余原样保留。
///
/// 只剥离开头那一段，不做别的规范化——本函数只服务于
/// [isLoginSuccessUrl] 的"同一站点、scheme 可能不同"判断。
String _stripUrlScheme(String url) =>
    url.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');

/// 判定"当前 URL 是否表示登录成功"。
///
/// 这是**主方案**（Phase 4.1 决策 1 的方案 A：URL 前缀匹配）：
/// 通用、不需要知道任何学校的页面结构、失败模式可预期。
///
/// **scheme 不敏感**（Phase 8 真机实测追加）：很多站点登录成功后会在
/// http / https 之间跳一次。例如学习通登录成功会 302 到
/// `http://i.mooc.chaoxing.com/...`，而插件按惯例声明的是
/// `https://i.mooc.chaoxing.com/` —— 若按字面前缀匹配就永远命中不了，
/// 表现为"登录明明成功了，登录页却卡住不返回"。
/// 因此先按原样比，不中再剥掉 scheme 比一次；两者都只在**开头**匹配，
/// 不会把 `https://evil.com/http://i.mooc...` 这类 URL 误判为成功。
///
/// 纯函数，便于单测（不需要真的起一个 WebView）。
/// 空前缀（未声明）时返回 `false` —— 表示"不靠 URL 判定"，
/// 由调用方退化为"拿到任意 Cookie 即视为成功"的兜底策略。
bool isLoginSuccessUrl(String currentUrl, String successUrlPrefix) {
  final String prefix = successUrlPrefix.trim();
  if (prefix.isEmpty) return false;
  final String url = currentUrl.trim();
  if (url.startsWith(prefix)) return true;
  return _stripUrlScheme(url).startsWith(_stripUrlScheme(prefix));
}

/// 把 path 归一化：空串视为 `/`，去掉末尾多余的 `/`。
///
/// 只用于"是不是同一个页面"的比较，不做 URL 解码 / 参数处理。
String _normalizedPath(String path) {
  String p = path.trim();
  if (p.isEmpty) return '/';
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// 两个 URL 是否属于同一主机（大小写不敏感）。
bool isSameHost(String a, String b) {
  final String hostA = _hostOf(a);
  final String hostB = _hostOf(b);
  return hostA.isNotEmpty && hostA == hostB;
}

/// 判定"当前页是否还停在**登录表单页**（即用户尚未登录）"。
///
/// 两条依据（任一成立即算表单页）：
/// 1. 与 [loginUrl] 同主机、**path 相同**——用户还停在插件声明的登录入口上；
/// 2. path 里含常见的登录路径关键词（`login` / `signin` / `cas` / `passport`…）。
///
/// **为什么比 path 而不是整串前缀**：插件常把 [loginUrl] 声明成站点根
/// （如 `https://xjw1.ncst.edu.cn/`）。用前缀比较的话，该站点的**任何**页面
/// 都以它开头，永远判不出"已经离开登录页"，自动跳转就永远不会触发。
///
/// 纯函数，便于单测。
bool isLoginFormUrl({required String currentUrl, required String loginUrl}) {
  final Uri? current = Uri.tryParse(currentUrl.trim());
  final Uri? login = Uri.tryParse(loginUrl.trim());
  if (current == null || login == null) return false;
  if (!isSameHost(currentUrl, loginUrl)) return false;

  if (_normalizedPath(current.path) == _normalizedPath(login.path)) return true;

  final String path = current.path.toLowerCase();
  for (final String keyword in const <String>[
    'login',
    'signin',
    'sign_in',
    'sign-in',
    'passport',
    'cas',
  ]) {
    if (path.contains(keyword)) return true;
  }
  return false;
}

/// 是否应该"登录后自动导航"到 `postLoginUrl`。
///
/// 触发条件（全部满足）：
/// - 插件声明了 `postLoginUrl`（空串 = 不启用，老插件行为不变）；
/// - 本轮还没自动导航过（避免在同一页反复跳）；
/// - 当前 URL 尚未命中 [successUrlPrefix]（已经到了目标就不必再跳）；
/// - 当前仍在**登录站点自己**的页面上（跨域跳转不介入——CAS 单点登录的
///   认证链路常在多个域之间来回，插手会把用户从流程中间踢走）；
/// - 当前**不是**登录表单页（见 [isLoginFormUrl]）。
///
/// 纯函数，便于单测（真实的导航行为无法在 `flutter test` 里跑）。
bool shouldAutoNavigateAfterLogin({
  required String currentUrl,
  required String loginUrl,
  required String successUrlPrefix,
  required String postLoginUrl,
  required bool alreadyNavigated,
}) {
  if (postLoginUrl.trim().isEmpty) return false;
  if (alreadyNavigated) return false;
  if (isLoginSuccessUrl(currentUrl, successUrlPrefix)) return false;
  if (!isSameHost(currentUrl, loginUrl)) return false;
  return !isLoginFormUrl(currentUrl: currentUrl, loginUrl: loginUrl);
}

/// 判定"这个 SSL 证书错误该不该放行"，返回**放行后允许的 host**；
/// 返回 `null` 表示**拒绝**（`cancel`）。
///
/// **只对 [loginUrl] 的 host 放行**——这是 Phase 4.2.1 的硬约束：
/// 学校教务系统用自签 / 不受信证书是常态（浏览器会提示"继续访问"，
/// 而 WebView 默认直接拒绝），但**绝不能全局放行**，
/// 否则登录流程里任何第三方域名的证书错误都会被静默接受。
///
/// 匹配规则（`errorUrl` 里含登录 host 是**必要**条件）：
/// - 精确同主机：`xjw1.ncst.edu.cn` == `xjw1.ncst.edu.cn` ✅
/// - 同主域的子域：`auth.xjw1.ncst.edu.cn` 的后缀是 `.xjw1.ncst.edu.cn` ✅
///   （教务系统常把认证跳转到另一台主机，那台主机的域名里必然带着它的父域）
/// - 反向则不成立：`xjw1.ncst.edu.cn.evil.com` ❌（它不以 `.<host>` 结尾）
/// - 登录 host 无法解析 / `errorUrl` 无主机 → 一律拒绝（fail closed）
///
/// 纯函数，便于单测（真实的 `SslAuthError` 无法在 `flutter test` 里构造）。
String? sslErrorHostToProceedOn({
  required String loginUrl,
  required String errorUrl,
}) {
  final String allowedHost = _hostOf(loginUrl);
  if (allowedHost.isEmpty) return null;

  final String errorHost = _hostOf(errorUrl);
  if (errorHost.isEmpty) return null;

  if (errorHost == allowedHost ||
      errorHost.endsWith('.$allowedHost') ||
      allowedHost.endsWith('.$errorHost')) {
    return allowedHost;
  }
  return null;
}

/// 从 URL 里取出**小写主机名**；解析不出主机时返回空串。
///
/// 兼容两种情况：带 scheme 的绝对 URL，以及只有主机名的裸串
/// （个别平台回调给的可能不是完整 URL）。
String _hostOf(String url) {
  final String trimmed = url.trim();
  if (trimmed.isEmpty) return '';

  final Uri? parsed = Uri.tryParse(trimmed);
  final String byParse = parsed?.host.trim().toLowerCase() ?? '';
  if (byParse.isNotEmpty) return byParse;

  final String hostPart = Uri.tryParse('https://$trimmed')?.host ?? '';
  return hostPart.trim().toLowerCase();
}

/// 把 WebView 的原始英文错误，翻译成一句**能直接照着排查**的人话提示。
///
/// 起因（Phase 8 真机实测）：学习通登录成功后 302 到 http，
/// 被 Android 的明文 HTTP 策略拦成 `net::ERR_CLEARTEXT_NOT_PERMITTED`。
/// 界面上原本只有一句英文原始报错，看到它的人无法一眼判断"该改哪里"——
/// 很容易误以为是"接口挂了"或"网络不通"（其实请求**根本没有发出去**）。
///
/// 返回 `null` 表示没有对应提示，界面就只显示原始报错。
///
/// 纯函数，便于单测。
String? loadErrorHint(String description) {
  final String d = description.toLowerCase();
  if (d.contains('err_cleartext_not_permitted')) {
    return '该站点走的是明文 HTTP（http://），被 Android 的网络策略拦下了。\n'
        '注意：这不是网络不通、也不是接口报错——请求根本没有发出去。\n'
        '解决：把该站点域名加进 android/app/src/main/res/xml/'
        'network_security_config.xml 的白名单，然后重新打包安装。';
  }
  if (d.contains('err_name_not_resolved')) {
    return '域名解析失败：多半是断网、DNS 异常，或该站点在当前网络下不可达。';
  }
  if (d.contains('err_internet_disconnected')) {
    return '设备当前没有网络连接。';
  }
  if (d.contains('err_timed_out') || d.contains('err_connection_timed_out')) {
    return '连接超时：站点无响应，或当前网络（校园网 / VPN）不允许访问。';
  }
  if (d.contains('err_connection_refused')) {
    return '连接被拒绝：对方端口没开，或这个地址已经失效。';
  }
  if (d.contains('err_ssl') || d.contains('err_cert')) {
    return 'SSL 证书校验失败：站点用了自签 / 过期证书。'
        '若确认该站点可信，重新进入登录页时会按登录站点 host 放行。';
  }
  return null;
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
/// - **SSL 证书错误（Phase 4.2.1）**：只对 [loginUrl] 的 host 放行，其他域名拒绝
///   （见 [sslErrorHostToProceedOn]）；放行后页面顶部显示一条黄色警告条
///   （`theme.warning`），并且**抑制同一 host 紧随其后的 `onWebResourceError` 报错页**
class WebViewLoginPage extends StatefulWidget {
  const WebViewLoginPage({
    super.key,
    required this.loginUrl,
    required this.successUrlPrefix,
    this.postLoginUrl = '',
    this.title,
    this.pluginId,
  });

  /// 登录页地址。
  final String loginUrl;

  /// 登录成功判定的 URL 前缀；空串表示未声明（走 Cookie 兜底）。
  final String successUrlPrefix;

  /// 登录成功后自动导航到的地址（插件声明，空串表示不自动导航）。
  ///
  /// 很多教务系统登录后停在首页，而成功判定前缀指向更深的业务页
  /// （如"选课结果"），不自动导航的话用户得自己点过去，登录页才会返回。
  final String postLoginUrl;

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
  String? _loadError;

  /// 是否已经判定成功过——防止"多次 onPageFinished"导致重复 pop。
  bool _finished = false;

  /// 本轮是否已经自动导航到 [WebViewLoginPage.postLoginUrl]。
  ///
  /// 回到登录表单页时会重置：用户第一次没登上、被服务端重定向回登录页时，
  /// 再次登录后仍应能自动跳转（否则只有第一次有效，体验很怪）。
  bool _postLoginNavigated = false;

  /// **本轮加载**放行过 SSL 错误的 host（`null` 表示没放行过）。
  ///
  /// 两个用途：
  /// 1. 顶部黄色警告条的显隐；
  /// 2. 抑制"放行同一 host 的证书错误后，紧随其后的 `onWebResourceError`"
  ///    ——否则会出现"已经放行了，却还显示加载失败页"的自相矛盾状态。
  ///
  /// `onPageStarted` 时重置：下一次加载重新判定，不会残留上一轮的状态。
  String? _sslProceedHost;

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
          onSslAuthError: _onSslAuthError,
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
        _loadError = '登录地址无效：${widget.loginUrl}';
      });
      return;
    }
    _controller.loadRequest(uri);
  }

  void _onPageStarted(String url) {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
      // 新一轮加载：上一轮放行过的记录不再适用（见 `_sslProceedHost` 注释）。
      _sslProceedHost = null;
    });
  }

  Future<void> _onPageFinished(String url) async {
    if (!mounted) return;
    setState(() => _loading = false);
    await _maybeFinish(url);
  }

  void _onWebResourceError(WebResourceError error) {
    final String url = error.url ?? '';
    // ⚠️ 诊断日志：**不过滤子资源**，先全部打出来。
    // 真机排障时"看起来不相干的子资源错误"往往才是根因（如证书错误、
    // 明文 HTTP 被拦、DNS 失败），过滤掉就等于把线索丢了。
    debugPrint('[WebViewLoginPage] 加载失败: '
        'code=${error.errorCode} '
        'desc=${error.description} '
        'type=${error.errorType} '
        'mainFrame=${error.isForMainFrame} '
        'url=$url');

    // 子资源（图片 / CSS）失败不该当成整页失败。
    if (error.isForMainFrame == false) return;
    if (!mounted) return;

    // 同一 host 刚刚按用户意图放行了证书错误 → 不再展示"加载失败"页：
    // 放行后 WebView 常会为这次导航再报一次错，那时页面其实能正常用。
    final String? proceeded = _sslProceedHost;
    if (proceeded != null &&
        (proceeded == _hostOf(url) || url.trim().isEmpty)) {
      debugPrint('[WebViewLoginPage] 该错误发生在已放行证书的 host（$proceeded），不显示报错页');
      setState(() => _loading = false);
      return;
    }

    final String? hint = loadErrorHint(error.description);
    setState(() {
      _loading = false;
      _loadError = '页面加载失败（${error.errorCode}）：${error.description}'
          '${hint == null ? '' : '\n\n$hint'}';
    });
  }

  /// SSL 证书错误：**只放行登录 URL 的 host**（Phase 4.2.1）。
  ///
  /// 背景：教务系统常用自签 / 不受信证书。手机浏览器会提示"继续访问"，
  /// 而 WebView 默认**直接拒绝**——真机表现就是 `-1` 加载失败
  /// （Phase 4.2 曾误判为"网络不可达"）。
  ///
  /// 这里用框架层 4.14.1 就有的 [NavigationDelegate.onSslAuthError]：
  /// 它给出 `proceed()` / `cancel()`，**不需要引入 webview_flutter_android 直接依赖**。
  /// 该 API 的 [SslAuthError] 只公开 `certificate` / `cancel()` / `proceed()`，
  /// 描述文案要从平台实现对象 `error.platform.description` 取
  /// （这是框架层公开字段，不算平台特有 API）。
  /// **不含 URL**，所以用 `currentUrl()` 作为"出错页面地址"的等价信息源——
  /// 判定失败的代价只是"拒绝"（fail closed），不会误放行别的域名。
  Future<void> _onSslAuthError(SslAuthError error) async {
    final String detail = 'platform=${error.platform.description}';
    String currentUrl = '';
    try {
      currentUrl = await _controller.currentUrl() ?? '';
    } catch (e) {
      debugPrint('[WebViewLoginPage] 读取当前 URL 失败：$e');
    }

    final String? allowedHost = sslErrorHostToProceedOn(
      loginUrl: widget.loginUrl,
      errorUrl: currentUrl,
    );

    if (allowedHost == null) {
      debugPrint('[WebViewLoginPage] SSL 错误拒绝: url="$currentUrl" $detail'
          '（不在登录 host 内）');
      await error.cancel();
      return;
    }

    debugPrint('[WebViewLoginPage] SSL 错误放行: url="$currentUrl" '
        'host=$allowedHost $detail');
    await error.proceed();
    if (!mounted) return;
    // 记下放行事实：用于顶部警告条 + 抑制紧随其后的 onWebResourceError。
    setState(() => _sslProceedHost = allowedHost);
  }

  /// 判断是否登录成功；成功则提取 Cookie 并返回。
  ///
  /// 成功判定有两条路：URL 命中 [WebViewLoginPage.successUrlPrefix]，
  /// 或（未声明前缀时）拿到任意 Cookie。都没命中时，交给
  /// [_maybeAutoNavigate] 尝试"登录后自动导航"。
  Future<void> _maybeFinish(String url) async {
    if (_finished) return;

    final bool byUrl = isLoginSuccessUrl(url, widget.successUrlPrefix);
    // 未声明成功前缀 → 兜底策略：拿到任意 Cookie 即视为成功。
    final bool cookieFallback = widget.successUrlPrefix.trim().isEmpty;

    if (byUrl || cookieFallback) {
      final String cookie = await _collectCookieString(url);

      if (byUrl) {
        if (cookie.isNotEmpty) {
          await _finish(cookie);
          return;
        }
        // URL 命中了却没拿到凭证 —— 这种"成功"没有意义，继续等下一页。
        debugPrint('[WebViewLoginPage] URL 已匹配前缀但未拿到 Cookie，继续等待：$url');
      } else if (cookie.isNotEmpty) {
        debugPrint('[WebViewLoginPage] 未声明成功前缀，按"拿到 Cookie"判定成功');
        await _finish(cookie);
        return;
      }
    }

    await _maybeAutoNavigate(url);
  }

  /// 已离开登录表单页 → 自动导航到插件声明的 [WebViewLoginPage.postLoginUrl]。
  ///
  /// 这是"登录完不用自己点菜单"的关键（P1 修正）：教务系统登录后通常停在首页，
  /// 而成功判定前缀指向"选课结果"这类更深一层的页面。自动跳过去之后，
  /// 下一次 `onPageFinished` 就会命中前缀、正常返回。
  ///
  /// 安全阀：只跳一次；回到表单页时重置；跨域一律不介入（见
  /// [shouldAutoNavigateAfterLogin]）。
  Future<void> _maybeAutoNavigate(String url) async {
    final String target = widget.postLoginUrl.trim();
    if (target.isEmpty) return;

    // 回到登录表单页：重置标志，让用户下次登录后还能自动跳转。
    if (_postLoginNavigated &&
        isLoginFormUrl(currentUrl: url, loginUrl: widget.loginUrl)) {
      debugPrint('[WebViewLoginPage] 已回到登录表单页，重置自动跳转标志');
      if (mounted) setState(() => _postLoginNavigated = false);
      return;
    }

    final bool should = shouldAutoNavigateAfterLogin(
      currentUrl: url,
      loginUrl: widget.loginUrl,
      successUrlPrefix: widget.successUrlPrefix,
      postLoginUrl: target,
      alreadyNavigated: _postLoginNavigated,
    );
    if (!should) return;

    final Uri? uri = Uri.tryParse(target);
    if (uri == null || uri.host.isEmpty) {
      debugPrint('[WebViewLoginPage] postLoginUrl 非法，跳过自动导航：$target');
      return;
    }

    debugPrint('[WebViewLoginPage] 已离开登录表单页，自动导航到：$target');
    if (mounted) setState(() => _postLoginNavigated = true);
    await _controller.loadRequest(uri);
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
          // 兜底：个别教务系统的登录流程比较特殊，自动跳转可能不触发。
          // 给一个显式入口，用户看到"已经登录了"就能自己走下一步，
          // 不至于卡在首页出不去（没有声明 postLoginUrl 时不显示）。
          if (widget.postLoginUrl.trim().isNotEmpty)
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              tooltip: '已登录？直接进入下一步',
              onPressed: _goPostLogin,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              setState(() {
                _loadError = null;
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

  /// 手动跳到 [WebViewLoginPage.postLoginUrl]（AppBar 兜底按钮）。
  void _goPostLogin() {
    final Uri? uri = Uri.tryParse(widget.postLoginUrl.trim());
    if (uri == null || uri.host.isEmpty) return;
    setState(() {
      _postLoginNavigated = true;
      _loading = true;
      _loadError = null;
    });
    _controller.loadRequest(uri);
  }

  Widget _buildBody(AppTheme theme) {
    final String? error = _loadError;
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
                    _loadError = null;
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

    return Column(
      children: <Widget>[
        if (_sslProceedHost != null) _buildSslWarning(theme),
        Expanded(
          child: Stack(
            children: <Widget>[
              WebViewWidget(controller: _controller),
              if (_loading)
                LinearProgressIndicator(
                  minHeight: theme.gridGap,
                  backgroundColor: theme.surface,
                  color: theme.primary,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 证书被放行时的提示条（Phase 4.2.1）。
  ///
  /// 只做**告知**，不做拦截：自签证书是教务常态，每次弹窗确认会很烦
  /// （决策：自动放行 + 日志，弹窗留给将来真有人要求时再加）。
  /// 颜色 / 字号 / 圆角 / 间距全部取自 [AppTheme]，无硬编码。
  Widget _buildSslWarning(AppTheme theme) {
    return Container(
      width: double.infinity,
      color: theme.warning,
      padding: EdgeInsets.symmetric(
        horizontal: theme.cardPadding,
        vertical: theme.cardPadding / 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: theme.bodySize,
            color: theme.onBackground,
          ),
          SizedBox(width: theme.gridGap),
          Expanded(
            child: Text(
              '该网站使用了不受信任的证书（已放行）',
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
