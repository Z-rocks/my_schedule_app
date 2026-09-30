// Phase 3.2a：JS 运行时沙箱与兜底。
//
// 职责：把 flutter_js（QuickJS）包成一个**不会拖死 UI 线程、不会因插件乱来而崩溃**的执行环境。
//
// 为什么必须用独立 isolate（实测结论，不是设计偏好）：
//   `QuickJsRuntime2.timeout` 实测**无法中断死循环**——`while(true){}` 传 timeout=1000
//   与 timeout=1 都会永久挂住，且因为 `evaluate()` 是同步 FFI 调用，Dart 侧的
//   `Future.timeout` / 测试 Timeout 也一起失效（主 isolate 被阻塞在原生调用里）。
//   因此唯一可靠的兜底是：**把 JS 放进子 isolate 跑，父 isolate 只管计时，
//   到点 `Isolate.kill(priority: immediate)`**。这样 UI 线程永远不会被 JS 阻塞，
//   卡死的也只是那个可以被丢弃的子 isolate。
//
// 关于 memoryLimit（**不要传**）：
//   `QuickJsRuntime2` 在 `memoryLimit > 0` 时会调用 `jsSetMemoryLimit`，
//   但该符号在**两个随包发布的二进制里都不存在**：
//     - Windows `quickjs_c_bridge.dll` → `Failed to lookup symbol 'jsSetMemoryLimit'`（error 127）
//     - Android `libfastdev_quickjs_runtime.so`（取自 APK）→ 符号名不在 .dynstr 中
//   （同库的 `jsNewRuntime` / `jsEval` / `jsSetMaxStackSize` / `jsFreeRuntime` 都在。）
//   传非 0 值会抛**未被捕获的** FFI 查找异常并直接打死子 isolate。
//   故本沙箱不传 memoryLimit；内存失控由"隔离 + 截止时间 kill"兜底。
import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

/// 单次 JS 执行的默认墙钟上限（毫秒级）。
///
/// 1000ms 对"解析一段插件脚本 / 跑一个同步函数"足够宽裕（正常求值实测 <1ms），
/// 又能让失控脚本在 1 秒内被掐掉。真实插件同步大表数据时可按需放宽（见 `execute` 的 timeout 参数）。
const Duration kDefaultJsTimeout = Duration(milliseconds: 1000);

/// 沙箱创建（子 isolate 启动 + QuickJS 初始化）的等待上限。
///
/// 实测 QuickJS 初始化约 22ms，这里给足余量；超时即视为"插件不可用"，
/// 而不是无限等下去——`memoryLimit` 那种"符号缺失打死 isolate"的场景就靠它兜住。
const Duration kJsSandboxCreateTimeout = Duration(seconds: 5);

/// QuickJS 栈上限，沿用 flutter_js 的默认值（1MB）。
const int kJsStackSize = 1024 * 1024;

/// 传给原生 `jsNewRuntime` 的 timeout 参数值（毫秒）。
///
/// 保留该参数是"纵深防御"：若将来换到实现了中断的二进制，它能生效。
/// **但当前实测无效**，真正的兜底是父 isolate 的截止时间 kill，不要依赖它。
const int kJsNativeTimeoutHintMs = 1000;

/// 插件在 JS 里向内核打日志用的通道名。
///
/// JS 侧：`sendMessage('log', JSON.stringify('...'))` → 转发到父 isolate → `onLog` / `debugPrint`。
/// 这是 Phase 3.2b 的 `ctx.log` 的雏形；也用来验证 **Dart↔JS 桥能穿过 isolate 边界**。
const String kSandboxLogChannel = 'log';

/// 沙箱执行结果的状态。
enum JsSandboxStatus {
  /// 执行成功，`value` 为 JS 返回值的字符串形式。
  success,

  /// JS 执行出错（语法错误、运行时异常），`message` 为错误信息。
  error,

  /// 执行超时（疑似死循环），子 isolate 已被 kill。
  timeout,

  /// 沙箱不可用（创建失败 / 已被销毁），`message` 为原因。
  unavailable,
}

/// 一次 JS 执行的结果。
///
/// 所有失败都表现为"带状态的结果对象"，**不抛异常**——调用方（插件管理 UI）
/// 据此把插件标记为不可用，而不是让异常冒泡崩掉页面。
@immutable
class JsSandboxResult {
  const JsSandboxResult._(
    this.status, {
    this.value,
    this.message,
    this.httpErrors = const <String>[],
  });

  /// 成功。
  const JsSandboxResult.success(
    String value, {
    List<String> httpErrors = const <String>[],
  }) : this._(JsSandboxStatus.success, value: value, httpErrors: httpErrors);

  /// JS 执行出错。
  const JsSandboxResult.error(
    String message, {
    List<String> httpErrors = const <String>[],
  }) : this._(JsSandboxStatus.error, message: message, httpErrors: httpErrors);

