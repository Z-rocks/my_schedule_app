# 已实现接口清单（API）

> 本文件是"契约文档"。
> 每生成完一个类，就把它的公开接口追加到对应小节。
> 每次生成新代码前，把本文件内容作为上下文提供给 AI，确保字段名、方法名一致。
> 只列**公开**接口，不列私有方法。

- 最后更新：2026-09-22（1.1–1.6 内核骨架；2.1 存储层；2.1.5 配置落盘；2.2a 学期配置 + 周次解析 + 网格）

---

## lib/models/

### `time_place.dart` — WeekType + TimePlace

#### `enum WeekType`
取值：`all`（每周）、`odd`（单周）、`even`（双周）。
- `static WeekType fromName(Object? value)` — 安全解析字符串，无法识别返回 `WeekType.all`
- `String get label` — 中文标签（`每周` / `单周` / `双周`）

> 与 `TimePlace.weeks` 的分工：`weeks` 是**基础周次**（不做单双过滤），单双周由 `WeekType` 记录、由 `TimetableLogic.hasClassInWeek` 过滤，因此同一份周次数据只存一次。

#### `class TimePlace`

一次课程安排的时间与地点（一节课可有多个）。

| 字段 | 类型 | 说明 |
|------|------|------|
| `day` | `int` | 星期几，1-7 表示周一到周日 |
| `startSession` | `int` | 起始节次，1-12 |
| `length` | `int` | 持续节数，至少为 1 |
| `room` | `String` | 上课地点，可能为空字符串 |
| `weeks` | `List<int>` | **基础**周次列表（未按单双过滤），如 `[4, 6, 7, 8]` |
| `rawWeeksText` | `String` | 原始周次文本，如 `"4,6-14周"` |
| `weekType` | `WeekType` | 单双周，默认 `WeekType.all` |

构造：`const TimePlace({required day, required startSession, required length, required room, required weeks, required rawWeeksText, WeekType weekType = WeekType.all})`

方法：
- `int get endSession` — 结束节次（含）
- `bool isActiveInWeek(int week)` — 该安排是否在 `week` 周生效（**只看基础周次，不叠加单双周**）
- `bool conflictsWith(TimePlace other)` — 同日且节次重叠
- `factory TimePlace.fromJson(Map<String, dynamic> json)` — 缺失 `weekType` 或值非法时回落 `WeekType.all`（兼容旧数据）
- `Map<String, dynamic> toJson()` — `weekType` 存 `'all' / 'odd' / 'even'`
- `TimePlace copyWith({int? day, int? startSession, int? length, String? room, List<int>? weeks, String? rawWeeksText, WeekType? weekType})`

---

### `semester_config.dart` — SemesterConfig

学期配置。**当前只支持单学期**，由 `SemesterProvider` 存在 `settings` Box 的 `kSemesterConfigKey` 下。

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 学期名称，如 `"2026-2027学年第一学期"` |
| `startDate` | `DateTime` | **第 1 周的周一** |
| `totalWeeks` | `int` | 总周数，至少为 1 |
| `description` | `String?` | 备注 |

构造：`const SemesterConfig({required name, required startDate, required totalWeeks, String? description})`

方法：
- `DateTime get endDate` — 最后一周周日 = `startDate + (totalWeeks * 7 - 1)` 天。**派生值，不存 JSON**
- `factory SemesterConfig.fromJson(Map<String, dynamic> json)` — 缺失/类型异常用兜底值，不崩
- `static SemesterConfig? tryDecode(String? raw)` — 从存储字符串解析；坏 JSON / 非对象 / 缺 `startDate` / 缺或非法 `totalWeeks` 一律返回 `null`（供 Provider 判定"未设置学期"，避免用兜底值伪造出一个学期）
- `Map<String, dynamic> toJson()` — **不含 `endDate`**；`startDate` 存 ISO8601 字符串
- `SemesterConfig copyWith({..., bool clearDescription})`

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

