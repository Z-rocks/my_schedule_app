// 检查更新（版本分发渠道：Gitee 镜像优先，GitHub 兜底）。
//
// 为什么是"多源"：GitHub 在国内网络下不稳定（连接超时、下载被重置是常态），
// 而 Gitee 的发行版（Release）结构与 GitHub 几乎一致——tag 就是版本号、
// body 就是更新说明、附件里放 APK。所以主源放 Gitee，GitHub 只做兜底：
// 任一源能拿到比本地新的版本就返回，两个都失败才报错。
//
// 版本号来源：[AppVersion]（Android 上从系统包信息读，即 `pubspec.yaml` 的
// `version` 经构建写入 AndroidManifest）。这里只负责"远端最新版是什么、
// 要不要更新、去哪下载"。
//
// 两家的字段差异（都实测过）：
// | 字段 | GitHub | Gitee |
// | tag/正文/预发布 | tag_name / body / prerelease | 同 |
// | 页面地址 | html_url | **没有**，用 repoWebUrl + /releases/tag/<tag> 拼 |
// | 附件 | assets[].browser_download_url | 同（无附件时会自动带源码 zip/tar） |
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 版本分发源。顺序即尝试顺序。
enum UpdateSource {
  /// Gitee 镜像（国内快，主源）。
  gitee(
    label: 'Gitee 镜像',
    apiUrl:
        'https://gitee.com/api/v5/repos/zrocks/my_schedule_app/releases/latest',
    repoWebUrl: 'https://gitee.com/zrocks/my_schedule_app',
  ),

  /// GitHub（兜底源）。
  github(
    label: 'GitHub',
    apiUrl:
        'https://api.github.com/repos/Z-rocks/my_schedule_app/releases/latest',
    repoWebUrl: 'https://github.com/Z-rocks/my_schedule_app',
  );

  const UpdateSource({
    required this.label,
    required this.apiUrl,
    required this.repoWebUrl,
  });

  /// 给用户看的名字。
  final String label;

  /// "最新 Release" 接口。
  final String apiUrl;

  /// 仓库网页地址（Gitee 不返回 html_url，用它拼 Release 页面）。
  final String repoWebUrl;

  /// 某个 tag 的 Release 页面地址。
  String releasePageUrl(String tag) => '$repoWebUrl/releases/tag/$tag';
}

