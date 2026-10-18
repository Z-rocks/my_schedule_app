// 校园网 / 校外网络探测（Phase 4.4）。
//
// 背景：华北理工的教务系统在校内是直连（xjw1 → 内网），校外会被 WebVPN
// 网关接管并跳到统一身份认证。两种网络下登录方式完全不同：
//   - 校园网：URP 账号密码 + 验证码；
//   - 校外：CAS 只给二维码（手机 UA 甚至直接显示"移动端浏览器登录已关闭"）。
//
// 这里不做任何学校判断：探测 URL 与"校外主机"都由插件 manifest 声明，
// 服务只负责发一次**不跟随重定向**的 GET，看 `Location` 跳到哪。
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 探测结果。
enum CampusNetwork {
  /// 同站（200，或 3xx 仍在探测 URL 的 host 上）→ 校园网。
  campus,

  /// 3xx 跳到插件声明的校外网关 host → 校外。
  offCampus,

  /// 超时 / DNS 失败 / 跳到不认识的 host / 配置不全 → 让调用方兜底。
  unknown,
}

/// 纯函数：根据一次探测响应判断网络环境。
///
/// 之所以抽成纯函数：`dio` 的真实网络无法在 `flutter test` 里稳定复现，
/// 而"Location 属于哪个 host"才是这段逻辑里唯一容易写错的部分。
///
/// 规则：
/// - `Location` 是绝对 URL：host == offCampusHost（或其子域）→ 校外；
///   host == probeHost → 校园；其他 host → 未知。
/// - `Location` 是相对路径（`/login`）→ 同站，校园。
/// - 没有 `Location` 的 200 → 校园；没有 `Location` 的 3xx → 未知。
/// - 5xx / 4xx → 未知（既不能证明在校内，也不能证明在校外）。
CampusNetwork classifyCampusProbe({
  required int statusCode,
  required String location,
  required String probeHost,
  required String offCampusHost,
}) {
  final String probe = probeHost.trim().toLowerCase();
  final String off = offCampusHost.trim().toLowerCase();
  final String raw = location.trim();

  if (raw.isNotEmpty) {
    final Uri? uri = Uri.tryParse(raw);
    final String host = (uri?.host ?? '').trim().toLowerCase();
    if (host.isNotEmpty) {
      if (off.isNotEmpty && (host == off || host.endsWith('.$off'))) {
        return CampusNetwork.offCampus;
      }
      if (probe.isNotEmpty && host == probe) {
        return CampusNetwork.campus;
      }
      return CampusNetwork.unknown;
    }
    // 相对路径（`/login`）或无法解析的 Location：仍在本站。
    if (raw.startsWith('/')) return CampusNetwork.campus;
  }

  if (statusCode == 200) return CampusNetwork.campus;
  return CampusNetwork.unknown;
}

/// 校园网探测服务。
class CampusNetworkService {
  CampusNetworkService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 6),
              ),
            );

  final Dio _dio;

  /// 探测当前网络。
  ///
  /// 超时默认 6 秒：登录页在等这个结果，不能让用户干等太久；
  /// 但校园网首次 TLS 握手偶尔会慢，4 秒偏紧。
  /// 失败一律返回 [CampusNetwork.unknown]，由登录页按"校外"兜底并允许手动切换。
  Future<CampusNetwork> probe({
    required String probeUrl,
    required String offCampusHost,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final Uri? uri = Uri.tryParse(probeUrl.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        offCampusHost.trim().isEmpty) {
      return CampusNetwork.unknown;
    }

    try {
      final Response<void> response = await _dio.get<void>(
        uri.toString(),
        options: Options(
          // 关键：不要跟到 WebVPN 登录页，否则既慢又拿不到"原始跳转"。
          followRedirects: false,
          validateStatus: (_) => true,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      final CampusNetwork result = classifyCampusProbe(
        statusCode: response.statusCode ?? 0,
        location: response.headers.value('location') ?? '',
        probeHost: uri.host,
        offCampusHost: offCampusHost,
      );
      debugPrint('[CampusNetworkService] 探测结果=${result.name} '
          'status=${response.statusCode} '
          'location=${response.headers.value('location') ?? ''}');
      return result;
    } catch (e) {
      debugPrint('[CampusNetworkService] 探测失败（按未知处理）：$e');
      return CampusNetwork.unknown;
    }
  }
}