工厂：`factory ModuleInfo.fromType(ModuleType type, {bool? enabled, bool available = true, int order = 0, String iconName = ''})` — 默认值取自枚举，`iconName` 需显式传入（模型层不依赖 Flutter）

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
- `FontWeight get titleFontWeight` — 由 `fontWeightTitle` 换算的类型化字重；只接受 100 的整数倍（100..900），非法值（0 / 150 / 999）回落 `FontWeight.w400`
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

导航栏模块状态。不引用其他 Provider；插件能力经 `updateCapabilities` 外部注入。**Phase 2.1.5 起 enabled 状态持久化到 `settings` Box**。

常量：`const int kMaxModules = 5`

初始状态：

| type | title | iconName | alwaysOn | 初始 available | 初始 enabled |
|------|-------|----------|:--------:|:--------------:|:------------:|
| timetable | 课表 | `calendar_month` | ✅ | true | true |
| courseList | 课程 | `book_outlined` | ❌ | true | true |
| exam | 考试 | `assignment_outlined` | ❌ | true | true |
| homework | 作业 | `edit_note` | ❌ | **false**（必须插件） | false |
| message | 消息 | `notifications_outlined` | ❌ | true | **false**（默认关闭） |
| settings | 设置 | `settings_outlined` | ❌ | true | true |

`iconName` 是 Material 图标名（字符串），由 UI 层 `home_page.dart` 的 `_iconFromName` 转成 `IconData`——**图标完全数据驱动**，改图标或加模块不需要动 UI 代码。

全新安装的 `visibleModules` = **课表 → 课程 → 考试 → 设置**（4 个）。

- `List<ModuleInfo> get allModules` — 全部模块（含不可用），顺序与初始定义一致，不可变视图
- `List<ModuleInfo> get visibleModules` — 导航栏实际显示。**选择规则**：常驻模块永远包含；非常驻需 `available && enabled`；总数最多 `kMaxModules`，超出时优先保留常驻、其余按模块列表顺序取。**输出顺序**：始终按 `_modules` 原始顺序（timetable → courseList → exam → homework → message → settings），而非"常驻在前、可选在后"，保证 toggle 时导航栏顺序不跳动
- `int get visibleCount`
- `ModuleInfo? getByType(ModuleType type)`
- `void toggle(ModuleType type, bool enabled)` — 常驻模块（课表/设置）为**空操作**，不可关闭；**变更后自动落盘**（fire-and-forget，见 `saveToStorage`）
- `void updateCapabilities(Set<String> capabilities)` — 当前**只调整 `homework`**：能力含 `'homework'` → `available = true`。`timetable`/`courseList`/`message` 是内置能力恒可用；`exam` 是插件可选增强（无插件也能手动添加考试），不由此方法改变
- `void resetToDefaults()` — 恢复初始配置，**同样落盘**（否则重启又被旧配置覆盖）

**持久化（`settings` Box，键 `kModuleEnabledStateKey`）**

- `Future<void> loadFromStorage()` — 恢复用户上次的开关配置。边界情况全部不崩溃：没存过/空串/坏 JSON/非对象 → 保持默认；某键值类型不符 → 跳过该键；只存了部分模块 → 其余用默认；存了不存在的模块 ID → 忽略；**常驻模块即使存的是 `false` 也强制启用**
- `Future<void> saveToStorage()` — 写入 `{"<capabilityId>": bool, ...}`
- `Map<String, bool> encodeEnabledState()` — 当前状态（`capabilityId → enabled`）
- `static Map<String, bool> decodeEnabledState(String? raw)` — 解析存储值，任何解析不出的内容被忽略；宽松接受 `bool` / 数字 `0|1` / `"true"|"false"|"1"|"0"`

> 键用 `ModuleInfo.capabilityId` 而不是 `ModuleType.name`：内置模块两者相等，插件模块没有 `ModuleType` 只有 `capabilityId`，用它才能统一覆盖两类。
> `available` **不受** `loadFromStorage` 影响——能力仍由插件决定；存储里的 `homework: true` 只是记录用户意图，等能力到位自动生效。

