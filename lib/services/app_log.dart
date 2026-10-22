// 运行日志（本地滚动日志 + 全局错误捕获 + 一键导出）。
//
// ## 为什么是文件而不是 Hive
//
// 日志是**追加写 + 按时间淘汰**的数据，而 Hive 的 Box 会整体驻留内存。
// 24 小时的日志可能有几千条，塞进 Hive 等于让常驻内存多背一份无用的历史；
// 而且崩溃时 Hive 的写入不保证已经落盘（`put` 是异步的），
// 恰好是"崩溃前那几条"最需要被看到。
//
// 所以日志走独立的纯文本文件：追加写、按行可读、导出时直接拷内容。
//
// ## 保留策略
//
// - 只保留最近 [retention]（默认 24 小时）的记录；
// - 内存里最多留 [maxEntries] 条（供日志页展示），超出丢最旧的；
// - 文件超过 [maxFileBytes] 时立即裁剪重写，避免无限增长；
// - 启动时、以及写入过程中每隔 1 小时各裁剪一次。
//
// ## 与现有代码的关系
//
// 项目里排查信息几乎都走 `debugPrint`（插件沙箱、课程同步、存储服务…），
// 所以这里**接管了全局 `debugPrint`**：原有调用一行都不用改，
// 输出会同时进日志文件。这是零侵入收集的关键。
//
// 但 `debugPrint` 只记为 debug 级——它无法区分"正常进度"和"出错了"。
// 真正的错误请显式调用 [e]，那样才会进错误计数、在日志页标红。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 日志级别。数值越大越严重。
enum LogLevel {
  /// 内部进度 / `debugPrint` 转发。
  debug,

  /// 用户可见的行为（页面跳转、按钮点击、同步完成）。
  info,

  /// 降级运行：功能可用但结果不完整（插件警告、解析跳过条目）。
  warn,

  /// 失败：异常、未捕获错误、功能不可用。
  error,
}

