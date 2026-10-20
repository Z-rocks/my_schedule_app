// 登录二维码桥（Phase 4.4）：把 CAS 二维码存进相册，并拉起微信扫一扫。
//
// 为什么需要原生：Flutter 侧没有"写系统相册"和"启动微信扫一扫"的跨平台能力；
// 这两件事都通过 `com.zys.myschedule/login_qr` 通道交给原生
// （Android：Kotlin；iOS：`AppDelegate.swift` 里的 LoginQrHandler）。
//
// 非 Android/iOS / 通道不可用 / 用户拒绝权限时，方法返回 `null` / `false`，
// 由登录页降级提示（截图手动扫 / 用另一台设备），不抛异常。
//
// iOS 实现说明：保存走 `UIImageWriteToSavedPhotosAlbum`（只加不删的权限），
// 拉起微信走 `UIApplication.open("weixin://dl/scan")`；
// **删除**（`deleteImage`）是 no-op——iOS 删相册资源要弹系统确认框，
// 打扰登录流程，不值得；登录页文案会按平台区分。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 二维码保存 + 微信扫一扫的桥接封装。全部为静态方法，无状态。
class QrLoginBridge {
  QrLoginBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.zys.myschedule/login_qr',
  );

  /// 是否支持（Android / iOS）。
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 登录成功后能否**自动**把二维码从相册删掉（仅 Android）。
  ///
  /// iOS 上删相册资源必须弹系统确认框，登录页据此调整文案
  /// （"自动删除" → "记得手动删掉"），不承诺做不到的事。
  static bool get canDeleteAfterLogin =>
      !kIsWeb && Platform.isAndroid;

  /// 把 PNG 字节写入系统相册，返回 `content://` URI；失败返回 `null`。
  ///
  /// Android 10+ 走 MediaStore 的 `IS_PENDING`，不需要存储权限；
  /// Android 7–9 需要 `WRITE_EXTERNAL_STORAGE`，Kotlin 侧会发起运行时申请。
  static Future<String?> saveImageToGallery(
    Uint8List bytes,
    String fileName,
  ) async {
    if (!supported || bytes.isEmpty) return null;
    try {
      return await _channel.invokeMethod<String>(
        'saveImageToGallery',
        <String, dynamic>{
          'bytes': bytes,
          'name': fileName,
        },
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[QrLoginBridge] 保存二维码失败：${e.code} ${e.message}');
      return null;
    }
  }

  /// 拉起微信扫一扫（`weixin://dl/scan`）。未安装微信 / 无法拉起返回 `false`。
  static Future<bool> openWeChatScanner() async {
    if (!supported) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>('openWeChatScanner');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 是否安装了微信。
  static Future<bool> isWeChatInstalled() async {
    if (!supported) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>('isWeChatInstalled');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 删除刚保存到相册的二维码（登录完成 / 页面销毁时清理）。
  static Future<bool> deleteImage(String? uri) async {
    if (!supported || uri == null || uri.trim().isEmpty) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'deleteImage',
        <String, dynamic>{'uri': uri},
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