---

### `course_provider.dart` — CourseProvider（`ChangeNotifier`）

课程列表状态。**Phase 2.1 起接入 Hive**：原始数据存 `courses` Box，覆盖层存 `overrides` Box（key 均为课程 ID）。

- `List<Course> get courses` — 全部课程（含隐藏），不可变视图
- `List<Course> get visibleCourses` — 过滤 `userOverride?.hidden == true`（即 `Course.isHidden`）
- `int get hiddenCount` / `int get length`
- `bool get isLoaded` — 是否已从 Hive 载入过（UI 可区分"空数据"与"尚未加载"）
- `Course? getById(String id)`

**Hive 读写（异步，内部 try-catch + `debugPrint`，失败不抛异常）**

- `Future<void> loadFromStorage()` — 读 `courses` Box，并把 `OverrideEngine.getAllOverrides()` **一次性**读出的覆盖层按课程 ID 挂载；解析失败的单条数据被跳过。会**替换**内存列表（不是累加）
- `Future<void> saveCourse(Course c)` — **先落盘再更新内存**：剥离覆盖层写 `courses` Box，覆盖层另交 `OverrideEngine` 写 `overrides` Box；落盘失败仍更新内存（本次会话的修改不丢）
- `Future<void> deleteCourse(String id)` — 同时删除 `courses` 与 `overrides` 中的记录（避免孤儿覆盖层）。教务课程应改用 `userOverride.hidden`，见 CONTEXT 3.3
- `Future<void> clearAll()` — 清空两个 Box 与内存（测试 / 重置用）

**纯内存操作（不落盘，供测试 / 临时预览）**

- `void setCourses(List<Course> list)` / `void addCourse(Course c)`（同 id 替换）/ `void updateCourse(Course c)`（upsert）/ `void clear()`

> 覆盖层保护：`saveCourse` 在课程**不带** `userOverride` 时**不会**删除 `overrides` Box 里的既有记录——插件重新同步原始数据时用户的修改必须保留（CONTEXT 3.3）。

---

## lib/services/

### `storage_service.dart` — StorageService

统一管理 Hive 初始化与 Box 访问。纯静态类（`StorageService._()` 禁止实例化）。

常量（Box 名，落盘后即契约，见 CONTEXT 4.2.1）：`kCoursesBoxName = 'courses'`、`kExamsBoxName = 'exams'`、`kHomeworksBoxName = 'homeworks'`、`kMessagesBoxName = 'messages'`、`kOverridesBoxName = 'overrides'`、`kSettingsBoxName = 'settings'`、`kPluginsBoxName = 'plugins'`、`kSkinsBoxName = 'skins'`

常量（`settings` Box 内的键名，同样属于契约）：`kModuleEnabledStateKey = 'module_enabled_state'`（值为 JSON 对象 `{"<capabilityId>": bool}`）、`kThemeBrightnessKey = 'theme_brightness'`（值为 `light` / `dark`）、`kSemesterConfigKey = 'semester_config'`（值为 `SemesterConfig` 的 JSON 字符串；单学期故为单值键）

- `static Future<void> init({String? path})` — 初始化 Hive 并依次打开 8 个 `Box<String>`。`path == null` 时走 `Hive.initFlutter()`（生产）；传 `path` 时走 `Hive.init(path)`（测试，免去 `path_provider` 平台依赖）。重复调用安全。初始化失败只 `debugPrint` 不抛
- `static Future<void> close()` — 关闭 Hive 并清空缓存的 Box 引用（测试收尾 / App 退出）
- `static bool get isInitialized`
- `static Box<String> get coursesBox` / `examsBox` / `homeworksBox` / `messagesBox` / `overridesBox` / `settingsBox` / `pluginsBox` / `skinsBox` — 未初始化或该 Box 打开失败时抛 `StateError`（由调用方 try-catch 兜住，不静默返回坏数据）

