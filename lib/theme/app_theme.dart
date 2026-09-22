// 主题模型：定义 App 的全部视觉令牌（颜色 / 字体 / 形状 / 间距 / 阴影 / 布局）
import 'package:flutter/material.dart';

import 'default_theme.dart' as defaults;

/// App 的视觉令牌集合，不可变。
///
/// 所有 UI 组件都应通过 `AppThemeExtension.of(context)` 拿到本对象来读样式，
/// **禁止**在 UI 里硬编码颜色、圆角、间距、字体（见 CONTEXT.md 3.2）。
///
/// 三种获取途径：
/// - `AppTheme.defaultTheme()` —— 内置默认蓝主题（合并基线）
/// - `AppTheme.fromJson(json)` —— 从皮肤 JSON 解析，缺失字段回落到默认主题
/// - `theme.merge(other)` —— 把 `other` 中**显式设置**的字段叠加到 `this` 上
class AppTheme {
  // —— 颜色 ——

  /// 主色。
  final Color primary;

  /// 次要色 / 强调色。
  final Color secondary;

  /// 页面背景色。
  final Color background;

  /// 卡片 / 表面色。
  final Color surface;

  /// 错误色。
  final Color error;

  /// 主色之上的前景色（主色按钮的文字/图标）。
  final Color onPrimary;

  /// 背景之上的前景色（正文文字）。
  final Color onBackground;

  /// 课程卡片配色池，课表按课程名哈希取色。
  final List<Color> courseCardColors;

  /// 考试强调色。
  final Color examHighlight;

  /// 作业强调色。
  final Color homeworkHighlight;

  // —— 字体 ——

  /// 字体族名，空字符串表示使用系统默认字体。
  final String fontFamily;

  /// 标题字号。
  final double titleSize;

  /// 正文字号。
  final double bodySize;

  /// 辅助说明字号。
  final double captionSize;

  /// 标题字重（`FontWeight.value`，如 400 / 500 / 600 / 700）。
  final int fontWeightTitle;

  // —— 形状 ——

  /// 卡片圆角半径。
  final double cardRadius;

  /// 按钮圆角半径。
  final double buttonRadius;

  /// 标签（Chip）圆角半径。
  final double chipRadius;

  // —— 间距 ——

  /// 卡片内边距。
  final double cardPadding;

  /// 网格间隙（课表单元格之间）。
  final double gridGap;

  /// 区块之间的间距。
  final double sectionGap;

  // —— 阴影 ——

  /// 卡片阴影颜色（通常带透明度）。
  final Color cardShadowColor;

  /// 卡片阴影模糊半径。
  final double cardShadowBlur;

  /// 卡片阴影垂直偏移。
  final double cardShadowOffsetY;

  // —— 布局 ——

  /// 课表单元格高度。
  final double timetableCellHeight;

  /// 课表左侧时间列宽度。
  final double timetableTimeColumnWidth;

  /// 课表是否显示周六周日。
  final bool showWeekend;

  /// 时间展示格式（`intl` 的 DateFormat 模式，如 `"HH:mm"`）。
  final String timeFormat;

  /// 记录哪些字段是**显式设置**过的（JSON 键名集合）。
  ///
  /// [merge] 靠它判断"该不该覆盖"：只有出现在这里的字段才会覆盖目标主题，
  /// 其余字段保持目标主题的原值。`AppTheme.defaultTheme()` 返回的实例该集合为空，
  /// 因此它作为合并基线时不会覆盖任何东西。
  final Set<String> _explicitFields;

  /// 构造一个主题。
  ///
  /// [explicitKeys] 是"被显式设置的字段名（JSON 键名）"集合，
  /// 供 [AppTheme.fromJson] 与 [merge] 内部使用。业务代码直接构造时留空即可：
  /// 留空意味着该主题在 [merge] 中不会覆盖任何字段，这通常正是想要的行为
  /// （默认主题就是靠这一点充当合并基线的）。
  const AppTheme({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.error,
    required this.onPrimary,
    required this.onBackground,
    required this.courseCardColors,
    required this.examHighlight,
    required this.homeworkHighlight,
    required this.fontFamily,
    required this.titleSize,
    required this.bodySize,
    required this.captionSize,
    required this.fontWeightTitle,
    required this.cardRadius,
    required this.buttonRadius,
    required this.chipRadius,
    required this.cardPadding,
    required this.gridGap,
    required this.sectionGap,
    required this.cardShadowColor,
    required this.cardShadowBlur,
    required this.cardShadowOffsetY,
    required this.timetableCellHeight,
    required this.timetableTimeColumnWidth,
    required this.showWeekend,
    required this.timeFormat,
    Set<String> explicitKeys = const <String>{},
  }) : _explicitFields = explicitKeys;

