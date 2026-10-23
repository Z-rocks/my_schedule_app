// 数据备份服务测试：导出结构 / 导入校验 / 覆盖语义 / 清空 / 清缓存。
//
// 这里的用例大多在验证**边界语义**而不是 happy path：
// 备份导入是"整箱替换"，一旦语义错了就是数据丢失，所以
// "未知 Box 要忽略"、"缺 Box 要清空"、"非字符串值要丢弃"这几条
// 都有专门的用例钉住。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:my_schedule_app/services/data_backup_service.dart';
import 'package:my_schedule_app/services/plugin_storage_service.dart';
import 'package:my_schedule_app/services/storage_service.dart';

void main() {
  late Directory tmp;
  late Directory cacheDir;
  late Directory pluginRoot;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('backup_test_');
    cacheDir = await Directory('${tmp.path}/cache').create();
    pluginRoot = await Directory('${tmp.path}/docs').create();
    PluginStorageService.setRootDirForTesting(pluginRoot.path);
    await StorageService.init(path: tmp.path);
  });

  tearDown(() async {
    PluginStorageService.setRootDirForTesting(null);
    await StorageService.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// 构造一份最小可用的合法备份。
  String backupText({
    Map<String, Map<String, String>>? boxes,
    int formatVersion = kBackupFormatVersion,
    String format = kBackupFormat,
  }) {
    return jsonEncode(<String, dynamic>{
      'format': format,
      'formatVersion': formatVersion,
      'appVersion': '0.6.0+3005',
      'exportedAt': '2026-10-23T18:00:00.000',
      'counts': <String, int>{},
      'boxes': boxes ?? <String, Map<String, String>>{},
    });
  }

  group('导出结构', () {
    test('空库也能导出，9 个 Box 全部就位', () async {
      final Map<String, dynamic> payload =
          jsonDecode(await DataBackupService.buildBackupJson())
              as Map<String, dynamic>;

      expect(payload['format'], kBackupFormat);
      expect(payload['formatVersion'], kBackupFormatVersion);
      expect(payload['appVersion'], isNotEmpty);
      expect(payload['exportedAt'], isNotEmpty);

      final Map<String, dynamic> boxes = payload['boxes'] as Map<String, dynamic>;
      for (final String name in kBackupBoxNames) {
        expect(boxes.containsKey(name), isTrue, reason: '缺少 Box $name');
      }
    });

    test('Box 里的值原样搬过去，不二次解析', () async {
      const String raw = '{"id":"c1","name":"高等数学","weeks":[1,2,3]}';
      await StorageService.coursesBox.put('c1', raw);

      final Map<String, dynamic> payload =
          jsonDecode(await DataBackupService.buildBackupJson())
              as Map<String, dynamic>;
      final Map<String, dynamic> courses =
          (payload['boxes'] as Map<String, dynamic>)['courses']
              as Map<String, dynamic>;

      expect(courses['c1'], raw);
      expect((payload['counts'] as Map<String, dynamic>)['courses'], 1);
    });

    test('插件 js 源码单独打包（Hive 里没有它们）', () async {
      await StorageService.pluginsBox.put(
        'demo',
        '{"id":"demo","name":"示例"}',
      );
      await PluginStorageService.installPlugin(
        pluginId: 'demo',
        jsSource: 'var __plugin = { id: "demo" };',
        manifestJson: '{"id":"demo"}',
      );

      final Map<String, dynamic> payload =
          jsonDecode(await DataBackupService.buildBackupJson())
              as Map<String, dynamic>;

      final Map<String, dynamic> files =
          payload['pluginFiles'] as Map<String, dynamic>;
      final Map<String, dynamic> manifests =
          payload['pluginManifests'] as Map<String, dynamic>;
      expect(files['demo'], contains('__plugin'));
      expect(manifests['demo'], contains('"demo"'));
    });

    test('export 会真的落盘，并回报各 Box 条目数', () async {
      await StorageService.coursesBox.put('c1', '{"id":"c1"}');
      await StorageService.examsBox.put('e1', '{"id":"e1"}');

      final BackupResult result = await DataBackupService.export(
        share: false,
        dirOverride: cacheDir,
      );

      expect(result.ok, isTrue);
      expect(await result.file!.exists(), isTrue);
      expect(result.counts[kCoursesBoxName], 1);
      expect(result.counts[kExamsBoxName], 1);
      expect(result.totalEntries, 2);

      final Map<String, dynamic> written =
          jsonDecode(await result.file!.readAsString()) as Map<String, dynamic>;
      expect(written['format'], kBackupFormat);
    });
  });

  group('导入校验', () {
    test('空文本 / 非 JSON 被拒', () {
      expect(DataBackupService.validate(''), '文件内容不是合法的 JSON');
      expect(DataBackupService.validate('   '), '文件内容不是合法的 JSON');
      expect(DataBackupService.validate('not json'), '文件内容不是合法的 JSON');
    });

    test('顶层不是对象被拒', () {
      expect(DataBackupService.validate('[1,2,3]'), '文件结构不正确：顶层应为对象');
    });

    test('format 不对被拒（防止误选别的 JSON）', () {
      expect(
        DataBackupService.validate(backupText(format: 'something-else')),
        '这不是校园助手的备份文件',
      );
    });

    test('缺 formatVersion 被拒', () {
      final String text = jsonEncode(<String, dynamic>{
        'format': kBackupFormat,
        'boxes': <String, dynamic>{},
      });
      expect(DataBackupService.validate(text), '备份文件缺少格式版本号');
    });

    test('来自更高版本的备份被拒，并提示升级', () {
      expect(
        DataBackupService.validate(
          backupText(formatVersion: kBackupFormatVersion + 1),
        ),
        contains('请先升级 App'),
      );
    });

    test('缺数据区被拒', () {
      final String text = jsonEncode(<String, dynamic>{
        'format': kBackupFormat,
        'formatVersion': 1,
      });
      expect(DataBackupService.validate(text), '备份文件缺少数据区');
    });

    test('合法备份通过校验', () {
      expect(DataBackupService.validate(backupText()), isNull);
    });

    test('summarize 统计各 Box 条目数', () {
      final String text = backupText(
        boxes: <String, Map<String, String>>{
          kCoursesBoxName: <String, String>{'a': '{}', 'b': '{}'},
          kExamsBoxName: <String, String>{'x': '{}'},
        },
      );
      final Map<String, int> counts = DataBackupService.summarize(text);
      expect(counts[kCoursesBoxName], 2);
      expect(counts[kExamsBoxName], 1);
      // 备份里没出现的 Box 不出现在统计里（UI 按 0 处理）。
      expect(counts.containsKey(kHomeworksBoxName), isFalse);
    });

    test('summarize 对非法文本返回空 Map', () {
      expect(DataBackupService.summarize('garbage'), isEmpty);
    });
  });

  group('导入语义', () {
    test('覆盖：旧数据被整箱替换', () async {
      await StorageService.coursesBox.put('old', '{"id":"old"}');

      final RestoreResult result = await DataBackupService.import(
        backupText(
          boxes: <String, Map<String, String>>{
            kCoursesBoxName: <String, String>{'new': '{"id":"new"}'},
          },
        ),
        createRollback: false,
      );

      expect(result.ok, isTrue);
      expect(StorageService.coursesBox.containsKey('old'), isFalse);
      expect(StorageService.coursesBox.get('new'), '{"id":"new"}');
      expect(result.counts[kCoursesBoxName], 1);
    });

    test('备份里没有的 Box 会被清空（整箱替换的应有之义）', () async {
      await StorageService.examsBox.put('e1', '{"id":"e1"}');

      await DataBackupService.import(
        backupText(
          boxes: <String, Map<String, String>>{
            kCoursesBoxName: <String, String>{'c1': '{}'},
          },
        ),
        createRollback: false,
      );

      expect(StorageService.examsBox.isEmpty, isTrue);
    });

    test('未知 Box 被忽略（不允许往白名单外写数据）', () async {
      final RestoreResult result = await DataBackupService.import(
        backupText(
          boxes: <String, Map<String, String>>{
            kCoursesBoxName: <String, String>{'c1': '{}'},
            'evil_box': <String, String>{'k': 'v'},
          },
        ),
        createRollback: false,
      );

      expect(result.ok, isTrue);
      expect(result.counts.containsKey('evil_box'), isFalse);
      // 白名单外的 Box 不该因为导入而被创建 / 打开。
      expect(Hive.isBoxOpen('evil_box'), isFalse);
    });

    test('非字符串值被丢弃，不写进 Box', () async {
      final String text = jsonEncode(<String, dynamic>{
        'format': kBackupFormat,
        'formatVersion': kBackupFormatVersion,
        'boxes': <String, dynamic>{
          kCoursesBoxName: <String, dynamic>{'ok': '{}', 'bad': 123},
        },
      });

      await DataBackupService.import(text, createRollback: false);

      expect(StorageService.coursesBox.get('ok'), '{}');
      expect(StorageService.coursesBox.containsKey('bad'), isFalse);
    });

    test('非法备份被拒时不动已有数据', () async {
      await StorageService.coursesBox.put('keep', '{"id":"keep"}');

      final RestoreResult result = await DataBackupService.import(
        'not a backup',
        createRollback: false,
      );

      expect(result.ok, isFalse);
      expect(StorageService.coursesBox.get('keep'), '{"id":"keep"}');
    });

    test('插件 js 与 manifest 一并恢复', () async {
      final String text = jsonEncode(<String, dynamic>{
        'format': kBackupFormat,
        'formatVersion': kBackupFormatVersion,
        'boxes': <String, dynamic>{},
        'pluginFiles': <String, String>{
          'restored': 'var __plugin = { id: "restored" };',
        },
        'pluginManifests': <String, String>{'restored': '{"id":"restored"}'},
      });

      final RestoreResult result =
          await DataBackupService.import(text, createRollback: false);

      expect(result.ok, isTrue);
      expect(result.pluginCount, 1);
      expect(await PluginStorageService.isInstalled('restored'), isTrue);
      expect(
        await PluginStorageService.getPluginManifestPath('restored'),
        isNotNull,
      );
    });
  });

  group('清空与清缓存', () {
    test('清空业务数据，保留设置与插件', () async {
      await StorageService.coursesBox.put('c1', '{}');
      await StorageService.examsBox.put('e1', '{}');
      await StorageService.homeworksBox.put('h1', '{}');
      await StorageService.overridesBox.put('c1', '{}');
      await StorageService.settingsBox.put(kSemesterConfigKey, '{}');
      await StorageService.pluginsBox.put('p1', '{}');

      final int cleared = await DataBackupService.clearBusinessData();

      expect(cleared, 4);
      expect(StorageService.coursesBox.isEmpty, isTrue);
      expect(StorageService.overridesBox.isEmpty, isTrue);
      // 配置类必须留着：用户清课表不是要重置整个 App。
      expect(StorageService.settingsBox.get(kSemesterConfigKey), '{}');
      expect(StorageService.pluginsBox.containsKey('p1'), isTrue);
    });

    test('清缓存删掉临时文件、保留 export 目录、回报释放字节', () async {
      final File junk = File('${cacheDir.path}/junk.bin');
      await junk.writeAsBytes(List<int>.filled(2048, 0));
      final Directory exportDir =
          await Directory('${cacheDir.path}/export').create();
      final File exported = File('${exportDir.path}/backup.json');
      await exported.writeAsString('{}');

      final ClearCacheResult result =
          await DataBackupService.clearCache(dirOverride: cacheDir);

      expect(result.ok, isTrue);
      expect(result.freedBytes, greaterThanOrEqualTo(2048));
      expect(await junk.exists(), isFalse);
      // 导出目录是用户的"刚生成还没发出去"的备份，不能顺手删。
      expect(await exported.exists(), isTrue);
    });
  });
}