/// 级别在日志行里的单字符编码。**落盘后即为格式契约**，
/// 改动会让旧日志文件解析失败。
extension LogLevelCode on LogLevel {
  String get code {
    switch (this) {
      case LogLevel.debug:
        return 'D';
      case LogLevel.info:
        return 'I';
      case LogLevel.warn:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }

  /// 中文短标签（日志页筛选器用）。
  String get label {
    switch (this) {
      case LogLevel.debug:
        return '调试';
      case LogLevel.info:
        return '信息';
      case LogLevel.warn:
        return '警告';
      case LogLevel.error:
        return '错误';
    }
  }

  static LogLevel? fromCode(String code) {
    switch (code) {
      case 'D':
        return LogLevel.debug;
      case 'I':
        return LogLevel.info;
      case 'W':
        return LogLevel.warn;
      case 'E':
        return LogLevel.error;
    }
    return null;
  }
}

/// 一条日志。
@immutable
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.data = const <String, Object?>{},
    this.error,
    this.stack,
  });

  /// 发生时刻（本地时间）。
  final DateTime time;

  final LogLevel level;

  /// 来源模块，如 `sync` / `plugin` / `page` / `action`。
  final String tag;

  final String message;

  /// 结构化附加信息（已脱敏）。空 Map 表示没有。
  final Map<String, Object?> data;

  /// 异常对象的 `toString()`。
  final String? error;

  /// 堆栈。
  final String? stack;

  bool get hasDetail => error != null || stack != null || data.isNotEmpty;

  /// 序列化成**单行**文本。
  ///
  /// 格式（制表符分隔，因为 message 里可能出现 `{` 而不会出现制表符）：
  /// ```
  /// 2026-10-22 16:30:30.123 E plugin 执行失败	{"e":"...","s":"...","d":{...}}
  /// ```
  /// 尾部 JSON 整体省略表示没有附加信息。
  String toLine() {
    final StringBuffer buffer = StringBuffer()
      ..write(_formatTime(time))
      ..write(' ')
      ..write(level.code)
      ..write(' ')
      ..write(tag)
      ..write(' ')
      // 行内不能有换行/制表符，否则解析会断成两条。
      ..write(message.replaceAll('\t', ' ').replaceAll('\n', ' ⏎ '));

    final Map<String, Object?> extra = <String, Object?>{};
    if (error != null) extra['e'] = error;
    if (stack != null) extra['s'] = stack;
    if (data.isNotEmpty) extra['d'] = data;
    if (extra.isNotEmpty) {
      buffer
        ..write('\t')
        ..write(_encodeExtra(extra));
    }
    return buffer.toString();
  }

  /// 解析 [toLine] 的产物。格式不符返回 `null`（宁可丢一条，也不抛异常
  /// ——调用方是启动流程，不能因为一行坏数据起不来）。
  static LogEntry? tryParse(String line) {
    if (line.isEmpty) return null;
    final RegExpMatch? match = _linePattern.firstMatch(line);
    if (match == null) return null;

    final DateTime? time = _parseTime(match.group(1)!);
    if (time == null) return null;
    final LogLevel? level = LogLevelCode.fromCode(match.group(2)!);
    if (level == null) return null;

    final String rest = match.group(4) ?? '';
    final int tab = rest.indexOf('\t');
    final String message = tab < 0 ? rest : rest.substring(0, tab);

    Map<String, Object?> extra = const <String, Object?>{};
    if (tab >= 0) {
      try {
        final Object? decoded = jsonDecode(rest.substring(tab + 1));
        if (decoded is Map) {
          extra = decoded.map(
            (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
          );
        }
      } catch (_) {
        // 附加信息坏了不影响正文，丢掉即可。
      }
    }

    final Object? rawData = extra['d'];
    return LogEntry(
      time: time,
      level: level,
      tag: match.group(3)!,
      message: message,
      error: extra['e']?.toString(),
      stack: extra['s']?.toString(),
      data: rawData is Map
          ? rawData.map(
              (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
            )
          : const <String, Object?>{},
    );
  }

  static final RegExp _linePattern = RegExp(
    r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) ([DIWE]) (\S+) (.*)$',
  );

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${three(t.millisecond)}';
  }

  static DateTime? _parseTime(String text) {
    // `2026-10-22 16:30:30.123`
    final int year = int.tryParse(text.substring(0, 4)) ?? 0;
    final int month = int.tryParse(text.substring(5, 7)) ?? 0;
    final int day = int.tryParse(text.substring(8, 10)) ?? 0;
    final int hour = int.tryParse(text.substring(11, 13)) ?? 0;
    final int minute = int.tryParse(text.substring(14, 16)) ?? 0;
    final int second = int.tryParse(text.substring(17, 19)) ?? 0;
    final int milli = int.tryParse(text.substring(20, 23)) ?? 0;
    if (year < 2000 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    return DateTime(year, month, day, hour, minute, second, milli);
  }

  static String _encodeExtra(Map<String, Object?> extra) {
    try {
      return jsonEncode(extra);
    } catch (_) {
      // data 里混进了不可序列化的对象：退回字符串形式，别让整条日志丢掉。
      return jsonEncode(<String, Object?>{
        'e': extra['e']?.toString(),
        's': extra['s']?.toString(),
        'd': extra['d']?.toString(),
      });
    }
  }
}

/// 运行日志的门面。全部为静态方法，无实例。
///
/// 所有公开写方法（[d] / [i] / [w] / [e]）都**永不抛异常**：
/// 日志写失败绝不能反过来把业务搞崩。
class AppLog {
  AppLog._();

  /// 保留时长。超过这个时间的记录在下次裁剪时被丢弃。
  static Duration retention = const Duration(hours: 24);

  /// 内存里保留的最大条数（日志页一次最多展示这么多）。
  static int maxEntries = 3000;

