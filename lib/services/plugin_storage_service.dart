// Phase 3.4：插件文件存储服务。
//
// 职责：管理插件在**应用私有目录**下的物理文件（安装 / 卸载 / 查询）。
// 这是"插件文件从哪来"的答案——3.2b.1 起的临时目录方案到此结束。
//
// 目录布局（`<appDocuments>` 由 path_provider 给出）：
// ```
// <appDocuments>/plugins/
//   <pluginId>.js               插件脚本（必需）
//   <pluginId>.manifest.json    元数据（可选）
// ```
// Android 上 `<appDocuments>` 是 `/data/user/0/<package>/app_flutter`，
// 因此插件目录是 `/data/user/0/<package>/app_flutter/plugins/`。
//
// **为什么不把安装路径存进 PluginMeta**：路径是 `pluginId` 的**纯函数**，
// 存下来既冗余又危险——iOS 的应用容器 UUID 每次 App 更新都会变，
// 存了绝对路径反而会在更新后失效。因此一律现算（[getPluginJsPath]）。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../runtime/plugin_manifest.dart' show kPluginManifestSuffix;

/// 插件文件所在的子目录名（相对应用私有文档目录）。
const String kPluginsSubdirName = 'plugins';

/// 插件 JS 文件的扩展名。
const String kPluginJsSuffix = '.js';

/// 插件 id 允许的字符：**只允许字母、数字、下划线、横线**。
///
/// 这是**路径安全**的关键：id 会被直接拼进文件名，若允许 `/`、`\`、`.`，
/// 攻击者可用 `../../` 之类做路径穿越，把文件写到插件目录之外。
/// 因此点号也在禁止之列（`..` 正是穿越的核心）。
final RegExp kPluginIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// 插件 id 的最大长度（防止生成超长文件名）。
const int kMaxPluginIdLength = 64;

/// 插件文件存储服务（纯静态类）。
///
/// 设计约定：
/// - **懒加载**：首次调用才向 path_provider 要目录并缓存，因此
///   `main.dart` 无需预热；path_provider 不可用时也只影响插件功能，不影响启动。
/// - **可注入根目录**：测试用 [setRootDirForTesting] 指向临时目录，
///   避免依赖平台插件（与 `StorageService.init({String? path})` 的思路一致）。
/// - **写文件用"临时文件 + 重命名"**：避免写到一半被中断时留下半个文件，
///   把原本能用的插件覆盖成坏文件。
/// - 查询类方法对非法 id 返回"找不到"，命令类方法（安装/卸载）抛
///   [ArgumentError]——非法 id 是调用方的编程错误，不该静默成功。
class PluginStorageService {
  /// 纯静态工具类，禁止实例化。
  PluginStorageService._();

  /// 测试注入的根目录（`null` 表示走 path_provider）。
  static String? _rootOverride;

  /// 已解析的插件目录缓存。
  static Directory? _cachedDir;

  /// 插件 id 是否合法（非空、长度合规、只含字母数字下划线横线）。
  static bool isValidPluginId(String pluginId) {
    if (pluginId.isEmpty || pluginId.length > kMaxPluginIdLength) return false;
    return kPluginIdPattern.hasMatch(pluginId);
  }

