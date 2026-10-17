// 插件状态：管理已安装插件列表，并汇总启用插件声明的能力
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/plugin_catalog.dart';
import '../models/plugin_meta.dart';
import '../runtime/js_sandbox.dart';
import '../runtime/plugin_context.dart' show PluginNotifyHandler;
import '../runtime/plugin_handle.dart';
import '../runtime/plugin_manager.dart';
import '../runtime/plugin_runtime.dart';
import '../services/plugin_storage_service.dart';
import '../services/storage_service.dart';

// 插件 id / asset 路径常量已迁到 `models/plugin_catalog.dart`（市场目录与
// 安装逻辑共用同一份）。这里 re-export，保持既有 `import plugin_provider.dart`
// 的调用方仍能拿到这些常量。
export '../models/plugin_catalog.dart'
    show
        kChaoxingPluginAssetPath,
        kChaoxingPluginId,
        kNcstPluginAssetPath,
        kNcstPluginId;

/// 已安装插件状态。
///
/// **Phase 3.3 起接线 PluginRuntime**：本类持有 [PluginManager]（组合关系），
/// 由它负责多插件的加载 / 卸载 / 能力汇总；本类负责状态通知与持久化。
/// 本类**不直接引用** ModuleProvider，能力集合仍由 Phase 1.4 的
/// `ChangeNotifierProxyProvider` 推给 `ModuleProvider.updateCapabilities`。
///
/// 持久化：插件列表存在 `plugins` Box，**一个插件 id 一个 key**，值为
/// `PluginMeta` 的 JSON（与 `courses` Box 的做法一致）。
class PluginProvider extends ChangeNotifier {
  PluginProvider({
    List<PluginMeta>? plugins,
    PluginManager? manager,
    PluginNotifyHandler? onNotify,
  })  : _manager = manager ??
            PluginManager(
              runtime: onNotify == null
                  ? null
                  : PluginRuntime(onNotify: onNotify),
            ),
        _onNotify = onNotify {
    if (plugins != null) _plugins.addAll(plugins);
  }

  /// 多插件运行时管理器。可注入以便测试（沿用 `ThemeProvider({ThemeEngine?})` 的先例）。
  final PluginManager _manager;

  /// `ctx.notify.schedule` 的落地回调（Phase 7）。
  ///
  /// 传 `null` 时插件通知退化为只记日志（测试 / 无 UI 场景）。
  /// `main.dart` 负责把它接到 `MessageProvider` 上——**Provider 之间不互相引用**
  /// （CONTEXT 4.5），所以用回调注入而不是让本类持有 `MessageProvider`。
  final PluginNotifyHandler? _onNotify;

  /// 当前的通知落地回调（供 `main.dart` 在 `MessageProvider` 就绪后补挂）。
  PluginNotifyHandler? get onNotify => _onNotify;

  final List<PluginMeta> _plugins = <PluginMeta>[];

  /// 加载失败原因（`meta.id` → 原因）。**只存内存，不落盘**：
  /// 它是运行时瞬时状态，持久化会在重启后显示过期错误。
  final Map<String, String> _loadErrors = <String, String>{};

  bool _disposed = false;
  bool _isLoaded = false;

  /// 是否已尝试从存储载入过（UI 可区分"没有插件"与"尚未加载"）。
  bool get isLoaded => _isLoaded;

  /// 全部已安装插件（含未启用的），返回不可变视图。
  List<PluginMeta> get plugins => UnmodifiableListView<PluginMeta>(_plugins);

  /// 已启用的插件。
  List<PluginMeta> get enabledPlugins => UnmodifiableListView<PluginMeta>(
        _plugins.where((PluginMeta p) => p.enabled).toList(),
      );

  /// 全部已启用插件声明的能力 ID 并集。
  ///
  /// 取 [PluginMeta.effectiveCapabilities]（即 `capabilities` 与各 `modules`
  /// 的 `capabilityId` 的并集），两种声明方式都支持：
  /// 插件既可以只写扁平的 `capabilities: ['exam']`，
  /// 也可以只贡献带 UI 元数据的 `modules`，都不会漏掉能力。
  ///
  /// > 注意：本 getter 只看"**启用**"，不看"是否加载成功"（Phase 1 起的行为，
  /// > 未改动）。要拿"真正加载成功的插件能力"，用 [loadedCapabilities]。
  Set<String> get allCapabilities {
    final Set<String> result = <String>{};
    for (final PluginMeta plugin in _plugins) {
      if (!plugin.enabled) continue;
      result.addAll(plugin.effectiveCapabilities);
    }
    return Set<String>.unmodifiable(result);
  }

