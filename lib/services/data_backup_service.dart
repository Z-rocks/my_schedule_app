// 数据备份服务：全量导出 / 导入 / 清空业务数据 / 清理缓存。
//
// ## 为什么需要它
//
// 本 App **没有后端、没有云同步**，所有数据只在本机 Hive 里。换手机、
// 清应用数据、卸载重装 = 全丢。所以"导出/导入"不是锦上添花，而是
// 唯一的数据安全网。
//
// ## 备份文件长什么样
//
// 单个 JSON（**明文，用户可读**）：
//
// ```json
// {
//   "format": "campus-assistant-backup",
//   "formatVersion": 1,
//   "appVersion": "0.6.0+3005",
//   "exportedAt": "2026-10-23T18:30:00.000",
//   "counts": { "courses": 32, "exams": 5, ... },
//   "boxes": { "courses": { "<id>": "<该条目的原始 JSON 字符串>" }, ... },
//   "pluginFiles": { "<pluginId>": "<插件 js 源码>" },
//   "pluginManifests": { "<pluginId>": "<manifest JSON>" }
// }
// ```
//
// 几个刻意的取舍：
//
// - **Box 的值原样存字符串，不二次解析**。Box 里的值本来就是 JSON 字符串，
//   再解析一层只会多一次失败机会，还会把"上游写坏了的数据"在导入时
//   静默修复成另一副样子。原样搬过去，坏数据还是坏数据，至少和导出前一致。
// - **插件 js 源码单独打包**。插件元数据在 `plugins` Box 里，但 `.js` 文件在
//   应用私有目录，**不在 Hive 里**——只导 Box 的话，导入后插件会显示"已安装"
//   却加载失败。
// - **绝不导出 Cookie**。登录凭据在 `flutter_secure_storage`（系统密钥库），
//   一旦写进明文 JSON 就等于把学号密码送出去了。导入后需要重新登录，
//   这一点必须在 UI 上明说。
//
// ## 导入策略：覆盖，且先留回滚点
//
// 合并会带来 ID 冲突、覆盖层错位、"哪条是新的"无法判断等问题，收益远小于
// 风险。所以导入 = **整箱替换**。但替换前会自动把当前数据写到
// `<appSupport>/backups/pre-import-*.json`，用户点错了还有得救（保留最近 3 份）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';
import 'app_version.dart';
import 'plugin_storage_service.dart';
import 'storage_service.dart';
import 'system_bridge.dart';

/// 备份文件的格式标识。导入时用它判断"这是不是本 App 的备份"。
const String kBackupFormat = 'campus-assistant-backup';

/// 当前备份格式版本。
///
/// **只在结构发生不兼容变化时 +1**：新增可选字段不用动它（导入侧对缺键
/// 有默认值），但字段改名 / 语义变化必须 +1，并在这里写清楚怎么迁移。
const int kBackupFormatVersion = 1;

/// 参与备份的 Box（顺序即导出顺序，便于人工比对）。
///
/// 白名单同时是**导入侧的护栏**：备份文件里出现别的 Box 名一律忽略，
/// 不允许一个被篡改的文件往任意 Box 里写数据。
const List<String> kBackupBoxNames = <String>[
  kCoursesBoxName,
  kExamsBoxName,
  kHomeworksBoxName,
  kMessagesBoxName,
  kOverridesBoxName,
  kSettingsBoxName,
  kPluginsBoxName,
  kSkinsBoxName,
  kPluginDataBoxName,
];

/// "清空课表数据"会清掉的 Box。
///
/// 刻意**不含** `settings` / `plugins` / `skins`：那三个装的是用户的
/// 配置与已装扩展，属于"环境"而不是"数据"。用户想清空课表，不该顺带
/// 把主题、导航栏布局、已装插件一起清掉。
const List<String> kClearableBoxNames = <String>[
  kCoursesBoxName,
  kExamsBoxName,
  kHomeworksBoxName,
  kMessagesBoxName,
  kOverridesBoxName,
];

/// 缓存目录里**不清理**的子目录。
///
/// 导出文件放这儿：用户可能刚导出、还没发出去，清缓存顺手删掉会很尴尬。
const String kExportSubdirName = 'export';

/// 回滚点目录名（位于应用支持目录下，不会被"清理缓存"误删）。
const String kBackupSubdirName = 'backups';

