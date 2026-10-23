// 课表图片分享：把当前周的课表截成 PNG 并拉起系统分享面板。
//
// ## 为什么走 RepaintBoundary 而不是重画一遍
//
// 重画一份"导出专用课表"意味着两套布局代码，改了课表样式就要改两处，
// 迟早对不上。这里直接截**用户当前看到的那一块**（`_buildBody` 的
// RepaintBoundary），所见即所得。
//
// 截的是课表主体、不含顶部操作栏：那上面有同步 / 添加按钮，
// 截进去发给同学很奇怪。周次信息放在分享标题里（`subject`）。
//
// ## 像素比 3.0
//
// 手机屏一般 2.75~3.0 dpr，按 3.0 导出可以保证在任何屏幕上放大都清晰，
// 同时一张周课表 PNG 通常在 1MB 以内，微信发原图也毫无压力。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';
import 'system_bridge.dart';

/// 图片文件名前缀。清旧图时按它匹配，避免误删同目录下的备份与日志。
const String kTimetableImagePrefix = 'campus-timetable-';

/// 导出结果。
class TimetableImageResult {
  const TimetableImageResult({
    required this.ok,
    this.file,
    this.message = '',
    this.shared = false,
  });

  final bool ok;
  final File? file;
  final String message;

  /// 是否已拉起系统分享面板（`false` 表示只生成了文件）。
  final bool shared;

  static TimetableImageResult failure(String message) =>
      TimetableImageResult(ok: false, message: message);
}

/// 课表图片导出服务。
class TimetableImageService {
  TimetableImageService._();

  /// 截图 → 写文件 → 拉起分享面板。
  ///
  /// [boundaryKey] 必须是包在 `RepaintBoundary` 上的 `GlobalKey`。
  static Future<TimetableImageResult> share({
    required GlobalKey boundaryKey,
    String subject = '课表',
    double pixelRatio = 3.0,
  }) async {
    final Uint8List? bytes = await _capturePng(boundaryKey, pixelRatio);
    if (bytes == null) {
      return TimetableImageResult.failure('课表还没准备好，请稍后再试');
    }
    try {
      final File file = await _writePng(bytes);
      final bool shared = await SystemBridge.shareFile(
        file.path,
        mimeType: 'image/png',
        subject: subject,
      );
      AppLog.action('timetable_share', <String, Object?>{
        'bytes': bytes.length,
        'shared': shared,
      });
      if (!shared) {
        AppLog.w('timetable', '系统分享不可用，仅生成图片',
            <String, Object?>{'path': file.path});
      }
      return TimetableImageResult(
        ok: true,
        file: file,
        message: file.path,
        shared: shared,
      );
    } catch (error, stack) {
      AppLog.e('timetable', '课表图片分享失败', error: error, stack: stack);
      return TimetableImageResult.failure('分享失败：$error');
    }
  }

  /// 只截图不分享（测试 / 预览用）。失败返回 `null`。
  static Future<Uint8List?> _capturePng(
    GlobalKey boundaryKey,
    double pixelRatio,
  ) async {
    try {
      final BuildContext? context = boundaryKey.currentContext;
      if (context == null) return null;
      final RenderObject? object = context.findRenderObject();
      if (object is! RenderRepaintBoundary) return null;
      // 还没完成布局就去 toImage 会抛 "was not laid out"。
      if (object.debugNeedsPaint) {
        await WidgetsBinding.instance.endOfFrame;
      }
      final ui.Image image = await object.toImage(pixelRatio: pixelRatio);
      try {
        final ByteData? data =
            await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (error) {
      debugPrint('[TimetableImage] 截图失败：$error');
      return null;
    }
  }

  static Future<File> _writePng(Uint8List bytes) async {
    final Directory base = await getTemporaryDirectory();
    // 复用 FileProvider 白名单里的 `export/`（见 res/xml/file_paths.xml），
    // 否则 shareFile 会因为 URI 不在授权目录里直接失败。
    final Directory dir =
        Directory('${base.path}${Platform.pathSeparator}export');
    if (!await dir.exists()) await dir.create(recursive: true);

    await _pruneOldImages(dir);

    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final String name = '$kTimetableImagePrefix${now.year}${two(now.month)}'
        '${two(now.day)}-${two(now.hour)}${two(now.minute)}'
        '${two(now.second)}.png';
    final File file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 删掉上一次导出的课表图。
  ///
  /// 课表图是"发完就没用"的临时产物，留着只会让 `cache/export/` 越来越大
  /// （而"清理缓存"会刻意保留这个目录）。只删自己的前缀，不碰日志和备份。
  static Future<void> _pruneOldImages(Directory dir) async {
    try {
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is! File) continue;
        final String name = entity.uri.pathSegments.last;
        if (!name.startsWith(kTimetableImagePrefix)) continue;
        try {
          await entity.delete();
        } catch (error) {
          debugPrint('[TimetableImage] 删除旧图失败：${entity.path} → $error');
        }
      }
    } catch (error) {
      debugPrint('[TimetableImage] 清理旧图失败：$error');
    }
  }
}