  /// 日志文件大小上限。超过就裁剪重写。
  static int maxFileBytes = 2 * 1024 * 1024;

  /// 单窗口（1 秒）内允许写入的最大条数，超出丢弃并汇总。
  ///
  /// 存在的意义：插件里一个 `for` 循环打日志就能在几秒内写爆文件，
  /// 那样反而把真正有用的记录挤掉了。
  static int floodLimitPerSecond = 300;

  /// 内存缓冲（已脱敏、已按时间升序）。日志页读这里。
  static final List<LogEntry> _entries = <LogEntry>[];

  /// 数据版本号：裁剪 / 清空 / 初始化完成时 +1，供日志页监听刷新。
  ///
  /// **不随每条写入递增**——高频写入下那会把 UI 刷爆。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static File? _logFile;
  static IOSink? _sink;
  static final List<String> _pending = <String>[];
  static Timer? _flushTimer;
  static Timer? _pruneTimer;

  static bool _initialized = false;
  static bool _handlersInstalled = false;
  static int _bytesWritten = 0;
  static DateTime _lastPrune = DateTime.fromMillisecondsSinceEpoch(0);

  /// 初始化失败的原因（日志页据此提示"日志功能不可用"）。
  static String initError = '';

  /// 是否可用。
  static bool get isReady => _initialized && _logFile != null;

  /// 日志文件路径（未初始化时为空串）。
  static String get filePath => _logFile?.path ?? '';

  /// 洪泛控制状态。
  static DateTime _windowStart = DateTime.fromMillisecondsSinceEpoch(0);
  static int _windowCount = 0;
  static int _droppedInWindow = 0;

  /// 初始化：定位目录、读回最近 24 小时、重写文件、安装全局捕获。
  ///
  /// [dirOverride] 只给测试用（跳过 path_provider 的平台通道）。
  /// [installHandlers] 为 `false` 时不接管 `FlutterError` / `debugPrint`
  /// （测试环境要保留自己的错误处理）。
  ///
  /// 重复调用安全。任何异常都被吞掉并记进 [initError]——
  /// **日志系统坏了不能让 App 起不来**。
  static Future<void> init({
    String? dirOverride,
    bool installHandlers = true,
  }) async {
    if (_initialized) return;
    _initialized = true;

    try {
      final Directory base = dirOverride != null
          ? Directory(dirOverride)
          : await getApplicationSupportDirectory();
      final Directory dir = Directory('${base.path}${Platform.pathSeparator}logs');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _logFile = File('${dir.path}${Platform.pathSeparator}app.log');
      await _loadExisting();
      await _rewriteFile();

      // 前台期间定时裁剪：App 长期挂着不重启时，靠它保证"只留近一天"。
      _pruneTimer?.cancel();
      _pruneTimer = Timer.periodic(const Duration(hours: 1), (Timer _) {
        prune();
        _flushNow();
      });
    } catch (error, stack) {
      initError = '$error';
      _logFile = null;
      // 此时还不能用 debugPrint（马上就会被替换成走日志的版本），直接 print。
      // ignore: avoid_print
      print('[AppLog] 初始化失败：$error\n$stack');
    }

    if (installHandlers) installErrorHandlers();

    revision.value++;
    i('log', '日志系统就绪', <String, Object?>{
      'file': filePath,
      'entries': _entries.length,
      'retentionHours': retention.inHours,
      if (initError.isNotEmpty) 'initError': initError,
    });
  }

  // ───────────────────────── 写入 API ─────────────────────────

  /// 调试级：内部进度。`debugPrint` 转发过来的也是这一级。
  static void d(String tag, String message, [Map<String, Object?>? data]) =>
      _add(LogLevel.debug, tag, message, data: data);

  /// 信息级：用户能感知的正常事件（同步完成、导入成功）。
  static void i(String tag, String message, [Map<String, Object?>? data]) =>
      _add(LogLevel.info, tag, message, data: data);

