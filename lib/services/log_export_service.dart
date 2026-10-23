// 日志导出：拼设备信息头 + 生成文件 + 拉起系统分享。
//
// 拆成独立服务而不是塞进 [AppLog]，是为了让日志内核保持**零平台依赖**
// （纯 `dart:io`，测试可直接跑）。设备型号、版本号、ABI 这些都要过
// 平台通道，只有真正"导出给用户"时才需要。
//
// ## 导出物长什么样
//
// ```
// ==== 校园助手 运行日志 ====
// 导出时间：2026-10-22 16:40:00
// App 版本：0.5.1+3004（release）
// 设备：Xiaomi 2211133C / Android 14 (SDK 34) / arm64-v8a
// 日志范围：2026-10-21 16:40 ~ 2026-10-22 16:40（共 1234 条，错误 3 条）
//
// ==== 日志内容（1234 条）====
// 2026-10-22 16:30:30.123 I sync 开始同步插件 {"pluginId":"ncst-phylab"}
// ...
// ```
//
// 头部信息是排查的第一现场：版本不对、机型特有问题、ABI 装错包，
// 都能从这几行直接看出来，省掉一轮来回问。
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_log.dart';
import 'app_version.dart';
import 'system_bridge.dart';

/// 导出结果。
class LogExportResult {
  const LogExportResult({
    required this.ok,
    this.file,
    this.message = '',
    this.shared = false,
  });

  final bool ok;

  /// 生成的文本文件（`ok` 为 true 时非空）。
  final File? file;

  /// 失败原因 / 提示文案（面向用户）。
  final String message;

  /// 是否已经通过系统分享面板发出去（`false` 表示只生成了文件）。
  final bool shared;

  static LogExportResult failure(String message) =>
      LogExportResult(ok: false, message: message);
}

/// 日志导出服务。
class LogExportService {
  LogExportService._();

  /// 生成导出文件。
  ///
  /// [problemsOnly] 为 `true` 时只导出警告与错误。
  static Future<LogExportResult> build({bool problemsOnly = false}) async {
    if (!AppLog.isReady) {
      return LogExportResult.failure(
        AppLog.initError.isEmpty ? '日志系统未初始化' : '日志不可用：${AppLog.initError}',
      );
    }
    try {
      // 导出前先落盘：最后几百毫秒的记录可能还在缓冲区里。
      await AppLog.flush();
      final String header = await buildHeader();
      final String text = AppLog.buildExportText(
        header: header,
        problemsOnly: problemsOnly,
      );
      final File file = await AppLog.writeExportFile(text);
      return LogExportResult(ok: true, file: file, message: file.path);
    } catch (error, stack) {
      AppLog.e('log', '生成导出文件失败', error: error, stack: stack);
      return LogExportResult.failure('生成日志文件失败：$error');
    }
  }

  /// 生成并直接拉起系统分享面板。
  ///
  /// 分享失败时**不删文件**：用户还能从"已保存到…"的提示里知道路径，
  /// 而删掉就什么都没有了。
  static Future<LogExportResult> share({bool problemsOnly = false}) async {
    final LogExportResult built = await build(problemsOnly: problemsOnly);
    if (!built.ok) return built;

    final File file = built.file!;
    final bool shared = await SystemBridge.shareFile(
      file.path,
      mimeType: 'text/plain',
      subject: '校园助手 运行日志',
    );
    if (shared) {
      AppLog.action('log_share', <String, Object?>{
        'bytes': await file.length(),
        'problemsOnly': problemsOnly,
      });
      return LogExportResult(
        ok: true,
        file: file,
        message: file.path,
        shared: true,
      );
    }
    AppLog.w('log', '系统分享不可用，仅生成文件', <String, Object?>{
      'path': file.path,
    });
    return LogExportResult(ok: true, file: file, message: file.path);
  }

  /// 拼设备信息头。任何一项取不到就写"未知"，不让导出失败。
  static Future<String> buildHeader() async {
    final String version = await AppVersion.load();
    final String model = await SystemBridge.deviceModel();
    final String abi = await SystemBridge.primaryAbi();
    final String os = await _osLabel();

    final List<LogEntry> entries = AppLog.snapshot();
    final DateTime? first = AppLog.firstTime;
    final DateTime? last = AppLog.lastTime;
    final int errors = AppLog.countAtLeast(LogLevel.error);
    final int warns = AppLog.countAtLeast(LogLevel.warn);

    final StringBuffer buffer = StringBuffer()
      ..writeln('==== 校园助手 运行日志 ====')
      ..writeln('导出时间：${_formatTime(DateTime.now())}')
      ..writeln('App 版本：$version（${_buildMode()}）')
      ..writeln(
        '设备：${model.isEmpty ? '未知' : model} / $os'
        '${abi.isEmpty ? '' : ' / $abi'}',
      )
      ..writeln('日志文件：${AppLog.filePath}')
      ..writeln(
        '日志范围：${first == null ? '无记录' : _formatTime(first)} ~ '
        '${last == null ? '无记录' : _formatTime(last)}'
        '（共 ${entries.length} 条，警告 $warns 条，错误 $errors 条）',
      );
    return buffer.toString();
  }

  /// 系统版本文案。
  ///
  /// 优先用原生给的 `Android 14 (SDK 34)`；拿不到时退回
  /// `Platform.operatingSystemVersion`——它在 Android 上是构建指纹
  /// （`android BP2A.250605.031.A3`），信息价值低，但总比"未知"强。
  static Future<String> _osLabel() async {
    final String native = await SystemBridge.androidRelease();
    if (native.isNotEmpty) return native;
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim();
  }

  static String _buildMode() {
    if (kReleaseMode) return 'release';
    if (kProfileMode) return 'profile';
    return 'debug';
  }

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
