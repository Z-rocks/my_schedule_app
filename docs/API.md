# 已实现接口清单（API）

> 本文件是"契约文档"。
> 每生成完一个类，就把它的公开接口追加到对应小节。
> 每次生成新代码前，把本文件内容作为上下文提供给 AI，确保字段名、方法名一致。
> 只列**公开**接口，不列私有方法。

- 最后更新：2026-09-21（Phase 1.1 模型 9 文件；1.2 主题 4 文件；1.3 状态管理 5 文件）

---

## lib/models/

### `time_place.dart` — TimePlace

一次课程安排的时间与地点（一节课可有多个）。

| 字段 | 类型 | 说明 |
|------|------|------|
| `day` | `int` | 星期几，1-7 表示周一到周日 |
| `startSession` | `int` | 起始节次，1-12 |
| `length` | `int` | 持续节数，至少为 1 |
| `room` | `String` | 上课地点，可能为空字符串 |
| `weeks` | `List<int>` | 解析后的周次列表，如 `[4, 6, 7, 8]` |
| `rawWeeksText` | `String` | 原始周次文本，如 `"4,6-14周"` |

构造：`const TimePlace({required day, required startSession, required length, required room, required weeks, required rawWeeksText})`

方法：
- `int get endSession` — 结束节次（含）
- `bool isActiveInWeek(int week)` — 该安排是否在 `week` 周生效
- `bool conflictsWith(TimePlace other)` — 同日且节次重叠
- `factory TimePlace.fromJson(Map<String, dynamic> json)`
- `Map<String, dynamic> toJson()`
- `TimePlace copyWith({int? day, int? startSession, int? length, String? room, List<int>? weeks, String? rawWeeksText})`

---

### `user_override.dart` — UserOverride

用户对某条原始数据（课程等）的覆盖层。字段为 `null` 表示"未覆盖"，回落到原始值。

| 字段 | 类型 | 说明 |
|------|------|------|
| `customName` | `String?` | 自定义课程名 |
| `customTeacher` | `String?` | 自定义教师名 |
| `customLocation` | `String?` | 自定义地点（考场 / 教室） |
| `customTime` | `DateTime?` | 自定义时间（考试开考时间等） |
| `customColor` | `int?` | 自定义颜色，ARGB 整数，如 `0xFF1E88E5` |
| `customCompleted` | `bool?` | 自定义完成状态（作业勾选），`null` 表示沿用原始值 |
| `note` | `String?` | 用户备注 |
| `hidden` | `bool` | 是否隐藏，默认 `false` |
| `customTimePlaces` | `List<TimePlace>?` | 自定义时间地点；空列表表示主动清空 |
| `updatedAt` | `DateTime` | 最后一次修改时间（构造时 `required`） |

构造：`const UserOverride({String? customName, String? customTeacher, String? customLocation, DateTime? customTime, int? customColor, bool? customCompleted, String? note, bool hidden = false, List<TimePlace>? customTimePlaces, required DateTime updatedAt})`

方法：
- `bool get isEmpty` — 是否为空覆盖层（用户什么都没改）
- `factory UserOverride.fromJson(Map<String, dynamic> json)`
- `Map<String, dynamic> toJson()` — `updatedAt` / `customTime` 存 ISO8601 字符串
- `UserOverride copyWith({..., bool clearCustomName, bool clearCustomTeacher, bool clearCustomLocation, bool clearCustomTime, bool clearCustomColor, bool clearCustomCompleted, bool clearNote, bool clearCustomTimePlaces})` — 因字段本身可空，用 `clearXxx` 开关显式清空某项覆盖

---

### `course.dart` — Course

一门课程。原始字段来自插件，用户修改全部放在 `userOverride` 中，二者分离存储。

常量：`const String kUserSourcePluginId = 'user'`

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 课程唯一 ID，建议 `"<插件ID>:<课程号>"` |
| `name` | `String` | 课程名 |
| `teacher` | `String` | 任课教师 |
| `unit` | `double` | 学分/学时 |
| `category` | `String` | 课程类别 |
| `timePlaces` | `List<TimePlace>` | 上课时间地点列表 |
| `sourcePluginId` | `String` | 来源插件 ID，用户自建为 `kUserSourcePluginId` |
| `userOverride` | `UserOverride?` | 用户覆盖层 |