  /// 警告级：功能降级但仍可用（插件警告、部分条目被跳过）。
  static void w(String tag, String message, [Map<String, Object?>? data]) =>
      _add(LogLevel.warn, tag, message, data: data);

  /// 错误级：失败。**排查 bug 主要看这一级**，所以请带上 [error] / [stack]。
  static void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, Object?>? data,
  }) {
    _add(
      LogLevel.error,
      tag,
      message,
      data: data,
      error: error?.toString(),
      stack: stack?.toString(),
    );
  }

  /// 用户行为埋点。
  ///
  /// 只记录**动作名 + 关键参数**，不记录任何输入内容
  /// （[redact] 会再兜一层，见 `_sensitiveKeys`）。
  static void action(String name, [Map<String, Object?>? data]) =>
      i('action', name, data);

  /// 页面进出埋点。[from] 记录来源页，用来还原"用户是怎么走到这一步的"。
  static void page(String route, {String? from}) =>
      i('page', route, <String, Object?>{'from': ?from});

  /// 网络请求结果。
  ///
  /// [url] 会被裁剪到 host + path（去掉 query，避免 token 泄漏）。
  static void net(
    String method,
    String url, {
    int? status,
    int? ms,
    Object? error,
  }) {
    final String safeUrl = sanitizeUrl(url);
    final bool failed = error != null || (status != null && status >= 400);
    final Map<String, Object?> data = <String, Object?>{
      'status': ?status,
      'ms': ?ms,
      'error': ?error?.toString(),
    };
    if (failed) {
      w('net', '$method $safeUrl', data);
    } else {
      d('net', '$method $safeUrl', data);
    }
  }

  /// 插件相关事件（加载、执行、失败）。
  static void plugin(
    String pluginId,
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stack,
    Map<String, Object?>? data,
  }) {
    final Map<String, Object?> merged = <String, Object?>{
      'plugin': pluginId,
      ...?data,
    };
    if (level == LogLevel.error) {
      e('plugin', message, error: error, stack: stack, data: merged);
    } else {
      _add(level, 'plugin', message, data: merged);
    }
  }

  // ───────────────────────── 读取 API ─────────────────────────

  /// 当前内存里的日志副本（按时间升序）。
  static List<LogEntry> snapshot() => List<LogEntry>.unmodifiable(_entries);

  /// 指定级别（含）以上的条数。
  static int countAtLeast(LogLevel level) =>
      _entries.where((LogEntry e) => e.level.index >= level.index).length;

  /// 最早 / 最晚记录时间（没有记录时为 `null`）。
  static DateTime? get firstTime => _entries.isEmpty ? null : _entries.first.time;
  static DateTime? get lastTime => _entries.isEmpty ? null : _entries.last.time;

  /// 清空日志（内存 + 文件）。
  static Future<void> clear() async {
    _entries.clear();
    _pending.clear();
    _bytesWritten = 0;
    await _rewriteFile();
    revision.value++;
    i('log', '日志已清空');
  }

  /// 立即把缓冲区落盘（App 退到后台 / 导出前调用）。
  static Future<void> flush() async {
    await _flushAsync();
  }

  // ───────────────────── 导出 ─────────────────────

  /// 生成导出文本。[header] 由调用方拼（设备信息在服务层取，
  /// 这里不依赖平台通道，测试可直接构造）。
  ///
  /// [problemsOnly] 为 `true` 时只导出 warn / error —— 日志量大时
  /// 用户只想发"出问题那部分"。
  static String buildExportText({
    String header = '',
    bool problemsOnly = false,
  }) {
    final List<LogEntry> picked = problemsOnly
        ? _entries.where((LogEntry e) => e.level.index >= LogLevel.warn.index).toList()
        : _entries;

    final StringBuffer buffer = StringBuffer();
    if (header.isNotEmpty) {
      buffer
        ..writeln(header)
        ..writeln();
    }
    buffer.writeln(
      '==== 日志内容（${picked.length} 条'
      '${problemsOnly ? '，仅警告与错误' : ''}）====',
    );
    for (final LogEntry entry in picked) {
      buffer.writeln(entry.toLine());
      // 堆栈单独缩进展开：这是排查崩溃最要紧的部分，不能挤在一行里。
      if (entry.stack != null && entry.stack!.trim().isNotEmpty) {
        for (final String line in entry.stack!.split('\n')) {
          if (line.trim().isEmpty) continue;
          buffer.writeln('    $line');
        }
      }
    }
    return buffer.toString();
  }

  /// 把导出内容写到缓存目录，返回文件。
  ///
  /// 放缓存目录而不是日志目录：分享出去之后文件就没用了，
  /// 缓存目录能被系统自动回收，也不占用户的"应用数据"。
  static Future<File> writeExportFile(
    String text, {
    String? dirOverride,
  }) async {
    final Directory base = dirOverride != null
        ? Directory(dirOverride)
        : await getTemporaryDirectory();
    final Directory dir = Directory('${base.path}${Platform.pathSeparator}export');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // 文件名带时间，方便用户连着发几份时区分。
    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final String name = 'campus-log-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}.txt';
    final File file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(text, flush: true);
    return file;
  }

  // ───────────────────── 全局捕获 ─────────────────────

  /// 安装全局错误捕获（幂等）。
  ///
  /// 三处：
  /// 1. `FlutterError.onError` —— 构建 / 布局 / 绘制阶段的异常（红屏那些）；
  /// 2. `PlatformDispatcher.instance.onError` —— 未捕获的异步异常
  ///    （`Future` 忘了 catch、`Timer` 里抛的）；
  /// 3. 全局 `debugPrint` —— 项目里所有既有排查输出，零改动收集。
  ///
  /// **不改原有的错误处理行为**：前两处都会继续调用原有回调，
  /// debug 下红屏照旧，只是多记了一份日志。
  static void installErrorHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;

    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      e(
        'flutter',
        details.exceptionAsString(),
        error: details.exception,
        stack: details.stack,
        data: <String, Object?>{
          if (details.library != null) 'library': details.library,
          if (details.context != null) 'context': '${details.context}',
          if (details.silent) 'silent': true,
        },
      );
      previous?.call(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      e('uncaught', '$error', error: error, stack: stack);
      // false = 继续交给平台默认处理（会打到 logcat，便于开发时看到）。
      return false;
    };

    _installDebugPrintHook();
  }

  static DebugPrintCallback? _originalDebugPrint;

  static void _installDebugPrintHook() {
    if (_originalDebugPrint != null) return;
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
      if (message == null || message.isEmpty) return;
      _logFromPrint(message);
    };
  }

  /// 把一条 `debugPrint` 拆成"标签 + 正文 + 堆栈"。
  ///
  /// 项目里的写法是 `debugPrint('[CourseSyncService] xxx')`，
  /// 所以方括号前缀直接当 tag，日志页就能按模块筛。
  static void _logFromPrint(String raw) {
    final List<String> lines = raw.split('\n');
    final String first = lines.first;
    final String? stack = lines.length > 1
        ? lines.skip(1).where((String l) => l.trim().isNotEmpty).join('\n')
        : null;

    String tag = 'print';
    String message = first;
    final RegExpMatch? match = _bracketTag.firstMatch(first);
    if (match != null) {
      tag = match.group(1)!.trim();
      message = first.substring(match.end).trim();
    }
    _add(LogLevel.debug, tag, message, stack: stack);
  }

  static final RegExp _bracketTag = RegExp(r'^\[([^\]\n]{1,48})\]\s*');

  // ───────────────────── 内部：写入 ─────────────────────

  static void _add(
    LogLevel level,
    String tag,
    String message, {
    Map<String, Object?>? data,
    String? error,
    String? stack,
  }) {
    // ⚠️ 整体兜底：全局 `debugPrint` 已被接管，而它会被框架和业务到处调用。
    // 这里一旦抛异常，就会冒泡到那个毫不相干的调用点，把正常功能搞崩。
    // 日志系统自身的任何故障都必须静默。
    try {
      _addUnsafe(level, tag, message, data: data, error: error, stack: stack);
    } catch (_) {
      // 故意吞掉。
    }
  }

  static void _addUnsafe(
    LogLevel level,
    String tag,
    String message, {
    Map<String, Object?>? data,
    String? error,
    String? stack,
  }) {
    if (!isReady) return;
    if (!_allow(level)) return;

    final LogEntry entry = LogEntry(
      time: DateTime.now(),
      level: level,
      tag: _clip(tag, 48),
      message: _clip(message, 2000),
      data: redactMap(data),
      error: error == null ? null : _clip(error, 2000),
      stack: stack == null ? null : _clip(stack, 8000),
    );

    _entries.add(entry);
    final String line = entry.toLine();
    _pending.add(line);
    _bytesWritten += line.length + 1;

    if (level == LogLevel.error) {
      // 错误不攒：崩溃往往就发生在下一条日志之前。
      _flushNow();
    } else {
      _scheduleFlush();
    }

    if (_bytesWritten > maxFileBytes ||
        _entries.length > maxEntries ||
        DateTime.now().difference(_lastPrune) > const Duration(hours: 1)) {
      // 必须去抖：超限之后**每一条**写入都会命中这个条件，
      // 直接 `unawaited(_compact())` 会并发跑几十次文件重写，
      // 把主 isolate 拖到卡顿（日志洪泛时尤其明显）。
      _scheduleCompact();
    }
  }

  static Timer? _compactTimer;
  static bool _compacting = false;

  static void _scheduleCompact() {
    if (_compactTimer != null || _compacting) return;
    _compactTimer = Timer(const Duration(seconds: 2), () {
      _compactTimer = null;
      unawaited(_compact());
    });
  }

  /// 洪泛保护。error 级永远放行。
  static bool _allow(LogLevel level) {
    if (level == LogLevel.error) return true;
    final DateTime now = DateTime.now();
    if (now.difference(_windowStart).inMilliseconds >= 1000) {
      final int dropped = _droppedInWindow;
      _windowStart = now;
      _windowCount = 0;
      _droppedInWindow = 0;
      if (dropped > 0) {
        // 汇总上一条窗口被丢弃的量：让用户知道日志有缺口。
        _appendDirect(
          '${_formatNow()} W log 上一秒日志过多，已丢弃 $dropped 条\n',
        );
      }
    }
    if (_windowCount >= floodLimitPerSecond) {
      _droppedInWindow++;
      return false;
    }
    _windowCount++;
    return true;
  }

  static void _appendDirect(String line) {
    _pending.add(line.trimRight());
    _bytesWritten += line.length;
    _scheduleFlush();
  }

  static void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 800), _flushNow);
  }

  static void _flushNow() {
    // 统一走 [_flushAsync]，不要在这里自己 `sink.writeln` + `flush`：
    // 那样会与随后的显式 `flush()` 在同一个 IOSink 上并发，
    // 实测结果是**文件变成空的**（两条 flush 互相顶掉）。
    unawaited(_flushAsync());
  }

  /// 正在排队的 flush。
  ///
  /// **必须串行**：同一个 IOSink 上叠加两次 `flush()` 会把彼此的数据顶掉
  /// （实测表现是文件变成空的）。每次调用都排在上一轮之后执行，
  /// 这样"error 级立刻落盘"撞上"正在进行的 flush"时也不会丢。
  static Future<void>? _flushing;

  static Future<void> _flushAsync() {
    final Future<void> next =
        (_flushing ?? Future<void>.value()).then((_) => _doFlush());
    _flushing = next;
    return next.whenComplete(() {
      if (identical(_flushing, next)) _flushing = null;
    });
  }

  static Future<void> _doFlush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final IOSink? sink = _sink;
    if (sink == null) return;
    if (_pending.isNotEmpty) {
      final List<String> lines = List<String>.of(_pending);
      _pending.clear();
      try {
        for (final String line in lines) {
          sink.writeln(line);
        }
      } catch (_) {
        // 写失败不影响业务。
      }
    }
    // **即使 _pending 是空的也要 flush**：`_flushNow`（error 级会触发）
    // 已经把内容塞进 sink，但它的 `flush()` 是 unawaited 的。
    // 这里直接 return 会拿到一个"看起来 flush 过了、其实还没落盘"的文件——
    // 导出时就会少掉最后几条，恰恰是最关键的那几条。
    try {
      await sink.flush();
    } catch (_) {
      // 同上。
    }
  }

  // ───────────────────── 内部：保留策略 ─────────────────────

  /// 按时间淘汰 + 按条数 / 体积截断，然后重写文件。
  static Future<void> prune() async {
    if (!isReady) return;
    _lastPrune = DateTime.now();
    final DateTime cutoff = _lastPrune.subtract(retention);
    final int before = _entries.length;
    _entries.removeWhere((LogEntry e) => e.time.isBefore(cutoff));
    _trimToLimits();
    if (_entries.length != before) {
      await _rewriteFile();
      revision.value++;
    }
  }

  /// 超出条数 / 体积上限时从最旧的开始丢。
  static void _trimToLimits() {
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    int bytes = _estimateBytes();
    while (bytes > maxFileBytes && _entries.length > 1) {
      // 一次丢 1/10，避免大文件下逐条循环太久。
      final int drop = (_entries.length ~/ 10).clamp(1, _entries.length - 1);
      for (int i = 0; i < drop; i++) {
        bytes -= _entries[i].toLine().length + 1;
      }
      _entries.removeRange(0, drop);
    }
  }

  static int _estimateBytes() {
    int total = 0;
    for (final LogEntry entry in _entries) {
      total += entry.toLine().length + 1;
    }
    return total;
  }

  static Future<void> _compact() async {
    if (_compacting) return;
    _compacting = true;
    try {
      // 先把缓冲区写进旧 sink，再重写文件——否则重写期间到期的
      // flush 会写到已被关闭的 sink 上，那几条就丢了。
      await _flushAsync();
      _lastPrune = DateTime.now();
      final DateTime cutoff = _lastPrune.subtract(retention);
      _entries.removeWhere((LogEntry e) => e.time.isBefore(cutoff));
      _trimToLimits();
      await _rewriteFile();
      revision.value++;
    } finally {
      _compacting = false;
    }
  }

  static Future<void> _loadExisting() async {
    final File? file = _logFile;
    if (file == null || !await file.exists()) return;
    try {
      final String text = await file.readAsString();
      final DateTime cutoff = DateTime.now().subtract(retention);
      for (final String line in const LineSplitter().convert(text)) {
        final LogEntry? entry = LogEntry.tryParse(line);
        if (entry == null) continue;
        if (entry.time.isBefore(cutoff)) continue;
        _entries.add(entry);
      }
      _trimToLimits();
    } catch (_) {
      // 读不回来就当没有历史——不能因此启动失败。
    }
  }

  static Future<void> _rewriteFile() async {
    await _closeSink();
    final File? file = _logFile;
    if (file == null) return;
    try {
      final StringBuffer buffer = StringBuffer();
      for (final LogEntry entry in _entries) {
        buffer.writeln(entry.toLine());
      }
      await file.writeAsString(buffer.toString(), flush: true);
      _bytesWritten = buffer.length;
      _sink = file.openWrite(mode: FileMode.append);
    } catch (_) {
      _sink = null;
    }
  }

  static Future<void> _closeSink() async {
    // 等正在进行的 flush 收尾，否则 close 会把还没写出去的数据丢掉。
    final Future<void>? running = _flushing;
    if (running != null) {
      try {
        await running;
      } catch (_) {
        // 忽略。
      }
    }
    final IOSink? sink = _sink;
    _sink = null;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {
      // 忽略。
    }
  }

  /// 测试用：清空全部状态（含全局 hook 的标记）。
  @visibleForTesting
  static Future<void> resetForTest() async {
    await _closeSink();
    _flushTimer?.cancel();
    _flushTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _compactTimer?.cancel();
    _compactTimer = null;
    _compacting = false;
    _flushing = null;
    _entries.clear();
    _pending.clear();
    _bytesWritten = 0;
    _initialized = false;
    _logFile = null;
    initError = '';
    _windowStart = DateTime.fromMillisecondsSinceEpoch(0);
    _windowCount = 0;
    _droppedInWindow = 0;
    _lastPrune = DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ───────────────────── 脱敏 ─────────────────────

  /// 命中即整值替换为 `***` 的键（小写子串匹配）。
  ///
  /// 用户会把日志发出来，所以**任何凭据都不能落进日志**：
  /// 教务系统的密码、Cookie、插件 token 都在这里被抹掉。
  static const List<String> _sensitiveKeys = <String>[
    'password',
    'passwd',
    'pwd',
    'token',
    'cookie',
    'authorization',
    'secret',
    'sessionid',
    'session_id',
    'ticket',
    'credential',
    'apikey',
    'api_key',
  ];

  /// 递归脱敏 Map / List。返回新对象，不改入参。
  static Map<String, Object?> redactMap(Map<String, Object?>? input) {
    if (input == null || input.isEmpty) return const <String, Object?>{};
    final Map<String, Object?> out = <String, Object?>{};
    input.forEach((String key, Object? value) {
      if (_isSensitiveKey(key)) {
        out[key] = '***';
      } else {
        out[key] = _redactValue(value, depth: 0);
      }
    });
    return out;
  }

  static Object? _redactValue(Object? value, {required int depth}) {
    if (depth > 4) return value?.toString();
    if (value is Map) {
      final Map<String, Object?> out = <String, Object?>{};
      value.forEach((Object? k, Object? v) {
        final String key = '$k';
        out[key] = _isSensitiveKey(key) ? '***' : _redactValue(v, depth: depth + 1);
      });
      return out;
    }
    if (value is Iterable) {
      return value
          .map((Object? v) => _redactValue(v, depth: depth + 1))
          .toList();
    }
    return value;
  }

  static bool _isSensitiveKey(String key) {
    final String lower = key.toLowerCase();
    for (final String needle in _sensitiveKeys) {
      if (lower.contains(needle)) return true;
    }
    return false;
  }

  /// URL 只留 `scheme://host/path`，丢掉 query 与 fragment。
  ///
  /// 教务系统的 URL 里常带 `?ticket=...`，原样记下来等于把登录凭据写进日志。
  static String sanitizeUrl(String url) {
    try {
      final Uri uri = Uri.parse(url);
      if (!uri.hasScheme) return url;
      final String path = uri.path.isEmpty ? '' : uri.path;
      // `Uri.host` **不含端口**，`:8100` 这类非默认端口必须单独拼回来：
      // 同一台机器上的不同端口是完全不同的服务（教务 80 / 实验系统 8100），
      // 丢掉端口的日志会让人对着错的地址排查半天。
      final bool isDefaultPort = !uri.hasPort ||
          (uri.scheme == 'http' && uri.port == 80) ||
          (uri.scheme == 'https' && uri.port == 443);
      final String port = isDefaultPort ? '' : ':${uri.port}';
      return '${uri.scheme}://${uri.host}$port$path';
    } catch (_) {
      return url;
    }
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  static String _formatNow() => LogEntry._formatTime(DateTime.now());
}
