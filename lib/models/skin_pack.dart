// 皮肤包模型：描述一份 `.skin.json` 装扮包的元信息与颜色/圆角/字体配置
/// 一份皮肤包（`.skin.json`）。
///
/// 皮肤只影响视觉表现，不改变业务逻辑。
/// 颜色一律用 ARGB 整数（如 `0xFF1E88E5`），由主题层转成 `Color` 使用，
/// 模型层不依赖 Flutter。
///
/// [lightColors] / [darkColors] 中的键与主题令牌一致，例如
/// `"primary"`、`"background"`、`"card"`、`"textPrimary"`、`"textSecondary"`、
/// `"divider"`、`"courseColors"`（值需为 `List<int>`）。
class SkinPack {
  /// 皮肤唯一 ID。
  final String id;

  /// 皮肤显示名。
  final String name;

  /// 皮肤版本号。
  final String version;

  /// 作者。
  final String author;

  /// 皮肤说明。
  final String description;

  /// 预览图地址（本地相对路径或 http URL），可为空。
  final String previewImage;

  /// 亮色模式的颜色表：令牌名 → ARGB 整数。
  final Map<String, int> lightColors;

  /// 暗色模式的颜色表：令牌名 → ARGB 整数。
  final Map<String, int> darkColors;

  /// 课程卡片配色池（ARGB 整数列表），课表按课程名哈希取色。
  final List<int> courseColors;

  /// 圆角半径（逻辑像素）。
  final double borderRadius;

  /// 卡片阴影高度。
  final double elevation;

  /// 字体族名，空字符串表示用系统默认。
  final String fontFamily;

  /// 主题模式偏好：`"light"` / `"dark"` / `"system"`。
  final String mode;

  /// 安装来源：`"builtin"`（内置）、`"workshop"`（创意工坊）、`"local"`（本地导入）。
  final String source;

  /// 安装时间；内置皮肤为约定的早期时间。
  final DateTime installedAt;

  const SkinPack({
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.author = '',
    this.description = '',
    this.previewImage = '',
    this.lightColors = const <String, int>{},
    this.darkColors = const <String, int>{},
    this.courseColors = const <int>[],
    this.borderRadius = 12,
    this.elevation = 0,
    this.fontFamily = '',
    this.mode = 'system',
    this.source = 'local',
    required this.installedAt,
  });

  /// 从 JSON 构造，缺失或类型异常的字段使用安全默认值，不抛异常。
  factory SkinPack.fromJson(Map<String, dynamic> json) {
    return SkinPack(
      id: _asString(json['id']),
      name: _asString(json['name']),
      version: _asString(json['version'], fallback: '1.0.0'),
      author: _asString(json['author']),
      description: _asString(json['description']),
      previewImage: _asString(json['previewImage']),
      lightColors: _asIntMap(json['lightColors']),
      darkColors: _asIntMap(json['darkColors']),
      courseColors: _asIntList(json['courseColors']),
      borderRadius: _asDouble(json['borderRadius'], fallback: 12),
      elevation: _asDouble(json['elevation'], fallback: 0),
      fontFamily: _asString(json['fontFamily']),
      mode: _asString(json['mode'], fallback: 'system'),
      source: _asString(json['source'], fallback: 'local'),
      installedAt: _asDateTime(json['installedAt']) ?? DateTime.now(),
    );
  }

  /// 是否内置皮肤（不可卸载）。
  bool get isBuiltIn => source == 'builtin';

  /// 是否来自创意工坊。
  bool get isFromWorkshop => source == 'workshop';

  /// 是否同时提供了亮/暗两套配色。
  bool get supportsDarkMode => darkColors.isNotEmpty;

  /// 是否配置了字体。
  bool get hasCustomFont => fontFamily.isNotEmpty;

  /// 是否配置了课程配色池。
  bool get hasCourseColors => courseColors.isNotEmpty;

