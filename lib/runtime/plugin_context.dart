// Phase 3.6：插件运行上下文（宿主侧）。
//
// 职责：给插件提供 `ctx.http` / `ctx.storage` / `ctx.log` / `ctx.notify` / `ctx.cookie`
// 这五类能力的**宿主实现**，并驱动"登记待办 → 宿主取数 → 重放插件函数"的循环。
//
// JS 侧的契约（`ctx` 对象与内部 primitive）在 `plugin_ctx_script.dart`；
// 本文件只管"宿主这一半"：真正发网络、真正读写 Hive、真正读凭证。
//
// 为什么需要重放（而不是让 JS 直接等 Dart）：见 `plugin_ctx_script.dart` 顶部说明。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/storage_service.dart';
import 'js_sandbox.dart';
import 'plugin_ctx_script.dart';

/// 一次 HTTP 请求的描述（由 JS 侧登记、宿主执行）。
@immutable
class PluginHttpRequest {
  const PluginHttpRequest({
    required this.method,
    required this.url,
    required this.key,
    this.body,
    this.headers = const <String, String>{},
  });

  /// `GET` / `POST`（当前 JS 侧只暴露这两个）。
  final String method;

  /// 目标 URL。
  final String url;

  /// 去重键（`method|url|body|headersJson`），与 JS 侧一致。
  final String key;

  /// 请求体，`null` 表示无。
  final String? body;

  /// 请求头。
  final Map<String, String> headers;

  /// 从 JS 登记的对象解析；字段缺失或类型不符时返回 `null`（跳过该条）。
  static PluginHttpRequest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Object? method = raw['method'];
    final Object? url = raw['url'];
    final Object? key = raw['key'];
    if (method is! String || url is! String || key is! String) return null;
    if (url.trim().isEmpty || key.isEmpty) return null;

    final Map<String, String> headers = <String, String>{};
    final Object? rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((dynamic k, dynamic v) {
        if (k != null && v != null) headers['$k'] = '$v';
      });
    }
    final Object? body = raw['body'];
    return PluginHttpRequest(
      method: method.toUpperCase(),
      url: url,
      key: key,
      body: body is String ? body : null,
      headers: headers,
    );
  }

  @override
  String toString() => 'PluginHttpRequest($method $url)';
}

