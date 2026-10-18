// Phase 3.2b.1：插件运行时骨架（PluginRuntime）。
//
// 职责：把「插件文件」变成「可执行的 JS」——读文件 / 校验格式 / 在 js_sandbox
// 里加载 / 按入口函数调用。**不做** ctx.http、ctx.storage 注入（留给 3.2b.2 / 3.2b.3），
// 也不接 UI。
//
// 四条错误路径全部降级为"带状态的 PluginHandle"，不抛异常：
//   文件不存在 / 非法 JS / 执行超时 / 沙箱不可用。
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'js_sandbox.dart';
import 'plugin_context.dart';
import 'plugin_ctx_script.dart';
import 'plugin_handle.dart';
import 'plugin_manifest.dart';

/// 插件运行时：加载插件文件并在沙箱里调用其入口函数。
///
/// 生命周期：`loadPlugin()` → 多次 `execute()` → `dispose()`。
/// 每个插件独占一个 [JsSandbox]；本类持有已创建的 handle，`dispose()` 会一并销毁。
class PluginRuntime {
  PluginRuntime({
    this.loadTimeout = kDefaultJsTimeout,
    this.executeTimeout = kDefaultJsTimeout,
    this.onLog,
    this.onNotify,
    @visibleForTesting this.simulateSandboxFailure = false,
    Dio? dio,
    // 命名参数不能以下划线开头，故无法用 initializing formal 直接赋给私有字段。
    // ignore: prefer_initializing_formals
  }) : _dio = dio;

  /// 加载（读文件 + 顶层求值 + 格式校验）的单步超时。
  final Duration loadTimeout;

  /// 调用入口函数时的默认超时。
  final Duration executeTimeout;

  /// 插件经 `sendMessage('log', ...')` 打出的日志回调（在父 isolate 上执行）。
  final void Function(String message)? onLog;

  /// `ctx.notify.schedule` 的落地回调（Phase 7）；`null` 表示只记日志。
  final PluginNotifyHandler? onNotify;

  /// 仅测试用：让沙箱创建失败，用于验证"沙箱不可用 → 插件降级"路径。
  @visibleForTesting
  final bool simulateSandboxFailure;

  /// 注入给 `PluginContext` 的 dio（测试可用 mock adapter）；`null` 时自建。
  final Dio? _dio;

  /// 本运行时创建过的所有 handle（含降级失败的），用于统一销毁。
  final List<PluginHandle> _handles = <PluginHandle>[];

  bool _disposed = false;

  /// 已创建的 handle 数量（含降级失败的）。
  int get handleCount => _handles.length;

