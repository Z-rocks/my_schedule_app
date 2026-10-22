// Phase 3.2b.1：已加载插件的句柄（PluginHandle）。
//
// 一个 handle = 一个插件 = **一个独占的 JsSandbox**。
// 为什么每插件一个沙箱（而不是共用一个）：插件的 `__plugin` 是全局变量，
// 共用会让两个插件互相覆盖；独占沙箱还能做到"某个插件死循环只打死它自己的
// isolate"，与 Phase 3.2a 的隔离设计一致。
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'js_sandbox.dart';
import 'plugin_context.dart';
import 'plugin_manifest.dart';

/// 插件在 JS 里必须定义的全局对象名。
///
/// 插件脚本形如：
/// ```js
/// var __plugin = {
///   id: 'demo-course-plugin',
///   name: '演示插件',
///   version: '1.0.0',
///   fetchCourses: function (args) { return { courses: [] }; }
/// };
/// ```
/// 其属性中的**函数**即入口函数，由 [buildPluginEntryCallScript] 调用。
const String kPluginGlobalName = '__plugin';

/// 构造"调用插件入口函数"的 JS 脚本。
///
/// 关键点（沿用 Phase 3.2a 约束 3）：
/// - 序列化只走 **JS 侧 `JSON.stringify` + Dart 侧 `jsonDecode`**，
///   不用 `convertValue`（QuickJS 后端是假实现）。
/// - 参数与函数名都用 `jsonEncode` 转成 **JSON 字符串字面量**再嵌进脚本。
///   JSON 的字符串转义是 JS 字符串字面义的子集，因此 `jsonEncode` 一次得到
///   `"fetchCourses"`，两次得到 `"{\"a\":1}"`——后者直接就是合法的 JS 字面量，
///   免去手写转义（手写转义在参数含引号/换行时极易出错）。
/// - `JSON.stringify(undefined)` 返回 `undefined` 而非字符串，故显式归一为 `'null'`。
String buildPluginEntryCallScript(
  String entryFunction,
  Map<String, dynamic>? args,
) {
  final String fnLiteral = jsonEncode(entryFunction);
  final String argsLiteral = jsonEncode(jsonEncode(args ?? const <String, dynamic>{}));
  return '''
(function () {
  var __f = $kPluginGlobalName[$fnLiteral];
  if (typeof __f !== 'function') {
    throw new Error('entry function not found: ' + $fnLiteral);
  }
  var __r = __f(JSON.parse($argsLiteral));
  return (__r === undefined) ? 'null' : JSON.stringify(__r);
})()
''';
}

/// 一个已加载插件的句柄。
///
/// **不可变值对象 + 持有独占沙箱**。加载失败时也返回一个 handle，只是
/// [status] 不是 `success`、[isUsable] 为 `false`，并在 [reason] 里给出原因——
/// 调用方据此把插件标记为不可用，而不是接异常。
@immutable
class PluginHandle {
  const PluginHandle({
    required this.status,
    this.manifest,
    this.source = '',
    this.entries = const <String>[],
    this.sourcePath,
    this.reason,
    JsSandbox? sandbox,
    PluginContext? context,
    // 命名参数不能以下划线开头，故无法用 initializing formal 直接赋给私有字段。
    // ignore: prefer_initializing_formals
  })  : _sandbox = sandbox,
        // ignore: prefer_initializing_formals
        _context = context;

  /// 加载/运行状态，复用 [JsSandboxStatus] 四态。
  ///
  /// - `success`：加载成功，可用
  /// - `error`：插件格式非法（语法错误 / 缺 `__plugin` / 缺 id / 无入口函数 / manifest 坏）
  /// - `timeout`：加载时脚本顶层就死循环，已被掐断
  /// - `unavailable`：文件不存在或不可读 / JS 沙箱不可用
  final JsSandboxStatus status;

  /// 插件元数据。降级过早（文件都读不到）时为 `null`。
  final PluginManifest? manifest;

  /// 插件 JS 源码（文件读不到时为空串）。
  final String source;

  /// 发现的入口函数名列表。
  final List<String> entries;

  /// 插件文件路径；从 `jsSource` 直接加载时为 `null`。
  final String? sourcePath;

  /// 降级原因（仅加载失败时有值）。
  final String? reason;

  /// 该插件独占的沙箱。降级过早时为 `null`。
  final JsSandbox? _sandbox;

  /// 该插件的运行上下文（宿主服务 + 重放循环）。降级过早时为 `null`。
  ///
  /// 有它时 [execute] 会走"登记待办 → 宿主取数 → 重放"的 ctx 流程；
  /// 没有它时退化为单次求值（兼容 Phase 3.5 之前的用法与测试）。
  final PluginContext? _context;

  /// 插件当前是否可用。
  ///
  /// **动态判定**：除加载状态为 `success` 外，还要求底层沙箱仍然存活。
  /// 因此插件某次执行超时（沙箱被 kill）后，这个 getter 会自动变成 `false`，
  /// 无需修改任何字段——这也让本类得以保持完全不可变。
  bool get isUsable => status == JsSandboxStatus.success && (_sandbox?.isUsable ?? false);

  /// 插件是否加载成功（只看加载结果，不含沙箱后续存活状态）。
  bool get isLoaded => status == JsSandboxStatus.success;

  /// 调用插件的一个入口函数。
  ///
  /// [args] 会经 JSON 传入 JS（插件侧收到一个普通对象）。
  /// 返回结果复用 [JsSandboxResult] 四态；**不抛异常**。
  ///
  /// **Phase 3.6 起走 ctx 流程**：若持有 [PluginContext]，会驱动
  /// "登记 HTTP 待办 → 宿主取数 → 重放插件函数"直到没有待办为止
  /// （因此插件函数可能被执行多次，见 `plugin_ctx_script.dart`）。
  Future<JsSandboxResult> execute(
    String entryFunction, {
    Map<String, dynamic>? args,
    Duration timeout = kDefaultJsTimeout,
    Map<String, Object?>? semester,
  }) async {
    if (status != JsSandboxStatus.success) {
      return JsSandboxResult.unavailable(reason ?? '插件未成功加载');
    }
    final JsSandbox? sandbox = _sandbox;
    if (sandbox == null) {
      return JsSandboxResult.unavailable('插件没有可用的 JS 沙箱');
    }
    if (!sandbox.isUsable) {
      // 沙箱已被销毁（多半是上次执行超时），句柄随之不可用。
      return JsSandboxResult.unavailable(reason ?? '插件运行时已被销毁');
    }
    final String script = buildPluginEntryCallScript(entryFunction, args);
    final PluginContext? context = _context;
    if (context == null) {
      return sandbox.execute(script, timeout: timeout);
    }
    return context.execute(
      sandbox: sandbox,
      entryCallScript: script,
      timeout: timeout,
      semester: semester,
    );
  }

  /// 销毁该插件独占的沙箱。幂等。
  Future<void> dispose() async {
    await _sandbox?.dispose();
  }

  @override
  String toString() => 'PluginHandle(${manifest?.id ?? sourcePath ?? '<inline>'}, '
      '${status.name}${reason == null ? '' : ', $reason'})';
}