/// 插件上下文：宿主注入给插件的 API 实现。
///
/// **不做权限系统**（本阶段所有插件都能用全部 ctx，见任务范围）；
/// 网络白名单同样不做。
class PluginContext {
  PluginContext({
    required this.pluginId,
    Dio? dio,
    FlutterSecureStorage? secureStorage,
  })  : _dio = dio ?? _defaultDio(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// 本上下文所属的插件 id（用于 storage 命名空间与日志前缀）。
  final String pluginId;

  final Dio _dio;
  final FlutterSecureStorage _secureStorage;

  /// HTTP 连接超时。
  static const Duration kHttpConnectTimeout = Duration(seconds: 10);

  /// HTTP 接收超时（首字节之后）。
  static const Duration kHttpReceiveTimeout = Duration(seconds: 15);

  /// 单次执行的**最大重放轮数**。
  ///
  /// 每轮最多满足一批新请求；一个正常的同步流程通常 1–3 轮就够。
  /// 超过上限说明插件在无限追加请求（或请求 key 每次都不同），
  /// 直接返回错误而不是无限循环。
  static const int kMaxReplayRounds = 8;

  /// 固定 UA：便于教务系统识别请求来自本 App。
  static const String kUserAgent = 'MySchedule/0.1';

  /// 凭证在 secure storage 里的 key 后缀（完整 key 为 `<pluginId>:cookie`）。
  static const String kCookieKeySuffix = ':cookie';

  /// storage 键前缀分隔符（`<pluginId>:<userKey>`）。
  static const String kStorageKeySeparator = ':';

  static Dio _defaultDio() {
    return Dio(BaseOptions(
      connectTimeout: kHttpConnectTimeout,
      receiveTimeout: kHttpReceiveTimeout,
      sendTimeout: kHttpConnectTimeout,
      responseType: ResponseType.plain,
    ));
  }

  // ─────────────────────────── 凭证 ───────────────────────────

  /// 读取本插件的 Cookie。
  ///
  /// **本阶段只读不写**：Phase 4 的 WebView 登录会把 Cookie 写进
  /// `flutter_secure_storage` 的 `<pluginId>:cookie`。
  /// 不存在或读取失败（含测试环境无平台通道）一律返回空字符串，不抛异常。
  Future<String> loadCookie() async {
    try {
      final String? value = await _secureStorage.read(
        key: '$pluginId$kCookieKeySuffix',
      );
      return value ?? '';
    } catch (e) {
      debugPrint('[Plugin:$pluginId] 读取 Cookie 失败（按空处理）：$e');
      return '';
    }
  }

  // ─────────────────────────── storage ───────────────────────────

  /// 读取本插件命名空间的全部 KV 快照（`userKey → value`）。
  ///
  /// 一次性读整表再按前缀过滤：Hive 的 `toMap()` 只访问一次 Box，
  /// 比逐个 `get` 更省（与 `OverrideEngine.getAllOverrides` 同一思路）。
  Future<Map<String, String>> loadStorageSnapshot() async {
    final String prefix = '$pluginId$kStorageKeySeparator';
    final Map<String, String> result = <String, String>{};
    try {
      StorageService.pluginDataBox.toMap().forEach((dynamic key, dynamic value) {
        if (key is! String || value is! String) return;
        if (!key.startsWith(prefix)) return;
        result[key.substring(prefix.length)] = value;
      });
    } catch (e) {
      debugPrint('[Plugin:$pluginId] 读取 storage 失败（按空处理）：$e');
    }
    return result;
  }

  /// 把最终轮的 storage 变更提交到 Hive。
  ///
  /// [touched] 只列本轮改动过的键：存在于 [storage] 的写入，不存在于其中的删除。
  /// 失败只记日志，不抛异常（插件的数据问题不该崩掉 App）。
  Future<void> commitStorageChanges({
    required Map<String, String> storage,
    required List<String> touched,
  }) async {
    if (touched.isEmpty) return;
    try {
      final box = StorageService.pluginDataBox;
      for (final String userKey in touched) {
        final String boxKey = '$pluginId$kStorageKeySeparator$userKey';
        if (storage.containsKey(userKey)) {
          await box.put(boxKey, storage[userKey]!);
        } else {
          await box.delete(boxKey);
        }
      }
    } catch (e) {
      debugPrint('[Plugin:$pluginId] 提交 storage 失败：$e');
    }
  }

  // ─────────────────────────── HTTP ───────────────────────────

  /// 依次执行一批请求，返回 `请求 key → 响应 JSON 字符串`。
  ///
  /// **串行**执行（不并发）：一个插件的请求通常有先后依赖（先登录页再取数据），
  /// 且串行对教务系统更友好。任何失败都编码进 JSON，不抛异常。
  Future<Map<String, String>> performHttpRequests(
    List<PluginHttpRequest> requests,
  ) async {
    final Map<String, String> result = <String, String>{};
    for (final PluginHttpRequest request in requests) {
      result[request.key] = await _performOne(request);
    }
    return result;
  }

  /// 执行单个请求，返回统一格式的响应 JSON。
  Future<String> _performOne(PluginHttpRequest request) async {
    try {
      final Response<String> response = await _dio.request<String>(
        request.url,
        data: request.body,
        options: Options(
          method: request.method,
          headers: <String, dynamic>{
            ...request.headers,
            'User-Agent': kUserAgent,
          },
          responseType: ResponseType.plain,
          followRedirects: true,
          connectTimeout: kHttpConnectTimeout,
          receiveTimeout: kHttpReceiveTimeout,
          sendTimeout: kHttpConnectTimeout,
          // 任何状态码都算"拿到了响应"——4xx/5xx 的正文对插件往往有用
          // （例如教务系统用 500 返回错误页）。由插件自己判断 status。
          validateStatus: (int? _) => true,
        ),
      );
      return jsonEncode(<String, dynamic>{
        'ok': true,
        'status': response.statusCode,
        'body': response.data ?? '',
        'headers': _flattenHeaders(response.headers),
      });
    } on DioException catch (e) {
      debugPrint('[Plugin:$pluginId] HTTP ${request.method} ${request.url} 失败：'
          '${e.type}');
      return jsonEncode(<String, dynamic>{
        'ok': false,
        'error': _errorName(e),
      });
    } catch (e) {
      debugPrint('[Plugin:$pluginId] HTTP 异常：$e');
      return jsonEncode(<String, dynamic>{'ok': false, 'error': '$e'});
    }
  }

  /// 把 dio 的超时/连接错误映射成插件能判断的短标识。
  ///
  /// 插件侧约定：`error === 'timeout'` 表示超时（见任务书决策 4）。
  static String _errorName(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'timeout';
      case DioExceptionType.badCertificate:
        return 'bad_certificate';
      case DioExceptionType.connectionError:
        return 'connection';
      case DioExceptionType.cancel:
        return 'cancelled';
      case DioExceptionType.badResponse:
        return 'bad_response';
      case DioExceptionType.unknown:
        return 'unknown';
    }
  }

