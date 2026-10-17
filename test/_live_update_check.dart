// 真机网络烟囱测试（不进 CI，也不参与默认 `flutter test` 扫描）。
//
// 目的：用**真实** Gitee 接口验证 UpdateService 的解析与回落，而不是只靠假数据。
// 跑法：flutter test test/_live_update_check.dart
//
// 命名不带 `_test.dart` 后缀，避免 `flutter test` 默认全量跑时联网。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/services/update_service.dart';

void main() {
  test('真实 Gitee：0.3.0 应能发现 0.3.1，且直链指向通用包', () async {
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

  test('真实 Gitee：本地已是 0.3.1 → upToDate', () async {
    final UpdateCheckResult r = await UpdateService.check(
      currentVersion: '0.3.1+4',
    );
    // ignore: avoid_print
    print('[live] upToDate 检查 → ${r.status} ${r.reason}');
    expect(r.status, UpdateStatus.upToDate);
  });
}