> 设计：所有 Box 统一 `Box<String>` 存 JSON 字符串，**不注册任何 `TypeAdapter`**（CONTEXT 禁止 `build_runner`），模型的 `toJson`/`fromJson` 是唯一序列化途径。

### `override_engine.dart` — OverrideEngine
用户覆盖层的读写入口（纯静态类）。覆盖层与原始数据分离存储，两边都以**课程 ID** 为 key。

- `static UserOverride? getOverride(String courseId)` — 无记录或解析失败返回 `null`
- `static Future<void> saveOverride(String courseId, UserOverride override)`
- `static Future<void> removeOverride(String courseId)`
- `static Map<String, UserOverride> getAllOverrides()` — 用 `box.toMap()` **一次取完**整表，再循环解析。相比"逐门课 `getOverride`"，把加载 N 门课从 O(N) 次 Box 访问降为 1 次；坏数据被跳过而不影响其余条目
- `static int get count`
- `static UserOverride? decodeOverride(String? raw)` — 空值 / 非 JSON / 非对象一律返回 `null`

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
- `void setBrightness(Brightness b)` — 同值不通知；**变更后自动落盘**
- `AppTheme previewSkin(SkinPack skin)` — 不改状态、不通知
- `Future<void> loadFromStorage()` — 从 `settings` Box 恢复明暗偏好（键 `kThemeBrightnessKey`，值为 `light` / `dark`）；没存过或值无法识别则保持默认 `Brightness.light`
- `Future<void> saveToStorage()` — 写入 `_brightness.name`
- `static Brightness? decodeBrightness(String? raw)` — 无法识别返回 `null`（调用方保持默认）
- `dispose()` 会一并 `dispose()` 内部引擎

---

### `semester_provider.dart` — SemesterProvider（`ChangeNotifier`）

学期配置状态（单学期）。存在 `settings` Box 的 `kSemesterConfigKey` 下。不引用其他 Provider。

- `SemesterConfig? get config` — `null` 表示还没设置学期
- `bool get hasConfig` — `config != null`
- `bool get isLoaded` — 是否已尝试从存储载入过（UI 可区分"没设置学期"与"尚未加载"）
- `Future<void> loadFromStorage()` — 用 `SemesterConfig.tryDecode` 解析；坏 JSON / 非对象 / 缺关键字段一律按**"未设置"**处理（保持 `null`），而不是用兜底值伪造学期
- `Future<void> save(SemesterConfig config)` — 内存与 `notifyListeners` **同步**完成（调用方无需 await 即可看到 UI 更新）；返回的 Future 对应落盘，`await` 它可确保已持久化，忽略则等价 fire-and-forget。落盘失败只记日志，不回滚内存
- `Future<void> clear()` — 内存与存储都清空

> 已知行为：`loadFromStorage` 即使读到与当前相同的配置也会通知一次（`SemesterConfig` 没有 `==`，未做比较）。启动时只调用一次，实际无影响。

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

## lib/services/

### `timetable_logic.dart` — TimetableLogic

课表逻辑的**纯函数**工具（全部 `static`，无状态、不依赖 Hive / Provider），可独立测试，也可在 Phase 3 插件运行时复用。

常量：`kDaysPerWeek = 7`、`kMaxSessions = 12`、`kMaxWeekNumber = 60`（单个周次区间允许展开的上限，防 `"1-999999"` 撑爆内存）

- `static List<int> parseWeeks(String rawText)` — 解析周次文本为**基础周次**（升序去重）
  - 支持 `"4,6-14周"` → `[4,6..14]`、`"第9周"` → `[9]`、`"1-16周"` → `[1..16]`、`""`/乱码 → `[]`
  - 容忍中英文标点（`，`/`、`/`－`/`~`）、空白、`第`/`周`/`星期` 前缀、`(单)`/`（双）` 括号标记
  - 容错：逐片段解析，非法片段跳过；反向区间（`5-1`）、多段连字符（`1-2-3`）、`0`/负数、超过 `kMaxWeekNumber` 的部分全部丢弃；**任何输入都不抛异常**
  - **不做单双周过滤**（过滤在 `hasClassInWeek`）