构造：`const Course({required id, required name, required teacher, required unit, required category, required timePlaces, required sourcePluginId, UserOverride? userOverride})`

方法：
- `bool get isUserCreated`
- `bool get isHidden` — `userOverride?.hidden ?? false`
- `String get displayName` — `userOverride?.customName ?? name`
- `String get displayTeacher` — `userOverride?.customTeacher ?? teacher`
- `List<TimePlace> get displayTimePlaces` — `userOverride?.customTimePlaces ?? timePlaces`
- `int? get displayColor` — `userOverride?.customColor`（`null` 时由主题层按课程名哈希分配）
- `bool isActiveInWeek(int week)`
- `factory Course.fromJson(Map<String, dynamic> json)`
- `Map<String, dynamic> toJson()`
- `Course copyWith({... , bool clearUserOverride})`

> JSON 键名与字段名一致，均为 `userOverride`。

---

### `exam.dart` — Exam

一场考试。原始字段来自插件，用户修改放在 `userOverride` 中。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 考试唯一 ID |
| `name` | `String` | 考试科目名 |
| `startTime` | `DateTime` | 开考时间（`required`） |
| `endTime` | `DateTime?` | 结束时间，`null` 表示未知 |
| `location` | `String` | 考场地点 |
| `seatNumber` | `String` | 座位号 |
| `examType` | `String` | 形式，如 `"闭卷"` / `"开卷"` |
| `unit` | `double` | 学分 |
| `durationMinutes` | `int` | 时长（分钟） |
| `courseId` | `String` | 关联课程 ID |
| `sourcePluginId` | `String` | 来源插件 ID |
| `remindMinutesBefore` | `int` | 提前提醒分钟数，0 为不提醒 |
| `userOverride` | `UserOverride?` | 用户覆盖层 |

构造：`const Exam({required id, required name, required startTime, DateTime? endTime, String location = '', String seatNumber = '', String examType = '', double unit = 0, int durationMinutes = 0, String courseId = '', required sourcePluginId, int remindMinutesBefore = 0, UserOverride? userOverride})`

方法：
- `bool get isUserCreated` / `bool get isHidden`
- `String get displayName` / `String get displayLocation` / `DateTime get displayStartTime` / `int? get displayColor`
- `DateTime get effectiveEndTime` — 优先 `endTime`，否则 `displayStartTime + durationMinutes`
- `bool hasStarted(DateTime now)`
- `Duration timeUntil(DateTime now)` — 已开始返回 `Duration.zero`
- `int daysUntil(DateTime now)` — 向上取整，已开始返回 0
- `factory Exam.fromJson(Map<String, dynamic> json)`
- `Map<String, dynamic> toJson()`
- `Exam copyWith({..., bool clearEndTime, bool clearUserOverride})`

---

### `homework.dart` — Homework

一项作业。原始字段来自插件，用户修改放在 `userOverride` 中。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 作业唯一 ID |
| `title` | `String` | 标题 |
| `description` | `String` | 作业要求 |
| `courseName` | `String` | 所属课程名 |
| `courseId` | `String` | 关联课程 ID |
| `deadline` | `DateTime?` | 截止时间，`null` 表示无截止 |
| `publishTime` | `DateTime?` | 发布时间 |
| `completed` | `bool` | 是否已完成，默认 `false` |
| `submitStatus` | `String` | 提交状态原文 |
| `attachments` | `List<String>` | 附件名列表，默认空 |
| `sourcePluginId` | `String` | 来源插件 ID |
| `remindMinutesBefore` | `int` | 提前提醒分钟数 |
| `userOverride` | `UserOverride?` | 用户覆盖层 |

构造：`const Homework({required id, required title, String description = '', String courseName = '', String courseId = '', DateTime? deadline, DateTime? publishTime, bool completed = false, String submitStatus = '', List<String> attachments = const [], required sourcePluginId, int remindMinutesBefore = 0, UserOverride? userOverride})`