  /// 取插件存储根目录（不存在则创建）。
  ///
  /// 结果会缓存；重复调用不会反复访问平台通道。
  static Future<Directory> getPluginsDir() async {
    final Directory? cached = _cachedDir;
    if (cached != null) return cached;

    final String base = _rootOverride ??
        (await getApplicationDocumentsDirectory()).path;
    final Directory dir = Directory('$base${Platform.pathSeparator}$kPluginsSubdirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDir = dir;
    return dir;
  }

  /// 安装插件：把 JS 源码（与可选 manifest）写入永久目录，返回 JS 文件路径。
  ///
  /// **重复安装会整体覆盖**：`manifestJson` 为 `null` 时会**删掉旧的
  /// `.manifest.json`**，避免上次的元数据残留、让加载器读到过期声明。
  ///
  /// [pluginId] 非法抛 [ArgumentError]；I/O 失败抛 [FileSystemException]（已记日志）。
  static Future<String> installPlugin({
    required String pluginId,
    required String jsSource,
    String? manifestJson,
  }) async {
    _requireValidId(pluginId);
    final Directory dir = await getPluginsDir();

    final String jsPath = _jsPathIn(dir, pluginId);
    await _writeAtomically(File(jsPath), jsSource);

    final File manifestFile = File(_manifestPathIn(dir, pluginId));
    if (manifestJson != null && manifestJson.trim().isNotEmpty) {
      await _writeAtomically(manifestFile, manifestJson);
    } else if (await manifestFile.exists()) {
      // 本次没带 manifest → 清掉旧的，避免残留过期元数据。
      try {
        await manifestFile.delete();
      } catch (e) {
        debugPrint('[PluginStorageService] 删除旧 manifest 失败：$e');
      }
    }
    return jsPath;
  }

  /// 从 assets 安装插件（用于**随 App 打包**的内置插件）。
  ///
  /// 与 [installPlugin] 的区别只在"源码从哪来"：这里用 `rootBundle` 读
  /// Flutter asset（路径形如 `assets/plugins/chaoxing.js`），读出内容后
  /// 走同一条安装路径落盘——因为**运行时只能从文件系统加载**
  /// （`PluginManager.defaultSourceResolver` 取的是 `<id>.js` 文件路径），
  /// 而 `rootBundle` 只能异步读、拿不到文件路径。
  ///
  /// asset 不存在或读取失败时抛 [FlutterError]（已记日志），
  /// 由调用方决定是否降级——不要静默吞掉，否则用户会以为"装了但没效果"。
  static Future<void> installFromAssets({
    required String pluginId,
    required String assetPath,
  }) async {
    _requireValidId(pluginId);
    String source;
    try {
      source = await rootBundle.loadString(assetPath);
    } catch (e) {
      debugPrint('[PluginStorageService] 读取 asset 失败：$assetPath → $e');
      throw FlutterError('读取内置插件 asset 失败：$assetPath');
    }
    if (source.trim().isEmpty) {
      debugPrint('[PluginStorageService] asset 内容为空：$assetPath');
      throw FlutterError('内置插件 asset 内容为空：$assetPath');
    }
    await installPlugin(pluginId: pluginId, jsSource: source);
  }

  /// 卸载插件：删除 `<id>.js` 与 `<id>.manifest.json`。文件不存在视为已卸载（幂等）。
  static Future<void> uninstallPlugin(String pluginId) async {
    _requireValidId(pluginId);
    final Directory dir = await getPluginsDir();
    await _deleteIfExists(File(_jsPathIn(dir, pluginId)));
    await _deleteIfExists(File(_manifestPathIn(dir, pluginId)));
  }

  /// 插件是否已安装（即 `<id>.js` 存在）。非法 id 返回 `false`。
  static Future<bool> isInstalled(String pluginId) async {
    if (!isValidPluginId(pluginId)) return false;
    try {
      final Directory dir = await getPluginsDir();
      return await File(_jsPathIn(dir, pluginId)).exists();
    } catch (e) {
      debugPrint('[PluginStorageService] isInstalled 失败：$e');
      return false;
    }
  }

  /// 列出所有已安装插件 id（扫描目录里的 `*.js`，按 id 升序）。
  ///
  /// 临时文件（`*.js.tmp`）与 manifest（`*.json`）都不会被计入。
  static Future<List<String>> listInstalled() async {
    final List<String> ids = <String>[];
    try {
      final Directory dir = await getPluginsDir();
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is! File) continue;
        final String name = _basename(entity.path);
        if (!name.endsWith(kPluginJsSuffix)) continue;
        final String id = name.substring(0, name.length - kPluginJsSuffix.length);
        if (id.isNotEmpty) ids.add(id);
      }
    } catch (e) {
      debugPrint('[PluginStorageService] listInstalled 失败：$e');
      return const <String>[];
    }
    ids.sort();
    return ids;
  }

  /// 取插件 JS 文件的**绝对路径**；未安装（文件不存在）或 id 非法返回 `null`。
  ///
  /// 每次现算而不缓存路径：见文件头"为什么不把安装路径存进 PluginMeta"。
  static Future<String?> getPluginJsPath(String pluginId) async {
    if (!isValidPluginId(pluginId)) return null;
    try {
      final Directory dir = await getPluginsDir();
      final File file = File(_jsPathIn(dir, pluginId));
      return await file.exists() ? file.path : null;
    } catch (e) {
      debugPrint('[PluginStorageService] getPluginJsPath 失败：$e');
      return null;
    }
  }

  /// 取插件 manifest 文件的绝对路径；不存在或 id 非法返回 `null`。
  static Future<String?> getPluginManifestPath(String pluginId) async {
    if (!isValidPluginId(pluginId)) return null;
    try {
      final Directory dir = await getPluginsDir();
      final File file = File(_manifestPathIn(dir, pluginId));
      return await file.exists() ? file.path : null;
    } catch (e) {
      debugPrint('[PluginStorageService] getPluginManifestPath 失败：$e');
      return null;
    }
  }

  /// 清除所有插件文件（测试用）。目录本身保留。
  static Future<void> clearAll() async {
    try {
      final Directory dir = await getPluginsDir();
      await for (final FileSystemEntity entity in dir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          debugPrint('[PluginStorageService] 删除 ${entity.path} 失败：$e');
        }
      }
    } catch (e) {
      debugPrint('[PluginStorageService] clearAll 失败：$e');
    }
  }

  /// 测试用：把根目录指向指定路径（传 `null` 恢复走 path_provider）。
  ///
  /// 会清掉已缓存的目录，保证下次调用按新根目录解析。
  @visibleForTesting
  static void setRootDirForTesting(String? rootDir) {
    _rootOverride = rootDir;
    _cachedDir = null;
  }

  // ─────────────────────────── 内部 ───────────────────────────

  /// 校验 id，非法直接抛（命令类方法的边界检查）。
  static void _requireValidId(String pluginId) {
    if (!isValidPluginId(pluginId)) {
      throw ArgumentError.value(
        pluginId,
        'pluginId',
        '非法插件 id：只允许字母、数字、下划线、横线，'
            '且长度 1-$kMaxPluginIdLength（防止路径穿越）',
      );
    }
  }

  /// 目录内的 JS 文件路径。
  static String _jsPathIn(Directory dir, String pluginId) =>
      '${dir.path}${Platform.pathSeparator}$pluginId$kPluginJsSuffix';

  /// 目录内的 manifest 文件路径（后缀复用 `plugin_manifest.dart` 的常量，避免漂移）。
  static String _manifestPathIn(Directory dir, String pluginId) =>
      '${dir.path}${Platform.pathSeparator}$pluginId$kPluginManifestSuffix';

  /// 原子写：先写 `<file>.tmp` 再重命名覆盖目标，避免留下半个文件。
  static Future<void> _writeAtomically(File target, String content) async {
    final File temp = File('${target.path}.tmp');
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(target.path);
    } catch (e) {
      debugPrint('[PluginStorageService] 写入 ${target.path} 失败：$e');
      // 清理可能残留的临时文件后向上抛，让调用方知道安装没成功。
      await _deleteIfExists(temp);
      rethrow;
    }
  }

  /// 删除文件（不存在则忽略），失败只记日志。
  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[PluginStorageService] 删除 ${file.path} 失败：$e');
    }
  }

  /// 取路径最后一段（不依赖 `path` 包，避免多加依赖）。
  static String _basename(String path) {
    final int index = path.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? path : path.substring(index + 1);
  }
}