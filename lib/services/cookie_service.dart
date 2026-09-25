// Phase 4.1：Cookie 的存取与格式化（插件登录凭证）。
//
// 存储位置：`flutter_secure_storage`，key = `<pluginId>:cookie`
// （CONTEXT 3.5：Cookie / Token 放 secure storage，按插件 ID 分 key）。
// 格式：HTTP 请求头的标准写法 `name1=value1; name2=value2`
// —— 这样插件侧可以直接 `ctx.http.get(url, { Cookie: ctx.cookie })`。
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Cookie 服务（纯静态类）。
///
/// 只负责"存 / 取 / 清 / 拼串"四件事；**不负责登录流程**（那是
/// `WebViewLoginPage` 的事），也不负责把 Cookie 塞回 WebView
/// （Phase 4.2 若要复用登录态再说）。
class CookieService {
  /// 纯静态工具类，禁止实例化。
  CookieService._();

  /// Cookie 在 secure storage 里的 key 后缀（完整 key 为 `<pluginId>:cookie`）。
  ///
  /// 与 `PluginContext.kCookieKeySuffix` **必须是同一个字符串**——
  /// 登录页写进去、插件 `ctx.cookie` 读出来，两边对不上就白搭。
  static const String kCookieKeySuffix = ':cookie';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// 拼接 cookie 时每项之间的分隔符（HTTP 头规范：`"; "`）。
  static const String kCookieSeparator = '; ';

  /// 保存插件的 Cookie（空串视为清除，避免留下无意义的空记录）。
  ///
  /// 失败只记日志、不抛异常：登录流程不该因为存储问题而崩掉。
  static Future<void> saveCookie(String pluginId, String cookie) async {
    final String key = '$pluginId$kCookieKeySuffix';
    try {
      if (cookie.trim().isEmpty) {
        await _storage.delete(key: key);
        return;
      }
      await _storage.write(key: key, value: cookie);
    } catch (e) {
      debugPrint('[CookieService] 保存 $pluginId 的 Cookie 失败：$e');
    }
  }

  /// 读取插件的 Cookie；**不存在或读取失败返回空串**（不是 `null`）。
  ///
  /// 返回空串而非 `null` 是为了对齐"Dart ↔ JS 边界只传字符串"的约定
  /// （`ctx.cookie` 永远返回字符串）。
  static Future<String> loadCookie(String pluginId) async {
    try {
      final String? value =
          await _storage.read(key: '$pluginId$kCookieKeySuffix');
      return value ?? '';
    } catch (e) {
      debugPrint('[CookieService] 读取 $pluginId 的 Cookie 失败（按空处理）：$e');
      return '';
    }
  }

  /// 清除插件的 Cookie（退出登录 / 卸载插件时用）。失败只记日志。
  static Future<void> clearCookie(String pluginId) async {
    try {
      await _storage.delete(key: '$pluginId$kCookieKeySuffix');
    } catch (e) {
      debugPrint('[CookieService] 清除 $pluginId 的 Cookie 失败：$e');
    }
  }

  /// 把 WebView 拿到的 Cookie 列表拼成 HTTP 头格式：`name1=value1; name2=value2`。
  ///
  /// - 名为空或**值里含 `;` / 换行**的条目会被跳过（拼进请求头会破坏格式）；
  /// - 同名 Cookie **后者覆盖前者**（调用方通常按"越具体越靠后"的顺序传入）；
  /// - 结果为空表示"没有可用的 Cookie"。
  static String formatCookies(List<WebViewCookie> cookies) {
    final Map<String, String> byName = <String, String>{};
    for (final WebViewCookie cookie in cookies) {
      final String name = cookie.name.trim();
      final String value = cookie.value;
      if (name.isEmpty) continue;
      if (value.contains(';') || value.contains('\n') || value.contains('\r')) {
        debugPrint('[CookieService] 跳过含非法字符的 Cookie：$name');
        continue;
      }
      byName[name] = value;
    }
    return byName.entries
        .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
        .join(kCookieSeparator);
  }
}