方法：
- `bool get isUserCreated` / `bool get isHidden` / `bool get isCompleted`（`userOverride?.customCompleted ?? completed`）
- `String get displayTitle` / `int? get displayColor`
- `DateTime? get displayDeadline` — 用户可改期
- `bool isOverdue(DateTime now)` — 已逾期且未完成
- `Duration? timeUntilDeadline(DateTime now)` — 无截止返回 `null`，已逾期返回 `Duration.zero`
- `int daysUntilDeadline(DateTime now)`
- `factory Homework.fromJson(Map<String, dynamic> json)`
- `Map<String, dynamic> toJson()`
- `Homework copyWith({..., bool clearDeadline, bool clearPublishTime, bool clearUserOverride})`

---

### `message.dart` — MessageType + Message

#### `enum MessageType`
取值：`course`（上课提醒）、`exam`（考试提醒）、`homework`（作业提醒）、`grade`（成绩通知）、`system`（系统通知）、`other`（其他）。

- `static MessageType fromName(Object? value)` — 安全解析字符串，无法识别返回 `MessageType.other`
- `String get label` — 中文展示标签

#### `class Message`

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 消息唯一 ID |
| `type` | `MessageType` | 消息类型 |
| `title` | `String` | 标题 |
| `body` | `String` | 正文 |
| `createdAt` | `DateTime` | 产生时间（`required`） |
| `read` | `bool` | 是否已读，默认 `false` |
| `targetId` | `String` | 关联目标 ID |
| `sourcePluginId` | `String` | 来源插件 ID，内核产生为 `'system'` |
| `extra` | `Map<String, dynamic>` | 附加数据，默认空 Map |

构造：`const Message({required id, required type, required title, String body = '', required createdAt, bool read = false, String targetId = '', String sourcePluginId = 'system', Map<String, dynamic> extra = const {}})`

方法：
- `bool get isUnread` / `bool get isSystem` / `bool get hasTarget`
- `bool isToday(DateTime now)`
- `factory Message.fromJson(Map<String, dynamic> json)` — `type` 存枚举名字符串
- `Map<String, dynamic> toJson()`
- `Message copyWith({...})`

---

### `module.dart` — ModuleType + ModuleInfo

#### `enum ModuleType`
取值：`timetable`（课表）、`courseList`（课程）、`exam`（考试）、`homework`（作业）、`message`（消息）、`settings`（设置）。

- `static ModuleType? fromName(Object? value)` — 安全解析，无法识别返回 `null`（视为插件自定义能力）
- `String get defaultTitle` — 默认中文标题
- `bool get canDisable` — 课表、设置返回 `false`（不可关闭）
- `bool get isDefaultEnabled` — 课表 / 课程 / 考试 / 设置默认开启
- `bool get isBuiltIn` — 恒为 `true`

#### `class ModuleInfo`

| 字段 | 类型 | 说明 |
|------|------|------|
| `capabilityId` | `String` | 模块唯一标识：内置用 `ModuleType.name`，插件用 `"<插件ID>.<能力名>"` |
| `type` | `ModuleType?` | 内置模块类型；插件能力为 `null` |
| `title` | `String` | 导航栏标题，用户可改 |
| `iconName` | `String` | Material 图标名，如 `"calendar_month"`（模型层不依赖 Flutter） |
| `enabled` | `bool` | 是否显示在导航栏 |
| `available` | `bool` | 能力是否被提供（内置恒 `true`；考试/作业需插件声明）。与 `enabled` 区分：只有 `available && enabled` 才真正显示 |
| `order` | `int` | 排序位置，越小越靠前 |
| `isBuiltIn` | `bool` | 是否内核内置 |
| `sourcePluginId` | `String` | 提供该模块的插件 ID |
| `alwaysOn` | `bool` | 是否常驻（课表 / 设置），常驻模块不可关闭 |

构造：`const ModuleInfo({required capabilityId, ModuleType? type, required title, String iconName = '', bool enabled = false, bool available = true, int order = 0, bool isBuiltIn = true, String sourcePluginId = '', bool alwaysOn = false})`

