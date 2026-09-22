// 模块模型：定义底部导航的可用模块（能力驱动）与用户在导航栏上的配置
/// 内置模块类型。插件声明的自定义能力用 [ModuleInfo.capabilityId] 标识，
/// 不在此枚举中；本枚举只覆盖内核自带的模块。
enum ModuleType {
  /// 课表，不可关闭。
  timetable,

  /// 课程列表。
  courseList,

  /// 考试安排。
  exam,

  /// 作业。
  homework,

  /// 消息。
  message,

  /// 设置，不可关闭。
  settings;

  /// 从 JSON 中的字符串安全解析，无法识别时返回 `null`
  /// （表示这是插件声明的自定义能力，应走 [ModuleInfo.capabilityId]）。
  static ModuleType? fromName(Object? value) {
    if (value is ModuleType) return value;
    if (value is! String) return null;
    final String key = value.trim().toLowerCase();
    for (final ModuleType type in ModuleType.values) {
      if (type.name == key) return type;
    }
    return null;
  }

  /// 默认中文标题。
  String get defaultTitle {
    switch (this) {
      case ModuleType.timetable:
        return '课表';
      case ModuleType.courseList:
        return '课程';
      case ModuleType.exam:
        return '考试';
      case ModuleType.homework:
        return '作业';
      case ModuleType.message:
        return '消息';
      case ModuleType.settings:
        return '设置';
    }
  }

  /// 该模块是否允许被用户关闭。课表与设置不可关闭。
  bool get canDisable =>
      this != ModuleType.timetable && this != ModuleType.settings;

  /// 该模块是否默认出现在导航栏上。
  ///
  /// 取值与 `ModuleProvider` 的初始模块配置保持一致：
  /// timetable / courseList / exam / settings 默认开启，
  /// homework / message 默认关闭（用户可在"导航栏配置"里开启）。
  bool get isDefaultEnabled =>
      this == ModuleType.timetable ||
      this == ModuleType.courseList ||
      this == ModuleType.exam ||
      this == ModuleType.settings;

  /// 是否由内核内置（恒为 `true`，插件能力见 [ModuleInfo.isBuiltIn]）。
  bool get isBuiltIn => true;
}

/// 一个可用模块的描述与用户配置。
///
/// 内核内置模块用 [type] 标识；插件声明的能力模块 [type] 为 `null`，
/// 靠 [capabilityId] 唯一标识。
class ModuleInfo {
  /// 模块唯一标识：内置模块用 [ModuleType.name]，插件模块用 `"<插件ID>.<能力名>"`。
  final String capabilityId;

  /// 内置模块类型；插件声明的能力为 `null`。
  final ModuleType? type;

  /// 导航栏上显示的标题，用户可改。
  final String title;

  /// 图标标识（Material 图标名，如 `"calendar_month"`），
  /// 由 UI 层映射为具体 IconData，模型层不依赖 Flutter。
  final String iconName;

  /// 是否启用（显示在底部导航栏上）。
  final bool enabled;

  /// 该模块的能力当前是否**可用**。
  ///
  /// 与 [enabled] 的区别：[available] 表示"能力被提供了"
  /// （内置模块恒为 `true`；考试 / 作业等模块需要已启用的插件声明对应能力），
  /// [enabled] 表示"用户是否把它放到了导航栏上"。
  /// 只有 `available && enabled` 的模块才会真正出现在导航栏上。
  final bool available;

  /// 导航栏中的排序位置，越小越靠前。
  final int order;

  /// 是否为内核内置模块（`false` 表示来自插件）。
  final bool isBuiltIn;

  /// 提供该模块的插件 ID，内置模块为空字符串。
  final String sourcePluginId;

  /// 该模块是否必须常驻（课表、设置），常驻模块不可关闭。
  final bool alwaysOn;

  const ModuleInfo({
    required this.capabilityId,
    this.type,
    required this.title,
    this.iconName = '',
    this.enabled = false,
    this.available = true,
    this.order = 0,
    this.isBuiltIn = true,
    this.sourcePluginId = '',
    this.alwaysOn = false,
  });

