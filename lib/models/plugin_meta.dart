// 插件元数据模型：描述插件的身份、版本、来源与它声明的能力
import 'module.dart';

/// 一个插件（`.js` 文件）的元数据。
///
/// 由插件头部声明解析而来，用于插件管理页展示与运行时加载校验。
/// 插件代码本身不在这里——已安装插件的文件位置由 `PluginStorageService`
/// 按 [id] 现算（见 [assetPath] 的说明）。
class PluginMeta {
  /// 插件唯一 ID，如 `"ncst-jwxt"`。
  final String id;

  /// 插件显示名，如 `"NCST 教务系统"`。
  final String name;

  /// 插件版本号，建议语义化版本 `"1.0.0"`。
  final String version;

  /// 插件作者。
  final String author;

  /// 插件说明。
  final String description;

  /// 适用学校/教务系统名称，便于用户判断是否可用。
  final String school;

  /// 插件声明的**数据能力** ID 列表，如 `['exam', 'homework', 'ncst.grade']`。
  ///
  /// 这是插件"能做什么"的扁平声明，由 `PluginProvider.allCapabilities`
  /// 汇总后推给 `ModuleProvider.updateCapabilities` 决定模块可用性。
  ///
  /// 与 [modules] 的分工：[capabilities] 只声明能力 ID（无 UI 信息），
  /// [modules] 则额外携带标题 / 图标 / 排序等元数据，用于在导航栏上**渲染**
  /// 插件贡献的模块。两者都声明时取并集，不会互相覆盖。
  final List<String> capabilities;

  /// 插件贡献的**导航栏模块**列表（含标题、图标、排序等 UI 元数据）。
  ///
  /// 插件可以给 App 增加导航栏模块；每个 [ModuleInfo.capabilityId]
  /// 同时也是一项能力，会被计入 [capabilities] 的并集。
  final List<ModuleInfo> modules;

  /// 插件入口文件名，如 `"ncst-jwxt.js"`。
  final String entryFile;

  /// **打包内置插件**的 asset 路径（相对 `assets/` 根，如 `plugins/ncst.js`）。
  ///
  /// **Phase 3.4 起不再用于定位已安装插件**：已安装插件的文件位置由
  /// `PluginStorageService.getPluginJsPath(id)` 按 [id] 现算（目录布局
  /// `<appDocuments>/plugins/<id>.js` 是 id 的纯函数）。
  ///
  /// 为什么不把安装路径存进这个字段：① 冗余（路径可由 id 推出）；
  /// ② **危险**——iOS 的应用容器 UUID 每次 App 更新都会变，存下的绝对路径
  /// 会在更新后失效。所以该字段只保留给"随 App 打包"的内置插件
  /// （那类插件要用 `rootBundle` 读，与文件系统路径是**两种加载方式**）。
  ///
  /// 键名保持 `assetPath` 不变：CONTEXT 4.2.1 规定序列化键名已冻结，
  /// 改名要写迁移，而收窄语义（本注释）零迁移成本。
  final String assetPath;

  /// 安装来源：`"local"`（本地导入）、`"workshop"`（创意工坊）、`"builtin"`（内置）。
  final String source;

  /// 从商店下载的原始 URL，内置/本地插件为空字符串。
  final String downloadUrl;

  /// 该插件是否有可用的更新（由商店索引比对得出）。
  final bool hasUpdate;

  /// 商店中的最新版本号，未知为空字符串。
  final String latestVersion;

  /// 是否已启用。
  final bool enabled;

  /// 安装时间。
  final DateTime installedAt;

  /// 最近一次成功同步的时间，`null` 表示从未同步。
  final DateTime? lastSyncAt;