/// 回滚点保留份数。
const int kMaxRollbackFiles = 3;

/// 导出结果。
class BackupResult {
  const BackupResult({
    required this.ok,
    this.file,
    this.message = '',
    this.shared = false,
    this.counts = const <String, int>{},
  });

  final bool ok;

  /// 生成的备份文件（`ok` 为 true 时非空）。
  final File? file;

  /// 失败原因 / 文件路径（面向用户）。
  final String message;

  /// 是否已通过系统分享面板发出去（`false` 表示只生成了文件）。
  final bool shared;

  /// 各 Box 的条目数。
  final Map<String, int> counts;

  /// 总条目数。
  int get totalEntries =>
      counts.values.fold<int>(0, (int sum, int v) => sum + v);

  static BackupResult failure(String message) =>
      BackupResult(ok: false, message: message);
}

/// 导入结果。
class RestoreResult {
  const RestoreResult({
    required this.ok,
    this.message = '',
    this.counts = const <String, int>{},
    this.pluginCount = 0,
    this.rollbackFile,
  });

  final bool ok;
  final String message;

  /// 各 Box 恢复的条目数。
  final Map<String, int> counts;

  /// 恢复的插件文件数。
  final int pluginCount;

  /// 导入前的自动回滚点（导入失败时为 `null`）。
  final File? rollbackFile;

  int get totalEntries =>
      counts.values.fold<int>(0, (int sum, int v) => sum + v);

  static RestoreResult failure(String message) =>
      RestoreResult(ok: false, message: message);
}

/// 清理缓存结果。
class ClearCacheResult {
  const ClearCacheResult({
    required this.ok,
    this.freedBytes = 0,
    this.message = '',
  });

  final bool ok;

  /// 释放的字节数（尽力统计；单个文件删不掉只少算，不影响整体）。
  final int freedBytes;

  final String message;
}

/// 数据备份服务。全部静态方法，无状态。
class DataBackupService {
  DataBackupService._();

  // ───────────────────────── 导出 ─────────────────────────