  /// 响应头 `Map<String, List<String>>` → `Map<String, String>`（多值逗号连接）。
  static Map<String, String> _flattenHeaders(Headers headers) {
    final Map<String, String> result = <String, String>{};
    headers.forEach((String name, List<String> values) {
      result[name] = values.join(', ');
    });
    return result;
  }

  // ─────────────────────── 执行（含重放） ───────────────────────

  /// 执行一次插件入口调用，必要时**重放**直到所有 `ctx.http` 请求都被满足。
  ///
  /// 返回与沙箱一致的 [JsSandboxResult]（四态）；**不抛异常**。
  ///
  /// 关键点：
  /// - 只要本轮登记了待办请求，就**无论本轮结果如何**（成功、抛错、`pending`）
  ///   都重放——这样插件写 `try/catch` 或直接 `throw` 都不影响正确性；
  /// - 只有**没有待办**的那一轮才是最终轮，其 storage / log / notify 副作用会被提交；
  /// - 轮数超过 [kMaxReplayRounds] 返回 `error`，避免死循环。
  Future<JsSandboxResult> execute({
    required JsSandbox sandbox,
    required String entryCallScript,
    Duration timeout = kDefaultJsTimeout,
  }) async {
    final String cookie = await loadCookie();
    final Map<String, String> storage = await loadStorageSnapshot();
    final Map<String, String> httpCache = <String, String>{};

    for (int round = 0; round < kMaxReplayRounds; round++) {
      final String preamble = buildCtxStateScript(
        httpCache: httpCache,
        storage: storage,
        cookie: cookie,
      );
      final JsSandboxResult result = await sandbox.execute(
        '$preamble\n$entryCallScript',
        timeout: timeout,
      );

      // 沙箱已死（超时被 kill / 不可用）→ 没有"下一轮"可言，直接返回。
      if (result.isTimeout || result.isUnavailable) return result;

      final _CtxRound? roundEffects = await _readRoundEffects(sandbox, timeout);
      if (roundEffects == null) {
        // 读不回副作用（沙箱出错）：只能把本轮结果原样返回。
        return result;
      }

      if (roundEffects.pending.isEmpty) {
        // ── 最终轮：提交副作用 ──
        await commitStorageChanges(
          storage: roundEffects.storage,
          touched: roundEffects.touched,
        );
        _emitLogs(roundEffects.logs);
        _emitNotifies(roundEffects.notifies);
        return result;
      }

      // ── 还有待办：取回响应后重放 ──
      debugPrint('[Plugin:$pluginId] 第 ${round + 1} 轮登记了 '
          '${roundEffects.pending.length} 个 HTTP 请求，取回后重放');
      httpCache.addAll(await performHttpRequests(roundEffects.pending));
    }

    debugPrint('[Plugin:$pluginId] 重放轮数超过上限 $kMaxReplayRounds');
    return JsSandboxResult.error(
      '插件 HTTP 重放轮数超过上限（$kMaxReplayRounds）',
    );
  }