工厂：`factory ModuleInfo.fromType(ModuleType type, {bool? enabled, bool available = true, int order = 0})` — 默认值取自枚举

方法：
- `bool get isVisible` — `available && enabled`
- `bool get isFromPlugin`
- `ModuleInfo withEnabled(bool value)` — 常驻模块强制保持 `true`
- `ModuleInfo withAvailable(bool value)`
- `factory ModuleInfo.fromJson(Map<String, dynamic> json)`
- `Map<String, dynamic> toJson()` — `type` 存枚举名，插件模块为 `null`
- `ModuleInfo copyWith({...})`

---

### `plugin_meta.dart` — PluginMeta

一个插件（`.js` 文件）的元数据。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 插件唯一 ID，如 `"ncst-jwxt"` |
| `name` | `String` | 显示名 |
| `version` | `String` | 版本号，默认 `'0.0.0'` |
| `author` / `description` / `school` | `String` | 作者 / 说明 / 适用学校 |
| `capabilities` | `List<String>` | **数据能力 ID 列表**，如 `['exam', 'homework']`（扁平声明，无 UI 信息） |
| `modules` | `List<ModuleInfo>` | 插件贡献的导航栏模块（含标题/图标/排序等 UI 元数据） |
| `entryFile` | `String` | 入口文件名 |
| `assetPath` | `String` | 本地路径 |
| `source` | `String` | `"builtin"` / `"workshop"` / `"local"` |
| `downloadUrl` | `String` | 商店原始 URL |
| `hasUpdate` | `bool` | 是否有更新 |
| `latestVersion` | `String` | 商店最新版本 |
| `enabled` | `bool` | 是否启用 |
| `installedAt` | `DateTime` | 安装时间（`required`） |
| `lastSyncAt` | `DateTime?` | 最近同步时间 |

构造：`const PluginMeta({required id, required name, String version = '0.0.0', String author = '', String description = '', String school = '', List<String> capabilities = const [], List<ModuleInfo> modules = const [], String entryFile = '', String assetPath = '', String source = 'local', String downloadUrl = '', bool hasUpdate = false, String latestVersion = '', bool enabled = false, required DateTime installedAt, DateTime? lastSyncAt})`

方法：
- `bool get isBuiltIn` / `bool get isFromWorkshop` / `bool get hasSynced` / `bool get hasModules`
- `Set<String> get effectiveCapabilities` — `capabilities` ∪ 各 `modules` 的 `capabilityId`（两种声明方式都支持，忽略空串）
- `bool get hasCapabilities` — `effectiveCapabilities.isNotEmpty`
- `factory PluginMeta.fromJson(Map<String, dynamic> json)` — `modules` 兼容 `ModuleInfo` Map 与纯字符串能力 ID；`capabilities` 忽略 `null` 与空串
- `Map<String, dynamic> toJson()`
- `PluginMeta copyWith({..., bool clearLastSyncAt})`

---

### `skin_pack.dart` — SkinPack

一份皮肤包（`.skin.json`）。颜色一律为 ARGB 整数，模型层不依赖 Flutter。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 皮肤唯一 ID |
| `name` | `String` | 显示名 |
| `version` | `String` | 版本号，默认 `'1.0.0'` |
| `author` / `description` | `String` | 作者 / 说明 |
| `previewImage` | `String` | 预览图路径或 URL |
| `lightColors` | `Map<String, int>` | 亮色令牌 → ARGB |
| `darkColors` | `Map<String, int>` | 暗色令牌 → ARGB |
| `courseColors` | `List<int>` | 课程卡片配色池 |
| `borderRadius` | `double` | 圆角，默认 12 |
| `elevation` | `double` | 卡片阴影，默认 0 |
| `fontFamily` | `String` | 字体族，空为系统默认 |
| `mode` | `String` | `"light"` / `"dark"` / `"system"` |
| `source` | `String` | `"builtin"` / `"workshop"` / `"local"` |
| `installedAt` | `DateTime` | 安装时间（`required`） |