- `static WeekType parseWeekType(String rawText)` — 用**关键词**匹配（教务写法变体多、带全半角括号，关键词比正则稳）：同时含"单"和"双"（如"单双周"）→ `all`；只含"单" → `odd`；只含"双" → `even`；都没有 → `all`
- `static int currentWeek(SemesterConfig config, {DateTime? now})` — 当前第几周
  - 只取年月日比较（避免时分秒造成 off-by-one）
  - `now < startDate` → `1`；超出 `totalWeeks` → `totalWeeks`；`totalWeeks < 1` → `1`
- `static bool hasClassInWeek(TimePlace tp, int week)` — 某周是否有该安排的课
  - `week` 不在 `tp.weeks` → `false`；`weekType == odd` 且偶数周 → `false`；`weekType == even` 且奇数周 → `false`；其余 → `true`
- `static List<List<Course?>> buildGrid(List<Course> courses, int week)` — 构建网格 `grid[day][session] = Course?`
  - 尺寸 `(kDaysPerWeek+1) × (kMaxSessions+1)`，索引 `0` 为占位，`day` 1-7 / `session` 1-12 有效（调用方可直接用"星期几/第几节"当下标）
  - **跨节**：`startSession` 起连续 `length` 格都填同一门课；越界的 `day`/`session` 直接忽略
  - 取 `Course.displayTimePlaces`（用户改过则用覆盖层）；**跳过** `userOverride.hidden == true` 的课程
  - 同一格被多门课占用时保留**先出现**的那门（按 `courses` 顺序）
- `static Course? courseAt(List<List<Course?>> grid, int day, int session)` — 越界返回 `null`
- `static int filledCellCount(List<List<Course?>> grid)` — 有课的格子数（判断课表是否为空）
- `static String formatWeeks(List<int> weeks)` — 压成展示文本，`[1,2,3,5]` → `"1-3,5"`

---

## lib/pages/

### `home_page.dart` — HomePage

主页外壳：底部导航栏的模块与顺序完全由 `ModuleProvider.visibleModules` 决定，用户在"导航栏配置"里改动后本页立即重建。

```dart
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
```

行为：
- 用 Material 3 的 `NavigationBar`（**不是** `BottomNavigationBar`）构建导航栏；图标取自 `iconFromName(module.iconName)`（见 `lib/widgets/module_icon.dart`），标签取自 `ModuleInfo.title`
- 页面映射（`_buildPage(context, module)`）：
  | ModuleType | 页面 |
  |------------|------|
  | `timetable` | `const TimetableView()` |
  | `courseList` | `const CourseListView()` |
  | `exam` | `const ExamView()` |
  | `homework` | `const HomeworkView()` |
  | `message` | `const MessageView()` |
  | `settings` | `const SettingsPage()` |
  | `null`（插件模块） | `_pendingPage(...)` — **Phase 3** 实现 |
- 用 `IndexedStack` 保活各页面，切回标签时保留滚动位置与内部状态（如课表页选中的周次）
- **越界保护**：`visibleModules` 变短导致 `_currentIndex` 越界时**重置为 0**（回到课表）。本帧先用修正后的下标渲染，再把 `_currentIndex` 归一化推迟到 `addPostFrameCallback`，避免在 `build` 中 `setState`
- `visibleModules` 为空时用 `EmptyState` 兜底（课表/设置常驻，正常不会出现）
- 样式全部经 `AppThemeExtension.of(context)` 读取，无硬编码颜色/尺寸

私有辅助（同文件内）：
- `Widget _pendingPage(BuildContext, ModuleInfo, String subtitle)` — 尚未实现的页面（插件模块）的临时外壳，用 `EmptyState`，不再单写占位类
- 图标解析（原 `_kIconByName` / `_iconFromName`）已在 Phase 1.6 抽到 `lib/widgets/module_icon.dart`

