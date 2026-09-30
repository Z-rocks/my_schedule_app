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

  /// 成功 / 正常状态色（Phase 3.5 新增）。
  ///
  /// 用于状态徽章、加载成功提示等"一切正常"的语义。
  /// 加这个令牌是因为 CONTEXT 3.2 禁止 UI 硬编码颜色，而原主题没有绿色。
  final Color success;

  /// 警告状态色（Phase 3.5 新增）。
  ///
  /// 用于"已启用但尚未就绪""需要用户注意但不算错误"的语义。
  final Color warning;

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
    required this.success,
    required this.warning,
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
    @protected Set<String> explicitKeys = const <String>{},
  }) : _explicitFields = explicitKeys;

  /// 内置默认蓝主题。实现位于 `default_theme.dart`。
  static AppTheme defaultTheme() => defaults.defaultTheme();

  /// 标题字重的类型化取值（由 [fontWeightTitle] 换算而来）。
  ///
  /// [fontWeightTitle] 用 int 是为了 JSON 序列化，UI 侧需要 `FontWeight`。
  /// 在这里统一换算，避免各页面 / 组件各写一份（CONTEXT.md 3.2 要求字体
  /// 也从主题读，不允许硬编码字重）。
  FontWeight get titleFontWeight {
    // FontWeight.values == [w100, w200, ..., w900]。
    // 只接受 100 的整数倍（100..900）；非法值（0、150、999 等）回落 w400，
    // 而不是被 ~/ 静默截断成别的字重。
    if (fontWeightTitle % 100 != 0) return FontWeight.w400;
    final int index = (fontWeightTitle ~/ 100) - 1;
    if (index < 0 || index >= FontWeight.values.length) {
      return FontWeight.w400;
    }
    return FontWeight.values[index];
  }

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
      success: color('success', base.success),
      warning: color('warning', base.warning),
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
      'success': _colorToHex(success),
      'warning': _colorToHex(warning),
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
      success: o.contains('success') ? other.success : success,
      warning: o.contains('warning') ? other.warning : warning,
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

  /// 返回指定明暗模式下的主题（**Phase 6 起为真实实现**）。
  ///
  /// 设计取舍：**不把两套配色都写成常量**，而是从已有令牌**推导**另一套。
  /// 原因：皮肤（`SkinPack`）只提供一套（或明暗两套）色表，
  /// 若这里写死一套暗色常量，皮肤的颜色就会被常量覆盖掉——那就不叫皮肤了。
  /// 推导能保证：**皮肤选什么色相，暗色模式就跟着什么色相**，
  /// 而明暗关系（背景深 / 文字浅 / 卡片分层）始终正确。
  ///
  /// 推导规则（只动"明暗相关"的令牌，强调色一律保留皮肤的取值）：
  ///
  /// | 令牌 | 规则 |
  /// |------|------|
  /// | `background` | 目标暗色 → HSL 亮度压到 [kDarkBackgroundLightness] |
  /// | `surface` | 同上，但比背景**略亮**，保证卡片有层次 |
  /// | `onBackground` / `onPrimary` | 目标亮色 → 压暗（深色文字）；目标暗色 → 提亮 |
  /// | `courseCardColors` | 同上按目标模式调整（浅色卡配深字 / 深色卡配浅字） |
  /// | `cardShadowColor` | 暗色下阴影要更明显（暗背景上 8% 黑几乎看不见） |
  /// | `primary` / `secondary` / `error` / `success` / `warning` | **不动** |
  ///
  /// 已经是目标模式时返回 `this`（避免无意义地重建对象）。
  AppTheme withBrightness(Brightness brightness) {
    if (this.brightness == brightness) return this;
    final bool toDark = brightness == Brightness.dark;

    return AppTheme(
      // 强调色保留：皮肤的色相是它的身份
      primary: primary,
      secondary: secondary,
      error: error,
      examHighlight: examHighlight,
      homeworkHighlight: homeworkHighlight,
      success: success,
      warning: warning,
      // 背景 / 表面：按目标模式重算明度
      background: toDark
          ? _withLightness(background, kDarkBackgroundLightness)
          : _withLightness(background, kLightBackgroundLightness),
      surface: toDark
          ? _withLightness(background, kDarkSurfaceLightness)
          : _withLightness(background, kLightSurfaceLightness),
      // 前景色：主色之上的文字要保证可读（与明暗无关，取对比色即可）
      onPrimary: _legibleOn(primary),
      onBackground: _contrastTextOn(
        toDark
            ? _withLightness(background, kDarkBackgroundLightness)
            : _withLightness(background, kLightBackgroundLightness),
      ),
      // 课程卡片配色池：整池按目标模式调整
      courseCardColors: courseCardColors
          .map((Color c) =>
              toDark ? _withLightness(c, kDarkCardLightness) : c)
          .toList(growable: false),
      fontFamily: fontFamily,
      titleSize: titleSize,
      bodySize: bodySize,
      captionSize: captionSize,
      fontWeightTitle: fontWeightTitle,
      cardRadius: cardRadius,
      buttonRadius: buttonRadius,
      chipRadius: chipRadius,
      cardPadding: cardPadding,
      gridGap: gridGap,
      sectionGap: sectionGap,
      cardShadowColor: toDark ? kDarkShadowColor : cardShadowColor,
      cardShadowBlur: cardShadowBlur,
      cardShadowOffsetY: cardShadowOffsetY,
      timetableCellHeight: timetableCellHeight,
      timetableTimeColumnWidth: timetableTimeColumnWidth,
      showWeekend: showWeekend,
      timeFormat: timeFormat,
      // 显式字段集合原样带过去：`withBrightness` 只是换一套取值，
      // 不改变"这个主题由皮肤显式指定了哪些字段"的事实。
      explicitKeys: _explicitFields,
    );
  }

  // ———————————— 明暗推导用的取值（Phase 6） ————————————

  /// 暗色模式的页面背景亮度（0–1）。压得很低但保留色相，皮肤色调仍在。
  static const double kDarkBackgroundLightness = 0.10;

  /// 暗色模式的卡片 / 表面亮度：比背景略亮，卡片才有层次。
  static const double kDarkSurfaceLightness = 0.16;

  /// 亮色模式的页面 / 表面亮度（把皮肤给的颜色校正到"确实是浅色"）。
  static const double kLightBackgroundLightness = 0.97;
  static const double kLightSurfaceLightness = 1.0;

  /// 暗色模式下课程卡片底色亮度：够深，才能承载浅色文字。
  static const double kDarkCardLightness = 0.26;

  /// 暗色模式下的卡片阴影：黑 40%，比亮色模式的 8% 明显得多
  /// （暗背景上低透明度阴影完全看不见）。
  static const Color kDarkShadowColor = Color(0x66000000);

  @override
  String toString() => 'AppTheme(primary: $primary, secondary: $secondary, '
      'background: $background, surface: $surface, error: $error, '
      'onPrimary: $onPrimary, onBackground: $onBackground, '
      'courseCardColors: ${courseCardColors.length} colors, '
      'examHighlight: $examHighlight, '
      'homeworkHighlight: $homeworkHighlight, '
      'success: $success, warning: $warning, fontFamily: $fontFamily, '
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

