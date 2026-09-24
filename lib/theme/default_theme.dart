// 默认蓝色主题：内置主题的完整令牌取值，作为所有皮肤的合并基线
import 'package:flutter/material.dart';

import 'app_theme.dart';

// —— 配色（prompt: 02-theme.md 指定）——

/// 主色：Material Blue 600。
const Color _kPrimary = Color(0xFF1E88E5);

/// 次要色：Material Blue 400（比主色浅一档，用于强调）。
const Color _kSecondary = Color(0xFF42A5F5);

/// 页面背景：极浅的蓝灰，让白色卡片有层次。
const Color _kBackground = Color(0xFFF5F7FA);

/// 卡片 / 表面色。
const Color _kSurface = Color(0xFFFFFFFF);

/// 错误色。
const Color _kError = Color(0xFFE53935);

/// 主色之上的前景色。
const Color _kOnPrimary = Color(0xFFFFFFFF);

/// 背景之上的正文色。
const Color _kOnBackground = Color(0xFF212121);

/// 考试强调色。
const Color _kExamHighlight = Color(0xFFE53935);

/// 作业强调色。
const Color _kHomeworkHighlight = Color(0xFFFB8C00);

/// 成功 / 正常状态色：Material Green 600（Phase 3.5 新增，用于状态徽章）。
const Color _kSuccess = Color(0xFF43A047);

/// 警告状态色：Material Amber 800（Phase 3.5 新增，用于"已启用但未就绪"）。
const Color _kWarning = Color(0xFFF9A825);

/// 课程卡片配色池：Material 100 档的柔和色，保证深色文字可读。
const List<Color> _kCourseCardColors = <Color>[
  Color(0xFFE3F2FD),
  Color(0xFFFCE4EC),
  Color(0xFFE8F5E9),
  Color(0xFFFFF3E0),
  Color(0xFFF3E5F5),
  Color(0xFFE0F7FA),
  Color(0xFFFFF9C4),
  Color(0xFFFFEBEE),
];

// —— 字体 ——

/// 空字符串表示使用系统默认字体（中文环境下即系统中文字体）。
const String _kFontFamily = '';

/// 标题字号。
const double _kTitleSize = 18;

/// 正文字号。
const double _kBodySize = 14;

/// 辅助说明字号。
const double _kCaptionSize = 12;

/// 标题字重：600（SemiBold）。
const int _kFontWeightTitle = 600;

// —— 形状 ——

/// 卡片圆角。
const double _kCardRadius = 12;

/// 按钮圆角。
const double _kButtonRadius = 8;

/// 标签圆角。
const double _kChipRadius = 16;

// —— 间距 ——

/// 卡片内边距。
const double _kCardPadding = 12;

/// 网格间隙。
const double _kGridGap = 4;

/// 区块间距。
const double _kSectionGap = 16;

// —— 阴影 ——

/// 卡片阴影色：8% 透明度的黑色。
const Color _kCardShadowColor = Color(0x14000000);

/// 卡片阴影模糊半径。
const double _kCardShadowBlur = 8;

/// 卡片阴影垂直偏移。
const double _kCardShadowOffsetY = 2;

// —— 布局 ——

/// 课表单元格高度。
///
/// Phase 2.2b.1 由 64 提到 72：真机验收反馈卡片文字太小，
/// 而 64px 减去上下留白后放不下"课程名 + 教师 + 教室"三行。
/// `AppTheme` 是启动时构造的、不落盘，因此改默认值不影响已有数据。
const double _kTimetableCellHeight = 72;

/// 课表时间列宽度。
const double _kTimetableTimeColumnWidth = 40;

/// 默认显示周六周日。
const bool _kShowWeekend = true;

/// 24 小时制时间格式（`intl` DateFormat 模式）。
const String _kTimeFormat = 'HH:mm';

/// 内置默认蓝主题。
///
/// 它是主题合并的**基线**：`_explicitFields` 为空，因此
/// `defaultTheme().merge(skinTheme)` 的结果就是"默认值 + 皮肤显式覆盖的字段"。
///
/// 取值说明见本文件顶部的常量；`prompt: 02-theme.md` 只指定了配色，
/// 字体 / 形状 / 间距 / 阴影 / 布局的数值是按 Material 常见取值设定的。
AppTheme defaultTheme() => const AppTheme(
      primary: _kPrimary,
      secondary: _kSecondary,
      background: _kBackground,
      surface: _kSurface,
      error: _kError,
      onPrimary: _kOnPrimary,
      onBackground: _kOnBackground,
      courseCardColors: _kCourseCardColors,
      examHighlight: _kExamHighlight,
      homeworkHighlight: _kHomeworkHighlight,
      success: _kSuccess,
      warning: _kWarning,
      fontFamily: _kFontFamily,
      titleSize: _kTitleSize,
      bodySize: _kBodySize,
      captionSize: _kCaptionSize,
      fontWeightTitle: _kFontWeightTitle,
      cardRadius: _kCardRadius,
      buttonRadius: _kButtonRadius,
      chipRadius: _kChipRadius,
      cardPadding: _kCardPadding,
      gridGap: _kGridGap,
      sectionGap: _kSectionGap,
      cardShadowColor: _kCardShadowColor,
      cardShadowBlur: _kCardShadowBlur,
      cardShadowOffsetY: _kCardShadowOffsetY,
      timetableCellHeight: _kTimetableCellHeight,
      timetableTimeColumnWidth: _kTimetableTimeColumnWidth,
      showWeekend: _kShowWeekend,
      timeFormat: _kTimeFormat,
    );