### `timetable/timetable_view.dart` — TimetableView

课表页（Phase 1.5 空态骨架，不接任何 Provider）。

```dart
const TimetableView({super.key, int totalWeeks = 20, int initialWeek = 1});
```

- `AppBar`：标题"课表"，右侧 `+` 按钮 → `SnackBar('添加课程（待实现）')`
- 周次选择器：`ListView.builder`（horizontal，高 `kWeekSelectorHeight = 48`）+ `ChoiceChip`，1..`totalWeeks`
  - 选中态用 `theme.primary` / `theme.onPrimary`，未选中用 `theme.surface` / `theme.onBackground`，圆角 `theme.chipRadius`
  - `initialWeek` 会钳制到 `1..totalWeeks`；默认第 1 周（Phase 2 接入学期配置后传入真实"当前周"）
  - 只改内部 state，不读业务数据
- Body：`EmptyState(icon: Icons.calendar_today, title: '还没有课表数据', subtitle: '点击右上角 + 添加课程，或安装插件从教务系统导入', actionLabel: '去设置安装插件', onAction: → SnackBar('请前往设置 → 插件管理'))`
- 常量：`kWeekSelectorHeight = 48`

### `course_list/course_list_view.dart` — CourseListView

`const CourseListView({super.key})` — AppBar"课程" + `EmptyState(Icons.book_outlined, '暂无课程')`。

### `exam/exam_view.dart` — ExamView

`const ExamView({super.key})` — AppBar"考试" + `EmptyState(Icons.assignment_outlined, '暂无考试安排', subtitle: '安装支持考试能力的插件后可导入')`。

### `homework/homework_view.dart` — HomeworkView

`const HomeworkView({super.key})` — AppBar"作业" + `EmptyState(Icons.edit_note, '暂无作业', subtitle: '安装学习通等插件后可查看')`。

### `message/message_view.dart` — MessageView

`const MessageView({super.key})` — AppBar"消息"，右侧"全部已读"按钮 → `SnackBar('已全部标记为已读')`；Body `EmptyState(Icons.notifications_none, '暂无消息')`。

### `settings/settings_page.dart` — SettingsPage

设置主页。`const SettingsPage({super.key})` — 除"导航栏配置"外全部为占位（SnackBar 或占位页）。

常量：`const String kAppVersion = 'v0.1.0'`（技术栈未含 `package_info_plus`，Phase 9 再改为运行时读取）

Body 为 `ListView`，分 6 组，每组 = 小标题 + 一张 `Card`（`color: theme.surface`、`elevation: 0`、圆角 `theme.cardRadius`），组内为 `ListTile`：

| 分组 | 条目 | 行为 |
|------|------|------|
| 账号 | 登录管理 `>` | `SnackBar('登录管理（待实现）')` |
| 扩展 | 插件管理 `>` | push `PluginManagePage` |
| 扩展 | 创意工坊 `>` | push `WorkshopPage` |
| 外观 | 深色模式 | `SnackBar('深色模式（待实现）')` |
| 外观 | 当前主题（右侧显示"默认蓝"） | `SnackBar('主题切换（待实现）')` |
| 布局 | 导航栏配置 `>` | push `ModuleConfigPage` |
| 布局 | 课表设置 `>` | push `TimetableSettingsPage` |
| 数据 | 导出数据 / 导入数据 | `SnackBar('导出（待实现）')` / `'导入（待实现）'` |
| 数据 | 清理缓存 | 确认框（取消/确定）→ 确定后 `SnackBar('已清理（待实现）')` |
| 关于 | 版本号（右侧 `v0.1.0`） | **不可点击**（`onTap == null`） |
| 关于 | 反馈 | `SnackBar('反馈（待实现）')` |

跳转统一用 `Navigator.of(context).push(MaterialPageRoute<void>(...))`。`清理缓存` 的 `showDialog` 之后有 `context.mounted` 检查（异步间隙保护）。

