// Phase 3.1 最小验证：flutter_js 集成测试。
// 该文件仅用于验证 flutter_js（QuickJS）能在本项目里跑起来，
// Phase 3.2 起会被正式的插件运行时（lib/runtime/plugin_runtime.dart）替代。
//
// 验证四件事：
//   1. 创建 JS 运行时并执行简单表达式（1 + 1 → 2）
//   2. 从 JS 调用 Dart 注入的函数
//   3. JS 构造对象，Dart 解析成 Map
//   4. 非法 JS 不崩溃，返回错误结果
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

/// Phase 3.1 最小验证类（纯静态，用完即弃）。
///
/// **不要**在此基础上扩展成插件运行时——沙箱、权限、文件加载都是 Phase 3.2+ 的事。
class PluginDemo {
  /// 禁止实例化：本类只提供静态方法。
  PluginDemo._();

  /// 创建并初始化一个 QuickJS 运行时。
  ///
  /// `getJavascriptRuntime()` 在 Android / Windows / Linux 上走 QuickJS，
  /// 其他平台走 JavaScriptCore，调用方无需关心平台差异。
  ///
  /// `xhr: false` 关掉内置的 fetch/XHR 扩展：本阶段不测网络，
  /// 少一层依赖就少一个失败点。Phase 3.2 需要 `ctx.http` 时再打开。
  static JavascriptRuntime _createRuntime() {
    return getJavascriptRuntime(xhr: false);
  }

  /// 执行 `1 + 1`，返回 2。
  ///
  /// 返回 `int?`：JS 侧结果不是数字（或执行出错）时为 `null`，
  /// 而不是抛异常——调用方据此判断"集成是否可用"。
  static int? evalSimple() {
    final JavascriptRuntime runtime = _createRuntime();
    try {
      final JsEvalResult result = runtime.evaluate('1 + 1');
      if (result.isError) {
        debugPrint('[PluginDemo] evalSimple 执行出错：${result.stringResult}');
        return null;
      }
      return _asInt(result.rawResult);
    } catch (e) {
      debugPrint('[PluginDemo] evalSimple 异常：$e');
      return null;
    } finally {
      runtime.dispose();
    }
  }

  /// 注入 Dart 函数供 JS 调用，返回该 Dart 函数给出的结果。
  ///
  /// 链路：JS 调 `sendMessage('demoEcho', '"ping"')`
  ///   → Dart 侧 `onMessage('demoEcho', ...)` 收到 `'ping'`
  ///   → Dart 返回 `'pong'`
  ///   → JS 把返回值拼进字符串 → Dart 取回。
  ///
  /// 这是**同步**往返：`sendMessage` 在 QuickJS 里是阻塞调用，
  /// 返回值直接回到 JS 表达式里。
  static String? evalWithCallback() {
    final JavascriptRuntime runtime = _createRuntime();
    try {
      // 注册 Dart 侧回调。参数是 JS 传过来的、已被 jsonDecode 的值。
      runtime.onMessage('demoEcho', (dynamic args) {
        debugPrint('[PluginDemo] JS 传回 Dart 的参数：$args');
        return 'pong';
      });

      // JS 调 sendMessage 并把 Dart 的返回值拼进结果串。
      final JsEvalResult result = runtime.evaluate(
        "sendMessage('demoEcho', JSON.stringify('ping')) + '|from-dart'",
      );
      if (result.isError) {
        debugPrint('[PluginDemo] evalWithCallback 执行出错：${result.stringResult}');
        return null;
      }
      return result.stringResult;
    } catch (e) {
      debugPrint('[PluginDemo] evalWithCallback 异常：$e');
      return null;
    } finally {
      runtime.dispose();
    }
  }

  /// JS 构造对象，Dart 解析成 Map。
  ///
  /// 为什么绕一层 `JSON.stringify`：QuickJS 后端的 `jsonStringify` 是
  /// `UnimplementedError`，而 `rawResult` 的实际 Dart 类型（Map / JSInvokable）
  /// 不够稳定。在 JS 侧 stringify、Dart 侧 `jsonDecode` 是最可靠的一条路，
  /// 也正好是 Phase 3.2 插件返回课程数据时要用的序列化方式。
  static Map<String, dynamic>? evalWithObject() {
    final JavascriptRuntime runtime = _createRuntime();
    try {
      const String script = '''
        (function () {
          var course = {
            name: '高等数学',
            teacher: '张三',
            unit: 3.5,
            weeks: [1, 2, 3],
            nested: { room: 'HE-405' }
          };
          return JSON.stringify(course);
        })()
      ''';
      final JsEvalResult result = runtime.evaluate(script);
      if (result.isError) {
        debugPrint('[PluginDemo] evalWithObject 执行出错：${result.stringResult}');
        return null;
      }
      return _decodeJsonObject(result.stringResult);
    } catch (e) {
      debugPrint('[PluginDemo] evalWithObject 异常：$e');
      return null;
    } finally {
      runtime.dispose();
    }
  }

  /// 执行非法 JS，返回错误信息；**不抛异常**（验证错误被兜住）。
  ///
  /// 返回 `null` 表示"没能拿到错误信息"——那才是真正的问题；
  /// 正常情况应返回非空字符串。
  static String? evalInvalid() {
    final JavascriptRuntime runtime = _createRuntime();
    try {
      final JsEvalResult result = runtime.evaluate('this is not valid javascript(((');
      debugPrint('[PluginDemo] 非法 JS 的 isError=${result.isError}');
      if (!result.isError) {
        // 语法错误却没被标记成错误，说明错误检测不可信。
        debugPrint('[PluginDemo] 非法 JS 未被识别为错误：${result.stringResult}');
        return null;
      }
      return result.stringResult;
    } catch (e) {
      // QuickJS 后端理论上不抛（错误走 isError），真抛了也算兜住。
      debugPrint('[PluginDemo] evalInvalid 抛出异常（已兜住）：$e');
      return e.toString();
    } finally {
      runtime.dispose();
    }
  }

  /// 把 JS 数值结果转成 `int`；非数值返回 `null`。
  ///
  /// QuickJS 的 `rawResult` 对数字是 `int` 还是 `double` 取决于实现，
  /// 故两种都接受，`2.0` 也认成 `2`。
  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is double && value == value.roundToDouble()) {
      return value.toInt();
    }
    return null;
  }

  /// 把 JSON 文本解析成 `Map`；非对象（数组 / 标量 / 坏 JSON）返回 `null`。
  static Map<String, dynamic>? _decodeJsonObject(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      debugPrint('[PluginDemo] 期望 JSON 对象，实际是：${decoded.runtimeType}');
      return null;
    } catch (e) {
      debugPrint('[PluginDemo] JSON 解析失败：$e');
      return null;
    }
  }
}