  /// 该插件是否**允许用户卸载**（Phase 3.5.1 新增，默认 `true`）。
  ///
  /// 这是**策略**，与 [source]（来源）是两件事，刻意分开：
  /// 从 assets 安装的示例插件来源确实是 `"builtin"`（随 App 打包），
  /// 但它**应当可以卸载**；只有**硬编码在代码里的系统级插件**才该禁止卸载。
  /// 之前用 `source == 'builtin'` 反推"不可卸载"，导致示例插件在详情页
  /// 看不到卸载入口（Phase 3.5.1 修正的正是这个 bug）。
  ///
  /// 新增字段，**向后兼容**：旧数据没有这个键时 [PluginMeta.fromJson] 回落 `true`，
  /// 因此无需迁移（CONTEXT 4.2.1 只要求"改名 / 改语义"时写迁移）。
  final bool isRemovable;

  const PluginMeta({
    required this.id,
    required this.name,
    this.version = '0.0.0',
    this.author = '',
    this.description = '',
    this.school = '',
    this.capabilities = const <String>[],
    this.modules = const <ModuleInfo>[],
    this.entryFile = '',
    this.assetPath = '',
    this.source = 'local',
    this.downloadUrl = '',
    this.hasUpdate = false,
    this.latestVersion = '',
    this.enabled = false,
    required this.installedAt,
    this.lastSyncAt,
    this.isRemovable = true,
  });

  /// 从 JSON 构造，缺失或类型异常的字段使用安全默认值，不抛异常。
  factory PluginMeta.fromJson(Map<String, dynamic> json) {
    return PluginMeta(
      id: _asString(json['id']),
      name: _asString(json['name']),
      version: _asString(json['version'], fallback: '0.0.0'),
      author: _asString(json['author']),
      description: _asString(json['description']),
      school: _asString(json['school']),
      capabilities: _asStringList(json['capabilities']),
      modules: _asModuleList(json['modules']),
      entryFile: _asString(json['entryFile']),
      assetPath: _asString(json['assetPath']),
      source: _asString(json['source'], fallback: 'local'),
      downloadUrl: _asString(json['downloadUrl']),
      hasUpdate: _asBool(json['hasUpdate']),
      latestVersion: _asString(json['latestVersion']),
      enabled: _asBool(json['enabled']),
      installedAt: _asDateTime(json['installedAt']) ?? DateTime.now(),
      lastSyncAt: _asDateTime(json['lastSyncAt']),
      // 旧数据没有该键 → 回落 true（向后兼容，无需迁移）。
      isRemovable: _asBool(json['isRemovable'], fallback: true),
    );
  }

  /// 是否为**内置来源**的插件（`source == 'builtin'`，即随 App 打包）。
  ///
  /// **注意**：这是**来源**，不是"能否卸载"。从 assets 安装的示例插件来源也是
  /// `"builtin"`，但它可以卸载。判断卸载请看 [isRemovable]。
  bool get isBuiltIn => source == 'builtin';

  /// 是否来自创意工坊。
  bool get isFromWorkshop => source == 'workshop';

  /// 是否曾经同步成功过。
  bool get hasSynced => lastSyncAt != null;

  /// 该插件是否声明了任何模块能力（[capabilities] 与 [modules] 任一非空）。
  bool get hasModules => modules.isNotEmpty;

  /// 该插件声明的全部能力 ID 的并集：[capabilities] ∪ 各 [modules] 的 capabilityId。
  ///
  /// 两种声明方式都支持，避免插件只写其中一处时能力被漏掉。
  /// 空字符串会被忽略。
  Set<String> get effectiveCapabilities {
    final Set<String> result = <String>{};
    for (final String capability in capabilities) {
      if (capability.isNotEmpty) result.add(capability);
    }
    for (final ModuleInfo module in modules) {
      if (module.capabilityId.isNotEmpty) result.add(module.capabilityId);
    }
    return result;
  }

  /// 该插件是否声明了任何能力。
  bool get hasCapabilities => effectiveCapabilities.isNotEmpty;