私有辅助（同文件内）：`_SettingsGroup`（小标题 + Card）、`_SettingsTile`（`showChevron` 控制 `>` 箭头，`trailingText` 显示只读值）。

### `settings/module_config_page.dart` — ModuleConfigPage

导航栏配置页。`const ModuleConfigPage({super.key})` — 用 `context.watch<ModuleProvider>()` 监听，勾选后本页与导航栏立即同步。

- 顶部提示卡：`'最多显示 5 个模块，课表和设置不可关闭'` + `'当前已显示 N/5 个'`（达到上限时该行用 `theme.error` 着色）
- `ListView.builder` 列出 `ModuleProvider.allModules`，每行 `ListTile`：
  - `leading`：`iconFromName(module.iconName)`
  - `title`：`module.title`
  - `subtitle`：模块不可用时显示 `'需要插件提供该能力'`
  - `trailing`：徽标 + `Switch`
    - `alwaysOn`（课表/设置）→ 徽标 `'必需'`，`Switch(value: true, onChanged: null)` 禁用且打开
    - `!available`（如未装插件时的作业）→ 徽标 `'未激活'`，`Switch(value: false, onChanged: null)` 禁用且关闭
    - 其余 → `Switch(value: module.enabled, onChanged: toggle)`
- **上限处理**（见下方说明）：先应用再校验，必要时回滚

### `settings/plugin_manage_page.dart` — PluginManagePage

`const PluginManagePage({super.key})` — AppBar"插件管理" + 右侧 `+` → `SnackBar('安装插件（待实现）')`；Body `EmptyState(Icons.extension, '还没有安装插件', subtitle: '插件可以从创意工坊下载，或从本地文件导入', actionLabel: '去创意工坊', onAction: push WorkshopPage)`。

### `settings/workshop_page.dart` — WorkshopPage

`const WorkshopPage({super.key})` — `DefaultTabController(length: 2)` + AppBar"创意工坊" + `TabBar`（皮肤 / 插件，配色取自主题）+ `TabBarView`：Tab1 `EmptyState(Icons.palette_outlined, '暂无皮肤', subtitle: '敬请期待')`，Tab2 `EmptyState(Icons.extension_outlined, '暂无插件', subtitle: '敬请期待')`。

### `settings/timetable_settings_page.dart` — TimetableSettingsPage

`const TimetableSettingsPage({super.key})` — 占位页：控件可操作（改内部 state），**不保存**，退出即丢失。

常量：`kMinCellHeight = 40`、`kMaxCellHeight = 100`

- `SwitchListTile '显示周末'`（默认 `true`）→ `SnackBar('（待实现）')`
- `SwitchListTile '显示节次时间'`（默认 `true`）→ `SnackBar('（待实现）')`
- `Slider '每节高度'`（40–100，默认 60，步进 10）→ `onChangeEnd` 弹 `SnackBar('（待实现）')`

---

## lib/widgets/

### `empty_state.dart` — EmptyState

所有模块页面共用的空态组件。

