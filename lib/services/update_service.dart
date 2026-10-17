// 检查更新（GitHub Releases 作为版本分发渠道）。
//
// 版本号来源：[AppVersion]（Android 上从系统包信息读，即 `pubspec.yaml` 的
// `version` 经构建写入 AndroidManifest）。这里只负责"远端最新版是什么、
// 要不要更新、去哪下载"。
//
// 为什么用 GitHub Releases 的公开 API：无需 token、无需自建服务，
// Release 的 tag 天然就是版本号，body 就是更新说明，assets 里放 APK。
// 限流是 60 次/小时/IP（未认证），手动"检查更新"的调用频率远低于此。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 版本分发所在的 GitHub 仓库（唯一配置点）。
const String kUpdateRepoOwner = 'Z-rocks';
const String kUpdateRepoName = 'my_schedule_app';

/// GitHub Releases API：最新一个正式 Release。
const String kUpdateApiUrl =
    'https://api.github.com/repos/$kUpdateRepoOwner/$kUpdateRepoName/releases/latest';

/// 检查结果的状态。
enum UpdateStatus {
  /// 已是最新（或远端版本不比本地新）。
  upToDate,

  /// 发现新版本。
  available,

  /// 检查失败（网络 / 限流 / 仓库没有 Release）。
  failed,
}

/// 一次"检查更新"的结果。
///
/// 三个状态互斥，用 [status] 区分；其余字段按状态填充。
@immutable
class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.status,
    required this.currentVersion,
    this.latestVersion = '',
    this.changelog = '',
    this.releaseUrl = '',
    this.apkUrl = '',
    this.reason = '',
  });

  /// 已是最新。
  factory UpdateCheckResult.upToDate({
    required String currentVersion,
    String latestVersion = '',
  }) {
    return UpdateCheckResult._(
      status: UpdateStatus.upToDate,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
    );
  }

  /// 有新版本。
  factory UpdateCheckResult.available({
    required String currentVersion,
    required String latestVersion,
    String changelog = '',
    String releaseUrl = '',
    String apkUrl = '',
  }) {
    return UpdateCheckResult._(
      status: UpdateStatus.available,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      changelog: changelog,
      releaseUrl: releaseUrl,
      apkUrl: apkUrl,
    );
  }

  /// 检查失败（[reason] 是给用户看的人话）。
  factory UpdateCheckResult.failed({
    required String currentVersion,
    required String reason,
  }) {
    return UpdateCheckResult._(
      status: UpdateStatus.failed,
      currentVersion: currentVersion,
      reason: reason,
    );
  }

  final UpdateStatus status;

  /// 本机版本（形如 `0.2.0+2`）。
  final String currentVersion;

  /// 远端最新版本（已去掉 `v` 前缀，形如 `0.2.1`）。
  final String latestVersion;

  /// Release 正文（更新说明，可能含 Markdown）。
  final String changelog;

  /// Release 页面地址（兜底下载入口）。
  final String releaseUrl;

  /// Release 里第一个 `.apk` 资产地址；没有则为空串。
  final String apkUrl;

  /// 失败原因。
  final String reason;

  /// 优先用于下载的地址：APK 直链 > Release 页面。
  String get downloadUrl => apkUrl.isNotEmpty ? apkUrl : releaseUrl;
}

/// 版本号比较与远端查询。
class UpdateService {
  UpdateService._();

