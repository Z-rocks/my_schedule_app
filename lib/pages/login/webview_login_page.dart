// Phase 4.1：通用 WebView 登录页（登录 + Cookie 提取）。
// Phase 4.2.1：新增 SSL 证书错误处理（**只放行登录 URL 的 host**）+ 诊断日志。
//
// **本页是通用组件**：不硬编码任何学校 URL、不依赖任何学校页面结构
// （CONTEXT 3.1：内核不知道任何具体学校的 URL / 字段名）。
// 登录地址与成功判定条件都由调用方（Phase 4.2 起是插件的 manifest）传入。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../runtime/plugin_qr_login.dart';
import '../../services/campus_network_service.dart';
import '../../services/app_log.dart';
import '../../services/cookie_service.dart';
import '../../services/qr_login_bridge.dart';
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

/// 登录页的网络模式（Phase 4.4）。
///
/// - [detecting]：正在探测校园网 / 校外，WebView 还没开始加载；
/// - [campus]：同站可达，用默认手机 UA 打开账号密码登录页；
/// - [offCampus]：走 WebVPN / CAS，换桌面 UA 并启用扫码辅助。
enum _LoginNetworkMode { detecting, campus, offCampus }

/// 网络模式选择弹层的返回值。
enum _NetworkChoice { campus, offCampus, detect }

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
    this.campusProbeUrl = '',
    this.offCampusHost = '',
    this.offCampusUserAgent = '',
    this.qrLogin,
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

  /// 校园网探测 URL（插件声明；空串 = 不探测，保持旧行为）。
  final String campusProbeUrl;

  /// 校外网关 host（插件声明；用于识别探测跳转，以及页面误入校外时自动切换）。
  final String offCampusHost;

  /// 校外登录使用的桌面 UA（插件声明；空串 = 不换 UA）。
  final String offCampusUserAgent;

  /// 校外 CAS 二维码配置（插件声明；`null` = 不启用扫码辅助）。
  final PluginQrLogin? qrLogin;

  /// AppBar 标题，默认"登录"。
  final String? title;

  /// 插件 id；非空时本页负责把 Cookie 落盘。
  final String? pluginId;

  @override
  State<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends State<WebViewLoginPage>
    with WidgetsBindingObserver {
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

  // ───────────────────── 校外登录（Phase 4.4） ─────────────────────

  /// 当前网络模式。
  _LoginNetworkMode _networkMode = _LoginNetworkMode.detecting;

  /// 探测失败（超时 / 未知跳转）时置 true，顶部提示改口为"已按校外模式打开"。
  bool _probeFailed = false;

  /// 是否已经因为"页面跳到校外网关"而自动切换过桌面 UA。
  ///
  /// 只自动切一次：用户手动选回"校园网"后，不应该被再次弹回校外模式。
  bool _autoSwitchedToOffCampus = false;

  /// 从 CAS 页面提取到的二维码 PNG。
  Uint8List? _qrPng;

  /// 二维码面板是否展开。
  bool _qrPanelVisible = false;

  /// 是否正在提取二维码（用于面板上的细进度条）。
  bool _qrExtracting = false;

  /// 提取轮次令牌：页面变化 / 重新提取时自增，旧轮次的结果直接丢弃。
  int _qrExtractToken = 0;

  /// 保存到相册后的 URI（登录完成 / 页面销毁时删除）。
  String? _savedQrUri;

  /// "保存并打开微信"是否正在进行，防止连点。
  bool _openingWeChat = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

    if (widget.campusProbeUrl.trim().isEmpty) {
      _networkMode = _LoginNetworkMode.campus;
      _load();
    } else {
      unawaited(_detectNetwork());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _qrExtractToken++;
    unawaited(_deleteSavedQr());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户切到微信扫码后，WebView 里的 1s 轮询可能被系统暂停 / 清掉。
    // 回到 App 时补一次 isUsed()，避免"微信已确认、App 还停在二维码页"。
    if (state == AppLifecycleState.resumed && _qrPanelVisible) {
      unawaited(_pollQrStatus());
    }
  }

  /// 探测当前是校园网还是校外，然后按对应模式打开登录页。
  Future<void> _detectNetwork() async {
    if (!mounted) return;
    setState(() {
      _networkMode = _LoginNetworkMode.detecting;
      _probeFailed = false;
      _loading = true;
      _loadError = null;
    });

    final CampusNetwork detected = await CampusNetworkService().probe(
      probeUrl: widget.campusProbeUrl,
      offCampusHost: widget.offCampusHost,
    );
    if (!mounted) return;

    switch (detected) {
      case CampusNetwork.campus:
        await _startLogin(_LoginNetworkMode.campus);
      case CampusNetwork.offCampus:
        await _startLogin(_LoginNetworkMode.offCampus);
      case CampusNetwork.unknown:
        // 探测失败时按校外兜底：校外模式的 CAS 页至少有二维码；
        // 反过来（校园网误判成校外）最多是桌面布局，账号密码仍可用。
        await _startLogin(_LoginNetworkMode.offCampus, probeFailed: true);
    }
  }

  /// 切换网络模式：设置 UA → 重新加载登录页。
  Future<void> _startLogin(
    _LoginNetworkMode mode, {
    bool probeFailed = false,
  }) async {
    if (!mounted) return;
    setState(() {
      _networkMode = mode;
      _probeFailed = probeFailed;
      _loading = true;
      _loadError = null;
      _finished = false;
      _postLoginNavigated = false;
      _qrPng = null;
      _qrPanelVisible = false;
      _qrExtracting = false;
      _qrExtractToken++;
    });

    try {
      if (mode == _LoginNetworkMode.offCampus) {
        final String ua = widget.offCampusUserAgent.trim();
        if (ua.isNotEmpty) await _controller.setUserAgent(ua);
      } else {
        // Android 的 WebSettings.setUserAgentString(null) 会恢复系统默认 UA，
        // 比"自己缓存一份默认 UA"更可靠（不会把桌面 UA 误存成默认值）。
        await _controller.setUserAgent(null);
      }
    } catch (e) {
      debugPrint('[WebViewLoginPage] 设置 UA 失败：$e');
    }
    if (!mounted) return;
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
      if (_isQrHost(url)) {
        // 二维码页刷新了：旧图可能已失效，等 onPageFinished 重新提取。
        _qrPng = null;
        _qrPanelVisible = false;
        _qrExtracting = false;
        _qrExtractToken++;
      } else if (_qrPng != null || _qrPanelVisible) {
        // 已经离开 CAS 二维码页（CAS 提交 / WebVPN 回调 / xjw1）：
        // 收起面板并清掉旧图，别让"微信扫码"浮在成功跳转的页面上。
        _qrPng = null;
        _qrPanelVisible = false;
        _qrExtracting = false;
        _qrExtractToken++;
      }
    });
    unawaited(_maybeAutoSwitchToOffCampus(url));
  }

  Future<void> _onPageFinished(String url) async {
    if (!mounted) return;
    setState(() => _loading = false);
    await _maybeFinish(url);
    if (!mounted) return;
    _scheduleQrExtract(url);
  }

  /// 如果页面实际跳到了校外网关（探测误判 / 网络切换），自动切桌面 UA 重来一次。
  ///
  /// 只切一次：用户手动选回"校园网"后不再强制弹回，避免来回跳。
  Future<void> _maybeAutoSwitchToOffCampus(String url) async {
    if (_autoSwitchedToOffCampus) return;
    if (_networkMode == _LoginNetworkMode.offCampus) return;
    final String host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    final String off = widget.offCampusHost.trim().toLowerCase();
    if (host.isEmpty || off.isEmpty) return;
    if (host != off && !host.endsWith('.$off')) return;

    _autoSwitchedToOffCampus = true;
    debugPrint('[WebViewLoginPage] 页面跳到校外网关（$host），自动切换桌面 UA');
    await _startLogin(_LoginNetworkMode.offCampus);
  }

  // ───────────────────── 二维码提取 / 扫码辅助 ─────────────────────

  /// 当前 URL 是否属于插件声明的二维码页 host。
  bool _isQrHost(String url) => widget.qrLogin?.matchesHost(url) ?? false;

  /// 页面加载完后尝试提取二维码；二维码是 AJAX 异步渲染的，失败重试几次。
  void _scheduleQrExtract(String url) {
    final PluginQrLogin? qr = widget.qrLogin;
    if (qr == null || !qr.isConfigured) return;
    if (_networkMode != _LoginNetworkMode.offCampus) return;
    if (!qr.matchesHost(url)) return;

    final int token = ++_qrExtractToken;
    if (mounted) setState(() => _qrExtracting = true);

    unawaited(() async {
      for (int attempt = 0; attempt < 12; attempt++) {
        if (!mounted || token != _qrExtractToken) return;
        if (await _tryExtractQr(qr)) {
          if (!mounted || token != _qrExtractToken) return;
          setState(() => _qrExtracting = false);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (!mounted || token != _qrExtractToken) return;
      setState(() => _qrExtracting = false);
      debugPrint('[WebViewLoginPage] 未能在 CAS 页找到二维码');
      _snack('未能自动提取二维码：请点右上角刷新重试，或用另一台设备扫描页面里的二维码。');
    }());
  }

  /// 从页面取一张二维码 PNG。成功返回 true。
  Future<bool> _tryExtractQr(PluginQrLogin qr) async {
    try {
      final Object raw =
          await _controller.runJavaScriptReturningResult(_qrExtractScript(qr));
      final String? text = _asJsString(raw);
      if (text == null || text.isEmpty) return false;

      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) return false;
      final String dataUrl = '${decoded['png'] ?? ''}';
      if (!dataUrl.startsWith('data:image/')) return false;
      final int comma = dataUrl.indexOf(',');
      if (comma < 0) return false;
      final Uint8List bytes = base64Decode(dataUrl.substring(comma + 1));
      if (bytes.isEmpty) return false;

      if (!mounted) return false;
      setState(() {
        _qrPng = bytes;
        _qrPanelVisible = true;
      });
      debugPrint('[WebViewLoginPage] 已提取二维码（${bytes.length} 字节）');
      return true;
    } catch (e) {
      debugPrint('[WebViewLoginPage] 提取二维码失败：$e');
      return false;
    }
  }

  /// 生成取二维码的 JS。
  ///
  /// 选择器来自插件，用 `jsonEncode` 转成 JS 字符串字面量，避免引号 / 反斜杠
  /// 把脚本拼坏。canvas 与二维码图同源，不会被 taint。
  String _qrExtractScript(PluginQrLogin qr) {
    final String root = qr.containerSelector.trim().isEmpty
        ? 'document'
        : 'document.querySelector(${jsonEncode(qr.containerSelector)}) || document';
    return '''
(function () {
  var root = $root;
  var img = root.querySelector(${jsonEncode(qr.imageSelector)});
  var uuid = root.querySelector(${jsonEncode(qr.uuidSelector)});
  if (!img || !uuid || !uuid.value || !img.complete || !img.naturalWidth) return '';
  try {
    var c = document.createElement('canvas');
    c.width = img.naturalWidth;
    c.height = img.naturalHeight;
    c.getContext('2d').drawImage(img, 0, 0);
    return JSON.stringify({ uuid: uuid.value, png: c.toDataURL('image/png') });
  } catch (e) {
    return '';
  }
})()
''';
  }

  /// WebView 的 JS 返回值可能是带引号的 JSON 字符串，统一还原成普通字符串。
  String? _asJsString(Object? raw) {
    if (raw == null) return null;
    final String text = raw.toString();
    if (text.isEmpty || text == 'null') return null;
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try {
        return jsonDecode(text) as String;
      } catch (_) {
        return text;
      }
    }
    return text;
  }

  /// 手动催一次 CAS 的二维码状态轮询（回到 App / 用户点"我已在微信确认"）。
  Future<void> _pollQrStatus() async {
    try {
      await _controller.runJavaScript(
        'if (typeof isUsed === "function") isUsed();',
      );
    } catch (e) {
      debugPrint('[WebViewLoginPage] 轮询二维码状态失败：$e');
    }
  }

  /// 刷新 CAS 二维码（页面自带 `refresh()`），然后重新提取。
  Future<void> _refreshQr() async {
    if (!mounted) return;
    setState(() {
      _qrPng = null;
      _qrPanelVisible = false;
      _qrExtracting = true;
    });
    try {
      await _controller.runJavaScript(
        'if (typeof refresh === "function") refresh();',
      );
    } catch (e) {
      debugPrint('[WebViewLoginPage] 刷新二维码失败：$e');
    }
    final String url = await _controller.currentUrl() ?? '';
    if (!mounted) return;
    _scheduleQrExtract(url);
  }

  /// 保存二维码到相册，并拉起微信扫一扫。
  Future<void> _saveAndOpenWeChat() async {
    final Uint8List? bytes = _qrPng;
    if (bytes == null || bytes.isEmpty || _openingWeChat) return;

    setState(() => _openingWeChat = true);
    try {
      // 上一次保存的二维码先清掉，避免相册里堆一串登录凭证。
      await _deleteSavedQr();

      final bool installed = await QrLoginBridge.isWeChatInstalled();
      if (!installed) {
        _snack('未检测到微信：请先安装微信，或用另一台设备扫描此二维码。');
        return;
      }

      final String? uri = await QrLoginBridge.saveImageToGallery(
        bytes,
        'campus_login_qr_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      if (uri == null) {
        _snack('保存二维码失败：请检查相册 / 存储权限，或截图后用微信「相册」识别。');
        return;
      }
      _savedQrUri = uri;

      final bool opened = await QrLoginBridge.openWeChatScanner();
      if (!opened) {
        _snack('未能拉起微信扫一扫：请手动打开微信 → 扫一扫 → 右上角相册。');
        return;
      }
      _snack('已保存二维码。请在微信里点右上角「相册」，选第一张二维码，再点「确认登录」。');
    } finally {
      if (mounted) setState(() => _openingWeChat = false);
    }
  }

  /// 删除刚保存到相册的二维码（登录成功 / 页面销毁）。
  Future<void> _deleteSavedQr() async {
    final String? uri = _savedQrUri;
    _savedQrUri = null;
    if (uri != null) await QrLoginBridge.deleteImage(uri);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 手动切换网络模式（探测失败的兜底入口）。
  Future<void> _showNetworkModeSheet() async {
    final _NetworkChoice? chosen = await showModalBottomSheet<_NetworkChoice>(
      context: context,
      backgroundColor: AppThemeExtension.of(context).surface,
      builder: (BuildContext sheetContext) {
        final AppTheme theme = AppThemeExtension.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(theme.cardPadding),
                child: Text(
                  '选择当前网络',
                  style: TextStyle(
                    fontSize: theme.titleSize,
                    color: theme.onBackground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.wifi, color: theme.primary),
                title: Text('我在校园网', style: TextStyle(color: theme.onBackground)),
                subtitle: Text(
                  '使用账号密码登录',
                  style: TextStyle(fontSize: theme.captionSize),
                ),
                onTap: () => Navigator.of(sheetContext).pop(_NetworkChoice.campus),
              ),
              ListTile(
                leading: Icon(Icons.qr_code_2, color: theme.primary),
                title: Text('我在校外', style: TextStyle(color: theme.onBackground)),
                subtitle: Text(
                  '使用微信扫码登录',
                  style: TextStyle(fontSize: theme.captionSize),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_NetworkChoice.offCampus),
              ),
              ListTile(
                leading: Icon(Icons.refresh, color: theme.onBackground),
                title: Text('重新检测', style: TextStyle(color: theme.onBackground)),
                onTap: () => Navigator.of(sheetContext).pop(_NetworkChoice.detect),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || chosen == null) return;
    switch (chosen) {
      case _NetworkChoice.campus:
        await _startLogin(_LoginNetworkMode.campus);
      case _NetworkChoice.offCampus:
        await _startLogin(_LoginNetworkMode.offCampus);
      case _NetworkChoice.detect:
        if (widget.campusProbeUrl.trim().isNotEmpty) {
          await _detectNetwork();
        }
    }
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
    // 二维码是临时登录凭证：登录成功后不再需要，顺手从相册清掉。
    // 不 await：清理失败不该拖慢 / 阻止登录返回。
    unawaited(_deleteSavedQr());
    final String? pluginId = widget.pluginId;
    if (pluginId != null && pluginId.isNotEmpty) {
      await CookieService.saveCookie(pluginId, cookie);
      debugPrint('[WebViewLoginPage] 已保存 $pluginId 的 Cookie（${cookie.length} 字符）');
      // 只记"登录成功 + Cookie 长度"，**绝不记 Cookie 内容**：
      // 那是能直接冒充用户身份的凭据，而日志是要发给开发者的。
      AppLog.action('plugin_login_ok', <String, Object?>{
        'plugin': pluginId,
        'cookieLength': cookie.length,
      });
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
          // 网络判断 / 手动切换（仅在插件声明了探测 URL 时有意义）。
          if (widget.campusProbeUrl.trim().isNotEmpty)
            IconButton(
              icon: Icon(
                _networkMode == _LoginNetworkMode.campus
                    ? Icons.wifi
                    : Icons.public,
              ),
              tooltip: '切换网络模式',
              onPressed: _networkMode == _LoginNetworkMode.detecting
                  ? null
                  : _showNetworkModeSheet,
            ),
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
              if (widget.campusProbeUrl.trim().isNotEmpty) ...<Widget>[
                SizedBox(height: theme.gridGap),
                TextButton(
                  onPressed: _showNetworkModeSheet,
                  child: const Text('切换网络模式'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        // 没声明探测 URL 的老插件保持原样：不显示网络条，也不做模式切换。
        if (widget.campusProbeUrl.trim().isNotEmpty)
          _buildNetworkBanner(theme),
        if (_sslProceedHost != null) _buildSslWarning(theme),
        Expanded(
          child: Stack(
            children: <Widget>[
              WebViewWidget(controller: _controller),
              if (_networkMode == _LoginNetworkMode.detecting)
                Positioned.fill(
                  child: ColoredBox(
                    color: theme.background,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          CircularProgressIndicator(color: theme.primary),
                          SizedBox(height: theme.sectionGap),
                          Text(
                            '正在判断网络环境…',
                            style: TextStyle(
                              fontSize: theme.bodySize,
                              color: theme.onBackground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_loading)
                LinearProgressIndicator(
                  minHeight: theme.gridGap,
                  backgroundColor: theme.surface,
                  color: theme.primary,
                ),
              if (_qrPng != null && _qrPanelVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildQrPanel(theme),
                ),
              if (_qrPng != null && !_qrPanelVisible)
                Positioned(
                  right: theme.cardPadding,
                  bottom: theme.cardPadding,
                  child: _buildQrEntry(theme),
                ),
              if (_qrPng == null &&
                  !_qrPanelVisible &&
                  _qrExtracting &&
                  _networkMode == _LoginNetworkMode.offCampus)
                Positioned(
                  right: theme.cardPadding,
                  bottom: theme.cardPadding,
                  child: _buildQrLoading(theme),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 顶部网络模式条：点击可手动切换（探测失败时的唯一入口）。
  Widget _buildNetworkBanner(AppTheme theme) {
    final bool detecting = _networkMode == _LoginNetworkMode.detecting;
    final bool campus = _networkMode == _LoginNetworkMode.campus;

    final String text;
    if (detecting) {
      text = '正在判断网络环境…';
    } else if (campus) {
      text = '校园网 · 账号密码登录';
    } else if (_probeFailed) {
      text = '网络检测失败 · 已按校外模式打开';
    } else {
      text = '校外网络 · 微信扫码登录';
    }

    final Color background =
        !detecting && _probeFailed ? theme.warning : theme.surface;
    return Material(
      color: background,
      child: InkWell(
        onTap: detecting ? null : _showNetworkModeSheet,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: theme.cardPadding,
            vertical: theme.gridGap,
          ),
          child: Row(
            children: <Widget>[
              if (detecting)
                SizedBox(
                  width: theme.bodySize,
                  height: theme.bodySize,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.primary,
                  ),
                )
              else
                Icon(
                  campus ? Icons.wifi : Icons.public,
                  size: theme.bodySize,
                  color: theme.onBackground,
                ),
              SizedBox(width: theme.gridGap),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: theme.captionSize,
                    color: theme.onBackground,
                  ),
                ),
              ),
              if (!detecting) ...<Widget>[
                Text(
                  '切换',
                  style: TextStyle(
                    fontSize: theme.captionSize,
                    color: theme.primary,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: theme.bodySize,
                  color: theme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 二维码面板：大图 + 保存到相册 + 拉起微信扫一扫。
  Widget _buildQrPanel(AppTheme theme) {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        margin: EdgeInsets.all(theme.gridGap),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(theme.cardRadius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: theme.cardShadowColor,
              blurRadius: theme.cardShadowBlur,
              offset: Offset(0, -theme.cardShadowOffsetY),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(theme.cardPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '微信扫码登录',
                      style: TextStyle(
                        fontSize: theme.titleSize,
                        fontWeight: FontWeight.w600,
                        color: theme.onBackground,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: theme.bodySize,
                      color: theme.onBackground,
                    ),
                    onPressed: () =>
                        setState(() => _qrPanelVisible = false),
                  ),
                ],
              ),
              Text(
                QrLoginBridge.canDeleteAfterLogin
                    ? '校外登录需要用微信确认。二维码只在本次登录有效，'
                        '登录成功后会自动从相册删除。'
                    : '校外登录需要用微信确认。二维码只在本次登录有效，'
                        '登录成功后请手动把它从相册删掉。',
                style: TextStyle(
                  fontSize: theme.captionSize,
                  color: theme.onBackground,
                ),
              ),
              SizedBox(height: theme.gridGap),
              Center(
                child: Container(
                  padding: EdgeInsets.all(theme.gridGap),
                  color: theme.background,
                  child: Image.memory(
                    _qrPng!,
                    width: 180,
                    height: 180,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              SizedBox(height: theme.gridGap),
              Text(
                '1. 点下面按钮保存二维码\n'
                '2. 打开微信「扫一扫」→ 右上角「相册」→ 选这张图\n'
                '3. 在微信里点「确认登录」',
                style: TextStyle(
                  fontSize: theme.captionSize,
                  color: theme.onBackground,
                  height: 1.5,
                ),
              ),
              if (_qrExtracting) ...<Widget>[
                SizedBox(height: theme.gridGap),
                LinearProgressIndicator(
                  minHeight: theme.gridGap,
                  backgroundColor: theme.surface,
                  color: theme.primary,
                ),
              ],
              SizedBox(height: theme.gridGap),
              FilledButton.icon(
                onPressed: _openingWeChat ? null : _saveAndOpenWeChat,
                icon: _openingWeChat
                    ? SizedBox(
                        width: theme.bodySize,
                        height: theme.bodySize,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.save_alt),
                label: const Text('保存二维码并打开微信'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: theme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.buttonRadius),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  TextButton(
                    onPressed: () {
                      _snack('正在确认…如果微信已点「确认登录」，页面会自动跳转。');
                      unawaited(_pollQrStatus());
                    },
                    child: const Text('我已在微信确认'),
                  ),
                  TextButton(
                    onPressed: _refreshQr,
                    child: const Text('刷新二维码'),
                  ),
                ],
              ),
              Text(
                '第一次使用：如果微信里出现「移动端浏览器登录已关闭」或要求关注 / 绑定'
                '学校的「一网通办」，请长按提示页里的二维码识别（或在微信里搜索学校的'
                '「一网通办」），完成绑定后回到这里点「刷新二维码」再扫一次。',
                style: TextStyle(
                  fontSize: theme.captionSize,
                  color: theme.onBackground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 二维码面板收起后的入口。
  Widget _buildQrEntry(AppTheme theme) {
    return FloatingActionButton.extended(
      onPressed: () => setState(() => _qrPanelVisible = true),
      backgroundColor: theme.primary,
      foregroundColor: theme.onPrimary,
      icon: const Icon(Icons.qr_code_2),
      label: const Text('微信扫码'),
    );
  }

  /// 正在从 CAS 页面取二维码时的轻提示。
  Widget _buildQrLoading(AppTheme theme) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.cardPadding,
        vertical: theme.gridGap,
      ),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: theme.bodySize,
            height: theme.bodySize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.primary,
            ),
          ),
          SizedBox(width: theme.gridGap),
          Text(
            '正在获取二维码…',
            style: TextStyle(
              fontSize: theme.captionSize,
              color: theme.onBackground,
            ),
          ),
        ],
      ),
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