  /// 用 [ModuleType] 快速构造一个内置模块，默认值取自枚举。
  factory ModuleInfo.fromType(
    ModuleType type, {
    bool? enabled,
    bool available = true,
    int order = 0,
  }) {
    return ModuleInfo(
      capabilityId: type.name,
      type: type,
      title: type.defaultTitle,
      enabled: enabled ?? type.isDefaultEnabled,
      available: available,
      order: order,
      isBuiltIn: true,
      alwaysOn: !type.canDisable,
    );
  }

  /// 从 JSON 构造，缺失或类型异常的字段使用安全默认值，不抛异常。
  factory ModuleInfo.fromJson(Map<String, dynamic> json) {
    final ModuleType? type = ModuleType.fromName(json['type']);
    final String capabilityId = _asString(json['capabilityId']);
    return ModuleInfo(
      capabilityId: capabilityId.isNotEmpty
          ? capabilityId
          : (type?.name ?? ''),
      type: type,
      title: _asString(json['title'], fallback: type?.defaultTitle ?? ''),
      iconName: _asString(json['iconName']),
      enabled: _asBool(json['enabled'], fallback: type?.isDefaultEnabled ?? false),
      available: _asBool(json['available'], fallback: true),
      order: _asInt(json['order']),
      isBuiltIn: _asBool(json['isBuiltIn'], fallback: type != null),
      sourcePluginId: _asString(json['sourcePluginId']),
      alwaysOn: _asBool(json['alwaysOn'], fallback: type != null && !type.canDisable),
    );
  }

  /// 是否真正能显示在导航栏上（能力可用且用户已启用）。
  bool get isVisible => available && enabled;

  /// 是否来自插件。
  bool get isFromPlugin => !isBuiltIn;

  /// 返回一个把 [enabled] 改成 [value] 的副本；
  /// 若该模块常驻（[alwaysOn]），则无论 [value] 为何都保持启用。
  ModuleInfo withEnabled(bool value) =>
      copyWith(enabled: alwaysOn ? true : value);

  /// 返回一个把 [available] 改成 [value] 的副本。
  ModuleInfo withAvailable(bool value) => copyWith(available: value);

  /// 序列化为可写入 Hive / JSON 的 Map。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'capabilityId': capabilityId,
      'type': type?.name,
      'title': title,
      'iconName': iconName,
      'enabled': enabled,
      'available': available,
      'order': order,
      'isBuiltIn': isBuiltIn,
      'sourcePluginId': sourcePluginId,
      'alwaysOn': alwaysOn,
    };
  }

  /// 复制并修改部分字段。
  ModuleInfo copyWith({
    String? capabilityId,
    ModuleType? type,
    String? title,
    String? iconName,
    bool? enabled,
    bool? available,
    int? order,
    bool? isBuiltIn,
    String? sourcePluginId,
    bool? alwaysOn,
  }) {
    return ModuleInfo(
      capabilityId: capabilityId ?? this.capabilityId,
      type: type ?? this.type,
      title: title ?? this.title,
      iconName: iconName ?? this.iconName,
      enabled: enabled ?? this.enabled,
      available: available ?? this.available,
      order: order ?? this.order,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      sourcePluginId: sourcePluginId ?? this.sourcePluginId,
      alwaysOn: alwaysOn ?? this.alwaysOn,
    );
  }

  @override
  String toString() => 'ModuleInfo(capabilityId: $capabilityId, '
      'type: ${type?.name}, title: $title, iconName: $iconName, '
      'enabled: $enabled, available: $available, order: $order, '
      'isBuiltIn: $isBuiltIn, '
      'sourcePluginId: $sourcePluginId, alwaysOn: $alwaysOn)';
}

/// 安全地把任意值转成 String。
String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

/// 安全地把任意值转成 int。
int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// 安全地把任意值转成 bool。
bool _asBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String text = value.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
  }
  return fallback;
}