// 版本比较 + 多源检查更新测试（P1-5 回归护栏）。
//
// 版本比较一旦写错，表现为"永远提示有更新"或"永远说已是最新"，
// 两种都很烦人且不容易在真机上发现，所以单独测纯函数。
//
// 多源部分（Gitee 镜像 → GitHub 兜底）用假的 HttpClientAdapter 打桩：
// 这是"用户能不能收到更新"的唯一通道，回落逻辑错了等于发版白发。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/services/update_service.dart';

/// 按 URL 打桩的假适配器：命中返回 JSON，未命中/传 int 则抛对应状态码。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.routes);

  final Map<String, Object> routes;

  /// 记录被请求过的 URL，用来断言"该回落的回落了、该停的停下了"。
  final List<String> hits = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String url = options.uri.toString();
    hits.add(url);
    final Object? route = routes[url];
    if (route == null) {
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(requestOptions: options, statusCode: 404),
        type: DioExceptionType.badResponse,
      );
    }
    if (route is int) {
      throw DioException(
        requestOptions: options,
        response:
            Response<dynamic>(requestOptions: options, statusCode: route),
        type: DioExceptionType.badResponse,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(route),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 造一个走假适配器的 Dio。
Dio _fakeDio(_FakeAdapter adapter) {
  final Dio dio = Dio();
  dio.httpClientAdapter = adapter;
  return dio;
}

/// 一份 Gitee 形状的 Release JSON（注意：**没有** html_url）。
Map<String, Object?> _giteeRelease({
  String tag = 'v0.3.1',
  bool prerelease = false,
  List<Map<String, String>>? assets,
}) {
  return <String, Object?>{
    'id': 1,
    'tag_name': tag,
    'target_commitish': 'main',
    'prerelease': prerelease,
    'name': tag,
    'body': '修复了一些问题',
    'created_at': '2026-10-17T10:00:00+08:00',
    'assets': assets ??
        <Map<String, String>>[
          <String, String>{
            'name': 'v$tag.zip',
            'browser_download_url':
                'https://gitee.com/zrocks/my_schedule_app/archive/refs/tags/$tag.zip',
          },
          <String, String>{
            'name': 'app-release.apk',
            'browser_download_url':
                'https://gitee.com/zrocks/my_schedule_app/releases/download/$tag/app-release.apk',
          },
        ],
  };
}

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

  group('多源检查更新（Gitee 优先，GitHub 兜底）', () {
    final String giteeUrl = UpdateSource.gitee.apiUrl;
    final String githubUrl = UpdateSource.github.apiUrl;

    test('Gitee 命中就直接用，不碰 GitHub', () async {
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        giteeUrl: _giteeRelease(),
        githubUrl: _giteeRelease(tag: 'v9.9.9'),
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.0+3',
        dio: _fakeDio(adapter),
      );

      expect(r.status, UpdateStatus.available);
      expect(r.latestVersion, '0.3.1');
      expect(r.source, 'Gitee 镜像');
      expect(adapter.hits, <String>[giteeUrl], reason: '第一个源成功就不该再查第二个');
    });

    test('Gitee 没有 html_url 时，Release 页面地址按仓库地址拼出来', () async {
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        giteeUrl: _giteeRelease(),
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.0',
        dio: _fakeDio(adapter),
      );

      expect(r.releaseUrl,
          'https://gitee.com/zrocks/my_schedule_app/releases/tag/v0.3.1');
      // assets 里第一个是源码 zip，必须跳过它取 .apk
      expect(
        r.apkUrl,
        'https://gitee.com/zrocks/my_schedule_app/releases/download/'
        'v0.3.1/app-release.apk',
      );
    });

    test('Gitee 404 → 回落 GitHub，source 标成 GitHub', () async {
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        giteeUrl: 404,
        githubUrl: <String, Object?>{
          ..._giteeRelease(tag: 'v0.3.2'),
          'html_url':
              'https://github.com/Z-rocks/my_schedule_app/releases/tag/v0.3.2',
        },
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.0',
        dio: _fakeDio(adapter),
      );

      expect(r.status, UpdateStatus.available);
      expect(r.latestVersion, '0.3.2');
      expect(r.source, 'GitHub');
      expect(r.releaseUrl,
          'https://github.com/Z-rocks/my_schedule_app/releases/tag/v0.3.2');
      expect(adapter.hits.length, 2);
    });

    test('Gitee 最新是预发布版 → 跳过它，回落 GitHub 的正式版', () async {
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        giteeUrl: _giteeRelease(tag: 'v0.4.0', prerelease: true),
        githubUrl: _giteeRelease(tag: 'v0.3.1'),
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.0',
        dio: _fakeDio(adapter),
      );

      expect(r.status, UpdateStatus.available);
      expect(r.latestVersion, '0.3.1', reason: '不该把预发布的 0.4.0 推给用户');
      expect(r.source, 'GitHub');
    });

    test('Gitee 版本不比本地新 → upToDate，不再回落', () async {
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        giteeUrl: _giteeRelease(tag: 'v0.3.0'),
        githubUrl: _giteeRelease(tag: 'v0.9.0'),
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.0+3',
        dio: _fakeDio(adapter),
      );

      expect(r.status, UpdateStatus.upToDate);
      expect(r.source, 'Gitee 镜像');
      expect(adapter.hits.length, 1);
    });

    test('两个源都失败 → failed，且原因里两家都点名（方便截图反馈）', () async {
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        giteeUrl: 404,
        githubUrl: 404,
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.0',
        dio: _fakeDio(adapter),
      );

      expect(r.status, UpdateStatus.failed);
      expect(r.reason, contains('Gitee 镜像'));
      expect(r.reason, contains('GitHub'));
      expect(r.reason, contains('还没有发布过 Release'));
    });

    test('只有源码包没有 APK 时，apkUrl 为空（回落到 Release 页面）', () async {
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        giteeUrl: _giteeRelease(
          assets: <Map<String, String>>[
            <String, String>{
              'name': 'v0.3.1.tar.gz',
              'browser_download_url': 'https://gitee.com/x/y/archive/v0.3.1.tar.gz',
            },
          ],
        ),
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.0',
        dio: _fakeDio(adapter),
      );

      expect(r.apkUrl, isEmpty);
      expect(r.downloadUrl, r.releaseUrl);
    });

    test('数据无法识别（非 JSON 对象）→ 该源失败并回落', () async {
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        giteeUrl: <String>['不是对象'],
        githubUrl: _giteeRelease(tag: 'v0.3.1'),
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.0',
        dio: _fakeDio(adapter),
      );

      expect(r.status, UpdateStatus.available);
      expect(r.source, 'GitHub');
    });

    test('同时挂了通用包和分架构包时，优先通用包（任意机型都能装）', () async {
      // 顺序故意把 arm64 放前面：assets 顺序不保证，不能靠位置判断。
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        giteeUrl: _giteeRelease(
          assets: <Map<String, String>>[
            <String, String>{
              'name': 'app-arm64-v8a-release.apk',
              'browser_download_url':
                  'https://gitee.com/x/y/releases/download/v0.3.1/app-arm64-v8a-release.apk',
            },
            <String, String>{
              'name': 'app-release.apk',
              'browser_download_url':
                  'https://gitee.com/x/y/releases/download/v0.3.1/app-release.apk',
            },
          ],
        ),
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.0',
        dio: _fakeDio(adapter),
      );

      expect(r.apkUrl, endsWith('/app-release.apk'));
    });

    test('没有通用包时退回第一个 APK（分架构包也能装）', () async {
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        giteeUrl: _giteeRelease(
          assets: <Map<String, String>>[
            <String, String>{
              'name': 'v0.3.1.zip',
              'browser_download_url': 'https://gitee.com/x/y/archive/v0.3.1.zip',
            },
            <String, String>{
              'name': 'app-arm64-v8a-release.apk',
              'browser_download_url':
                  'https://gitee.com/x/y/releases/download/v0.3.1/app-arm64-v8a-release.apk',
            },
          ],
        ),
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.0',
        dio: _fakeDio(adapter),
      );

      expect(r.apkUrl, endsWith('/app-arm64-v8a-release.apk'));
    });
  });

  // v0.3.4 起：手机更新时优先拿裁剪包（21MB），不再一律拉通用包（58MB）。
  // 但裁剪包必须**精确匹配**设备 ABI——把 arm64 包发给 armeabi-v7a 老机型
  // 会直接装不上，所以匹配不上时只能退回通用包，不能"随便拿一个"。
  group('按设备 ABI 选包', () {
    final List<Map<String, String>> assets = <Map<String, String>>[
      <String, String>{
        'name': 'app-release.apk',
        'browser_download_url': 'https://x/app-release.apk',
      },
      <String, String>{
        'name': 'app-arm64-v8a-release.apk',
        'browser_download_url': 'https://x/app-arm64-v8a-release.apk',
      },
      <String, String>{
        'name': 'app-armeabi-v7a-release.apk',
        'browser_download_url': 'https://x/app-armeabi-v7a-release.apk',
      },
    ];

    test('arm64-v8a → arm64 裁剪包', () {
      expect(selectApkUrl(assets, 'arm64-v8a'),
          'https://x/app-arm64-v8a-release.apk');
    });

    test('armeabi-v7a → v7 裁剪包（不能误拿 arm64）', () {
      expect(selectApkUrl(assets, 'armeabi-v7a'),
          'https://x/app-armeabi-v7a-release.apk');
    });

    test('ABI 未知 → 通用包', () {
      expect(selectApkUrl(assets, ''), 'https://x/app-release.apk');
    });

    test('Release 里没有该 ABI 的包 → 回落通用包，不拿别的架构顶', () {
      final List<Map<String, String>> onlyArm64 = <Map<String, String>>[
        <String, String>{
          'name': 'app-release.apk',
          'browser_download_url': 'https://x/app-release.apk',
        },
        <String, String>{
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url': 'https://x/app-arm64-v8a-release.apk',
        },
      ];
      expect(selectApkUrl(onlyArm64, 'x86_64'), 'https://x/app-release.apk');
    });

    test('连通用包都没有时才退回第一个 apk', () {
      final List<Map<String, String>> noUniversal = <Map<String, String>>[
        <String, String>{
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url': 'https://x/app-arm64-v8a-release.apk',
        },
      ];
      expect(selectApkUrl(noUniversal, ''), 'https://x/app-arm64-v8a-release.apk');
    });

    test('只有源码包 → 空串（交给 Release 页面兜底）', () {
      final List<Map<String, String>> onlySource = <Map<String, String>>[
        <String, String>{
          'name': 'v0.3.4.zip',
          'browser_download_url': 'https://x/v0.3.4.zip',
        },
      ];
      expect(selectApkUrl(onlySource, 'arm64-v8a'), isEmpty);
    });

    test('裁剪包文件名与构建脚本产物一致', () {
      expect(apkNameForAbi('arm64-v8a'), 'app-arm64-v8a-release.apk');
      expect(apkNameForAbi('ARM64-V8A'), 'app-arm64-v8a-release.apk');
    });

    test('check 传入 abi 时，端到端选到裁剪包', () async {
      final _FakeAdapter adapter = _FakeAdapter(<String, Object>{
        UpdateSource.gitee.apiUrl: _giteeRelease(
          tag: 'v0.3.4',
          assets: <Map<String, String>>[
            <String, String>{
              'name': 'app-release.apk',
              'browser_download_url':
                  'https://gitee.com/x/y/releases/download/v0.3.4/app-release.apk',
            },
            <String, String>{
              'name': 'app-arm64-v8a-release.apk',
              'browser_download_url':
                  'https://gitee.com/x/y/releases/download/v0.3.4/app-arm64-v8a-release.apk',
            },
          ],
        ),
      });

      final UpdateCheckResult r = await UpdateService.check(
        currentVersion: '0.3.3+6',
        dio: _fakeDio(adapter),
        abi: 'arm64-v8a',
      );

      expect(r.apkUrl, endsWith('/app-arm64-v8a-release.apk'));
    });
  });
}