  /// 查询 GitHub 最新 Release，并与 [currentVersion] 比较。
  ///
  /// **永不抛异常**：网络错误、限流、JSON 结构异常都折成
  /// [UpdateStatus.failed]，由 UI 决定怎么提示。
  ///
  /// [dio] 仅用于测试注入。
  static Future<UpdateCheckResult> check({
    required String currentVersion,
    Dio? dio,
  }) async {
    final Dio client = dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            // GitHub API 要求带 User-Agent，缺了会被 403。
            headers: const <String, String>{
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'my-schedule-app',
            },
          ),
        );

    try {
      final Response<dynamic> response =
          await client.get<dynamic>(kUpdateApiUrl);
      final Object? data = response.data;
      final Map<String, dynamic>? json = data is Map<String, dynamic>
          ? data
          : (data is String ? _tryDecodeObject(data) : null);

      if (json == null) {
        return UpdateCheckResult.failed(
          currentVersion: currentVersion,
          reason: 'GitHub 返回的数据无法识别',
        );
      }

      final String tag = (json['tag_name'] as String? ?? '').trim();
      final String latest = _stripVersionPrefix(tag);
      if (latest.isEmpty) {
        return UpdateCheckResult.failed(
          currentVersion: currentVersion,
          reason: 'Release 缺少版本号（tag_name）',
        );
      }

      final String changelog = (json['body'] as String? ?? '').trim();
      final String releaseUrl = (json['html_url'] as String? ?? '').trim();
      final String apkUrl = _firstApkUrl(json['assets']);

      if (isNewerVersion(latest, currentVersion)) {
        return UpdateCheckResult.available(
          currentVersion: currentVersion,
          latestVersion: latest,
          changelog: changelog,
          releaseUrl: releaseUrl,
          apkUrl: apkUrl,
        );
      }

      return UpdateCheckResult.upToDate(
        currentVersion: currentVersion,
        latestVersion: latest,
      );
    } on DioException catch (e) {
      return UpdateCheckResult.failed(
        currentVersion: currentVersion,
        reason: _friendlyDioError(e),
      );
    } catch (e) {
      debugPrint('[UpdateService] 检查更新失败：$e');
      return UpdateCheckResult.failed(
        currentVersion: currentVersion,
        reason: '检查失败：$e',
      );
    }
  }

  /// 把 Dio 的错误翻译成能直接照着排查的人话。
  static String _friendlyDioError(DioException e) {
    final int? code = e.response?.statusCode;
    if (code == 404) {
      return '仓库还没有发布过 Release（或仓库地址已变更）';
    }
    if (code == 403) {
      // GitHub 未认证调用限流 60 次/小时。
      return 'GitHub 拒绝了请求（可能触发了限流），请稍后再试';
    }
    if (code != null && code >= 500) {
      return 'GitHub 服务暂时不可用（HTTP $code）';
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '连接 GitHub 超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '无法连接 GitHub，请检查网络（部分网络环境需要代理）';
      case DioExceptionType.badResponse:
        return 'GitHub 返回异常（HTTP ${code ?? '未知'}）';
      default:
        return '检查更新失败：${e.message ?? e.type.name}';
    }
  }

  /// 从 `assets` 数组里取第一个 `.apk` 的下载地址。
  static String _firstApkUrl(Object? assets) {
    if (assets is! List) return '';
    for (final Object? asset in assets) {
      if (asset is! Map) continue;
      final String name = (asset['name']?.toString() ?? '').toLowerCase();
      if (!name.endsWith('.apk')) continue;
      final String url =
          (asset['browser_download_url']?.toString() ?? '').trim();
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  static Map<String, dynamic>? _tryDecodeObject(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// 去掉版本号前面的 `v` / `V`。
String _stripVersionPrefix(String raw) {
  String s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  return s.trim();
}

/// 把版本号拆成可比较的数字段（固定 3 段，缺的补 0）。
///
/// 支持的输入：`v0.2.0`、`0.2.0+2`、`0.2`（→ 0.2.0）、`1.0.0-beta.1`（忽略预发布）。
List<int> _versionSegments(String raw) {
  String s = _stripVersionPrefix(raw);
  // 去掉 build 元数据（`+2`）与预发布后缀（`-beta.1`）。
  final int plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  final int dash = s.indexOf('-');
  if (dash >= 0) s = s.substring(0, dash);

  final List<int> segments = <int>[];
  for (final String part in s.split('.')) {
    segments.add(int.tryParse(part.trim()) ?? 0);
  }
  while (segments.length < 3) {
    segments.add(0);
  }
  return segments;
}

/// [latest] 是否比 [current] 新（语义化版本，按主/次/补丁三段比较）。
///
/// 只比三段数字：`0.2.0+2` 与 `0.2.0+3` 视为同一版本——build number 不参与
/// "要不要提示更新"的判断，否则每次打包自增都会弹更新，没有意义。
bool isNewerVersion(String latest, String current) {
  final List<int> a = _versionSegments(latest);
  final List<int> b = _versionSegments(current);
  for (int i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