  /// 生成备份 JSON 文本（不落盘）。
  ///
  /// 测试直接断言这里产出的结构；UI 侧走 [export]。
  static Future<String> buildBackupJson() async {
    final Map<String, Map<String, String>> boxes =
        <String, Map<String, String>>{};
    for (final String name in kBackupBoxNames) {
      final Box<String>? box = _boxOrNull(name);
      if (box == null) continue;
      final Map<String, String> entries = <String, String>{};
      for (final Object? key in box.keys) {
        final String? value = _stringValue(box.get(key));
        if (value != null) entries['$key'] = value;
      }
      boxes[name] = entries;
    }

    final Map<String, String> pluginFiles = <String, String>{};
    final Map<String, String> pluginManifests = <String, String>{};
    try {
      for (final String id in await PluginStorageService.listInstalled()) {
        final String? jsPath =
            await PluginStorageService.getPluginJsPath(id);
        if (jsPath != null) {
          final String? source = await _readText(jsPath);
          if (source != null) pluginFiles[id] = source;
        }
        final String? manifestPath =
            await PluginStorageService.getPluginManifestPath(id);
        if (manifestPath != null) {
          final String? manifest = await _readText(manifestPath);
          if (manifest != null) pluginManifests[id] = manifest;
        }
      }
    } catch (error) {
      // 插件目录读不到不该让整个备份失败——课表数据才是主角。
      debugPrint('[DataBackup] 读取插件文件失败（跳过）：$error');
      AppLog.w('backup', '读取插件文件失败，备份不含插件源码',
          <String, Object?>{'error': '$error'});
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'format': kBackupFormat,
      'formatVersion': kBackupFormatVersion,
      'appVersion': await AppVersion.load(),
      'exportedAt': DateTime.now().toIso8601String(),
      'counts': <String, int>{
        for (final MapEntry<String, Map<String, String>> e in boxes.entries)
          e.key: e.value.length,
      },
      'boxes': boxes,
      'pluginFiles': pluginFiles,
      'pluginManifests': pluginManifests,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 导出到缓存目录并（可选）拉起系统分享面板。
  ///
  /// 分享失败**不删文件**：用户至少还能从提示里看到路径。
  /// [dirOverride] 仅供测试注入临时目录（生产环境传 `null`，走 `path_provider`）。
  static Future<BackupResult> export({
    bool share = true,
    Directory? dirOverride,
  }) async {
    try {
      final String text = await buildBackupJson();
      final Map<String, int> counts = _countsOf(text);
      final File file = await _writeExportFile(text, dirOverride: dirOverride);

      if (!share) {
        AppLog.action('data_export', <String, Object?>{
          'bytes': await file.length(),
          'total': counts.values.fold<int>(0, (int a, int b) => a + b),
          'shared': false,
        });
        return BackupResult(
          ok: true,
          file: file,
          message: file.path,
          counts: counts,
        );
      }

      final bool shared = await SystemBridge.shareFile(
        file.path,
        mimeType: 'application/json',
        subject: '校园助手 数据备份',
      );
      AppLog.action('data_export', <String, Object?>{
        'bytes': await file.length(),
        'total': counts.values.fold<int>(0, (int a, int b) => a + b),
        'shared': shared,
      });
      if (!shared) {
        AppLog.w('backup', '系统分享不可用，仅生成备份文件',
            <String, Object?>{'path': file.path});
      }
      return BackupResult(
        ok: true,
        file: file,
        message: file.path,
        shared: shared,
        counts: counts,
      );
    } catch (error, stack) {
      AppLog.e('backup', '导出数据失败', error: error, stack: stack);
      return BackupResult.failure('导出失败：$error');
    }
  }

  // ───────────────────────── 导入 ─────────────────────────

  /// 解析并校验备份文本。成功返回 `null`，失败返回面向用户的错误文案。
  ///
  /// 抽成独立方法是为了让 UI 能"先校验、再弹确认框"——校验通过才知道
  /// 该在确认框里写"将覆盖 N 门课程"。
  static String? validate(String text) {
    final Object? decoded = _decode(text);
    if (decoded == null) return '文件内容不是合法的 JSON';
    if (decoded is! Map) return '文件结构不正确：顶层应为对象';

    final Object? format = decoded['format'];
    if (format != kBackupFormat) {
      return '这不是校园助手的备份文件';
    }
    final Object? version = decoded['formatVersion'];
    if (version is! int) return '备份文件缺少格式版本号';
    if (version > kBackupFormatVersion) {
      return '备份来自更新版本的 App（格式 v$version），请先升级 App';
    }
    final Object? boxes = decoded['boxes'];
    if (boxes is! Map) return '备份文件缺少数据区';
    return null;
  }

  /// 统计备份文件里各 Box 的条目数（用于确认框文案）。
  ///
  /// 解析失败 / 结构不对时返回空 Map，调用方按"0 条"处理即可。
  static Map<String, int> summarize(String text) {
    final Object? decoded = _decode(text);
    if (decoded is! Map) return <String, int>{};
    final Object? boxes = decoded['boxes'];
    if (boxes is! Map) return <String, int>{};
    final Map<String, int> result = <String, int>{};
    for (final String name in kBackupBoxNames) {
      final Object? entries = boxes[name];
      if (entries is Map) result[name] = entries.length;
    }
    return result;
  }

  /// 导入备份文本。
  ///
  /// 流程：校验 → 写回滚点 → 逐 Box 清空并写回 → 恢复插件文件。
  /// [createRollback] 为 `false` 时不写回滚点（测试用）。
  static Future<RestoreResult> import(
    String text, {
    bool createRollback = true,
  }) async {
    final String? invalid = validate(text);
    if (invalid != null) {
      AppLog.w('backup', '导入被拒绝：$invalid');
      return RestoreResult.failure(invalid);
    }

    final Map<String, dynamic> root = _decode(text)! as Map<String, dynamic>;
    final Map<String, dynamic> boxes = root['boxes'] as Map<String, dynamic>;

    File? rollback;
    if (createRollback) {
      rollback = await _writeRollbackPoint();
    }

    final Map<String, int> restored = <String, int>{};
    try {
      for (final String name in kBackupBoxNames) {
        final Box<String>? box = _boxOrNull(name);
        if (box == null) continue;
        final Object? raw = boxes[name];
        final Map<String, String> entries =
            raw is Map ? _stringMap(raw) : <String, String>{};
        await box.clear();
        if (entries.isNotEmpty) await box.putAll(entries);
        restored[name] = entries.length;
      }
    } catch (error, stack) {
      AppLog.e('backup', '导入数据失败', error: error, stack: stack);
      final String hint = rollback == null
          ? ''
          : '；导入前的数据已保存在 ${rollback.path}';
      return RestoreResult(
        ok: false,
        message: '导入失败：$error$hint',
        counts: restored,
        rollbackFile: rollback,
      );
    }

    final int pluginCount = await _restorePlugins(
      pluginFiles: _stringMap(root['pluginFiles']),
      manifests: _stringMap(root['pluginManifests']),
    );

    AppLog.action('data_import', <String, Object?>{
      'total': restored.values.fold<int>(0, (int a, int b) => a + b),
      'plugins': pluginCount,
      'rollback': rollback?.path,
    });
    return RestoreResult(
      ok: true,
      counts: restored,
      pluginCount: pluginCount,
      rollbackFile: rollback,
    );
  }

  /// 从文件导入。
  static Future<RestoreResult> importFromFile(File file) async {
    try {
      final String text = await file.readAsString();
      return await import(text);
    } catch (error, stack) {
      AppLog.e('backup', '读取备份文件失败', error: error, stack: stack);
      return RestoreResult.failure('读取文件失败：$error');
    }
  }

  /// 把插件 js 与 manifest 写回插件目录。
  ///
  /// 单个插件写失败只跳过它——不能让一个坏插件把已经写好的课表数据
  /// 连带判定为"导入失败"。
  static Future<int> _restorePlugins({
    required Map<String, String> pluginFiles,
    required Map<String, String> manifests,
  }) async {
    int count = 0;
    for (final MapEntry<String, String> entry in pluginFiles.entries) {
      try {
        await PluginStorageService.installPlugin(
          pluginId: entry.key,
          jsSource: entry.value,
          manifestJson: manifests[entry.key],
        );
        count++;
      } catch (error) {
        debugPrint('[DataBackup] 恢复插件 ${entry.key} 失败：$error');
        AppLog.w('backup', '恢复插件失败',
            <String, Object?>{'pluginId': entry.key, 'error': '$error'});
      }
    }
    return count;
  }

  // ───────────────────────── 清空 / 清缓存 ─────────────────────────

  /// 清空课表业务数据（见 [kClearableBoxNames]），返回清掉的条目总数。
  ///
  /// **不碰**设置、插件、皮肤。调用方清完后需要让各 Provider 重新载入。
  static Future<int> clearBusinessData() async {
    int total = 0;
    for (final String name in kClearableBoxNames) {
      final Box<String>? box = _boxOrNull(name);
      if (box == null) continue;
      total += box.length;
      try {
        await box.clear();
      } catch (error, stack) {
        AppLog.e('backup', '清空 Box 失败', error: error,
            stack: stack, data: <String, Object?>{'box': name});
      }
    }
    AppLog.action('data_clear', <String, Object?>{'entries': total});
    return total;
  }

  /// 清理缓存目录（保留 [kExportSubdirName]，见其注释）。
  ///
  /// 只删缓存目录下的内容：那里是 Flutter 的临时文件、图片缓存、
  /// 网络临时文件，删掉不影响任何已持久化的数据。
  ///
  /// [dirOverride] 仅供测试注入临时目录。
  static Future<ClearCacheResult> clearCache({Directory? dirOverride}) async {
    try {
      final Directory dir = dirOverride ?? await getTemporaryDirectory();
      if (!await dir.exists()) {
        return const ClearCacheResult(ok: true);
      }
      int freed = 0;
      await for (final FileSystemEntity entity in dir.list()) {
        final String name = _basename(entity.path);
        if (name == kExportSubdirName) continue;
        freed += await _sizeOf(entity);
        try {
          await entity.delete(recursive: true);
        } catch (error) {
          // 正在被占用的临时文件删不掉是正常的，少算它的体积即可。
          debugPrint('[DataBackup] 删除缓存项失败：${entity.path} → $error');
        }
      }
      AppLog.action('cache_clear', <String, Object?>{'freedBytes': freed});
      return ClearCacheResult(ok: true, freedBytes: freed);
    } catch (error, stack) {
      AppLog.e('backup', '清理缓存失败', error: error, stack: stack);
      return ClearCacheResult(ok: false, message: '清理失败：$error');
    }
  }

  // ───────────────────────── 内部工具 ─────────────────────────

  /// 取已打开的 Box；未初始化 / 打开失败返回 `null`（调用方跳过即可）。
  static Box<String>? _boxOrNull(String name) {
    try {
      if (!Hive.isBoxOpen(name)) return null;
      return Hive.box<String>(name);
    } catch (error) {
      debugPrint('[DataBackup] 取 Box "$name" 失败：$error');
      return null;
    }
  }

  static Future<File> _writeExportFile(
    String text, {
    Directory? dirOverride,
  }) async {
    final Directory base = dirOverride ?? await getTemporaryDirectory();
    final Directory dir =
        Directory('${base.path}${Platform.pathSeparator}$kExportSubdirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final String name = 'campus-backup-${now.year}${two(now.month)}'
        '${two(now.day)}-${two(now.hour)}${two(now.minute)}'
        '${two(now.second)}.json';
    final File file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(text, flush: true);
    return file;
  }

  /// 导入前把当前数据存一份到 `<appSupport>/backups/`。
  ///
  /// 任何失败都返回 `null` 而不是抛异常：回滚点是"额外的保险"，
  /// 它坏掉不该阻断导入本身。
  static Future<File?> _writeRollbackPoint() async {
    try {
      final Directory base = await getApplicationSupportDirectory();
      final Directory dir =
          Directory('${base.path}${Platform.pathSeparator}$kBackupSubdirName');
      if (!await dir.exists()) await dir.create(recursive: true);

      final String text = await buildBackupJson();
      final DateTime now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final File file = File(
        '${dir.path}${Platform.pathSeparator}pre-import-'
        '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.json',
      );
      await file.writeAsString(text, flush: true);
      await _pruneRollbackFiles(dir);
      return file;
    } catch (error) {
      debugPrint('[DataBackup] 写回滚点失败（继续导入）：$error');
      return null;
    }
  }

  /// 只保留最近 [kMaxRollbackFiles] 份回滚点。
  static Future<void> _pruneRollbackFiles(Directory dir) async {
    try {
      final List<File> files = <File>[];
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is File && _basename(entity.path).endsWith('.json')) {
          files.add(entity);
        }
      }
      if (files.length <= kMaxRollbackFiles) return;
      files.sort((File a, File b) => b.path.compareTo(a.path));
      for (final File stale in files.skip(kMaxRollbackFiles)) {
        try {
          await stale.delete();
        } catch (_) {
          // 删不掉就算了，下次再清。
        }
      }
    } catch (error) {
      debugPrint('[DataBackup] 清理旧回滚点失败：$error');
    }
  }

  static Future<String?> _readText(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (error) {
      debugPrint('[DataBackup] 读取文件失败：$path → $error');
      return null;
    }
  }

  static Object? _decode(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  static Map<String, int> _countsOf(String text) {
    final Object? decoded = _decode(text);
    if (decoded is! Map) return <String, int>{};
    final Object? counts = decoded['counts'];
    if (counts is! Map) return <String, int>{};
    final Map<String, int> result = <String, int>{};
    for (final String name in kBackupBoxNames) {
      final Object? value = counts[name];
      if (value is int) result[name] = value;
    }
    return result;
  }

  /// 把任意 Map 收敛成 `Map<String, String>`，非字符串值直接丢弃。
  ///
  /// 丢弃而不是 `toString()`：备份文件被手工改过时，`123` 变成 `"123"`
  /// 写回 Box 会变成一条"看起来像 JSON 但其实不是"的脏数据。
  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return <String, String>{};
    final Map<String, String> result = <String, String>{};
    for (final MapEntry<Object?, Object?> entry in raw.entries) {
      final String? value = _stringValue(entry.value);
      if (value != null) result['${entry.key}'] = value;
    }
    return result;
  }

  static String? _stringValue(Object? value) => value is String ? value : null;

  static Future<int> _sizeOf(FileSystemEntity entity) async {
    try {
      if (entity is File) return await entity.length();
      if (entity is Directory) {
        int total = 0;
        await for (final FileSystemEntity child in entity.list()) {
          total += await _sizeOf(child);
        }
        return total;
      }
    } catch (_) {
      // 统计失败按 0 算，不影响删除。
    }
    return 0;
  }

  static String _basename(String path) {
    final int index = path.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? path : path.substring(index + 1);
  }
}