  /// 内置默认蓝主题。实现位于 `default_theme.dart`。
  static AppTheme defaultTheme() => defaults.defaultTheme();

  /// 被显式设置过的字段名（JSON 键名）只读视图，便于调试与校验。
  Set<String> get explicitFields => Set<String>.unmodifiable(_explicitFields);

  /// 当前主题属于亮色还是暗色（由 [background] 的亮度推断）。
  Brightness get brightness =>
      background.computeLuminance() > 0.5 ? Brightness.light : Brightness.dark;

  /// 从皮肤 JSON 解析主题。
  ///
  /// 兜底规则（保证不崩溃）：
  /// - 缺失的字段 → 用 `defaultTheme()` 的对应值，且**不**计入显式字段
  /// - 类型不对或无法解析的值 → 同样回落到默认值，且**不**计入显式字段
  /// - 颜色接受 `"#RRGGBB"` / `"#AARRGGBB"` 字符串，也兼容 ARGB 整数
  ///
  /// 只有成功解析出来的字段才会记入 [_explicitFields]，
  /// 因此一份"只写了 primary"的皮肤不会把其他字段覆盖成默认值。
  factory AppTheme.fromJson(Map<String, dynamic> json) {
    final AppTheme base = defaults.defaultTheme();
    final Set<String> explicit = <String>{};

    Color color(String key, Color fallback) {
      if (!json.containsKey(key)) return fallback;
      final Color? parsed = _tryParseColor(json[key]);
      if (parsed == null) return fallback;
      explicit.add(key);
      return parsed;
    }

    double number(String key, double fallback) {
      if (!json.containsKey(key)) return fallback;
      final double? parsed = _tryParseDouble(json[key]);
      if (parsed == null) return fallback;
      explicit.add(key);
      return parsed;
    }

    int integer(String key, int fallback) {
      if (!json.containsKey(key)) return fallback;
      final int? parsed = _tryParseInt(json[key]);
      if (parsed == null) return fallback;
      explicit.add(key);
      return parsed;
    }

    String text(String key, String fallback) {
      if (!json.containsKey(key)) return fallback;
      final Object? value = json[key];
      if (value is! String) return fallback;
      explicit.add(key);
      return value;
    }

    bool flag(String key, bool fallback) {
      if (!json.containsKey(key)) return fallback;
      final bool? parsed = _tryParseBool(json[key]);
      if (parsed == null) return fallback;
      explicit.add(key);
      return parsed;
    }

    List<Color> colors(String key, List<Color> fallback) {
      if (!json.containsKey(key)) return fallback;
      final List<Color>? parsed = _tryParseColorList(json[key]);
      // 空配色池没有意义，视为未设置，回落默认池。
      if (parsed == null || parsed.isEmpty) return fallback;
      explicit.add(key);
      return parsed;
    }

    return AppTheme(
      primary: color('primary', base.primary),
      secondary: color('secondary', base.secondary),
      background: color('background', base.background),
      surface: color('surface', base.surface),
      error: color('error', base.error),
      onPrimary: color('onPrimary', base.onPrimary),
      onBackground: color('onBackground', base.onBackground),
      courseCardColors:
          colors('courseCardColors', base.courseCardColors),
      examHighlight: color('examHighlight', base.examHighlight),
      homeworkHighlight: color('homeworkHighlight', base.homeworkHighlight),
      fontFamily: text('fontFamily', base.fontFamily),
      titleSize: number('titleSize', base.titleSize),
      bodySize: number('bodySize', base.bodySize),
      captionSize: number('captionSize', base.captionSize),
      fontWeightTitle: integer('fontWeightTitle', base.fontWeightTitle),
      cardRadius: number('cardRadius', base.cardRadius),
      buttonRadius: number('buttonRadius', base.buttonRadius),
      chipRadius: number('chipRadius', base.chipRadius),
      cardPadding: number('cardPadding', base.cardPadding),
      gridGap: number('gridGap', base.gridGap),
      sectionGap: number('sectionGap', base.sectionGap),
      cardShadowColor: color('cardShadowColor', base.cardShadowColor),
      cardShadowBlur: number('cardShadowBlur', base.cardShadowBlur),
      cardShadowOffsetY:
          number('cardShadowOffsetY', base.cardShadowOffsetY),
      timetableCellHeight:
          number('timetableCellHeight', base.timetableCellHeight),
      timetableTimeColumnWidth: number(
          'timetableTimeColumnWidth', base.timetableTimeColumnWidth),
      showWeekend: flag('showWeekend', base.showWeekend),
      timeFormat: text('timeFormat', base.timeFormat),
      explicitKeys: explicit,
    );
  }

