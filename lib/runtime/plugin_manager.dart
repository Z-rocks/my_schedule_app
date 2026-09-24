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
import 'js_sandbox.dart';
import 'plugin_handle.dart';
import 'plugin_runtime.dart';

/// "从哪读插件的 JS"：路径或直接给源码，二者给其一。
typedef PluginSource = ({String? path, String? jsSource});

/// 把 [PluginMeta] 解析成实际可加载的来源。
///
/// 抽成可注入的函数是为了两件事：
/// 1. **测试**可以绕过文件系统，直接给 `jsSource`（否则必须往磁盘写 .js 文件）；
/// 2. Phase 3.4 接入 `path_provider` 后，只需换一个解析器，本类不用改。
typedef PluginSourceResolver = PluginSource Function(PluginMeta meta);

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

  /// 默认来源解析器：用 [PluginMeta.assetPath] 作为文件路径。
  ///
  /// `assetPath` 为空时两者都给 `null`，由 [load] 降级为"没有可加载的本地文件"
  /// （Phase 3.4 接入 `path_provider` 后才会真正有值）。
  static PluginSource defaultSourceResolver(PluginMeta meta) {
    final String path = meta.assetPath.trim();
    return (path: path.isEmpty ? null : path, jsSource: null);
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

    final PluginSource source = jsSource != null
        ? (path: null, jsSource: jsSource)
        : _resolveSource(meta);

    // 没有可加载的来源：直接降级，不必白起一个沙箱。
    if (source.path == null && source.jsSource == null) {
      debugPrint('[PluginManager] 插件 ${meta.id} 没有可加载的本地文件');
      return _record(
        meta,
        PluginHandle(
          status: JsSandboxStatus.unavailable,
          reason: '插件 "${meta.id}" 没有可加载的本地文件（assetPath 为空）；'
              '文件定位待 Phase 3.4 接入 path_provider',
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