  /// 按 [token] 取亮色；找不到时返回 [fallback]。
  int lightColor(String token, {required int fallback}) =>
      lightColors[token] ?? fallback;

  /// 按 [token] 取暗色；找不到时回落到亮色，再回落到 [fallback]。
  int darkColor(String token, {required int fallback}) =>
      darkColors[token] ?? lightColors[token] ?? fallback;

  /// 按课程名取配色池中的颜色；配色池为空时返回 `null`。
  int? colorForCourse(String courseName) {
    if (courseColors.isEmpty) return null;
    final int index = courseName.hashCode.abs() % courseColors.length;
    return courseColors[index];
  }

  /// 序列化为可写入 Hive / JSON 的 Map。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'version': version,
      'author': author,
      'description': description,
      'previewImage': previewImage,
      'lightColors': lightColors,
      'darkColors': darkColors,
      'courseColors': courseColors,
      'borderRadius': borderRadius,
      'elevation': elevation,
      'fontFamily': fontFamily,
      'mode': mode,
      'source': source,
      'installedAt': installedAt.toIso8601String(),
    };
  }

  /// 复制并修改部分字段。
  SkinPack copyWith({
    String? id,
    String? name,
    String? version,
    String? author,
    String? description,
    String? previewImage,
    Map<String, int>? lightColors,
    Map<String, int>? darkColors,
    List<int>? courseColors,
    double? borderRadius,
    double? elevation,
    String? fontFamily,
    String? mode,
    String? source,
    DateTime? installedAt,
  }) {
    return SkinPack(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      previewImage: previewImage ?? this.previewImage,
      lightColors: lightColors ?? this.lightColors,
      darkColors: darkColors ?? this.darkColors,
      courseColors: courseColors ?? this.courseColors,
      borderRadius: borderRadius ?? this.borderRadius,
      elevation: elevation ?? this.elevation,
      fontFamily: fontFamily ?? this.fontFamily,
      mode: mode ?? this.mode,
      source: source ?? this.source,
      installedAt: installedAt ?? this.installedAt,
    );
  }

  @override
  String toString() => 'SkinPack(id: $id, name: $name, version: $version, '
      'author: $author, description: $description, '
      'previewImage: $previewImage, lightColors: $lightColors, '
      'darkColors: $darkColors, courseColors: $courseColors, '
      'borderRadius: $borderRadius, elevation: $elevation, '
      'fontFamily: $fontFamily, mode: $mode, source: $source, '
      'installedAt: $installedAt)';
}

/// 安全地把任意值转成 String。
String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

/// 安全地把任意值转成 double。
double _asDouble(Object? value, {required double fallback}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? fallback;
  return fallback;
}

/// 安全地把任意值转成 DateTime。
DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// 安全地把任意值转成 `List<int>`，忽略无法转换的元素。
List<int> _asIntList(Object? value) {
  if (value is! List) return const <int>[];
  final List<int> result = <int>[];
  for (final Object? item in value) {
    final int? parsed = _parseColor(item);
    if (parsed != null) result.add(parsed);
  }
  return result;
}

/// 安全地把任意值转成 `Map<String, int>`（颜色表），忽略非法条目。
Map<String, int> _asIntMap(Object? value) {
  if (value is! Map) return const <String, int>{};
  final Map<String, int> result = <String, int>{};
  value.forEach((dynamic key, dynamic item) {
    if (key == null) return;
    final int? parsed = _parseColor(item);
    if (parsed != null) result[key.toString()] = parsed;
  });
  return result;
}

/// 解析颜色：接受 ARGB 整数，也接受 `"#1E88E5"` / `"#FF1E88E5"` 形式的字符串。
int? _parseColor(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is! String) return null;
  String text = value.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('#')) text = text.substring(1);
  if (text.startsWith('0x') || text.startsWith('0X')) text = text.substring(2);
  if (text.length == 6) text = 'FF$text';
  if (text.length != 8) return null;
  return int.tryParse(text, radix: 16);
}