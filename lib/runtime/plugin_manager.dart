// Phase 3.3：多插件管理器（PluginManager）。
//
// 职责：管理"当前已加载的插件运行时句柄"——加载 / 卸载 / 查询 / 能力汇总。
// 它把 Phase 3.2b.1 的 PluginRuntime（只能加载**单个**插件）包成多插件管理。
//
// **本类不继承 ChangeNotifier**（无状态服务）：它只管资源生命周期，
// 通知 UI 是 PluginProvider 的职责。这样它也就能在没有 Flutter 依赖的场景下复用。
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/plugin_meta.dart';
import '../services/plugin_storage_service.dart';
import 'js_sandbox.dart';
import 'plugin_handle.dart';
import 'plugin_runtime.dart';

/// "从哪读插件的 JS"：路径或直接给源码，二者给其一。
typedef PluginSource = ({String? path, String? jsSource});

/// 把 [PluginMeta] 解析成实际可加载的来源。
///
/// **Phase 3.4 起改为异步**（原为同步 `PluginSource Function(PluginMeta)`）：
/// 解析默认要查"插件文件在不在"（`PluginStorageService.getPluginJsPath`），
/// 这本身就是异步 I/O。同步签名只能靠"必须先预热一个全局缓存、否则静默返回
/// null"来伪装，那是个很容易踩的坑（忘了预热就变成"插件莫名不可用"）。
/// 而 [PluginManager.load] 本来就是 `async`，await 解析器零额外成本。
///
/// 抽成可注入的函数是为了两件事：
/// 1. **测试**可以绕过文件系统，直接给 `jsSource`（否则必须往磁盘写 .js 文件）；
/// 2. 将来换安装位置或加内置插件时，只换解析器，本类不用改。
typedef PluginSourceResolver = Future<PluginSource> Function(PluginMeta meta);

/// 多插件管理器：`id → PluginHandle` 的映射 + 生命周期管理。
///
/// 生命周期：`load()` → 多次查询 → `unload()` / `disposeAll()`。
/// 每个插件在 [PluginRuntime] 里独占一个 `JsSandbox`（见 3.2b.1 说明）。
class PluginManager {
  PluginManager({
    PluginRuntime? runtime,
    PluginSourceResolver? sourceResolver,
  })  : _runtime = runtime ?? PluginRuntime(),
        _resolveSource = sourceResolver ?? defaultSourceResolver;

  /// 默认来源解析器：从**插件安装目录**取 `<id>.js`（Phase 3.4 起）。
  ///
  /// 路径由 `PluginStorageService` 按 `meta.id` 现算，不读 `meta.assetPath`：
  /// 安装路径是 id 的纯函数，存进 meta 既冗余、又会在应用容器路径变化后失效。
  ///
  /// 插件未安装（文件不存在）时两者都给 `null`，由 [load] 降级为"插件未安装"。
  static Future<PluginSource> defaultSourceResolver(PluginMeta meta) async {
    // id 非法（如含 `../`）时不抛异常，直接当作"没有可加载的文件"，
    // 让降级路径统一处理；非法 id 本身由 PluginStorageService 拒绝。
    if (!PluginStorageService.isValidPluginId(meta.id)) {
      debugPrint('[PluginManager] 插件 id 非法，无法定位文件：${meta.id}');
      return (path: null, jsSource: null);
    }
    final String? path = await PluginStorageService.getPluginJsPath(meta.id);
    return (path: path, jsSource: null);
  }

  final PluginRuntime _runtime;
  final PluginSourceResolver _resolveSource;

  /// 已加载插件的运行时映射（`meta.id` → handle）。
  ///
  /// **包含加载失败的降级 handle**（`isUsable == false`）——这样调用方
  /// 既能查到"这个插件尝试加载过"，也能读到失败原因；要重试请先 `unload`。
  final Map<String, PluginHandle> _handles = <String, PluginHandle>{};

  /// 各 handle 对应的 meta（用于能力汇总时补齐 `modules` 里的 capabilityId）。
  final Map<String, PluginMeta> _metas = <String, PluginMeta>{};

  bool _disposed = false;

  /// 已加载插件的运行时映射，返回不可变视图。
  Map<String, PluginHandle> get loadedHandles =>
      UnmodifiableMapView<String, PluginHandle>(_handles);

  /// 已成功加载（沙箱可用）的插件数量。
  int get loadedCount =>
      _handles.values.where((PluginHandle h) => h.isUsable).length;

  /// 全部 handle 数量（含加载失败的降级 handle）。
  int get handleCount => _handles.length;