  /// 执行超时。
  const JsSandboxResult.timeout(String message)
      : this._(JsSandboxStatus.timeout, message: message);

  /// 沙箱不可用。
  const JsSandboxResult.unavailable(String message)
      : this._(JsSandboxStatus.unavailable, message: message);

  /// 结果状态。
  final JsSandboxStatus status;

  /// 成功时的 JS 返回值（`JsEvalResult.stringResult`）。
  final String? value;

  /// 失败原因（错误信息 / 超时说明 / 不可用原因）。
  final String? message;

  /// 本次执行期间宿主记录到的 HTTP 失败短标识（Phase 4.3）。
  ///
  /// 由 `PluginContext` 从 `ctx.http` 置入，取值是宿主自己的错误枚举
  /// （`timeout` / `connection` / `bad_certificate` / `bad_response` /
  /// `cancelled` / `unknown`），**不含任何学校相关信息**。
  ///
  /// 为什么需要它：插件把失败包装成 `{error: '人话原因'}` 之后就只剩一句中文，
  /// 宿主无法判断"该不该重试"。保留原始错误类别后，重试决策就有据可依
  /// （见 `CourseSyncService`）。为空表示本次执行没有发生 HTTP 真失败。
  final List<String> httpErrors;

  /// 是否成功。
  bool get isSuccess => status == JsSandboxStatus.success;

  /// 是否因为沙箱不可用而失败（调用方据此降级为"插件不可用"）。
  bool get isUnavailable => status == JsSandboxStatus.unavailable;

  /// 是否超时。
  bool get isTimeout => status == JsSandboxStatus.timeout;

  /// 复制并替换 [httpErrors]（其余字段不变）。
  JsSandboxResult withHttpErrors(List<String> errors) => JsSandboxResult._(
        status,
        value: value,
        message: message,
        httpErrors: List<String>.unmodifiable(errors),
      );

  @override
  String toString() => 'JsSandboxResult(${status.name}, value: $value, '
      'message: $message, httpErrors: $httpErrors)';
}

/// 子 isolate 的启动配置（跨 isolate 传递，只能用可发送的普通对象）。
class _WorkerConfig {
  const _WorkerConfig({
    required this.reply,
    required this.stackSize,
    required this.nativeTimeoutMs,
    required this.simulateCreateFailure,
  });

  final SendPort reply;
  final int stackSize;
  final int nativeTimeoutMs;

  /// 仅测试用：让子 isolate 在创建运行时前失败，用于验证"创建失败 → 降级"路径。
  final bool simulateCreateFailure;
}

/// 子 isolate → 父 isolate 的握手消息：创建成功。
class _WorkerReady {
  const _WorkerReady();
}

/// 子 isolate → 父 isolate 的握手消息：创建失败。
class _WorkerCreateFailed {
  const _WorkerCreateFailed(this.reason);
  final String reason;
}

/// 父 isolate → 子 isolate 的求值请求。
class _EvalRequest {
  const _EvalRequest({required this.script, required this.reply, required this.seq});
  final String script;
  final SendPort reply;
  final int seq;
}

/// 子 isolate → 父 isolate 的求值结果。
class _EvalReply {
  const _EvalReply({required this.seq, this.value, this.error});
  final int seq;
  final String? value;
  final String? error;
}

/// 子 isolate → 父 isolate 的插件日志（来自 JS 的 `sendMessage('log', ...)`）。
class _LogMessage {
  const _LogMessage(this.message);
  final String message;
}

/// 子 isolate 的入口：建运行时 → 握手 → 循环处理求值请求。
///
/// 顶层函数（不能是闭包）：`Isolate.spawn` 的入口必须能在新 isolate 里独立解析。
void _sandboxWorkerMain(_WorkerConfig config) {
  JavascriptRuntime? runtime;
  try {
    if (config.simulateCreateFailure) {
      throw StateError('模拟的运行时创建失败（仅测试用）');
    }
    // 直接构造 QuickJsRuntime2 而不是走 getJavascriptRuntime()：
    // 后者只透传 extraArgs['stackSize']，**不接受也不转发** timeout / memoryLimit。
    runtime = QuickJsRuntime2(
      stackSize: config.stackSize,
      timeout: config.nativeTimeoutMs,
    );

    // 注册 Dart 侧回调：JS 调 `sendMessage('log', ...)` 时转发给父 isolate。
    // 沿用 Phase 3.1 的 `evaluate + onMessage` 主干（不用 convertValue）。
    runtime.onMessage(kSandboxLogChannel, (dynamic args) {
      config.reply.send(_LogMessage('$args'));
    });
  } catch (e) {
    // 创建失败必须回报，不能静默——父 isolate 据此把沙箱标成"不可用"。
    config.reply.send(_WorkerCreateFailed('$e'));
    return;
  }

  config.reply.send(const _WorkerReady());

  // 用一个长驻 ReceivePort 接收求值请求（沙箱可复用，不必每次重建 isolate）。
  final ReceivePort requestPort = ReceivePort();
  config.reply.send(requestPort.sendPort);

  requestPort.listen((dynamic message) {
    if (message is! _EvalRequest) return;
    try {
      final JsEvalResult result = runtime!.evaluate(message.script);
      if (result.isError) {
        // QuickJS 后端语法错误不抛异常，只置 isError，必须显式检查。
        message.reply.send(
          _EvalReply(seq: message.seq, error: result.stringResult),
        );
      } else {
        message.reply.send(
          _EvalReply(seq: message.seq, value: result.stringResult),
        );
      }
    } catch (e) {
      message.reply.send(_EvalReply(seq: message.seq, error: '$e'));
    }
  });
}