构造：`const SkinPack({required id, required name, String version = '1.0.0', String author = '', String description = '', String previewImage = '', Map<String, int> lightColors = const {}, Map<String, int> darkColors = const {}, List<int> courseColors = const [], double borderRadius = 12, double elevation = 0, String fontFamily = '', String mode = 'system', String source = 'local', required DateTime installedAt})`

方法：
- `bool get isBuiltIn` / `bool get isFromWorkshop` / `bool get supportsDarkMode` / `bool get hasCustomFont` / `bool get hasCourseColors`
- `int lightColor(String token, {required int fallback})`
- `int darkColor(String token, {required int fallback})` — 缺失时回落亮色
- `int? colorForCourse(String courseName)` — 按课程名哈希取色，配色池为空返回 `null`
- `factory SkinPack.fromJson(Map<String, dynamic> json)` — 颜色兼容 ARGB 整数与 `"#1E88E5"` / `"#FF1E88E5"` 字符串
- `Map<String, dynamic> toJson()`
- `SkinPack copyWith({...})`

---

## lib/theme/

### `app_theme.dart` — AppTheme

App 的全部视觉令牌集合，不可变（28 个字段）。UI 必须经 `AppThemeExtension.of(context)` 读取，禁止硬编码。

**颜色**

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `primary` | `Color` | `#1E88E5` | 主色 |
| `secondary` | `Color` | `#42A5F5` | 次要色 / 强调色 |
| `background` | `Color` | `#F5F7FA` | 页面背景 |
| `surface` | `Color` | `#FFFFFF` | 卡片 / 表面 |
| `error` | `Color` | `#E53935` | 错误色 |
| `onPrimary` | `Color` | `#FFFFFF` | 主色之上的前景色 |
| `onBackground` | `Color` | `#212121` | 背景之上的正文色 |
| `courseCardColors` | `List<Color>` | 8 色（`#E3F2FD`/`#FCE4EC`/`#E8F5E9`/`#FFF3E0`/`#F3E5F5`/`#E0F7FA`/`#FFF9C4`/`#FFEBEE`） | 课程卡片配色池 |
| `examHighlight` | `Color` | `#E53935` | 考试强调色 |
| `homeworkHighlight` | `Color` | `#FB8C00` | 作业强调色 |

**字体 / 形状 / 间距 / 阴影 / 布局**

| 字段 | 类型 | 默认值 |
|------|------|--------|
| `fontFamily` | `String` | `''`（系统默认） |
| `titleSize` / `bodySize` / `captionSize` | `double` | `18` / `14` / `12` |
| `fontWeightTitle` | `int` | `600` |
| `cardRadius` / `buttonRadius` / `chipRadius` | `double` | `12` / `8` / `16` |
| `cardPadding` / `gridGap` / `sectionGap` | `double` | `12` / `4` / `16` |
| `cardShadowColor` | `Color` | `#14000000` |
| `cardShadowBlur` / `cardShadowOffsetY` | `double` | `8` / `2` |
| `timetableCellHeight` / `timetableTimeColumnWidth` | `double` | `64` / `40` |
| `showWeekend` | `bool` | `true` |
| `timeFormat` | `String` | `'HH:mm'` |

构造：`const AppTheme({...28 个字段全部 required..., Set<String> explicitKeys = const {}})` — `explicitKeys` 供 `fromJson` / `merge` 内部使用，业务代码留空。

方法：
- `static AppTheme defaultTheme()` — 内置默认蓝主题（合并基线）
- `Set<String> get explicitFields` — 被显式设置的字段名只读视图
- `Brightness get brightness` — 由 `background` 亮度推断
- `factory AppTheme.fromJson(Map<String, dynamic> json)` — 缺失/非法字段回落默认值且不计入显式字段；颜色接受 `"#RRGGBB"` / `"#AARRGGBB"` / 无 `#` / `0x` 前缀 / ARGB 整数
- `Map<String, dynamic> toJson()` — 颜色输出 hex（不透明写 `#RRGGBB`，否则 `#AARRGGBB`）；输出全部 28 个键
- `AppTheme merge(AppTheme other)` — 仅 `other` 显式设置的字段覆盖 `this`；结果显式字段为并集
- `AppTheme withBrightness(Brightness brightness)` — **Phase 1 简化实现：返回 `this`**（暗色配色留待 Phase 6 由 `SkinPack.darkColors` 提供）

