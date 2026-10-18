// 插件声明的登录二维码配置（校外 CAS 扫码登录用）。
//
// 内核不硬编码任何学校 URL / 选择器：host 与三个 selector 全部来自
// 插件 manifest（`__plugin.qrLogin`），由登录页在运行时使用。
//
// 为什么单独做一个类：二维码相关字段有 4 个，散在 `PluginManifest` 里
// 会让调用方（登录页 / 详情页）到处传 4 个参数；聚成一个不可变对象更清楚。

/// 登录二维码页的定位配置。
///
/// 典型值（NCST）：
/// ```json
/// {
///   "host": "authserver.ncst.edu.cn",
///   "containerSelector": ".ncst-qrcode",
///   "imageSelector": "#qr_img",
///   "uuidSelector": "#uuid"
/// }
/// ```
class PluginQrLogin {
  const PluginQrLogin({
    required this.host,
    this.containerSelector = '',
    this.imageSelector = '#qr_img',
    this.uuidSelector = '#uuid',
  });

  /// 二维码页面所在主机（大小写不敏感，允许同主域子域）。
  final String host;

  /// 二维码区域的容器选择器；空串表示从 `document` 找。
  final String containerSelector;

  /// 二维码 `<img>` 的选择器。
  final String imageSelector;

  /// 二维码 UUID 隐藏域的选择器。
  final String uuidSelector;

  /// 是否配置了可用的二维码 host。
  bool get isConfigured => host.trim().isNotEmpty;

  /// [url] 是否属于二维码页面主机（同 host 或 `.<host>` 子域）。
  ///
  /// 只做**后缀**匹配：`authserver.ncst.edu.cn.evil.com` 这类前缀伪装不匹配。
  bool matchesHost(String url) {
    final String allowed = host.trim().toLowerCase();
    if (allowed.isEmpty) return false;
    final String actual =
        Uri.tryParse(url.trim())?.host.trim().toLowerCase() ?? '';
    if (actual.isEmpty) return false;
    return actual == allowed || actual.endsWith('.$allowed');
  }

  /// 从 JSON 构造；缺失字段用兜底值，任何输入都不抛异常。
  factory PluginQrLogin.fromJson(Map<String, dynamic> json) {
    return PluginQrLogin(
      host: _asString(json['host']),
      containerSelector: _asString(json['containerSelector']),
      imageSelector: _asString(json['imageSelector'], '#qr_img'),
      uuidSelector: _asString(json['uuidSelector'], '#uuid'),
    );
  }

  /// 解析 `qrLogin` 字段；不是对象或 host 为空时返回 `null`。
  static PluginQrLogin? tryParse(Object? value) {
    if (value is! Map) return null;
    final Map<String, dynamic> json = <String, dynamic>{
      for (final MapEntry<Object?, Object?> e in value.entries)
        '${e.key}': e.value,
    };
    final PluginQrLogin parsed = PluginQrLogin.fromJson(json);
    return parsed.isConfigured ? parsed : null;
  }

  /// 序列化为 JSON；空的可选字段不写，保持 manifest 干净。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'host': host,
      if (containerSelector.isNotEmpty) 'containerSelector': containerSelector,
      'imageSelector': imageSelector,
      'uuidSelector': uuidSelector,
    };
  }

  @override
  String toString() => 'PluginQrLogin($host)';

  static String _asString(Object? value, [String fallback = '']) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }
}