  /// 加载一个插件。
  ///
  /// - **已经加载且可用** → 直接返回既有 handle（跳过，不重复建沙箱）
  /// - 既有 handle 是**降级**的（上次加载失败）→ 先销毁再重试
  /// - [jsSource] 优先于 [sourceResolver]（供测试 / 内联插件使用）
  ///
  /// **不抛异常**：任何失败都返回降级 handle 并 `debugPrint` 原因。
  Future<PluginHandle> load(PluginMeta meta, {String? jsSource}) async {
    if (_disposed) {
      return PluginHandle(
        status: JsSandboxStatus.unavailable,
        reason: '插件管理器已销毁',
      );
    }

    final PluginHandle? existing = _handles[meta.id];
    if (existing != null && existing.isUsable) {
      debugPrint('[PluginManager] 插件 ${meta.id} 已加载且可用，跳过');
      return existing;
    }
    if (existing != null) {
      // 上次失败的降级句柄：清掉再重试（它的沙箱可能已死）。
      await existing.dispose();
      _handles.remove(meta.id);
    }

    PluginSource source;
    if (jsSource != null) {
      source = (path: null, jsSource: jsSource);
    } else {
      try {
        source = await _resolveSource(meta);
      } catch (e) {
        // 解析器（默认走文件系统）可能因权限/插件异常失败，兜住并降级。
        debugPrint('[PluginManager] 解析插件 ${meta.id} 的来源失败：$e');
        source = (path: null, jsSource: null);
      }
    }

    // 没有可加载的来源：直接降级，不必白起一个沙箱。
    if (source.path == null && source.jsSource == null) {
      debugPrint('[PluginManager] 插件 ${meta.id} 没有可加载的文件');
      return _record(
        meta,
        PluginHandle(
          status: JsSandboxStatus.unavailable,
          reason: '插件 "${meta.id}" 未安装（在插件目录中找不到 '
              '$kPluginJsSuffix 文件），或插件 id 非法',
        ),
      );
    }

    PluginHandle handle;
    try {
      handle = await _runtime.loadPlugin(
        path: source.path,
        jsSource: source.jsSource,
      );
    } catch (e) {
      // PluginRuntime 自身不抛，但这里再兜一层，保证"加载失败不影响其他插件"。
      debugPrint('[PluginManager] 插件 ${meta.id} 加载抛异常：$e');
      handle = PluginHandle(
        status: JsSandboxStatus.unavailable,
        reason: '插件加载抛异常：$e',
      );
    }

    // 插件自报的 id 与安装记录的 id 不一致时给出提示（仍按安装 id 管理）。
    final String? declaredId = handle.manifest?.id;
    if (declaredId != null && declaredId.isNotEmpty && declaredId != meta.id) {
      debugPrint('[PluginManager] 注意：插件 ${meta.id} 自报 id 为 "$declaredId"，'
          '仍按安装 id 管理');
    }
    return _record(meta, handle);
  }

  /// 卸载一个插件（销毁沙箱并移出映射）。找不到该 id 时为空操作。
  Future<void> unload(String pluginId) async {
    final PluginHandle? handle = _handles.remove(pluginId);
    _metas.remove(pluginId);
    await handle?.dispose();
  }

  /// 获取某个插件的句柄（含加载失败的降级句柄）；不存在返回 `null`。
  PluginHandle? getHandle(String pluginId) => _handles[pluginId];

  /// 该插件是否已加载**且可用**。
  bool isLoaded(String pluginId) => _handles[pluginId]?.isUsable ?? false;

  /// 已加载插件（沙箱可用）声明的能力并集，已去重。
  ///
  /// 同时取两处来源，避免漏掉任何一种声明方式：
  /// - `handle.manifest.capabilities`（插件 JS / manifest 文件里声明的）
  /// - `meta.effectiveCapabilities`（`capabilities` ∪ 各 `modules` 的 capabilityId）
  ///
  /// **只统计沙箱可用的插件**——加载失败的插件不该让模块变成可用。
  Set<String> get allLoadedCapabilities {
    final Set<String> result = <String>{};
    for (final MapEntry<String, PluginHandle> entry in _handles.entries) {
      if (!entry.value.isUsable) continue;
      result.addAll(entry.value.manifest?.capabilities ?? const <String>[]);
      result.addAll(_metas[entry.key]?.effectiveCapabilities ?? const <String>{});
    }
    return Set<String>.unmodifiable(result);
  }

  /// 已加载插件里加载失败的原因（`meta.id` → 原因）。供 UI 展示。
  Map<String, String> get loadErrors {
    final Map<String, String> result = <String, String>{};
    for (final MapEntry<String, PluginHandle> entry in _handles.entries) {
      final PluginHandle handle = entry.value;
      if (handle.isUsable) continue;
      result[entry.key] = handle.reason ?? handle.status.name;
    }
    return Map<String, String>.unmodifiable(result);
  }

  /// 卸载全部并销毁内部运行时（App 退出 / 测试收尾用）。幂等。
  Future<void> disposeAll() async {
    if (_disposed) return;
    _disposed = true;
    final List<PluginHandle> handles = _handles.values.toList();
    _handles.clear();
    _metas.clear();
    for (final PluginHandle handle in handles) {
      await handle.dispose();
    }
    // 运行时由本类持有，一并销毁（其 dispose 幂等）。
    await _runtime.dispose();
  }

  /// 记入映射并返回同一个 handle。
  PluginHandle _record(PluginMeta meta, PluginHandle handle) {
    _handles[meta.id] = handle;
    _metas[meta.id] = meta;
    if (handle.isUsable) {
      debugPrint('[PluginManager] 插件 ${meta.id} 加载成功，'
          '入口函数 ${handle.entries}');
    } else {
      debugPrint('[PluginManager] 插件 ${meta.id} 降级为不可用'
          '（${handle.status.name}）：${handle.reason}');
    }
    return handle;
  }
}