---

### `default_theme.dart` — 默认蓝主题

- `AppTheme defaultTheme()` — 返回内置默认蓝主题。全部取值为编译期常量，`explicitFields` 为空，因此它是主题合并的**基线**：`defaultTheme().merge(skinTheme)` = 默认值 + 皮肤显式覆盖的字段。

---

### `theme_engine.dart` — ThemeEngine（`ChangeNotifier`）

把 `SkinPack` 解析成 `AppTheme` 并管理"当前主题"状态。

- `AppTheme get current` — 当前生效主题
- `String get currentSkinId` — 当前皮肤 ID，`''` 表示内置默认（Phase 2 持久化到 Hive `settings`）
- `Future<void> loadSkin(SkinPack skin)` — 皮肤 → 主题 JSON → `fromJson` → merge 到默认主题 → `notifyListeners()`；异常被捕获并 `debugPrint`，保持原主题不崩
- `AppTheme preview(SkinPack skin)` — 返回合并结果，**不改状态**（与 `loadSkin` 结果一致）
- `Future<void> reset()` — 恢复默认主题
- `void applyTheme(AppTheme theme)` — 直接应用已构造的主题（并清空 `currentSkinId`）

皮肤令牌映射（私有，见 `_kSkinTokenAliases`）：

| 皮肤令牌 | AppTheme 字段 |
|----------|---------------|
| `card` | `surface` |
| `textPrimary` / `textSecondary` | `onBackground` |
| `courseColors` | `courseCardColors` |
| 其余同名令牌（`primary`/`background`/`error`/…） | 直接同名映射 |

其他映射：`borderRadius` → `cardRadius`；`fontFamily` → `fontFamily`（非空才映射）；`elevation` → `cardShadowOffsetY`；`mode == 'dark'` 且有 `darkColors` 时选暗色表，否则用 `lightColors`。

---

### `theme_extension.dart` — AppThemeExtension（`ThemeExtension<AppThemeExtension>`）

把 `AppTheme` 注册进 `ThemeData.extensions`。

- `final AppTheme theme`
- `const AppThemeExtension({required AppTheme theme})`
- `static AppTheme of(BuildContext context)` — 读当前主题；未注册扩展时回退 `AppTheme.defaultTheme()`
- `static AppTheme? maybeOf(BuildContext context)` — 未注册返回 `null`
- `AppThemeExtension copyWith({AppTheme? theme})`
- `AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t)` — **Phase 1 简化实现：返回 `this`**（不做插值）

---

## lib/providers/

### `module_provider.dart` — ModuleProvider（`ChangeNotifier`）

导航栏模块状态。不引用其他 Provider；插件能力经 `updateCapabilities` 外部注入。

常量：`const int kMaxModules = 5`（CONTEXT 4.1 建议 `MAX_MODULES`，但 `constant_identifier_names` lint 会报 info，故用 `k` 前缀）

初始状态：

| type | alwaysOn | 初始 available | 初始 enabled |
|------|:--------:|:--------------:|:------------:|
| timetable | ✅ | true | true |
| courseList | ❌ | true | true |
| exam | ❌ | true | true |
| homework | ❌ | **false**（必须插件） | false |
| message | ❌ | true | **false**（默认关闭） |
| settings | ✅ | true | true |

全新安装的 `visibleModules` = **课表 → 课程 → 考试 → 设置**（4 个）。

