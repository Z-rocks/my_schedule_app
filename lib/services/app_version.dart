// 应用版本号：从平台读真实包信息，避免 Dart 侧再维护一份常量。
//
// 背景：设置页曾写死 `const String kAppVersion = 'v0.1.0'`，而 `pubspec.yaml`
// 早已是 `0.2.0+2` —— 两份版本号必然漂移，用户看到的永远是错的那个。
//
// 现在的单一真相链路：
//   pubspec.yaml `version: 0.3.1+4`
//     → flutter build 写入 AndroidManifest 的 versionName / versionCode
//     → 系统 PackageInfo
//     → SystemSettingsBridge.appVersion()（Kotlin）
//     → SystemBridge.appVersion()（Dart 通道）
//
// 只有非 Android 平台（桌面 / iOS，当前不发布）才用到 [kFallbackAppVersion]，
// 该常量由 `test/app_version_test.dart` 校验与 pubspec 一致，防止再次漂移。
import 'package:flutter/foundation.dart';

import 'system_bridge.dart';

/// 非 Android 平台的兜底版本号（**不含** build number）。
///
/// 只在读不到平台包信息时使用；Android 真机永远走系统读取，不会用到它
/// （iOS 也走系统读取，`AppDelegate.swift` 的 SystemChannelHandler 提供）。
/// 修改 `pubspec.yaml` 的 version 时请同步此值——测试会检查两者是否一致。
const String kFallbackAppVersion = '0.5.0';

/// 版本号读取入口（带缓存）。
///
/// 缓存的是 [Future] 而非结果：设置页可能在首帧就 build，此时读取还没完成；
/// 缓存 Future 保证多个 `FutureBuilder` 共享同一次平台调用，不会重复跨通道。
class AppVersion {
  AppVersion._();

  static Future<String>? _pending;

  /// 读取版本号，形如 `0.2.0+2`（Android）或 `0.2.0`（兜底）。
  ///
  /// 永不抛异常：读不到就返回 [kFallbackAppVersion]。
  static Future<String> load() => _pending ??= _resolve();

  static Future<String> _resolve() async {
    final String fromPlatform = await SystemBridge.appVersion();
    if (fromPlatform.isNotEmpty) return fromPlatform;

    debugPrint(
      '[AppVersion] 未能从平台读取版本号（非 Android 或通道不可用），'
      '使用兜底常量 $kFallbackAppVersion',
    );
    return kFallbackAppVersion;
  }

  /// 重置缓存（仅供测试使用）。
  @visibleForTesting
  static void resetCache() => _pending = null;
}