  /// **已成功加载**（沙箱可用）插件的能力并集，转发给 [PluginManager]。
  ///
  /// 与 [allCapabilities] 的区别：后者按"已启用"算，本 getter 按"确实加载成功"算。
  Set<String> get loadedCapabilities => _manager.allLoadedCapabilities;

  /// 已加载插件的运行时映射（`id` → handle，含加载失败的降级 handle）。
  Map<String, PluginHandle> get loadedHandles => _manager.loadedHandles;

  /// 已成功加载的插件数量。
  int get loadedCount => _manager.loadedCount;

  /// 加载失败原因映射（`id` → 原因），不可变视图。
  Map<String, String> get loadErrors =>
      UnmodifiableMapView<String, String>(_loadErrors);

  /// 某个插件的加载失败原因；没有则返回 `null`。
  String? loadErrorOf(String id) => _loadErrors[id];

  /// 已启用插件数量。
  int get enabledCount => _plugins.where((PluginMeta p) => p.enabled).length;

  /// 有可用更新的插件数量。
  int get updatableCount =>
      _plugins.where((PluginMeta p) => p.hasUpdate).length;

  /// 按 [id] 查找插件；不存在返回 `null`。
  PluginMeta? getById(String id) {
    for (final PluginMeta plugin in _plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  /// 取某个插件的运行时句柄；不存在返回 `null`。
  PluginHandle? getHandle(String id) => _manager.getHandle(id);

  /// 找出第一个**已启用且声明了** [capability] 的插件；没有则返回 `null`。
  ///
  /// "已启用"与"运行时可用"是两件事：本方法**不看**加载结果，
  /// 因此适合用来给出准确的错误提示（"插件启用了但没加载成功"）。
  /// 要"确实能调用"的插件请用 [firstUsableWithCapability]。
  PluginMeta? firstEnabledWithCapability(String capability) {
    for (final PluginMeta plugin in _plugins) {
      if (!plugin.enabled) continue;
      if (plugin.effectiveCapabilities.contains(capability)) return plugin;
    }
    return null;
  }

  /// 找出第一个**已启用、运行时可用、且声明了** [capability] 的插件。
  ///
  /// Phase 8 新增：作业 / 考试页需要"从哪个插件抓数据"，
  /// 而能力集合（[allCapabilities]）只回答"有没有这种能力"、不回答"是谁提供的"。
  ///
  /// 多个插件声明同一能力时取**安装顺序最靠前**的那个（列表顺序即安装顺序），
  /// 保证行为可预期；不按"最新安装"取是为了让用户重装插件不会静默换源。
  PluginMeta? firstUsableWithCapability(String capability) {
    for (final PluginMeta plugin in _plugins) {
      if (!plugin.enabled) continue;
      if (!plugin.effectiveCapabilities.contains(capability)) continue;
      final PluginHandle? handle = getHandle(plugin.id);
      if (handle != null && handle.isUsable) return plugin;
    }
    return null;
  }

  // ─────────────────────────── 存储 ───────────────────────────

  /// 从 `plugins` Box 恢复插件列表。
  ///
  /// 边界情况全部不崩溃：没存过 → 空列表；坏 JSON / 非对象 → 跳过该条；
  /// 存储未初始化（`StateError`）→ 保持现状。**会替换内存列表**（不是累加）。
  Future<void> loadFromStorage() async {
    final List<PluginMeta> loaded = <PluginMeta>[];
    try {
      final Map<dynamic, dynamic> raw = StorageService.pluginsBox.toMap();
      for (final Object? value in raw.values) {
        if (value is! String) continue;
        final PluginMeta? meta = _decodeMeta(value);
        if (meta != null) loaded.add(meta);
      }
      _plugins
        ..clear()
        ..addAll(loaded);
    } catch (e) {
      debugPrint('PluginProvider.loadFromStorage 失败（按"没有插件"处理）: $e');
    } finally {
      _isLoaded = true;
    }
    _notify();
  }

  /// 把内存里的插件列表整体写回存储（覆盖式）。
  Future<void> saveToStorage() async {
    try {
      final box = StorageService.pluginsBox;
      await box.clear();
      for (final PluginMeta plugin in _plugins) {
        await box.put(plugin.id, jsonEncode(plugin.toJson()));
      }
    } catch (e) {
      debugPrint('PluginProvider.saveToStorage 失败: $e');
    }
  }

  /// 清空内存与存储（测试 / 重置用）。
  Future<void> clearAll() async {
    _plugins.clear();
    _loadErrors.clear();
    await _manager.disposeAll();
    try {
      await StorageService.pluginsBox.clear();
    } catch (e) {
      debugPrint('PluginProvider.clearAll 清存储失败: $e');
    }
    _notify();
  }

  // ─────────────────────── 插件运行时接线 ───────────────────────

  /// App 启动时调用：遍历所有 `enabled` 的插件，逐个加载。
  ///
  /// **单个插件加载失败不影响其他插件**（每个都单独 try-catch），
  /// 失败原因记入 [loadErrors]；其 `enabled` 状态在存储里**保留 true**，
  /// 用户重启后可重试。
  Future<void> loadAllEnabledPlugins() async {
    for (final PluginMeta meta in enabledPlugins) {
      await _loadOne(meta);
    }
    _notify();
  }

  /// 手动加载单个插件。
  ///
  /// [jsSource] 可绕过文件系统直接给源码（测试 / 内联插件用）。
  /// 找不到该 id 时返回一个降级 handle，不抛异常。
  Future<PluginHandle> loadPlugin(String id, {String? jsSource}) async {
    final PluginMeta? meta = getById(id);
    if (meta == null) {
      debugPrint('[PluginProvider] loadPlugin：找不到插件 $id');
      return PluginHandle(
        status: JsSandboxStatus.unavailable,
        reason: '找不到插件 $id',
      );
    }
    final PluginHandle handle = await _loadOne(meta, jsSource: jsSource);
    _notify();
    return handle;
  }

  /// 手动卸载单个插件（只销毁运行时，不改 `enabled` 状态）。
  Future<void> unloadPlugin(String id) async {
    await _manager.unload(id);
    _loadErrors.remove(id);
    _notify();
  }

  /// 启用 / 停用插件。找不到该 id 时为空操作。
  ///
  /// 流程：改内存并**立即通知**（UI 不等异步）→ 落盘 `enabled` →
  /// 启用则加载运行时、停用则卸载运行时 → 再通知一次。
  ///
  /// **无论加载成功失败都会落盘 `enabled`**（用户重启后可重试加载）。
  Future<void> togglePlugin(String id, bool enabled) async {
    final int index = _indexOf(id);
    if (index < 0) return;
    if (_plugins[index].enabled == enabled) return;

    _plugins[index] = _plugins[index].copyWith(enabled: enabled);
    // 先通知，让 UI 立刻反映开关状态，不等加载结果。
    _notify();

    await _persistOne(_plugins[index]);

    if (enabled) {
      await _loadOne(_plugins[index]);
    } else {
      await _manager.unload(id);
      _loadErrors.remove(id);
    }
    _notify();
  }

  // ─────────────────────── 内置插件安装 ───────────────────────

  /// 安装**内置**插件（从 assets）并自动启用。
  ///
  /// 流程：`installFromAssets` 落盘 → `addPlugin`（先以 `enabled: false` 落盘）→
  /// `togglePlugin(id, true)` 启用（复用同一条启停链路，避免重写"落盘 + 加载运行时"）。
  ///
  /// 任何一步失败都不抛异常：只 `debugPrint` + 返回 `false`，让 UI 用 SnackBar 提示。
  /// 重复调用安全（`addPlugin` 同 id 替换、`installPlugin` 覆盖文件）。
  ///
  /// [fallbackName] / [fallbackCapabilities]：插件声明读不到时的兜底
  /// （正常情况下加载成功后会用插件自报的 name/capabilities 补齐）。
  Future<bool> installBuiltinPlugin({
    required String pluginId,
    required String assetPath,
    required String fallbackName,
    List<String> fallbackCapabilities = const <String>[],
    String author = 'MySchedule',
    String description = '',
  }) async {
    try {
      await PluginStorageService.installFromAssets(
        pluginId: pluginId,
        assetPath: assetPath,
      );
    } catch (e) {
      debugPrint('[PluginProvider] 安装内置插件 $pluginId 失败：$e');
      return false;
    }

    final PluginMeta existing = getById(pluginId) ??
        PluginMeta(
          id: pluginId,
          name: fallbackName,
          version: '1.0.0',
          author: author,
          description: description,
          capabilities: fallbackCapabilities,
          source: 'builtin',
          // 显式声明可卸载：来源虽是 builtin（随 App 打包），但用户应当能卸掉。
          // 写成显式而非依赖默认值，是为了防止将来有人改默认值时
          // 静默把内置插件变成"不可卸载"（Phase 3.5.1 的教训）。
          isRemovable: true,
          enabled: false,
          installedAt: DateTime.now(),
        );
    await addPlugin(existing.copyWith(enabled: false));
    await togglePlugin(pluginId, true);
    debugPrint('[PluginProvider] 内置插件已安装并启用：$pluginId');
    return true;
  }

  /// 从**市场目录**安装一个插件（创意工坊 → 插件市场的统一入口）。
  ///
  /// 目录条目里的 name / description / capabilities 直接作为 fallback 传给
  /// [installBuiltinPlugin]；安装成功后运行时用插件自述补齐能力，
  /// 所以市场展示的标签与安装后的实际能力不会打架。
  ///
  /// 已安装时是**幂等**的：会重新覆盖插件文件并重新启用，不会产生第二份记录。
  Future<bool> installCatalogPlugin(PluginCatalogEntry entry) {
    return installBuiltinPlugin(
      pluginId: entry.id,
      assetPath: entry.assetPath,
      fallbackName: entry.name,
      fallbackCapabilities: entry.capabilities,
      description: entry.description,
      author: entry.author,
    );
  }

  /// 安装内置的 **NCST 教务插件**。
  ///
  /// 等价于 `installCatalogPlugin(pluginCatalogEntry(kNcstPluginId)!)`，
  /// 保留这个具名方法是为了让调用方（以及将来的快捷入口）不必自己查目录。
  /// 装完即为"已启用"，用户接着在插件详情页点「登录」→「立即同步」。
  /// 真实 URL 只在 `assets/plugins/ncst-jwxt.js` 里，内核不硬编码（CONTEXT 3.1）。
  Future<bool> installNcstPlugin() {
    final PluginCatalogEntry? entry = pluginCatalogEntry(kNcstPluginId);
    if (entry == null) {
      debugPrint('[PluginProvider] 目录里找不到 $kNcstPluginId');
      return Future<bool>.value(false);
    }
    return installCatalogPlugin(entry);
  }

  /// 安装内置的**学习通（超星）插件**。
  ///
  /// 装完即为"已启用"。用户在插件详情页点「登录」完成学习通登录后，
  /// 到作业页 / 考试页点右上角「抓取」→ 勾选课程 → 抓取。
  ///
  /// 声明 `homework` + `exam` 两个能力，所以装上之后导航栏里的作业、
  /// 考试两个模块会自动可用（能力 → 模块可用性由 `ModuleProvider` 联动）。
  /// 所有学习通 URL 只在 `assets/plugins/chaoxing.js` 里（CONTEXT 3.1）。
  Future<bool> installChaoxingPlugin() {
    final PluginCatalogEntry? entry = pluginCatalogEntry(kChaoxingPluginId);
    if (entry == null) {
      debugPrint('[PluginProvider] 目录里找不到 $kChaoxingPluginId');
      return Future<bool>.value(false);
    }
    return installCatalogPlugin(entry);
  }

  // ─────────────────────────── 增删 ───────────────────────────

  /// 新增插件（同 id 已存在则替换），并落盘。
  ///
  /// > Phase 3.3 由 `void` 改为 `Future<void>`（原签名在 lib/ 里**没有调用方**，
  /// > 插件管理页仍是占位页），以便调用方 `await` 落盘完成。
  Future<void> addPlugin(PluginMeta p) async {
    final int index = _indexOf(p.id);
    if (index >= 0) {
      _plugins[index] = p;
    } else {
      _plugins.add(p);
    }
    await _persistOne(p);
    _notify();
  }

  /// 卸载插件：**销毁运行时 + 删除磁盘上的插件文件 + 从列表与存储移除**。
  ///
  /// **`isRemovable == false` 的插件不可卸载**，调用为空操作（留给硬编码的
  /// 系统级插件）。注意这与"来源是 builtin"**不是一回事**：
  /// 从 assets 安装的示例插件来源也是 `builtin`，但它可以卸载（Phase 3.5.1 修正）。
  Future<void> removePlugin(String id) async {
    final int index = _indexOf(id);
    if (index < 0) return;
    if (!_plugins[index].isRemovable) {
      debugPrint('[PluginProvider] 插件 $id 标记为不可卸载，忽略卸载请求');
      return;
    }
    _plugins.removeAt(index);
    _loadErrors.remove(id);
    // 先通知：列表已经变了，UI 立刻反映，不等文件 I/O 与沙箱销毁。
    // （与 togglePlugin 同一思路：先更新可观察状态，再做异步收尾。）
    _notify();

    await _manager.unload(id);

    // 删除磁盘上的 `<id>.js` 与 `<id>.manifest.json`。
    //
    // Phase 3.5.1 补上这一步：此前只删了元数据，**插件文件会留在磁盘上**
    // （而确认框早已声称"插件文件与运行时都会被移除"，属于文案与实现不符）。
    // 失败只记日志、不抛：元数据已移除，遗留文件不影响功能（下次安装会覆盖它）。
    try {
      await PluginStorageService.uninstallPlugin(id);
    } catch (e) {
      debugPrint('[PluginProvider] 删除插件 $id 的文件失败（元数据已移除）：$e');
    }

    await _persistRemove(id);
  }

  /// 清空插件列表（**仅内存**，测试 / 重置用；要连存储一起清用 [clearAll]）。
  void clear() {
    if (_plugins.isEmpty) return;
    _plugins.clear();
    _loadErrors.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    // 同步的 dispose 里没法 await，这里 fire-and-forget 释放所有沙箱。
    unawaited(
      _manager.disposeAll().catchError((Object e) {
        debugPrint('PluginProvider.dispose 释放插件运行时失败: $e');
      }),
    );
    super.dispose();
  }

  // ─────────────────────────── 内部 ───────────────────────────

  /// 加载单个插件并记录结果（成功则回写 meta 能力，失败则记错误）。不抛异常。
  Future<PluginHandle> _loadOne(PluginMeta meta, {String? jsSource}) async {
    PluginHandle handle;
    try {
      handle = await _manager.load(meta, jsSource: jsSource);
    } catch (e) {
      // 双保险：manager 已兜住，这里保证"一个插件失败不影响其他插件"。
      debugPrint('[PluginProvider] 插件 ${meta.id} 加载异常：$e');
      _loadErrors[meta.id] = '$e';
      return PluginHandle(
        status: JsSandboxStatus.unavailable,
        reason: '插件加载异常：$e',
      );
    }

    if (handle.isUsable) {
      _loadErrors.remove(meta.id);
      await _applyLoadedManifest(meta, handle);
    } else {
      _loadErrors[meta.id] = handle.reason ?? handle.status.name;
    }
    return handle;
  }

  /// 加载成功后用插件**自报的能力**补齐 meta（`capabilities` 取并集，不覆盖）。
  ///
  /// 为什么取并集而不是直接替换：`PluginMeta.modules` 里的 `capabilityId`
  /// 不在 `PluginManifest.capabilities` 里，替换会丢掉模块声明的能力。
  /// 只在真的变化时才写盘，避免每次启动都产生一次无意义写入。
  Future<void> _applyLoadedManifest(PluginMeta meta, PluginHandle handle) async {
    final List<String> declared = handle.manifest?.capabilities ?? const <String>[];
    if (declared.isEmpty) return;

    final Set<String> merged = <String>{...meta.capabilities, ...declared};
    if (merged.length == meta.capabilities.length) return;

    final int index = _indexOf(meta.id);
    if (index < 0) return;
    final PluginMeta updated =
        _plugins[index].copyWith(capabilities: merged.toList(growable: false));
    _plugins[index] = updated;
    await _persistOne(updated);
  }

  /// 写单个插件到存储；失败只记日志。
  Future<void> _persistOne(PluginMeta meta) async {
    try {
      await StorageService.pluginsBox.put(meta.id, jsonEncode(meta.toJson()));
    } catch (e) {
      debugPrint('PluginProvider 落盘插件 ${meta.id} 失败: $e');
    }
  }

  /// 从存储删除单个插件；失败只记日志。
  Future<void> _persistRemove(String id) async {
    try {
      await StorageService.pluginsBox.delete(id);
    } catch (e) {
      debugPrint('PluginProvider 删除插件 $id 的存储失败: $e');
    }
  }

  /// 解析存储里的一条插件 JSON；坏数据返回 `null`。
  static PluginMeta? _decodeMeta(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final PluginMeta meta = PluginMeta.fromJson(decoded);
      // id 是契约键，缺了就没法管理，视为坏数据。
      return meta.id.isEmpty ? null : meta;
    } catch (e) {
      debugPrint('PluginProvider 解析插件存储失败: $e');
      return null;
    }
  }

  /// 已释放则不再通知，避免异步回调触发 `ChangeNotifier` 的 assert。
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  int _indexOf(String id) {
    for (int i = 0; i < _plugins.length; i++) {
      if (_plugins[i].id == id) return i;
    }
    return -1;
  }
}