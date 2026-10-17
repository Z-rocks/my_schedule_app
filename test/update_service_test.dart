// 版本比较测试（P1-5 回归护栏）。
//
// 版本比较一旦写错，表现为"永远提示有更新"或"永远说已是最新"，
// 两种都很烦人且不容易在真机上发现，所以单独测纯函数。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/services/update_service.dart';

void main() {
  group('isNewerVersion', () {
    test('补丁号变大 → 有新版本', () {
      expect(isNewerVersion('0.2.1', '0.2.0+2'), isTrue);
    });

    test('同一版本（带 v 前缀 / build 号不同）→ 不算新版本', () {
      expect(isNewerVersion('v0.2.0', '0.2.0+2'), isFalse);
      expect(isNewerVersion('0.2.0+9', '0.2.0+2'), isFalse);
    });

    test('次版本变大 → 有新版本', () {
      expect(isNewerVersion('0.3', '0.2.9'), isTrue);
    });

    test('主版本变大 → 有新版本', () {
      expect(isNewerVersion('1.0.0', '0.9.9'), isTrue);
    });

    test('本地更新（远端更旧）→ 不提示', () {
      expect(isNewerVersion('0.1.9', '0.2.0'), isFalse);
    });

    test('按数值比较而不是字符串比较（0.10 > 0.9）', () {
      expect(isNewerVersion('0.10.0', '0.9.0'), isTrue);
    });

    test('缺段按 0 补齐（0.2 == 0.2.0）', () {
      expect(isNewerVersion('0.2', '0.2.0'), isFalse);
      expect(isNewerVersion('0.2.1', '0.2'), isTrue);
    });

    test('预发布后缀被忽略（1.0.0-beta.1 视作 1.0.0）', () {
      expect(isNewerVersion('1.0.0-beta.1', '0.9.9'), isTrue);
      expect(isNewerVersion('1.0.0-beta.1', '1.0.0'), isFalse);
    });
  });

  group('UpdateCheckResult.downloadUrl', () {
    test('优先用 APK 直链', () {
      final UpdateCheckResult r = UpdateCheckResult.available(
        currentVersion: '0.2.0',
        latestVersion: '0.3.0',
        apkUrl: 'https://example.com/app.apk',
        releaseUrl: 'https://github.com/x/y/releases/tag/v0.3.0',
      );
      expect(r.downloadUrl, 'https://example.com/app.apk');
    });

    test('没有 APK 资产时退回 Release 页面', () {
      final UpdateCheckResult r = UpdateCheckResult.available(
        currentVersion: '0.2.0',
        latestVersion: '0.3.0',
        releaseUrl: 'https://github.com/x/y/releases/tag/v0.3.0',
      );
      expect(r.downloadUrl, 'https://github.com/x/y/releases/tag/v0.3.0');
    });
  });
}