```dart
const EmptyState({
  super.key,
  required IconData icon,
  required String title,
  String? subtitle,
  String? actionLabel,
  VoidCallback? onAction,
});
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `icon` | `IconData` | 空态图标，尺寸固定 `kEmptyStateIconSize = 80` |
| `title` | `String` | 主文案（必填），用 `theme.titleSize` + `theme.titleFontWeight` + `theme.onBackground` |
| `subtitle` | `String?` | 副文案，`null` 不显示；用 `theme.captionSize` + 低透明度正文色 |
| `actionLabel` | `String?` | 按钮文字，`null` 不显示按钮 |
| `onAction` | `VoidCallback?` | 按钮回调；与 `actionLabel` **同时提供**才显示按钮 |

- 垂直居中（`Center` + `Column(mainAxisSize: min)`），内边距 `theme.cardPadding * 2`
- 按钮为 `FilledButton`，背景 `theme.primary` / 前景 `theme.onPrimary` / 圆角 `theme.buttonRadius`
- 常量：`kEmptyStateIconSize = 80`（`AppTheme` 无图标尺寸令牌，故为组件级常量）

### `module_icon.dart` — 模块图标解析

由 `home_page.dart` 抽出（Phase 1.6，PROGRESS 阻塞表已记录该计划），供主页导航栏与设置页的导航栏配置共用。

- `const Map<String, IconData> kModuleIconByName` — 图标名 → `IconData`。覆盖 6 个内置模块图标（`calendar_month` / `book_outlined` / `assignment_outlined` / `edit_note` / `notifications_outlined` / `settings_outlined`）与 4 个预留插件图标（`grade_outlined` / `school_outlined` / `task_outlined` / `message_outlined`）
- `IconData iconFromName(String name)` — 查表；**查不到（含空串、插件未声明 `iconName`）兜底 `Icons.extension`**

---

## lib/ 根

### `main.dart` — 入口

- `Future<void> main()` — `WidgetsFlutterBinding.ensureInitialized()` → `await StorageService.init()` → 依次建 `CourseProvider` / `ModuleProvider` / `SemesterProvider` / `ThemeProvider` 并各自 `await loadFromStorage()` → `runApp(buildApp(...))`。**先读数据再起 UI**，避免首帧闪一下默认值（如导航栏先显示默认 4 个模块再跳成用户配置）
- `Widget buildApp({CourseProvider? courseProvider, ModuleProvider? moduleProvider, SemesterProvider? semesterProvider, ThemeProvider? themeProvider})` — 构建完整 App（Provider 树 + `MyApp`）。抽成函数是为了让 widget 测试直接 `pumpWidget(buildApp())`，验证的就是 `main()` 真正使用的那棵树
  - `courseProvider` / `semesterProvider` / `themeProvider` 传入时用 `ChangeNotifierProvider.value`（实例归调用方所有，不随树销毁而 dispose）；不传时内部 `create` 空实例（测试 / 预览用，不访问 Hive）
  - `moduleProvider` 由 `ChangeNotifierProxyProvider` 创建（该 Provider 无 `.value` 变体），注入的实例会被树接管生命周期；**不要**把同一个 `ModuleProvider` 实例同时传给两棵树（先卸载的那棵会 dispose 它）

Provider 顺序（即依赖顺序，被依赖者必须在前）：

| # | Provider | 依赖 |
|---|----------|------|
| 1 | `ChangeNotifierProvider<ThemeProvider>` | 无 |
| 2 | `ChangeNotifierProvider<PluginProvider>` | 无 |
| 3 | `ChangeNotifierProxyProvider<PluginProvider, ModuleProvider>` | PluginProvider |
| 4 | `ChangeNotifierProvider<CourseProvider>` | 无 |
| 5 | `ChangeNotifierProvider<MessageProvider>` | 无 |

> 注：prompt 把 `ModuleProvider` 列在第 2 位、`PluginProvider` 列在最后，但 `ChangeNotifierProxyProvider<PluginProvider, ModuleProvider>` 必须能读到 `PluginProvider`，故两者顺序对调。

proxy 的 `update` 回调每次 `PluginProvider` 通知时调用 `ModuleProvider.updateCapabilities(pluginProvider.allCapabilities)`；首次 build 时 `moduleProvider` 为 `null` 需自建。由于 `updateCapabilities` 只在可用性真正变化时才通知，默认状态下不会在 build 阶段触发 `notifyListeners`。

### `app.dart` — MyApp

```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context);
}
```

- 必须位于 `MultiProvider` **之下**（通过 `context.watch<ThemeProvider>()` 读主题）
- `MaterialApp`：`title: '我的课表'`、`debugShowCheckedModeBanner: false`、`home: const HomePage()`
- `theme`：`ColorScheme.fromSeed(seedColor: theme.primary)`、`useMaterial3: true`、`fontFamily`（非空时）、`extensions: [AppThemeExtension(theme: theme)]`

---

## lib/widgets/

（待填充）