/// JS 运行时沙箱：**在独立 isolate 里**跑 QuickJS，带墙钟超时与失败降级。
///
/// 生命周期：`create()` → 多次 `execute()` → `dispose()`。
/// 一旦某次执行超时，子 isolate 已被 kill，沙箱即变为不可用
/// （`isUsable == false`），后续调用返回 `unavailable`；需要继续用就重新 `create()`。
///
/// 不做的事（留给后续阶段）：权限控制、插件文件加载、`ctx.http` / `ctx.storage` 等
/// 跨 isolate 的服务注入。本阶段只保证"跑得起来、卡不死、崩不了"。
class JsSandbox {
  /// 私有构造用**位置参数**：Dart 不允许命名参数以下划线开头，
  /// 而字段是私有的，故只能用位置形式的 initializing formal。
  JsSandbox._(
    this._isolate,
    this._receivePort,
    this._requestPort,
    this._usable,
    this._unavailableReason,
  );

  /// 不可用沙箱的私有构造：不持有 isolate / 端口，永远返回 `unavailable`。
  JsSandbox._unavailable(String reason) : this._(null, null, null, false, reason);

  final Isolate? _isolate;
  final ReceivePort? _receivePort;
  final SendPort? _requestPort;

  /// 串行化队列：同一时刻只允许一个求值在飞，避免请求/应答错配。
  Future<void> _queue = Future<void>.value();

  /// 当前在飞的请求序号（单调递增，用于校验应答归属）。
  int _seq = 0;

  bool _disposed = false;
  bool _usable;

  /// 不可用原因（创建失败 / 超时后销毁 / 已 dispose）。
  String? _unavailableReason;

  /// 沙箱是否仍可用（创建成功且未因超时被销毁）。
  bool get isUsable => _usable && !_disposed;

  /// 不可用原因（创建失败 / 超时后销毁 / 已 dispose）；可用时为 `null`。
  ///
  /// 供上层（如 `PluginRuntime`）把"插件不可用"的具体原因透传给用户。
  String? get unavailableReason => _usable ? null : _unavailableReason;

  /// 创建一个沙箱。
  ///
  /// 任何创建失败（子 isolate 起不来、QuickJS 初始化抛异常、超时无应答）
  /// 都会**降级为不可用沙箱**并 `debugPrint` 原因，而不是抛异常——
  /// 调用方拿到对象后先看 `isUsable`，据此把插件标记为"不可用"。
  ///
  /// [simulateCreateFailure] 仅测试用，用于验证降级路径。
  /// [onLog] 接收插件在 JS 里经 `sendMessage('log', ...)` 打出的日志
  /// （在**父** isolate 上回调，可安全更新 UI）。
  static Future<JsSandbox> create({
    int stackSize = kJsStackSize,
    Duration createTimeout = kJsSandboxCreateTimeout,
    void Function(String message)? onLog,
    @visibleForTesting bool simulateCreateFailure = false,
  }) async {
    final ReceivePort receivePort = ReceivePort();
    final Completer<JsSandbox> completer = Completer<JsSandbox>();

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<_WorkerConfig>(
        _sandboxWorkerMain,
        _WorkerConfig(
          reply: receivePort.sendPort,
          stackSize: stackSize,
          nativeTimeoutMs: kJsNativeTimeoutHintMs,
          simulateCreateFailure: simulateCreateFailure,
        ),
        debugName: 'js-sandbox',
      );
    } catch (e) {
      receivePort.close();
      debugPrint('[JsSandbox] 子 isolate 创建失败，降级为不可用：$e');
      return JsSandbox._unavailable('子 isolate 创建失败：$e');
    }

    Timer? timer;
    bool portClosed = false;

    void cleanup() {
      isolate?.kill(priority: Isolate.immediate);
      if (!portClosed) {
        portClosed = true;
        receivePort.close();
      }
    }