/// 兼容旧引用：GitHub 仓库坐标与接口地址。
const String kUpdateRepoOwner = 'Z-rocks';
const String kUpdateRepoName = 'my_schedule_app';
const String kUpdateApiUrl = 'https://api.github.com/repos/'
    '$kUpdateRepoOwner/$kUpdateRepoName/releases/latest';

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
    this.source = '',
    this.reason = '',
  });

  /// 已是最新。
  factory UpdateCheckResult.upToDate({
    required String currentVersion,
    String latestVersion = '',
    String source = '',
  }) {
    return UpdateCheckResult._(
      status: UpdateStatus.upToDate,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      source: source,
    );
  }

  /// 有新版本。
  factory UpdateCheckResult.available({
    required String currentVersion,
    required String latestVersion,
    String changelog = '',
    String releaseUrl = '',
    String apkUrl = '',
    String source = '',
  }) {
    return UpdateCheckResult._(
      status: UpdateStatus.available,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      changelog: changelog,
      releaseUrl: releaseUrl,
      apkUrl: apkUrl,
      source: source,
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

  /// 本机版本（形如 `0.3.0+3`）。
  final String currentVersion;

  /// 远端最新版本（已去掉 `v` 前缀，形如 `0.3.1`）。
  final String latestVersion;

  /// Release 正文（更新说明，可能含 Markdown）。
  final String changelog;

  /// Release 页面地址（兜底下载入口）。
  final String releaseUrl;

  /// Release 里第一个 `.apk` 资产地址；没有则为空串。
  final String apkUrl;

  /// 这次结果来自哪个源（[UpdateSource.label]），UI 用来告诉用户"从哪下的"。
  final String source;

  /// 失败原因。
  final String reason;

  /// 优先用于下载的地址：APK 直链 > Release 页面。
  String get downloadUrl => apkUrl.isNotEmpty ? apkUrl : releaseUrl;
}

/// 一次源查询的结果：要么拿到 [result]，要么拿到 [error]。
class _Attempt {
  const _Attempt.ok(UpdateCheckResult this.result) : error = '';
  const _Attempt.fail(String this.error) : result = null;

  final UpdateCheckResult? result;
  final String error;
}

/// 归一化后的 Release 信息（屏蔽 Gitee / GitHub 的字段差异）。
@immutable
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.changelog,
    required this.releaseUrl,
    required this.apkUrl,
    required this.prerelease,
  });

  /// 从任一家的 JSON 解析；缺 tag 时返回 null（没有版本号就没有意义）。
  static ReleaseInfo? fromJson(Map<String, dynamic> json, UpdateSource source) {
    final String tag = (json['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty) return null;
    // GitHub 给 html_url；Gitee 没有，用仓库地址拼。
    final String htmlUrl = (json['html_url'] as String? ?? '').trim();
    return ReleaseInfo(
      tag: tag,
      changelog: (json['body'] as String? ?? '').trim(),
      releaseUrl:
          htmlUrl.isNotEmpty ? htmlUrl : source.releasePageUrl(tag),
      apkUrl: _firstApkUrl(json['assets']),
      prerelease: json['prerelease'] == true,
    );
  }

  final String tag;
  final String changelog;
  final String releaseUrl;
  final String apkUrl;
  final bool prerelease;
}

/// 版本号比较与远端查询。
class UpdateService {
  UpdateService._();

  /// 查询远端最新 Release，并与 [currentVersion] 比较。
  ///
  /// 按 [sources] 顺序逐个尝试（默认 Gitee 镜像 → GitHub），
  /// **第一个成功的源说了算**：镜像与主仓库理论上同版本，不必交叉比对。
  ///
  /// **永不抛异常**：网络错误、限流、JSON 结构异常都折成
  /// [UpdateStatus.failed]，由 UI 决定怎么提示。
  ///
  /// [dio] 仅用于测试注入。
  static Future<UpdateCheckResult> check({
    required String currentVersion,
    Dio? dio,
    List<UpdateSource> sources = const <UpdateSource>[
      UpdateSource.gitee,
      UpdateSource.github,
    ],
  }) async {
    final Dio client = dio ?? _defaultClient();
    final List<String> errors = <String>[];

    for (final UpdateSource source in sources) {
      final _Attempt attempt = await _trySource(client, source, currentVersion);
      final UpdateCheckResult? result = attempt.result;
      if (result != null) return result;
      debugPrint('[UpdateService] ${source.label} 失败：${attempt.error}');
      errors.add('${source.label}：${attempt.error}');
    }

    return UpdateCheckResult.failed(
      currentVersion: currentVersion,
      reason: errors.isEmpty
          ? '没有可用的下载源'
          // 两个源都挂时把原因都列出来，用户截图反馈时能直接定位。
          : '所有下载源都失败了（${errors.join('；')}）',
    );
  }

  static Dio _defaultClient() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        // GitHub 要求带 User-Agent（缺了 403）；Gitee 不介意。
        headers: const <String, String>{
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'my-schedule-app',
        },
      ),
    );
  }

  /// 查一个源。成功返回 [_Attempt.ok]，失败返回带人话原因的 [_Attempt.fail]。
  static Future<_Attempt> _trySource(
    Dio client,
    UpdateSource source,
    String currentVersion,
  ) async {
    try {
      final Response<dynamic> response = await client.get<dynamic>(source.apiUrl);
      final Object? data = response.data;
      final Map<String, dynamic>? json = data is Map<String, dynamic>
          ? data
          : (data is String ? _tryDecodeObject(data) : null);

      if (json == null) {
        return _Attempt.fail('返回的数据无法识别');
      }

      final ReleaseInfo? info = ReleaseInfo.fromJson(json, source);
      if (info == null) {
        return _Attempt.fail('Release 缺少版本号（tag_name）');
      }
      if (info.prerelease) {
        // 预发布版不提示升级：它可能比正式版更不稳定。
        return _Attempt.fail('最新 Release 是预发布版，已跳过');
      }

      final String latest = _stripVersionPrefix(info.tag);
      if (latest.isEmpty) {
        return _Attempt.fail('Release 的版本号为空');
      }

      if (isNewerVersion(latest, currentVersion)) {
        return _Attempt.ok(
          UpdateCheckResult.available(
            currentVersion: currentVersion,
            latestVersion: latest,
            changelog: info.changelog,
            releaseUrl: info.releaseUrl,
            apkUrl: info.apkUrl,
            source: source.label,
          ),
        );
      }

      return _Attempt.ok(
        UpdateCheckResult.upToDate(
          currentVersion: currentVersion,
          latestVersion: latest,
          source: source.label,
        ),
      );
    } on DioException catch (e) {
      return _Attempt.fail(_friendlyDioError(e, source));
    } catch (e) {
      return _Attempt.fail('检查失败：$e');
    }
  }

  /// 把 Dio 的错误翻译成能直接照着排查的人话。
  static String _friendlyDioError(DioException e, UpdateSource source) {
    final int? code = e.response?.statusCode;
    if (code == 404) {
      return '还没有发布过 Release（或仓库地址已变更）';
    }
    if (code == 403) {
      // GitHub 未认证调用限流 60 次/小时；Gitee 偶发风控。
      return '请求被拒绝（可能触发了限流），请稍后再试';
    }
    if (code != null && code >= 500) {
      return '服务暂时不可用（HTTP $code）';
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '连接超时';
      case DioExceptionType.connectionError:
        return '无法连接（部分网络环境需要代理）';
      case DioExceptionType.badResponse:
        return '返回异常（HTTP ${code ?? '未知'}）';
      default:
        return e.message ?? e.type.name;
    }
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

/// Release 里通用包的文件名（`flutter build apk --release` 的默认产物名）。
const String kUniversalApkName = 'app-release.apk';

/// 从 `assets` 数组里挑一个 APK 的下载地址。
///
/// 两条规则，按优先级：
/// 1. **优先精确匹配通用包** `app-release.apk`。Release 里同时挂分架构包时
///    （`app-arm64-v8a-release.apk` 等），通用包才能在任意机型上装。
/// 2. 没有通用包时取第一个 `.apk`。
///
/// 不能直接取第 0 个：Gitee 在没有上传附件时会自动塞源码
/// `v1.2.3.zip` / `.tar.gz`，GitHub 的 `assets` 顺序也不保证按上传时间。
String _firstApkUrl(Object? assets) {
  if (assets is! List) return '';
  String firstApk = '';
  for (final Object? asset in assets) {
    if (asset is! Map) continue;
    final String name = (asset['name']?.toString() ?? '').toLowerCase();
    if (!name.endsWith('.apk')) continue;
    final String url =
        (asset['browser_download_url']?.toString() ?? '').trim();
    if (url.isEmpty) continue;
    if (name == kUniversalApkName) return url;
    if (firstApk.isEmpty) firstApk = url;
  }
  return firstApk;
}

/// 去掉版本号前面的 `v` / `V`。
String _stripVersionPrefix(String raw) {
  String s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  return s.trim();
}

/// 把版本号拆成可比较的数字段（固定 3 段，缺的补 0）。
///
/// 支持的输入：`v0.3.0`、`0.3.0+3`、`0.3`（→ 0.3.0）、`1.0.0-beta.1`（忽略预发布）。
List<int> _versionSegments(String raw) {
  String s = _stripVersionPrefix(raw);
  // 去掉 build 元数据（`+3`）与预发布后缀（`-beta.1`）。
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
/// 只比三段数字：`0.3.0+2` 与 `0.3.0+3` 视为同一版本——build number 不参与
/// "要不要提示更新"的判断，否则每次打包自增都会弹更新，没有意义。
bool isNewerVersion(String latest, String current) {
  final List<int> a = _versionSegments(latest);
  final List<int> b = _versionSegments(current);
  for (int i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