  /// 加载一个插件。
  ///
  /// 三种来源（按优先级）：[jsSource] 直接给源码 → [path] 读文件 → 都没有则降级。
  /// [manifestPath] 不传时，默认在 `path` 同目录找同主名的 `.manifest.json`。
  ///
  /// **任何失败都返回降级 handle**（`isUsable == false` + [PluginHandle.reason]），
  /// 绝不抛异常。调用方读 `handle.status` / `handle.reason` 决定怎么提示用户。
  Future<PluginHandle> loadPlugin({
    String? path,
    String? jsSource,
    String? manifestPath,
  }) async {
    if (_disposed) {
      return _degraded(
        JsSandboxStatus.unavailable,
        reason: '插件运行时已销毁',
      );
    }

    // ── 1. 取源码 ──────────────────────────────────────────────
    String source;
    if (jsSource != null && jsSource.trim().isNotEmpty) {
      source = jsSource;
    } else if (path != null && path.trim().isNotEmpty) {
      try {
        source = await File(path).readAsString();
      } catch (e) {
        // 错误路径 ①：文件不存在 / 不可读
        debugPrint('[PluginRuntime] 读取插件文件失败：$path → $e');
        return _degraded(
          JsSandboxStatus.unavailable,
          sourcePath: path,
          reason: '插件文件不存在或不可读：$path',
        );
      }
      if (source.trim().isEmpty) {
        debugPrint('[PluginRuntime] 插件文件为空：$path');
        return _degraded(
          JsSandboxStatus.unavailable,
          sourcePath: path,
          reason: '插件文件为空：$path',
        );
      }
    } else {
      return _degraded(
        JsSandboxStatus.unavailable,
        reason: '必须提供 path 或 jsSource',
      );
    }

    // ── 2. 起沙箱 ──────────────────────────────────────────────
    final JsSandbox sandbox = await JsSandbox.create(
      onLog: onLog,
      // 该开关本身也是 @visibleForTesting，这里只是把它透传下去（仅测试会置真）。
      // ignore: invalid_use_of_visible_for_testing_member
      simulateCreateFailure: simulateSandboxFailure,
    );
    if (!sandbox.isUsable) {
      // 错误路径 ②：沙箱不可用（创建失败 / 超时）
      final String why = sandbox.unavailableReason ?? '未知原因';
      debugPrint('[PluginRuntime] JS 沙箱不可用：$why');
      return _degraded(
        JsSandboxStatus.unavailable,
        source: source,
        sourcePath: path,
        reason: 'JS 沙箱不可用：$why',
      );
    }

    // 从这里开始沙箱已建立，任何失败都要负责销毁它，避免泄漏 isolate。
    PluginHandle fail(
      JsSandboxStatus status, {
      String? reason,
      PluginManifest? manifest,
      List<String> entries = const <String>[],
    }) {
      final PluginHandle handle = _degraded(
        status,
        manifest: manifest,
        source: source,
        sourcePath: path,
        entries: entries,
        reason: reason,
      );
      // 降级 handle 不持有沙箱 → 立刻销毁，防止 isolate 泄漏。
      unawaitedDispose(sandbox);
      return handle;
    }

    // ── 3. 注入 ctx，再顶层求值把插件的全局定义装进沙箱 ─────────
    //
    // 顺序很重要：ctx 必须先定义好，插件的顶层代码才能引用它。
    // （ctx 的"本轮状态"由 PluginContext 在每次执行前重置。）
    final JsSandboxResult ctxResult =
        await sandbox.execute(kPluginCtxScript, timeout: loadTimeout);
    if (!ctxResult.isSuccess) {
      return fail(
        ctxResult.status,
        reason: '注入插件上下文（ctx）失败：${ctxResult.message}',
      );
    }

    final JsSandboxResult loadResult =
        await sandbox.execute(source, timeout: loadTimeout);
    if (!loadResult.isSuccess) {
      // 错误路径 ③：非法 JS（error）或顶层死循环（timeout）
      final String why = loadResult.message ?? loadResult.status.name;
      debugPrint('[PluginRuntime] 插件脚本加载失败（${loadResult.status.name}）：$why');
      return fail(
        loadResult.status,
        reason: loadResult.isTimeout
            ? '插件脚本加载超时（顶层可能死循环）：$why'
            : '插件脚本加载失败：$why',
      );
    }

    // ── 4. 校验 `__plugin` 存在且是对象 ────────────────────────
    final JsSandboxResult shapeCheck = await sandbox.execute(
      "(typeof $kPluginGlobalName === 'object' && $kPluginGlobalName !== null)"
      " ? 'true' : 'false'",
      timeout: loadTimeout,
    );
    if (!shapeCheck.isSuccess) {
      return fail(shapeCheck.status,
          reason: '校验插件全局对象时失败：${shapeCheck.message}');
    }
    if (shapeCheck.value != 'true') {
      debugPrint('[PluginRuntime] 插件未定义全局 $kPluginGlobalName');
      return fail(
        JsSandboxStatus.error,
        reason: '插件未定义全局 $kPluginGlobalName 对象（需 `var $kPluginGlobalName = {...}`）',
      );
    }

    // ── 5. 收集入口函数 ────────────────────────────────────────
    final JsSandboxResult entriesResult = await sandbox.execute(
      "JSON.stringify(Object.keys($kPluginGlobalName).filter(function (k) {"
      " return typeof $kPluginGlobalName[k] === 'function'; }))",
      timeout: loadTimeout,
    );
    if (!entriesResult.isSuccess) {
      return fail(entriesResult.status,
          reason: '收集插件入口函数失败：${entriesResult.message}');
    }
    final List<String> entries = _decodeStringList(entriesResult.value);
    if (entries.isEmpty) {
      return fail(
        JsSandboxStatus.error,
        reason: '插件未定义任何入口函数（$kPluginGlobalName 里至少需要一个函数属性）',
      );
    }

    // ── 6. 取 manifest（文件优先，其次从 JS 推导）──────────────
    PluginManifest? manifest;
    final String? resolvedManifestPath =
        manifestPath ?? (path == null ? null : _defaultManifestPath(path));
    if (resolvedManifestPath != null) {
      final File manifestFile = File(resolvedManifestPath);
      if (await manifestFile.exists()) {
        String raw;
        try {
          raw = await manifestFile.readAsString();
        } catch (e) {
          debugPrint('[PluginRuntime] 读取 manifest 失败：$e');
          return fail(JsSandboxStatus.error,
              reason: '插件 manifest 不可读：$resolvedManifestPath');
        }
        manifest = PluginManifest.tryDecode(raw);
        if (manifest == null) {
          // manifest 文件存在但坏 → 视为格式非法，不静默忽略
          return fail(JsSandboxStatus.error,
              reason: '插件 manifest 解析失败（需含非空 id）：$resolvedManifestPath');
        }
      }
    }
    manifest ??= await _deriveManifest(sandbox);
    if (manifest == null || !manifest.hasValidId) {
      return fail(
        JsSandboxStatus.error,
        entries: entries,
        reason: '插件缺少 id（需在 manifest 文件里，或 $kPluginGlobalName.id 上提供）',
      );
    }

    debugPrint('[PluginRuntime] 插件加载成功：${manifest.id}，入口函数 $entries');
    final PluginHandle handle = PluginHandle(
      status: JsSandboxStatus.success,
      manifest: manifest,
      source: source,
      entries: entries,
      sourcePath: path,
      sandbox: sandbox,
      // 宿主侧 ctx：真正发网络 / 读写 Hive / 读凭证 + 驱动重放。
      context: PluginContext(
        pluginId: manifest.id,
        dio: _dio,
        onNotify: onNotify,
      ),
    );
    _handles.add(handle);
    return handle;
  }

