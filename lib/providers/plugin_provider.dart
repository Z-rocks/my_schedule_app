// 插件状态：管理已安装插件列表，并汇总启用插件声明的能力
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/plugin_meta.dart';
import '../runtime/js_sandbox.dart';
import '../runtime/plugin_handle.dart';
import '../runtime/plugin_manager.dart';
import '../services/storage_service.dart';

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
  }) : _manager = manager ?? PluginManager() {
    if (plugins != null) _plugins.addAll(plugins);
  }

  /// 多插件运行时管理器。可注入以便测试（沿用 `ThemeProvider({ThemeEngine?})` 的先例）。
  final PluginManager _manager;

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

  /// 卸载插件（从列表移除并删存储）。
  ///
  /// 内置插件（[PluginMeta.isBuiltIn]）不可卸载，调用为空操作。
  /// 会一并销毁其运行时沙箱。
  Future<void> removePlugin(String id) async {
    final int index = _indexOf(id);
    if (index < 0) return;
    if (_plugins[index].isBuiltIn) return;
    _plugins.removeAt(index);
    await _manager.unload(id);
    _loadErrors.remove(id);
    await _persistRemove(id);
    _notify();
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