  /// 读回本轮的待办请求与副作用。
  Future<_CtxRound?> _readRoundEffects(
    JsSandbox sandbox,
    Duration timeout,
  ) async {
    final JsSandboxResult dump = await sandbox.execute(
      kCtxDumpScript,
      timeout: timeout,
    );
    if (!dump.isSuccess || dump.value == null) {
      debugPrint('[Plugin:$pluginId] 读回 ctx 副作用失败：${dump.message}');
      return null;
    }
    return _CtxRound.tryParse(dump.value!);
  }

  /// `ctx.log` 输出（最终轮才输出，避免重放刷屏）。
  void _emitLogs(List<_CtxLog> logs) {
    for (final _CtxLog log in logs) {
      if (log.level == 'error') {
        debugPrint('[Plugin:$pluginId][error] ${log.message}');
      } else {
        debugPrint('[Plugin:$pluginId] ${log.message}');
      }
    }
  }

  /// `ctx.notify.schedule` 占位实现：只记日志，不真弹通知（Phase 7 接）。
  void _emitNotifies(List<_CtxNotify> notifies) {
    for (final _CtxNotify notify in notifies) {
      debugPrint('[Plugin:$pluginId][notify] 计划提醒「${notify.title}」'
          '（${notify.triggerAtIso}）：${notify.body} —— Phase 7 接真实通知');
    }
  }
}

/// 一轮的副作用（内部解析结果）。
class _CtxRound {
  const _CtxRound({
    required this.pending,
    required this.storage,
    required this.touched,
    required this.logs,
    required this.notifies,
  });

  final List<PluginHttpRequest> pending;
  final Map<String, String> storage;
  final List<String> touched;
  final List<_CtxLog> logs;
  final List<_CtxNotify> notifies;

  /// 从 dump JSON 解析；坏数据一律按"空"处理，不抛异常。
  static _CtxRound? tryParse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      debugPrint('[PluginContext] 解析 ctx dump 失败：$e');
      return null;
    }
    if (decoded is! Map) return null;

    final List<PluginHttpRequest> pending = <PluginHttpRequest>[];
    final Object? rawPending = decoded['pending'];
    if (rawPending is List) {
      for (final Object? item in rawPending) {
        final PluginHttpRequest? request = PluginHttpRequest.tryParse(item);
        if (request != null) pending.add(request);
      }
    }

    final Map<String, String> storage = <String, String>{};
    final Object? rawStorage = decoded['storage'];
    if (rawStorage is Map) {
      rawStorage.forEach((dynamic k, dynamic v) {
        if (k != null && v != null) storage['$k'] = '$v';
      });
    }

    final List<String> touched = <String>[];
    final Object? rawTouched = decoded['touched'];
    if (rawTouched is List) {
      for (final Object? item in rawTouched) {
        if (item != null) touched.add('$item');
      }
    }

    final List<_CtxLog> logs = <_CtxLog>[];
    final Object? rawLogs = decoded['logs'];
    if (rawLogs is List) {
      for (final Object? item in rawLogs) {
        if (item is Map) {
          logs.add(_CtxLog(
            level: '${item['level'] ?? 'info'}',
            message: '${item['msg'] ?? ''}',
          ));
        }
      }
    }

    final List<_CtxNotify> notifies = <_CtxNotify>[];
    final Object? rawNotifies = decoded['notifies'];
    if (rawNotifies is List) {
      for (final Object? item in rawNotifies) {
        if (item is Map) {
          notifies.add(_CtxNotify(
            title: '${item['title'] ?? ''}',
            body: '${item['body'] ?? ''}',
            triggerAtIso: '${item['triggerAtIso'] ?? ''}',
          ));
        }
      }
    }

    return _CtxRound(
      pending: pending,
      storage: storage,
      touched: touched,
      logs: logs,
      notifies: notifies,
    );
  }
}

/// `ctx.log` 的一条记录。
class _CtxLog {
  const _CtxLog({required this.level, required this.message});
  final String level;
  final String message;
}

/// `ctx.notify.schedule` 的一次调用。
class _CtxNotify {
  const _CtxNotify({
    required this.title,
    required this.body,
    required this.triggerAtIso,
  });
  final String title;
  final String body;
  final String triggerAtIso;
}