  /// 序列化为可写入 Hive / JSON 的 Map。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'version': version,
      'author': author,
      'description': description,
      'school': school,
      'capabilities': capabilities,
      'modules': modules.map((ModuleInfo e) => e.toJson()).toList(),
      'entryFile': entryFile,
      'assetPath': assetPath,
      'source': source,
      'downloadUrl': downloadUrl,
      'hasUpdate': hasUpdate,
      'latestVersion': latestVersion,
      'enabled': enabled,
      'installedAt': installedAt.toIso8601String(),
      'lastSyncAt': lastSyncAt?.toIso8601String(),
      'isRemovable': isRemovable,
    };
  }

  /// 复制并修改部分字段。[clearLastSyncAt] 用于显式清空同步时间。
  PluginMeta copyWith({
    String? id,
    String? name,
    String? version,
    String? author,
    String? description,
    String? school,
    List<String>? capabilities,
    List<ModuleInfo>? modules,
    String? entryFile,
    String? assetPath,
    String? source,
    String? downloadUrl,
    bool? hasUpdate,
    String? latestVersion,
    bool? enabled,
    DateTime? installedAt,
    DateTime? lastSyncAt,
    bool? isRemovable,
    bool clearLastSyncAt = false,
  }) {
    return PluginMeta(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      school: school ?? this.school,
      capabilities: capabilities ?? this.capabilities,
      modules: modules ?? this.modules,
      entryFile: entryFile ?? this.entryFile,
      assetPath: assetPath ?? this.assetPath,
      source: source ?? this.source,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      latestVersion: latestVersion ?? this.latestVersion,
      enabled: enabled ?? this.enabled,
      installedAt: installedAt ?? this.installedAt,
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      isRemovable: isRemovable ?? this.isRemovable,
    );
  }

  @override
  String toString() => 'PluginMeta(id: $id, name: $name, version: $version, '
      'author: $author, description: $description, school: $school, '
      'capabilities: $capabilities, modules: $modules, '
      'entryFile: $entryFile, assetPath: $assetPath, '
      'source: $source, downloadUrl: $downloadUrl, hasUpdate: $hasUpdate, '
      'latestVersion: $latestVersion, enabled: $enabled, '
      'installedAt: $installedAt, lastSyncAt: $lastSyncAt, '
      'isRemovable: $isRemovable)';
}

/// 安全地把任意值转成 String。
String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

/// 安全地把任意值转成 bool。
///
/// [fallback] 是"值缺失或无法识别"时的结果。默认 `false`（`hasUpdate` / `enabled`
/// 都该如此），但 `isRemovable` 传 `true`——它必须**向后兼容**：
/// 旧数据没有这个键，语义上应当是"可卸载"。
bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String text = value.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
  }
  return fallback;
}

/// 安全地把任意值转成 DateTime。
DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// 安全地把任意值转成 `List<String>`，忽略 `null` 与空字符串。
List<String> _asStringList(Object? value) {
  if (value is! List) return const <String>[];
  final List<String> result = <String>[];
  for (final Object? item in value) {
    if (item is String) {
      if (item.isNotEmpty) result.add(item);
    } else if (item != null) {
      final String text = item.toString();
      if (text.isNotEmpty) result.add(text);
    }
  }
  return result;
}

/// 安全地把任意值转成 `List<ModuleInfo>`，忽略非法元素。
List<ModuleInfo> _asModuleList(Object? value) {
  if (value is! List) return const <ModuleInfo>[];
  final List<ModuleInfo> result = <ModuleInfo>[];
  for (final Object? item in value) {
    if (item is ModuleInfo) {
      result.add(item);
    } else if (item is Map) {
      final Map<String, dynamic> map = <String, dynamic>{};
      item.forEach((dynamic key, dynamic val) {
        if (key != null) map[key.toString()] = val;
      });
      result.add(ModuleInfo.fromJson(map));
    } else if (item is String) {
      // 允许插件只声明能力 ID 字符串。
      result.add(ModuleInfo(
        capabilityId: item,
        title: item,
        isBuiltIn: false,
      ));
    }
  }
  return result;
}