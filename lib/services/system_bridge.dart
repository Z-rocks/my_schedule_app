// 系统设置跳转桥（Phase W5）：小组件"省电引导"用。
//
// Kotlin 侧 [SystemSettingsBridge] 提供三个方法：manufacturer（厂商名，
// 用于给用户展示对应的操作路径）、openAppDetails（应用信息页）、
// openBatterySettings（电池优化列表页）。这里做一层封装：
// - 非 Android 平台（iOS/桌面）所有方法直接返回不可用，不抛异常；
// - 通道异常（老版本 APK 覆盖安装等）一律兜底为 false/空串。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 打开系统设置页的能力封装。全部为静态方法，无状态。
class SystemBridge {
  SystemBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.zys.myschedule/system',
  );

  /// 是否支持（仅 Android 真机有效）。
  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// 设备厂商（小写，如 `xiaomi`）。取不到返回空串。
  static Future<String> manufacturer() async {
    if (!supported) return '';
    try {
      final String? value = await _channel.invokeMethod<String>(
        'manufacturer',
      );
      return value ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  /// 打开本应用的系统信息页。成功返回 true；机型没有该页时返回 false。
  static Future<bool> openAppDetails() => _open('openAppDetails');

  /// 打开系统"电池优化"列表页。
  static Future<bool> openBatterySettings() => _open('openBatterySettings');

  /// 打开本应用的权限管理页（"桌面快捷方式"开关所在的两级页面）。
  ///
  /// 小米/HyperOS：桌面在真正落桌面之前会检查 MIUIOP(10017)「桌面快捷方式」，
  /// 默认"拒绝"，所以"添加到桌面"会被桌面静默拦掉（logcat：
  /// `add widget failed, <pkg> has no permission`）。用户允许一次即可。
  static Future<bool> openPermissionEditor() => _open('openPermissionEditor');

  /// 用系统浏览器打开 http / https 链接（"检查更新 → 前往下载"用）。
  ///
  /// 非 Android 平台 / 链接非法 / 通道不可用一律返回 `false`，
  /// 由调用方决定降级（例如复制链接到剪贴板）。
  static Future<bool> openUrl(String url) async {
    if (!supported || url.trim().isEmpty) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'openUrl',
        <String, dynamic>{'url': url},
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 本应用版本号，形如 `0.2.0+2`（versionName + versionCode）。
  ///
  /// **Android 上是版本号的唯一真相**：值来自系统包信息，而系统的
  /// versionName 由 Flutter 构建时按 `pubspec.yaml` 的 `version` 写入，
  /// 所以 Dart 侧不需要（也不应该）再维护一份常量。
  ///
  /// 非 Android 平台 / 通道不可用时返回空串，由调用方兜底。
  static Future<String> appVersion() async {
    if (!supported) return '';
    try {
      final String? value = await _channel.invokeMethod<String>('appVersion');
      return value ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  static Future<bool> _open(String method) async {
    if (!supported) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>(method);
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