  /// 序列化为皮肤 JSON。
  ///
  /// 颜色输出为 hex 字符串：不透明色写 `"#RRGGBB"`，带透明度写 `"#AARRGGBB"`。
  /// 输出包含**全部**字段，因此 `AppTheme.fromJson(theme.toJson())` 会得到一个
  /// 所有字段都显式设置的主题（用于持久化，语义正确）。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'primary': _colorToHex(primary),
      'secondary': _colorToHex(secondary),
      'background': _colorToHex(background),
      'surface': _colorToHex(surface),
      'error': _colorToHex(error),
      'onPrimary': _colorToHex(onPrimary),
      'onBackground': _colorToHex(onBackground),
      'courseCardColors':
          courseCardColors.map(_colorToHex).toList(growable: false),
      'examHighlight': _colorToHex(examHighlight),
      'homeworkHighlight': _colorToHex(homeworkHighlight),
      'fontFamily': fontFamily,
      'titleSize': titleSize,
      'bodySize': bodySize,
      'captionSize': captionSize,
      'fontWeightTitle': fontWeightTitle,
      'cardRadius': cardRadius,
      'buttonRadius': buttonRadius,
      'chipRadius': chipRadius,
      'cardPadding': cardPadding,
      'gridGap': gridGap,
      'sectionGap': sectionGap,
      'cardShadowColor': _colorToHex(cardShadowColor),
      'cardShadowBlur': cardShadowBlur,
      'cardShadowOffsetY': cardShadowOffsetY,
      'timetableCellHeight': timetableCellHeight,
      'timetableTimeColumnWidth': timetableTimeColumnWidth,
      'showWeekend': showWeekend,
      'timeFormat': timeFormat,
    };
  }

  /// 把 [other] 中**显式设置**过的字段叠加到 `this` 上，返回新主题。
  ///
  /// 判断依据是 [other] 的显式字段集合（由 `fromJson` 解析时记录）：
  /// 集合里有的字段用 `other` 的值，其余一律保留 `this` 的值。
  /// 合并结果的显式字段集合是两者的并集，因此可以安全地链式合并。
  AppTheme merge(AppTheme other) {
    final Set<String> o = other._explicitFields;
    if (o.isEmpty) return this;
    return AppTheme(
      primary: o.contains('primary') ? other.primary : primary,
      secondary: o.contains('secondary') ? other.secondary : secondary,
      background: o.contains('background') ? other.background : background,
      surface: o.contains('surface') ? other.surface : surface,
      error: o.contains('error') ? other.error : error,
      onPrimary: o.contains('onPrimary') ? other.onPrimary : onPrimary,
      onBackground:
          o.contains('onBackground') ? other.onBackground : onBackground,
      courseCardColors: o.contains('courseCardColors')
          ? other.courseCardColors
          : courseCardColors,
      examHighlight:
          o.contains('examHighlight') ? other.examHighlight : examHighlight,
      homeworkHighlight: o.contains('homeworkHighlight')
          ? other.homeworkHighlight
          : homeworkHighlight,
      fontFamily: o.contains('fontFamily') ? other.fontFamily : fontFamily,
      titleSize: o.contains('titleSize') ? other.titleSize : titleSize,
      bodySize: o.contains('bodySize') ? other.bodySize : bodySize,
      captionSize: o.contains('captionSize') ? other.captionSize : captionSize,
      fontWeightTitle: o.contains('fontWeightTitle')
          ? other.fontWeightTitle
          : fontWeightTitle,
      cardRadius: o.contains('cardRadius') ? other.cardRadius : cardRadius,
      buttonRadius:
          o.contains('buttonRadius') ? other.buttonRadius : buttonRadius,
      chipRadius: o.contains('chipRadius') ? other.chipRadius : chipRadius,
      cardPadding:
          o.contains('cardPadding') ? other.cardPadding : cardPadding,
      gridGap: o.contains('gridGap') ? other.gridGap : gridGap,
      sectionGap: o.contains('sectionGap') ? other.sectionGap : sectionGap,
      cardShadowColor: o.contains('cardShadowColor')
          ? other.cardShadowColor
          : cardShadowColor,
      cardShadowBlur: o.contains('cardShadowBlur')
          ? other.cardShadowBlur
          : cardShadowBlur,
      cardShadowOffsetY: o.contains('cardShadowOffsetY')
          ? other.cardShadowOffsetY
          : cardShadowOffsetY,
      timetableCellHeight: o.contains('timetableCellHeight')
          ? other.timetableCellHeight
          : timetableCellHeight,
      timetableTimeColumnWidth: o.contains('timetableTimeColumnWidth')
          ? other.timetableTimeColumnWidth
          : timetableTimeColumnWidth,
      showWeekend: o.contains('showWeekend') ? other.showWeekend : showWeekend,
      timeFormat: o.contains('timeFormat') ? other.timeFormat : timeFormat,
      explicitKeys: <String>{..._explicitFields, ...o},
    );
  }

  /// 返回指定明暗模式下的主题。
  ///
  /// **Phase 1 简化实现**：直接返回 `this`，不做颜色推导。
  /// 原因：`AppTheme` 只有一套颜色令牌，暗色配色要到 Phase 6 由
  /// `SkinPack.darkColors` 提供（届时按 [brightness] 选取色表并重算本方法）。
  /// 保留该方法是为了让调用方（Phase 1.4 的 `app.dart`）的接口先稳定下来。
  AppTheme withBrightness(Brightness brightness) => this;

  @override
  String toString() => 'AppTheme(primary: $primary, secondary: $secondary, '
      'background: $background, surface: $surface, error: $error, '
      'onPrimary: $onPrimary, onBackground: $onBackground, '
      'courseCardColors: ${courseCardColors.length} colors, '
      'examHighlight: $examHighlight, '
      'homeworkHighlight: $homeworkHighlight, fontFamily: $fontFamily, '
      'titleSize: $titleSize, bodySize: $bodySize, '
      'captionSize: $captionSize, fontWeightTitle: $fontWeightTitle, '
      'cardRadius: $cardRadius, buttonRadius: $buttonRadius, '
      'chipRadius: $chipRadius, cardPadding: $cardPadding, '
      'gridGap: $gridGap, sectionGap: $sectionGap, '
      'cardShadowColor: $cardShadowColor, cardShadowBlur: $cardShadowBlur, '
      'cardShadowOffsetY: $cardShadowOffsetY, '
      'timetableCellHeight: $timetableCellHeight, '
      'timetableTimeColumnWidth: $timetableTimeColumnWidth, '
      'showWeekend: $showWeekend, timeFormat: $timeFormat)';
}

