# 任务：主题系统（Phase 1.2）

## 目标
在 `lib/theme/` 目录下生成主题系统文件。

## 要生成的文件

### 1. `lib/theme/app_theme.dart` — AppTheme
**字段（全部 final）**

颜色：
- `primary`, `secondary`, `background`, `surface`, `error` (Color)
- `onPrimary`, `onBackground` (Color)
- `courseCardColors` (List<Color>)
- `examHighlight`, `homeworkHighlight` (Color)

字体：
- `fontFamily` (String)
- `titleSize`, `bodySize`, `captionSize` (double)
- `fontWeightTitle` (int)

形状：
- `cardRadius`, `buttonRadius`, `chipRadius` (double)

间距：
- `cardPadding`, `gridGap`, `sectionGap` (double)

阴影：
- `cardShadowColor` (Color)
- `cardShadowBlur`, `cardShadowOffsetY` (double)

布局：
- `timetableCellHeight`, `timetableTimeColumnWidth` (double)
- `showWeekend` (bool)
- `timeFormat` (String)

**实现**
- 构造函数（所有字段 required）
- `AppTheme.fromJson(Map<String, dynamic> json)` — 从皮肤 JSON 解析
    - 颜色字段是 hex 字符串（如 `"#1E88E5"`），用工具函数 `_parseColor` 解析
    - 缺失字段用默认值兜底
    - 解析时记录哪些字段被显式设置（用 `Set<String> _explicitFields` 保存）
- `Map<String, dynamic> toJson()`
- `AppTheme merge(AppTheme other)` — 合并
    - `other` 中显式设置的字段覆盖 `this`
    - 通过 `other._explicitFields` 判断
- `AppTheme withBrightness(Brightness brightness)` — Phase 1 可以简单返回 this

**工具函数**（同一文件内私有）
- `Color _parseColor(String hex)` — 支持 `"#RRGGBB"` 和 `"#AARRGGBB"`

### 2. `lib/theme/default_theme.dart` — 默认主题
提供一个静态方法或工厂：
- `AppTheme.defaultTheme()` 返回默认蓝色主题

使用颜色：
- `primary: #1E88E5`
- `background: #F5F7FA`
- `surface: #FFFFFF`
- `error: #E53935`
- `onPrimary: #FFFFFF`
- `onBackground: #212121`
- `courseCardColors: ['#E3F2FD', '#FCE4EC', '#E8F5E9', '#FFF3E0', '#F3E5F5', '#E0F7FA', '#FFF9C4', '#FFEBEE']`
- `examHighlight: #E53935`
- `homeworkHighlight: #FB8C00`

### 3. `lib/theme/theme_engine.dart` — ThemeEngine
```dart
class ThemeEngine extends ChangeNotifier {
  AppTheme get current;
  
  Future<void> loadSkin(SkinPack skin);
  AppTheme preview(SkinPack skin);
  Future<void> reset();
  void applyTheme(AppTheme theme);
}
```

- 内部持有 `AppTheme _current = AppTheme.defaultTheme()`
- `loadSkin` 解析皮肤 JSON → merge 到默认主题 → notifyListeners
- `preview` 不改状态，直接返回合并结果
- 依赖 `lib/models/skin_pack.dart`（假设已存在或由本提示词一并生成）

### 4. `lib/theme/theme_extension.dart` — AppThemeExtension
```dart
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final AppTheme theme;
  
  AppThemeExtension({required this.theme});
  
  @override
  AppThemeExtension copyWith({AppTheme? theme});
  
  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t);
}
```

- `lerp` 可以直接返回 `this`（Phase 1 不做颜色渐变）

## 约束
- 严格遵循 `docs/CONTEXT.md` 的代码规范
- 所有字段 `final`
- `fromJson` 必须有兜底，缺失字段不能崩
- 不引入外部依赖（`SkinPack` 除外）
- 颜色解析工具函数放在 `app_theme.dart` 内部

## 输出
- 每个文件单独代码块
- 代码块前标注文件路径
- 完整输出
- 写完后额外输出 API 接口清单