- `List<ModuleInfo> get allModules` — 全部模块（含不可用），顺序与初始定义一致，不可变视图
- `List<ModuleInfo> get visibleModules` — 导航栏实际显示。**选择规则**：常驻模块永远包含；非常驻需 `available && enabled`；总数最多 `kMaxModules`，超出时优先保留常驻、其余按模块列表顺序取。**输出顺序**：始终按 `_modules` 原始顺序（timetable → courseList → exam → homework → message → settings），而非"常驻在前、可选在后"，保证 toggle 时导航栏顺序不跳动
- `int get visibleCount`
- `ModuleInfo? getByType(ModuleType type)`
- `void toggle(ModuleType type, bool enabled)` — 常驻模块（课表/设置）为**空操作**，不可关闭
- `void updateCapabilities(Set<String> capabilities)` — 当前**只调整 `homework`**：能力含 `'homework'` → `available = true`。`timetable`/`courseList`/`message` 是内置能力恒可用；`exam` 是插件可选增强（无插件也能手动添加考试），不由此方法改变
- `void resetToDefaults()` — 恢复初始配置

---

### `course_provider.dart` — CourseProvider（`ChangeNotifier`）

课程列表状态。**Phase 1 仅内存**，不接 Hive，重启清空。

- `List<Course> get courses` — 全部课程（含隐藏），不可变视图
- `List<Course> get visibleCourses` — 过滤 `userOverride?.hidden == true`（即 `Course.isHidden`）
- `int get hiddenCount` / `int get length`
- `Course? getById(String id)`
- `void setCourses(List<Course> list)`
- `void addCourse(Course c)` — 同 id 已存在则替换
- `void updateCourse(Course c)` — 按 id 定位；找不到则按新增处理（upsert）
- `void deleteCourse(String id)` — 教务课程应改用 `userOverride.hidden`，见 CONTEXT 3.3
- `void clear()`

---

### `theme_provider.dart` — ThemeProvider（`ChangeNotifier`）

包装 `ThemeEngine`（Phase 1.2）。

构造：`ThemeProvider({ThemeEngine? engine})` — 可注入外部引擎（测试用），默认自建

- `AppTheme get currentTheme`
- `String get currentSkinId` — `''` 表示内置默认主题
- `Brightness get brightness` — 用户明暗偏好，默认 `Brightness.light`
- `AppTheme get themedForBrightness` — `currentTheme.withBrightness(brightness)`
- `Future<void> applySkin(SkinPack skin)` — 调 `engine.loadSkin` 后 `notifyListeners`
- `Future<void> resetTheme()` — 调 `engine.reset` 后 `notifyListeners`
- `void setBrightness(Brightness b)` — 同值不通知
- `AppTheme previewSkin(SkinPack skin)` — 不改状态、不通知
- `dispose()` 会一并 `dispose()` 内部引擎

---

### `plugin_provider.dart` — PluginProvider（`ChangeNotifier`）

已安装插件状态。**Phase 1 为空列表**，只提供接口。

构造：`PluginProvider({List<PluginMeta>? plugins})`

- `List<PluginMeta> get plugins` — 全部插件（含未启用），不可变视图
- `List<PluginMeta> get enabledPlugins`
- `Set<String> get allCapabilities` — 已启用插件的 `effectiveCapabilities` 并集（`capabilities` ∪ `modules` 能力），不可变集合
- `int get enabledCount` / `int get updatableCount`
- `PluginMeta? getById(String id)`
- `void addPlugin(PluginMeta p)` — 同 id 则替换
- `void removePlugin(String id)` — 内置插件（`isBuiltIn`）不可卸载
- `void togglePlugin(String id, bool enabled)`
- `void clear()`

---

### `message_provider.dart` — MessageProvider（`ChangeNotifier`）

消息列表状态。**Phase 1 仅内存**。

常量：`const int kMessageRetentionDays = 30`

- `List<Message> get messages` — **始终按 `createdAt` 倒序**（新的在前；同时间按 id 稳定排序），不可变视图
- `int get unreadCount` / `int get length`
- `Message? getById(String id)`
- `void addMessage(Message m)` — 同 id 替换，插入后重排
- `void markAsRead(String id)` — 已读或不存在的 id 为空操作
- `void markAllAsRead()` — 无未读时不通知
- `int clearOldMessages({DateTime? now})` — 删除早于 `now - 30 天` 的消息，返回删除条数；`now` 供测试注入
- `void removeMessage(String id)` / `void clear()`

---

## lib/pages/

（待填充）

---

## lib/widgets/

（待填充）