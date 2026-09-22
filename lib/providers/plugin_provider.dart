// 插件状态：管理已安装插件列表，并汇总启用插件声明的能力
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/plugin_meta.dart';

/// 已安装插件状态。
///
/// **Phase 1 为空列表**：只提供接口，真实加载在 Phase 3（插件运行时）接入。
///
/// [allCapabilities] 会被 Phase 1.4 通过 `ChangeNotifierProxyProvider`
/// 推送给 `ModuleProvider.updateCapabilities`；本类**不直接引用** ModuleProvider。
class PluginProvider extends ChangeNotifier {
  PluginProvider({List<PluginMeta>? plugins}) {
    if (plugins != null) _plugins.addAll(plugins);
  }

  final List<PluginMeta> _plugins = <PluginMeta>[];
  bool _disposed = false;

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
  Set<String> get allCapabilities {
    final Set<String> result = <String>{};
    for (final PluginMeta plugin in _plugins) {
      if (!plugin.enabled) continue;
      result.addAll(plugin.effectiveCapabilities);
    }
    return Set<String>.unmodifiable(result);
  }

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

  /// 新增插件；同 id 已存在则替换。
  void addPlugin(PluginMeta p) {
    final int index = _indexOf(p.id);
    if (index >= 0) {
      _plugins[index] = p;
    } else {
      _plugins.add(p);
    }
    _notify();
  }

  /// 卸载插件。
  ///
  /// 内置插件（[PluginMeta.isBuiltIn]）不可卸载，调用为空操作。
  void removePlugin(String id) {
    final int index = _indexOf(id);
    if (index < 0) return;
    if (_plugins[index].isBuiltIn) return;
    _plugins.removeAt(index);
    _notify();
  }

  /// 启用 / 停用插件。找不到该 id 时为空操作。
  void togglePlugin(String id, bool enabled) {
    final int index = _indexOf(id);
    if (index < 0) return;
    if (_plugins[index].enabled == enabled) return;
    _plugins[index] = _plugins[index].copyWith(enabled: enabled);
    _notify();
  }

  /// 清空插件列表（测试 / 重置用）。
  void clear() {
    if (_plugins.isEmpty) return;
    _plugins.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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