  /// 调用某个插件的入口函数。委托给 [PluginHandle.execute]。
  ///
  /// 返回 [JsSandboxResult] 四态；**不抛异常**。插件执行超时后该插件的沙箱
  /// 会被 kill，`handle.isUsable` 随之变为 `false`，后续调用返回 `unavailable`。
  Future<JsSandboxResult> execute(
    PluginHandle handle,
    String entryFunction, {
    Map<String, dynamic>? args,
    Duration? timeout,
  }) {
    if (_disposed) {
      return Future<JsSandboxResult>.value(
        const JsSandboxResult.unavailable('插件运行时已销毁'),
      );
    }
    return handle.execute(
      entryFunction,
      args: args,
      timeout: timeout ?? executeTimeout,
    );
  }

  /// 销毁所有插件的沙箱。幂等。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final PluginHandle handle in _handles) {
      await handle.dispose();
    }
    _handles.clear();
  }

  /// 造一个降级 handle（不入 `_handles`——它不持有沙箱，无需统一销毁）。
  PluginHandle _degraded(
    JsSandboxStatus status, {
    String? reason,
    PluginManifest? manifest,
    String source = '',
    String? sourcePath,
    List<String> entries = const <String>[],
  }) {
    debugPrint('[PluginRuntime] 插件降级（${status.name}）：$reason');
    return PluginHandle(
      status: status,
      manifest: manifest,
      source: source,
      sourcePath: sourcePath,
      entries: entries,
      reason: reason,
    );
  }

  /// 从 `__plugin` 的 id/name/version/capabilities 推导 manifest。
  ///
  /// 走 JS 侧 `JSON.stringify` + Dart 侧 `jsonDecode`（不用 `convertValue`）。
  /// 推导失败返回 `null`（由调用方降级），不抛异常。
  Future<PluginManifest?> _deriveManifest(JsSandbox sandbox) async {
    final JsSandboxResult r = await sandbox.execute(
      "JSON.stringify({"
      " id: $kPluginGlobalName.id,"
      " name: $kPluginGlobalName.name,"
      " version: $kPluginGlobalName.version,"
      " author: $kPluginGlobalName.author,"
      " description: $kPluginGlobalName.description,"
      " school: $kPluginGlobalName.school,"
      " capabilities: $kPluginGlobalName.capabilities,"
      // Phase 4.1：登录页 URL 与成功判定前缀由插件自己声明（各校地址不同）
      " loginUrl: $kPluginGlobalName.loginUrl,"
      " checkUrl: $kPluginGlobalName.checkUrl,"
      // 登录成功后自动导航的目标（可选）：教务系统登录后常停在首页，
      // 而 checkUrl 在更深的业务页，声明它才能"登录完自动到那一步"。
      " postLoginUrl: $kPluginGlobalName.postLoginUrl,"
      // 校外登录：校园网探测 + 桌面 UA + CAS 二维码定位（均可选）。
      " campusProbeUrl: $kPluginGlobalName.campusProbeUrl,"
      " offCampusHost: $kPluginGlobalName.offCampusHost,"
      " offCampusUserAgent: $kPluginGlobalName.offCampusUserAgent,"
      " qrLogin: $kPluginGlobalName.qrLogin"
      "})",
      timeout: loadTimeout,
    );
    if (!r.isSuccess) {
      debugPrint('[PluginRuntime] 推导 manifest 失败：${r.message}');
      return null;
    }
    final Object? decoded = _tryDecodeJson(r.value);
    if (decoded is! Map<String, dynamic>) return null;
    return PluginManifest.fromJson(decoded);
  }

  /// 由插件路径推出默认 manifest 路径：`a.js` → `a.manifest.json`。
  static String _defaultManifestPath(String pluginPath) {
    final int dot = pluginPath.lastIndexOf('.');
    final int sep = pluginPath.lastIndexOf(RegExp(r'[/\\]'));
    if (dot > sep) {
      return '${pluginPath.substring(0, dot)}$kPluginManifestSuffix';
    }
    return '$pluginPath$kPluginManifestSuffix';
  }

  /// 解析 JSON 字符串列表；坏 JSON 或非数组返回空列表。
  static List<String> _decodeStringList(String? raw) {
    final Object? decoded = _tryDecodeJson(raw);
    if (decoded is! List) return const <String>[];
    return decoded.whereType<String>().toList(growable: false);
  }

  /// 安全 jsonDecode：`null` / 坏 JSON 返回 `null`，不抛异常。
  static Object? _tryDecodeJson(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'undefined') return null;
    try {
      return jsonDecode(raw);
    } catch (e) {
      debugPrint('[PluginRuntime] JSON 解析失败：$e');
      return null;
    }
  }
}

/// 不等待地销毁沙箱（降级路径用，避免让失败路径再阻塞一次）。
void unawaitedDispose(JsSandbox sandbox) {
  sandbox.dispose().catchError((Object e) {
    debugPrint('[PluginRuntime] 销毁沙箱失败：$e');
  });
}