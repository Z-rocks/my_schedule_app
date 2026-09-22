// 模块状态：管理底部导航栏可用模块的启用状态与能力可用性
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/module.dart';

/// 底部导航栏最多显示的模块数（CONTEXT.md 3.4）。
///
/// 注：CONTEXT.md 4.1 的常量命名规范写的是全大写下划线（`MAX_MODULES`），
/// 但项目启用的 `flutter_lints` 中 `constant_identifier_names` 会对此报 info，
/// 与本阶段"analyze 零问题"的验收冲突，故采用 Dart/Flutter 惯例的 `k` 前缀。
const int kMaxModules = 5;

/// 导航栏模块状态。
///
/// 三个状态维度（见 [ModuleInfo] 的文档）：
/// - [ModuleInfo.alwaysOn]：课表 / 设置常驻，不可关闭
/// - [ModuleInfo.available]：能力是否被提供（考试 / 作业需要插件声明）
/// - [ModuleInfo.enabled]：用户是否把它放上导航栏
///
/// 本类不引用任何其他 Provider；插件能力通过 [updateCapabilities] 由外部注入
/// （Phase 1.4 用 `ChangeNotifierProxyProvider` 从 PluginProvider 联动过来）。
class ModuleProvider extends ChangeNotifier {
  /// 内置模块的初始定义（顺序即导航栏默认顺序）。
  ///
  /// - 初始 available：
  ///   - timetable / courseList / exam / message / settings 为 `true`
  ///     （exam 支持手动添加考试，不依赖插件）
  ///   - homework 为 `false`（作业数据必须来自插件，无插件时不可用）
  /// - 初始 enabled：timetable / courseList / exam / settings 为 `true`，
  ///   homework / message 为 `false`（与 [ModuleType.isDefaultEnabled] 一致）
  ///
  /// 这里**显式**写出 `enabled` 而不依赖 [ModuleType.isDefaultEnabled]，
  /// 一是让初始表一目了然，二是避免以后改枚举默认值时静默改变导航栏。
  static final List<ModuleInfo> _initialModules = <ModuleInfo>[
    ModuleInfo.fromType(ModuleType.timetable, enabled: true, order: 0),
    ModuleInfo.fromType(ModuleType.courseList, enabled: true, order: 1),
    ModuleInfo.fromType(ModuleType.exam, enabled: true, order: 2),
    ModuleInfo.fromType(
        ModuleType.homework, enabled: false, available: false, order: 3),
    ModuleInfo.fromType(ModuleType.message, enabled: false, order: 4),
    ModuleInfo.fromType(ModuleType.settings, enabled: true, order: 5),
  ];

  final List<ModuleInfo> _modules = List<ModuleInfo>.of(_initialModules);
  bool _disposed = false;

  /// 全部模块（含不可用的），供"导航栏配置"页展示。
  ///
  /// 顺序与初始定义一致，返回不可变视图。
  List<ModuleInfo> get allModules => UnmodifiableListView<ModuleInfo>(_modules);

  /// 真正显示在底部导航栏上的模块。
  ///
  /// **选择规则**（CONTEXT.md 3.4 + prompt）：
  /// 1. [ModuleInfo.alwaysOn] 的模块永远包含（课表 / 设置不可关闭）
  /// 2. 非常驻模块需 `available && enabled` 才包含
  /// 3. 总数最多 [kMaxModules] 个；超出时**优先保留常驻模块**，
  ///    其余按模块列表顺序取，直到填满
  ///
  /// 常驻模块即使让总数超过 [kMaxModules] 也不会被裁掉（"required 永远包含"优先）。
  ///
  /// **输出顺序**：始终按 [_modules] 的原始定义顺序
  /// （timetable → courseList → exam → homework → message → settings），
  /// 而不是"常驻在前、可选在后"。这样用户开关模块时底部导航的顺序保持稳定，
  /// 不会因为某个模块被 toggle 而整条导航栏跳动。
  List<ModuleInfo> get visibleModules {
    final List<ModuleInfo> required = <ModuleInfo>[];
    final List<ModuleInfo> optional = <ModuleInfo>[];
    for (final ModuleInfo module in _modules) {
      if (module.alwaysOn) {
        required.add(module);
      } else if (module.available && module.enabled) {
        optional.add(module);
      }
    }

    // 先决定"选中哪些"（capabilityId 唯一，用它做集合去重）。
    final Set<String> selectedIds = <String>{
      for (final ModuleInfo module in required) module.capabilityId,
    };
    int slots = kMaxModules - selectedIds.length;
    for (final ModuleInfo module in optional) {
      if (slots <= 0) break;
      if (selectedIds.add(module.capabilityId)) slots--;
    }

    // 再按原始定义顺序输出。
    return UnmodifiableListView<ModuleInfo>(
      _modules
          .where((ModuleInfo m) => selectedIds.contains(m.capabilityId))
          .toList(),
    );
  }

  /// 导航栏实际显示的模块数量。
  int get visibleCount => visibleModules.length;

  /// 按 [ModuleType] 取模块；不存在返回 `null`。
  ModuleInfo? getByType(ModuleType type) {
    for (final ModuleInfo module in _modules) {
      if (module.type == type) return module;
    }
    return null;
  }

  /// 切换模块的启用状态。
  ///
  /// 常驻模块（课表 / 设置）不可关闭：对它们的调用是**空操作**，保持启用
  /// （CONTEXT.md 3.4 "课表、设置不可关闭"）。
  /// 不可用的模块（能力未提供）允许记录用户的启用意图，
  /// 但不会出现在 [visibleModules] 中，等能力可用后自动生效。
  void toggle(ModuleType type, bool enabled) {
    final int index = _indexOfType(type);
    if (index < 0) return;

    final ModuleInfo module = _modules[index];
    if (module.alwaysOn) return; // 常驻模块不可关闭
    if (module.enabled == enabled) return;

    _modules[index] = module.withEnabled(enabled);
    _notify();
  }

  /// 用插件声明的能力集合更新各模块的可用性。
  ///
  /// 各类模块与能力的关系：
  /// - `timetable` / `courseList` / `message` 是**内置能力**，恒可用
  /// - `exam` 是**插件可选增强**：无插件也能手动添加考试，因此本方法不改变它的
  ///   可用性；插件声明 `exam` 能力后只是额外提供自动拉取（Phase 4）
  /// - `homework` 是**插件专属**：作业数据只能来自插件，无插件时不可用
  ///
  /// 因此本方法当前**只调整 `homework` 的可用性**：
  /// 能力集合含 `'homework'` → available = true，否则 false。
  /// 传入空集时 `homework` 变为不可用，`exam` 保持可用。
  void updateCapabilities(Set<String> capabilities) {
    bool changed = false;
    for (int i = 0; i < _modules.length; i++) {
      final ModuleInfo module = _modules[i];
      final ModuleType? type = module.type;
      // exam 初始即可用（手动添加考试），只有 homework 依赖插件能力。
      if (type != ModuleType.homework) continue;

      final bool available = capabilities.contains(type!.name);
      if (module.available == available) continue;
      _modules[i] = module.withAvailable(available);
      changed = true;
    }
    if (changed) _notify();
  }

  /// 恢复初始模块配置（设置页"恢复默认"用）。
  void resetToDefaults() {
    _modules
      ..clear()
      ..addAll(_initialModules);
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

  int _indexOfType(ModuleType type) {
    for (int i = 0; i < _modules.length; i++) {
      if (_modules[i].type == type) return i;
    }
    return -1;
  }
}