/// 把颜色搬到指定 HSL 亮度上（保留色相与饱和度）。
///
/// 这是明暗推导的核心：**只改明度、不动色相**，所以皮肤的色调在暗色模式下
/// 依然认得出（蓝色皮肤暗色下还是蓝的，不会变成中性灰）。
///
/// 灰色（饱和度 0）也能正确处理——HSL 转换对无彩色一样成立。
Color _withLightness(Color color, double lightness) {
  final HSLColor hsl = HSLColor.fromColor(color);
  return hsl.withLightness(lightness.clamp(0.0, 1.0)).toColor();
}

/// 在给定背景色上取"可读的正文色"。
///
/// 判据是背景的相对亮度（`computeLuminance`，已含 sRGB 线性化，
/// 比直接看 HSL 亮度更贴近人眼感受）：背景偏暗 → 用浅色文字，反之用深色。
///
/// 用 [kDarkModeTextOn] / [kLightModeTextOn] 这两个"接近纯白 / 纯黑"的取值，
/// 而不是动态反色——纯反色会得到彩色文字（例如深蓝底反成浅黄），
/// 正文色应当是中性且高对比的。
Color _contrastTextOn(Color background) =>
    background.computeLuminance() > 0.5 ? kLightModeTextOn : kDarkModeTextOn;

/// 亮背景上的正文色（近黑，带一点柔和不刺眼）。
const Color kLightModeTextOn = Color(0xFF1A1A1A);

/// 暗背景上的正文色（近白，避免纯白在暗色下过于刺眼）。
const Color kDarkModeTextOn = Color(0xFFEDEDED);

/// 取"叠在 [background] 上仍可读"的前景色（用于 `onPrimary`）。
///
/// 与 [_contrastTextOn] 的关系：这里返回**纯白或纯黑**，
/// 因为主色之上的通常是按钮文字 / 图标，需要最大对比度。
Color _legibleOn(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

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