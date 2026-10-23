// 系统设置跳转桥（Phase W5）：小组件"省电引导"用。
//
// Kotlin 侧 [SystemSettingsBridge] 提供三个方法：manufacturer（厂商名，
// 用于给用户展示对应的操作路径）、openAppDetails（应用信息页）、
// openBatterySettings（电池优化列表页）。这里做一层封装：
// - Android 专属能力（厂商名 / 应用详情 / 电池优化 / 主 ABI）在其它平台
//   直接返回不可用，不空打通道；
// - 跨平台能力（openUrl / appVersion）iOS 也有实现（`AppDelegate.swift`
//   的 SystemChannelHandler），用于"前往下载 / 检查更新"与版本号显示；
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

  /// 是否有系统桥实现（Android / iOS）。
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 是否支持 Android 专属的系统设置跳转（厂商名 / 应用详情 / 电池优化）。
  ///
  /// iOS 没有这些页面，相关入口在 UI 上已经隐藏。
  static bool get isAndroidSettingsSupported =>
      !kIsWeb && Platform.isAndroid;

  /// 设备厂商（小写，如 `xiaomi`）。取不到返回空串。仅 Android。
  static Future<String> manufacturer() async {
    if (!isAndroidSettingsSupported) return '';
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
  /// Android / iOS 都支持；链接非法 / 通道不可用返回 `false`，
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

  /// 本应用版本号，形如 `0.2.0+2`（Android：versionName + versionCode；
  /// iOS：CFBundleShortVersionString + CFBundleVersion）。
  ///
  /// **是版本号的唯一真相**：值来自系统包信息，而系统的版本号由 Flutter
  /// 构建时按 `pubspec.yaml` 的 `version` 写入，
  /// 所以 Dart 侧不需要（也不应该）再维护一份常量。
  ///
  /// 平台不支持 / 通道不可用时返回空串，由调用方兜底。
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

  /// 主 ABI，形如 `arm64-v8a` / `armeabi-v7a` / `x86_64`。
  ///
  /// 检查更新时用它挑裁剪包（`app-arm64-v8a-release.apk`），
  /// 挑不到再回落通用包。取不到返回空串，调用方必须能处理空值。
  static Future<String> primaryAbi() async {
    // iOS 没有 ABI 概念，恒为空串（更新时取 .ipa，不需要选架构）。
    if (!isAndroidSettingsSupported) return '';
    try {
      final String? value = await _channel.invokeMethod<String>('primaryAbi');
      return value ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  /// 当前安装的包是不是**通用包**（一个 APK 里塞了多个 ABI）。
  ///
  /// 用途：检查更新时"装什么就更新什么"——通用包用户继续拿通用包，
  /// 不让更新把他手里的 APK 悄悄换成只认 arm64 的裁剪包。
  ///
  /// 判定是原生侧读本 APK 的 `lib/` 目录得出的（≥2 个 ABI 子目录即通用包）。
  /// 非 Android / 通道不可用 / 读取失败一律返回 `false`，
  /// 即**退回原有行为**（按 ABI 挑裁剪包），不会因为探测失败把包选错。
  static Future<bool> installedIsUniversalApk() async {
    if (!isAndroidSettingsSupported) return false;
    try {
      final bool? value =
          await _channel.invokeMethod<bool>('installedIsUniversalApk');
      return value ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 设备型号，形如 `Xiaomi 2211133C`。
  ///
  /// 用途：日志导出的头部信息。**机型特有问题**（MIUI 杀后台、
  /// 某家 ROM 的权限策略）只有拿到型号才能定位，所以值得单独取一次。
  /// 非 Android / 通道不可用返回空串。
  static Future<String> deviceModel() async {
    if (!isAndroidSettingsSupported) return '';
    try {
      final String? value = await _channel.invokeMethod<String>('deviceModel');
      return value ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  /// 系统版本，形如 `Android 14 (SDK 34)`。
  ///
  /// 用途：日志导出的头部信息。**不能用 `Platform.operatingSystemVersion`**：
  /// Android 上它返回构建指纹（`android BP2A.250605.031.A3`），
  /// 既不是版本号也不是能对照的编号，排查"某版本才有"的问题时用不上。
  ///
  /// 非 Android / 通道不可用返回空串，调用方自行回落。
  static Future<String> androidRelease() async {
    if (!isAndroidSettingsSupported) return '';
    try {
      final String? value =
          await _channel.invokeMethod<String>('androidRelease');
      return value ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  /// 用系统分享面板发一个本地文件（日志导出用）。
  ///
  /// 走 `FileProvider` + `Intent.ACTION_SEND`：微信、QQ、邮件、网盘
  /// 都能作为目标，用户想发到哪就发到哪——比"保存到某个固定目录、
  /// 再让用户自己去翻文件管理器"靠谱得多。
  ///
  /// [filePath] 必须落在 `FileProvider` 声明过的目录下
  /// （见 `res/xml/file_paths.xml`：缓存目录的 `export/` 子目录）。
  ///
  /// 返回 `true` 表示分享面板已拉起（**不代表**用户真的发出去）。
  static Future<bool> shareFile(
    String filePath, {
    String mimeType = 'text/plain',
    String subject = '',
  }) async {
    if (!isAndroidSettingsSupported || filePath.isEmpty) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'shareFile',
        <String, dynamic>{
          'path': filePath,
          'mimeType': mimeType,
          'subject': subject,
        },
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> _open(String method) async {
    if (!isAndroidSettingsSupported) return false;
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
