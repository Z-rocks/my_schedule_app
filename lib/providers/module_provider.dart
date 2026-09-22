// 模块状态：管理底部导航栏可用模块的启用状态与能力可用性
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/module.dart';
import '../services/storage_service.dart';

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
  /// [ModuleInfo.iconName] 是 Material 图标名，UI 层（`home_page.dart` 的
  /// `_iconFromName`）把它转成 `IconData`。图标因此完全由数据驱动，
  /// 新增模块或改图标不需要动 UI 代码。
  ///
  /// 这里**显式**写出 `enabled` 与 `iconName` 而不依赖枚举默认值，
  /// 一是让初始表一目了然，二是避免以后改枚举时静默改变导航栏。
  static final List<ModuleInfo> _initialModules = <ModuleInfo>[
    ModuleInfo.fromType(ModuleType.timetable,
        enabled: true, order: 0, iconName: 'calendar_month'),
    ModuleInfo.fromType(ModuleType.courseList,
        enabled: true, order: 1, iconName: 'book_outlined'),
    ModuleInfo.fromType(ModuleType.exam,
        enabled: true, order: 2, iconName: 'assignment_outlined'),
    ModuleInfo.fromType(ModuleType.homework,
        enabled: false, available: false, order: 3, iconName: 'edit_note'),
    ModuleInfo.fromType(ModuleType.message,
        enabled: false, order: 4, iconName: 'notifications_outlined'),
    ModuleInfo.fromType(ModuleType.settings,
        enabled: true, order: 5, iconName: 'settings_outlined'),
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
  ///
  /// 切换成功后**自动落盘**（见 [saveToStorage]），因此杀进程重开仍保留配置。
  void toggle(ModuleType type, bool enabled) {
    final int index = _indexOfType(type);
    if (index < 0) return;

    final ModuleInfo module = _modules[index];
    if (module.alwaysOn) return; // 常驻模块不可关闭
    if (module.enabled == enabled) return;

    _modules[index] = module.withEnabled(enabled);
    _notify();
    // 不 await：toggle 是同步接口（Switch.onChanged 直接用），
    // 落盘失败只记日志，不阻塞 UI 也不回滚内存状态。
    unawaited(saveToStorage());
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
  ///
  /// 同样会落盘——否则"恢复默认"重启后又被存储里的旧配置覆盖回去。
  void resetToDefaults() {
    _modules
      ..clear()
      ..addAll(_initialModules);
    _notify();
    unawaited(saveToStorage());
  }

  // ————————————————— 持久化（settings Box） —————————————————

  /// 从 `settings` Box 恢复用户上次的导航栏开关配置。
  ///
  /// 边界情况（都不崩溃）：
  /// - 没存过 / 空串 / 坏 JSON / 不是对象 → 保持初始默认配置
  /// - 某个键的值类型不符（如 `"yes"`）→ 跳过该键，该模块用默认值
  /// - 只存了部分模块 → 未出现的模块用默认值
  /// - 存了当前不存在的模块 ID（插件卸载等）→ 忽略
  /// - 常驻模块即使存的是 `false` → 仍强制启用（见下）
  Future<void> loadFromStorage() async {
    try {
      final String? raw =
          StorageService.settingsBox.get(kModuleEnabledStateKey);
      final Map<String, bool> stored = decodeEnabledState(raw);
      if (stored.isEmpty) return;

      bool changed = false;
      for (int i = 0; i < _modules.length; i++) {
        final ModuleInfo module = _modules[i];
        final bool? enabled = stored[module.capabilityId];
        if (enabled == null) continue; // 存储里没有 → 保持默认

        // 走 withEnabled：它内部对常驻模块强制 true，
        // 所以"课表/设置不可关闭"的规则只有一份实现（在 ModuleInfo 里），
        // loadFromStorage 与 toggle 共用，不需要在这里再写一遍。
        final ModuleInfo next = module.withEnabled(enabled);
        if (next.enabled == module.enabled) continue;
        _modules[i] = next;
        changed = true;
      }
      if (changed) _notify();
    } catch (error, stackTrace) {
      debugPrint('ModuleProvider.loadFromStorage 失败（保持默认配置）: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 把当前的 enabled 状态写入 `settings` Box。
  ///
  /// 存储结构：`settings` Box 的键 [kModuleEnabledStateKey]，
  /// 值是一个 JSON 对象 `{"<capabilityId>": <bool>, ...}`（见 [encodeEnabledState]）。
  Future<void> saveToStorage() async {
    try {
      await StorageService.settingsBox.put(
        kModuleEnabledStateKey,
        jsonEncode(encodeEnabledState()),
      );
    } catch (error, stackTrace) {
      debugPrint('ModuleProvider.saveToStorage 失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 当前 enabled 状态：`capabilityId → enabled`。
  ///
  /// 用 [ModuleInfo.capabilityId] 而不是 `ModuleType.name` 作键：
  /// 内置模块两者相等，而插件模块没有 `ModuleType`，只有 `capabilityId`，
  /// 用它才能统一覆盖两类模块。
  Map<String, bool> encodeEnabledState() => <String, bool>{
        for (final ModuleInfo module in _modules)
          module.capabilityId: module.enabled,
      };

  /// 解析存储里的模块配置。
  ///
  /// 任何解析不出来的内容都被**忽略**而不是抛异常：
  /// 返回空 Map 表示"整份数据不可用，全部走默认值"，
  /// 某个键被跳过表示"只有这个模块走默认值"。
  static Map<String, bool> decodeEnabledState(String? raw) {
    if (raw == null || raw.isEmpty) return <String, bool>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        debugPrint('ModuleProvider: 模块配置不是 JSON 对象，改用默认配置');
        return <String, bool>{};
      }

      final Map<String, bool> result = <String, bool>{};
      decoded.forEach((dynamic key, dynamic value) {
        if (key == null) return;
        final String id = key.toString();
        if (id.isEmpty) return;
        final bool? flag = _asBoolOrNull(value);
        if (flag == null) {
          debugPrint('ModuleProvider: 模块 "$id" 的配置值类型不符，已忽略');
          return;
        }
        result[id] = flag;
      });
      return result;
    } catch (error) {
      debugPrint('ModuleProvider: 模块配置解析失败，改用默认配置: $error');
      return <String, bool>{};
    }
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

/// 宽松地把 JSON 值转成 bool：接受 `bool`、数字（0/1）与 `"true"/"false"/"1"/"0"`。
/// 其余类型返回 `null`（调用方据此跳过该键，改用默认值）。
bool? _asBoolOrNull(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
    }
  }
  return null;
}