    receivePort.listen((dynamic message) {
      if (message is _WorkerCreateFailed) {
        if (!completer.isCompleted) {
          debugPrint('[JsSandbox] QuickJS 运行时创建失败，降级为不可用：${message.reason}');
          completer.complete(
            JsSandbox._unavailable('运行时创建失败：${message.reason}'),
          );
        }
      } else if (message is _WorkerReady) {
        // 握手成功，等子 isolate 发来请求端口。
        debugPrint('[JsSandbox] 子 isolate 就绪');
      } else if (message is _LogMessage) {
        // 插件日志：在父 isolate 上回调，方便调用方接到 UI 或日志系统。
        debugPrint('[JsSandbox][plugin] ${message.message}');
        onLog?.call(message.message);
      } else if (message is SendPort) {
        if (!completer.isCompleted) {
          completer.complete(
            JsSandbox._(isolate, receivePort, message, true, null),
          );
        }
      }
    });

    // 兜底：子 isolate 若被原生层打死（如符号缺失）会**静默消失**，
    // 既不发 ready 也不发 failed，只能靠这个计时器把等待收敛掉。
    timer = Timer(createTimeout, () {
      if (!completer.isCompleted) {
        debugPrint('[JsSandbox] 创建超时（${createTimeout.inMilliseconds}ms），降级为不可用');
        completer.complete(JsSandbox._unavailable('创建超时'));
      }
    });

    final JsSandbox sandbox = await completer.future;
    timer.cancel();

    // 失败路径：立刻收掉刚起的 isolate 与端口，避免泄漏。
    if (!sandbox.isUsable) cleanup();
    return sandbox;
  }

  /// 在沙箱里执行一段 JS。
  ///
  /// [timeout] 是**墙钟**上限（不是 JS 内部的计时）：超过就 kill 子 isolate 并返回
  /// `timeout` 状态。这是挡住死循环的唯一有效手段（见文件头说明）。
  ///
  /// 返回结果对象而非抛异常；`unavailable` 表示沙箱本身不可用，调用方应降级。
  Future<JsSandboxResult> execute(
    String script, {
    Duration timeout = kDefaultJsTimeout,
  }) {
    return _serialize(() => _executeLocked(script, timeout));
  }

  Future<JsSandboxResult> _executeLocked(String script, Duration timeout) async {
    if (_disposed) {
      return const JsSandboxResult.unavailable('沙箱已销毁');
    }
    if (!_usable) {
      return JsSandboxResult.unavailable(_unavailableReason ?? '沙箱不可用');
    }
    final SendPort? requestPort = _requestPort;
    final ReceivePort? receivePort = _receivePort;
    if (requestPort == null || receivePort == null) {
      return JsSandboxResult.unavailable(_unavailableReason ?? '沙箱未就绪');
    }

    final int seq = ++_seq;
    final ReceivePort replyPort = ReceivePort();
    final Completer<JsSandboxResult> completer = Completer<JsSandboxResult>();

    replyPort.listen((dynamic message) {
      if (message is! _EvalReply || message.seq != seq) return;
      if (completer.isCompleted) return;
      if (message.error != null) {
        completer.complete(JsSandboxResult.error(message.error!));
      } else {
        completer.complete(JsSandboxResult.success(message.value ?? 'null'));
      }
    });

    requestPort.send(
      _EvalRequest(script: script, reply: replyPort.sendPort, seq: seq),
    );

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      // 到点没回来 = 疑似死循环（或原生层卡死）：把子 isolate 整个丢掉。
      // 这是唯一能真正掐断 `while(true){}` 的手段。
      debugPrint(
        '[JsSandbox] 执行超时（${timeout.inMilliseconds}ms），已终止子 isolate：'
        '${_preview(script)}',
      );
      _destroyIsolate();
      _usable = false;
      _unavailableReason = '执行超时后沙箱已销毁';
      return JsSandboxResult.timeout('执行超时（${timeout.inMilliseconds}ms）');
    } catch (e) {
      debugPrint('[JsSandbox] 执行异常：$e');
      return JsSandboxResult.error('$e');
    } finally {
      replyPort.close();
    }
  }

  /// 销毁沙箱：kill 子 isolate 并关闭端口。幂等。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _usable = false;
    _destroyIsolate();
  }

  void _destroyIsolate() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
  }

  /// 把脚本截断成短预览，避免超时日志把整段插件代码打出来。
  static String _preview(String script) {
    final String oneLine = script.replaceAll('\n', ' ').trim();
    return oneLine.length <= 40 ? oneLine : '${oneLine.substring(0, 40)}...';
  }

  /// 串行执行：保证同一时刻只有一个求值在飞。
  Future<T> _serialize<T>(Future<T> Function() action) {
    final Future<T> next = _queue.then((_) => action());
    // 让队列本身永不因单次失败而中断。
    _queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}
