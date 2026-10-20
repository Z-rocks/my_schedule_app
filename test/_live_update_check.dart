// 真机网络烟囱测试（不进 CI，也不参与默认 `flutter test` 扫描）。
//
// 目的：用**真实** Gitee 接口验证 UpdateService 的解析与回落，而不是只靠假数据。
// 跑法：flutter test test/_live_update_check.dart
//
// 命名不带 `_test.dart` 后缀，避免 `flutter test` 默认全量跑时联网。
//
// ⚠️ 不要在这里写死"本地版本 X 应是最新"：线上每发一版，这种断言就会假失败。
// 需要验证 upToDate 时，先查出线上真实最新版本，再拿它当"当前版本"查第二次。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/services/update_service.dart';

void main() {
  test('真实 Gitee：0.3.0 应能发现线上新版本，且直链指向通用包', () async {
    final UpdateCheckResult r = await UpdateService.check(
      currentVersion: '0.3.0+3',
    );

    // 打印出来方便人工核对
    // ignore: avoid_print
    print('[live] status=${r.status} source=${r.source} '
        'latest=${r.latestVersion} apk=${r.apkUrl}');
    // ignore: avoid_print
    print('[live] changelog 前 80 字：${r.changelog.length > 80 ? r.changelog.substring(0, 80) : r.changelog}');

    expect(r.status, UpdateStatus.available);
    expect(r.source, UpdateSource.gitee.label, reason: 'Gitee 应该命中，不该回落到 GitHub');
    expect(isNewerVersion(r.latestVersion, '0.3.0'), isTrue);
    expect(r.apkUrl, endsWith('/app-release.apk'), reason: '必须选通用包，不能选分架构包');
    expect(r.releaseUrl, contains('gitee.com/zrocks/my_schedule_app'));
    expect(r.changelog, isNotEmpty, reason: 'Release body 应该被解析出来');
  });

  test('真实 Gitee：arm64 设备更新时选裁剪包，不是通用包', () async {
    final UpdateCheckResult r = await UpdateService.check(
      currentVersion: '0.3.0+3',
      abi: 'arm64-v8a',
    );
    // ignore: avoid_print
    print('[live] arm64 选包 → ${r.apkUrl}');
    expect(r.apkUrl, endsWith('/app-arm64-v8a-release.apk'),
        reason: '手机更新应该拿 23MB 裁剪包，不是 59MB 通用包');
  });

  test('真实 Gitee：iOS 端只会拿 ipa，绝不会拿 apk', () async {
    final UpdateCheckResult r = await UpdateService.check(
      currentVersion: '0.3.0+3',
      kind: PackageKind.ipa,
    );
    // ignore: avoid_print
    print('[live] iOS 选包 → apkUrl=${r.apkUrl.isEmpty ? "(空)" : r.apkUrl}'
        ' downloadUrl=${r.downloadUrl}');

    expect(r.status, UpdateStatus.available);
    // 两种合法状态：Release 里有 ipa → 指向 .ipa；没有 ipa → 空并回落 Release 页。
    // 断言写成"绝不出现 .apk"，无论将来传不传 ipa 都不会假失败。
    expect(r.apkUrl.endsWith('.apk'), isFalse,
        reason: 'iOS 绝不能下 Android 包');
    if (r.apkUrl.isEmpty) {
      expect(r.downloadUrl, contains('/releases/tag/'),
          reason: '没有 ipa 时应回落到 Release 页面');
    } else {
      expect(r.apkUrl, endsWith('.ipa'));
    }
  });

  test('真实 Gitee：以线上最新版本为当前版本 → upToDate', () async {
    final UpdateCheckResult probe = await UpdateService.check(
      currentVersion: '0.0.1+1',
    );
    expect(probe.latestVersion, isNotEmpty, reason: '先要能查到线上版本');
    // ignore: avoid_print
    print('[live] 线上最新=${probe.latestVersion}，用它当当前版本再查一次');

    final UpdateCheckResult r = await UpdateService.check(
      currentVersion: probe.latestVersion,
    );
    // ignore: avoid_print
    print('[live] upToDate 检查 → ${r.status} ${r.reason}');
    expect(r.status, UpdateStatus.upToDate);
  });
}