/// 解析颜色：接受 `"#RRGGBB"` / `"#AARRGGBB"` 字符串（可省略 `#` 或写 `0x` 前缀），
/// 也接受 ARGB 整数与已经是 `Color` 的值。无法解析返回 `null`。
Color? _tryParseColor(Object? value) {
  if (value is Color) return value;
  if (value is int) return Color(value);
  if (value is! String) return null;

  String text = value.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('#')) {
    text = text.substring(1);
  } else if (text.startsWith('0x') || text.startsWith('0X')) {
    text = text.substring(2);
  }
  // 6 位补上不透明 alpha。
  if (text.length == 6) text = 'FF$text';
  if (text.length != 8) return null;

  final int? argb = int.tryParse(text, radix: 16);
  return argb == null ? null : Color(argb);
}

/// 把颜色序列化成 hex 字符串：不透明写 `"#RRGGBB"`，否则写 `"#AARRGGBB"`。
String _colorToHex(Color color) {
  final String hex =
      color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
  return hex.startsWith('FF') ? '#${hex.substring(2)}' : '#$hex';
}

/// 解析颜色列表，忽略无法解析的元素；非列表或全部失败返回 `null`。
List<Color>? _tryParseColorList(Object? value) {
  if (value is! List) return null;
  final List<Color> result = <Color>[];
  for (final Object? item in value) {
    final Color? parsed = _tryParseColor(item);
    if (parsed != null) result.add(parsed);
  }
  return result.isEmpty ? null : result;
}

/// 解析 double，兼容 `num` 与数字字符串。
double? _tryParseDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

/// 解析 int，兼容 `num` 与数字字符串。
int? _tryParseInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// 解析 bool，兼容 `0/1` 与 `"true"/"false"`。
bool? _tryParseBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String text = value.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
  }
  return null;
}