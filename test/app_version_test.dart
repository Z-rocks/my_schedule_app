// 版本号一致性测试（P0-3 回归护栏）。
//
// 起因：设置页曾写死 `v0.1.0`，而 pubspec 是 `0.2.0+2`，用户看到的是错的版本。
// 现在 Android 上走平台读取（唯一真相），只有非 Android 平台用兜底常量
// [kFallbackAppVersion]——所以必须保证这个常量不会再次与 pubspec 漂移。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/services/app_version.dart';

void main() {
  test('兜底版本号与 pubspec.yaml 的 version 一致', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? match =
        RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
            .firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml 里找不到 version 字段');
    expect(
      kFallbackAppVersion,
      match!.group(1),
      reason: '改 pubspec 的 version 时，记得同步 kFallbackAppVersion',
    );
  });

  test('非 Android 环境回落到兜底版本号（不抛异常）', () async {
    AppVersion.resetCache();
    expect(await AppVersion.load(), kFallbackAppVersion);
  });
}
