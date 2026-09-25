# 已实现接口清单（API）

> 本文件是"契约文档"。
> 每生成完一个类，就把它的公开接口追加到对应小节。
> 每次生成新代码前，把本文件内容作为上下文提供给 AI，确保字段名、方法名一致。
> 只列**公开**接口，不列私有方法。

- 最后更新：2026-09-24（1.1–1.6 内核骨架；2.1 存储层；2.1.5 配置落盘；2.2a 学期配置 + 周次解析；2.2b 课表网格；2.2b.1 字号 + 滑动切周；2.2b.3 视觉重构；2.2b.4 卡片只显示教室；2.2c.1 学期配置页；2.2c.2 添加课程页；3.1 flutter_js 集成验证；3.2a JS 运行时沙箱与兜底；3.2b.1 插件文件加载 + PluginRuntime 骨架；3.3 多插件管理 PluginManager；3.4 插件文件持久化 PluginStorageService；3.5 插件管理 UI 接入；3.5.1 插件可卸载性 isRemovable；3.6 插件上下文 ctx；4.1 WebView 登录页 + Cookie 提取）

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
| `assetPath` | `String` | **打包内置插件**的 asset 路径（相对 `assets/` 根）。**Phase 3.4 起不再用于定位已安装插件**——那由 `PluginStorageService.getPluginJsPath(id)` 现算。键名保持不变（schema 已冻结，改名要写迁移；收窄语义零迁移成本） |
| `source` | `String` | `"builtin"` / `"workshop"` / `"local"` |
| `downloadUrl` | `String` | 商店原始 URL |
| `hasUpdate` | `bool` | 是否有更新 |
| `latestVersion` | `String` | 商店最新版本 |
| `enabled` | `bool` | 是否启用 |
| `installedAt` | `DateTime` | 安装时间（`required`） |
| `lastSyncAt` | `DateTime?` | 最近同步时间 |
| `isRemovable` | `bool` | **是否允许用户卸载（Phase 3.5.1 新增，默认 `true`）**。这是**策略**，与 `source`（来源）是两件事：从 assets 安装的示例插件来源确实是 `"builtin"`，但**应当可以卸载**；只有**硬编码的系统级插件**才设为 `false`。缺键回落 `true`（向后兼容，**无需迁移**） |

构造：`const PluginMeta({required id, required name, String version = '0.0.0', String author = '', String description = '', String school = '', List<String> capabilities = const [], List<ModuleInfo> modules = const [], String entryFile = '', String assetPath = '', String source = 'local', String downloadUrl = '', bool hasUpdate = false, String latestVersion = '', bool enabled = false, required DateTime installedAt, DateTime? lastSyncAt, bool isRemovable = true})`

方法：
- `bool get isBuiltIn` / `bool get isFromWorkshop` / `bool get hasSynced` / `bool get hasModules`
  - **`isBuiltIn` 是"来源"不是"能否卸载"**（`source == 'builtin'`）。判断卸载请看 `isRemovable`
- `Set<String> get effectiveCapabilities` — `capabilities` ∪ 各 `modules` 的 `capabilityId`（两种声明方式都支持，忽略空串）
- `bool get hasCapabilities` — `effectiveCapabilities.isNotEmpty`
- `factory PluginMeta.fromJson(Map<String, dynamic> json)` — `modules` 兼容 `ModuleInfo` Map 与纯字符串能力 ID；`capabilities` 忽略 `null` 与空串；`isRemovable` 缺键或值无法识别时回落 `true`
- `Map<String, dynamic> toJson()`
- `PluginMeta copyWith({..., bool clearLastSyncAt, bool? isRemovable})`

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

App 的全部视觉令牌集合，不可变（**30 个字段**，Phase 3.5 由 28 增至 30：新增 `success` / `warning`）。UI 必须经 `AppThemeExtension.of(context)` 读取，禁止硬编码。

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
| `success` | `Color` | `#43A047` | **成功 / 正常状态色（Phase 3.5 新增）**。用于状态徽章等"一切正常"语义；加它是因为 CONTEXT 3.2 禁止硬编码颜色，而原主题没有绿色 |
| `warning` | `Color` | `#F9A825` | **警告状态色（Phase 3.5 新增）**。用于"已启用但尚未就绪"等语义 |

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
| `timetableCellHeight` / `timetableTimeColumnWidth` | `double` | `72` / `40` |
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

### `cookie_service.dart` — CookieService（Phase 4.1）

插件登录凭证的**存取与格式化**（纯静态类）。只负责"存 / 取 / 清 / 拼串"四件事，
**不负责登录流程**（那是 `WebViewLoginPage`），也不负责把 Cookie 塞回 WebView。

存储位置：`flutter_secure_storage`，key = **`<pluginId>:cookie`**（CONTEXT 3.5）。
格式：HTTP 请求头标准写法 `name1=value1; name2=value2`
—— 插件侧可直接 `ctx.http.get(url, { Cookie: ctx.cookie })`。

常量：`kCookieKeySuffix = ':cookie'`（**必须与 `PluginContext.kCookieKeySuffix` 一致**：
登录页写进去、`ctx.cookie` 读出来，两边对不上就白搭）、`kCookieSeparator = '; '`

- `static Future<void> saveCookie(String pluginId, String cookie)` — 保存；**空串等价于清除**（不留空记录）
- `static Future<String> loadCookie(String pluginId)` — 读取；**不存在或失败返回空串**（不是 `null`，对齐"边界只传字符串"）
- `static Future<void> clearCookie(String pluginId)` — 清除（退出登录 / 卸载插件用）
- `static String formatCookies(List<WebViewCookie> cookies)` — 拼成 HTTP 头格式：
  跳过**空名**与**值含 `;` / 换行**的条目（会拼坏请求头）；**同名后者覆盖前者**；
  空列表返回空串

三个写方法失败都只 `debugPrint`、**不抛异常**：登录流程不该因存储问题崩掉。

### `storage_service.dart` — StorageService

统一管理 Hive 初始化与 Box 访问。纯静态类（`StorageService._()` 禁止实例化）。

常量（Box 名，落盘后即契约，见 CONTEXT 4.2.1）：`kCoursesBoxName = 'courses'`、`kExamsBoxName = 'exams'`、`kHomeworksBoxName = 'homeworks'`、`kMessagesBoxName = 'messages'`、`kOverridesBoxName = 'overrides'`、`kSettingsBoxName = 'settings'`、`kPluginsBoxName = 'plugins'`、`kSkinsBoxName = 'skins'`、**`kPluginDataBoxName = 'plugin_data'`（Phase 3.6 新增）**

常量（`settings` Box 内的键名，同样属于契约）：`kModuleEnabledStateKey = 'module_enabled_state'`（值为 JSON 对象 `{"<capabilityId>": bool}`）、`kThemeBrightnessKey = 'theme_brightness'`（值为 `light` / `dark`）、`kSemesterConfigKey = 'semester_config'`（值为 `SemesterConfig` 的 JSON 字符串；单学期故为单值键）、`kGestureSwitchWeekKey = 'gesture_switch_week'`（值为 JSON `true` / `false`）

- `static Future<void> init({String? path})` — 初始化 Hive 并依次打开 **9** 个 `Box<String>`。`path == null` 时走 `Hive.initFlutter()`（生产）；传 `path` 时走 `Hive.init(path)`（测试，免去 `path_provider` 平台依赖）。重复调用安全。初始化失败只 `debugPrint` 不抛
- `static Future<void> close()` — 关闭 Hive 并清空缓存的 Box 引用（测试收尾 / App 退出）
- `static bool get isInitialized`
- `static Box<String> get coursesBox` / `examsBox` / `homeworksBox` / `messagesBox` / `overridesBox` / `settingsBox` / `pluginsBox` / `skinsBox` / **`pluginDataBox`** — 未初始化或该 Box 打开失败时抛 `StateError`（由调用方 try-catch 兜住，不静默返回坏数据）

> 设计：所有 Box 统一 `Box<String>` 存 JSON 字符串，**不注册任何 `TypeAdapter`**（CONTEXT 禁止 `build_runner`），模型的 `toJson`/`fromJson` 是唯一序列化途径。

### `plugin_storage_service.dart` — PluginStorageService（Phase 3.4）

插件**物理文件**的存储服务（纯静态类）：管理插件在应用私有目录下的安装 / 卸载 / 查询。
这是"插件文件从哪来"的答案——3.2b.1 起的临时目录方案到此结束。

**目录布局**（`<appDocuments>` 由 `path_provider` 给出）：

```
<appDocuments>/plugins/
  <pluginId>.js               插件脚本（必需）
  <pluginId>.manifest.json    元数据（可选）
```

Android 上 `<appDocuments>` 是 `/data/user/0/<package>/app_flutter`，
因此插件目录为 `/data/user/0/<package>/app_flutter/plugins/`。

常量：`kPluginsSubdirName = 'plugins'`、`kPluginJsSuffix = '.js'`、
`kPluginIdPattern = RegExp(r'^[A-Za-z0-9_-]+$')`、`kMaxPluginIdLength = 64`

**`pluginId` 校验（路径安全）**

- `static bool isValidPluginId(String pluginId)` — 非空、长度 ≤ 64、**只含字母 / 数字 / 下划线 / 横线**
- 点号也在禁止之列：id 会被直接拼进文件名，若允许 `.`、`/`、`\`，攻击者可用 `../../` 做**路径穿越**把文件写到插件目录之外
- **约定**：查询类方法对非法 id 返回"找不到"（`false` / `null`）；命令类方法（`installPlugin` / `uninstallPlugin`）抛 `ArgumentError`——非法 id 是调用方的编程错误，不该静默成功

**方法**

- `static Future<Directory> getPluginsDir()` — 取插件根目录（不存在则创建）。结果**缓存**，重复调用不反复访问平台通道
- `static Future<String> installPlugin({required String pluginId, required String jsSource, String? manifestJson})` — 安装，返回 JS 文件绝对路径
  - **重复安装整体覆盖**；`manifestJson` 为 `null` 时**删掉旧的 `.manifest.json`**，避免上次元数据残留让加载器读到过期声明
  - **写文件用"临时文件 + 重命名"**（`<name>.js.tmp` → rename），避免写到一半被中断时留下半个文件、把原本能用的插件覆盖成坏文件
  - 非法 id 抛 `ArgumentError`；I/O 失败记日志后 rethrow（不让调用方误以为安装成功）
- `static Future<void> uninstallPlugin(String pluginId)` — 删除两个文件；**不存在视为已卸载（幂等）**
- `static Future<bool> isInstalled(String pluginId)` — `<id>.js` 是否存在
- `static Future<List<String>> listInstalled()` — 扫描目录里的 `*.js`，返回 id 列表（升序）。`*.js.tmp` 与 `*.json` 都不计入
- `static Future<String?> getPluginJsPath(String pluginId)` — JS 文件绝对路径；**未安装返回 `null`**
- `static Future<String?> getPluginManifestPath(String pluginId)` — manifest 绝对路径；不存在返回 `null`
- `static Future<void> clearAll()` — 清除目录内全部文件（测试用），目录本身保留
- `static Future<void> installFromAssets({required String pluginId, required String assetPath})` — **Phase 3.5 新增**：从 **assets** 安装（用于随 App 打包的内置 / 示例插件）。用 `rootBundle.loadString(assetPath)` 读出内容后走同一条 `installPlugin` 落盘路径——因为**运行时只能从文件系统加载**（`defaultSourceResolver` 取的是 `<id>.js` 文件路径），而 `rootBundle` 拿不到文件路径。asset 不存在 / 内容为空时记日志并抛 `FlutterError`（不静默吞掉，否则用户会以为"装了但没效果"）
- `static void setRootDirForTesting(String? rootDir)`（`@visibleForTesting`）— 把根目录指向临时路径并清缓存，**测试免去 `path_provider` 平台通道**（与 `StorageService.init({String? path})` 同思路）

> **为什么不把安装路径存进 `PluginMeta`**：路径是 `pluginId` 的**纯函数**，存下来既冗余又危险——
> iOS 的应用容器 UUID 每次 App 更新都会变，存下的绝对路径会在更新后失效。因此一律现算。
>
> **懒加载**：首次调用才向 `path_provider` 要目录，故 `main.dart` **无需预热**；
> path_provider 不可用时也只影响插件功能，不影响 App 启动。

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

### `settings_provider.dart` — SettingsProvider（`ChangeNotifier`）

UI 偏好设置（Phase 2.2b.1 新增）。目前只有"左右滑动切换周次"，后续把 `TimetableSettingsPage` 里其余几个内存态偏好也迁进来。

**为什么单独建 Provider 而不是塞进 `SemesterProvider`**：后者建模的是**学期这个领域对象**（起止日期、总周数），存 `semester_config` 一条业务数据；而"滑动切周"是**纯交互偏好**，与学期内容无关。混在一起会让那个类说不清职责，且"显示周末/显示节次时间/每节高度"三个待持久化的偏好也需要同一个归宿。

构造：`SettingsProvider({bool initialGestureSwitchWeek = true})`

- `bool get gestureSwitchWeek` — 是否允许课表页左右滑动切周，默认 `true`
- `bool get isLoaded`
- `Future<void> loadFromStorage()` — 从 `settings` Box 的 `kGestureSwitchWeekKey` 读取；空值 / 非法 JSON / 类型不符一律**回落 `true`**
- `Future<void> setGestureSwitchWeek(bool value)` — 内存与通知**同步**完成（调用方无需 await 即见 UI 更新）；返回的 Future 对应落盘，`await` 可确保持久化、忽略则等价 fire-and-forget。同值不通知也不写。落盘失败只记日志
- `static bool? decodeBool(String? raw)` — 写入用 `jsonEncode`（存 `"true"` / `"false"`）；读取同时兼容裸字符串 `true`/`false`、数字 `0`/`1` 与已解析的 bool，无法识别返回 `null`

---

### `plugin_provider.dart` — PluginProvider（`ChangeNotifier`）

已安装插件状态。**Phase 3.3 起接线 `PluginRuntime`**：本类持有 `PluginManager`（组合关系），
由它负责多插件的加载 / 卸载 / 能力汇总；本类负责状态通知与持久化。
仍**不直接引用** ModuleProvider——能力集合由 Phase 1.4 的 `ChangeNotifierProxyProvider` 推给它。

**持久化（Phase 3.3 新增）**：插件列表存 `plugins` Box，**一个插件 id 一个 key**，
值为 `PluginMeta` 的 JSON（与 `courses` Box 的做法一致）。

构造：`PluginProvider({List<PluginMeta>? plugins, PluginManager? manager})`
（`manager` 可注入以便测试，沿用 `ThemeProvider({ThemeEngine?})` 的先例）

**列表与查询**

- `List<PluginMeta> get plugins` — 全部插件（含未启用），不可变视图
- `List<PluginMeta> get enabledPlugins`
- `Set<String> get allCapabilities` — 已启用插件的 `effectiveCapabilities` 并集（`capabilities` ∪ `modules` 能力），不可变集合。**只看"启用"，不看"是否加载成功"**（Phase 1 起的行为，未改动）
- `Set<String> get loadedCapabilities` — **已成功加载**（沙箱可用）插件的能力并集，转发给 `PluginManager.allLoadedCapabilities`
- `Map<String, PluginHandle> get loadedHandles` — `id → handle`（含加载失败的降级 handle）
- `int get loadedCount` / `int get enabledCount` / `int get updatableCount`
- `Map<String, String> get loadErrors` — 加载失败原因（`id` → 原因），不可变视图
- `String? loadErrorOf(String id)`
- `PluginMeta? getById(String id)` / `PluginHandle? getHandle(String id)`
- `bool get isLoaded` — 是否已尝试从存储载入过（区分"没有插件"与"尚未加载"）

**运行时接线**

- `Future<void> loadAllEnabledPlugins()` — App 启动时调用：遍历所有 `enabled` 插件逐个加载。**单个插件失败不影响其他插件**（每个单独 try-catch），失败原因记入 `loadErrors`；其 `enabled` 在存储里**保留 true**，用户重启后可重试
- `Future<PluginHandle> loadPlugin(String id, {String? jsSource})` — 手动加载单个；`jsSource` 可绕过文件系统直接给源码（测试 / 内联插件用）。找不到 id 时返回降级 handle，不抛异常
- `Future<void> unloadPlugin(String id)` — 手动卸载（只销毁运行时，**不改 `enabled`**）

**启停（Phase 3.3 改造）**

- `Future<void> togglePlugin(String id, bool enabled)` — 流程：改内存并**立即通知**（UI 不等异步）→ 落盘 `enabled` → 启用则 `_manager.load(meta)`、停用则 `_manager.unload(id)` → 再通知一次。**无论加载成功失败都落盘 `enabled`**。找不到 id 或同值时为**空操作**

**增删**

- `Future<void> addPlugin(PluginMeta p)` — 同 id 则替换，并落盘
- `Future<void> removePlugin(String id)` — **销毁运行时 + 删除磁盘插件文件 + 从列表与存储移除**。
  `isRemovable == false` 的插件**不可卸载**（空操作，留给硬编码的系统级插件）——
  注意这与"来源是 `builtin`"**不是一回事**：从 assets 安装的示例插件来源也是 `builtin`，但它可以卸载。
  **Phase 3.5.1 起会真正删除 `<id>.js` / `<id>.manifest.json`**（此前只删元数据，文件会留在磁盘上）；
  删文件失败只记日志、不抛（元数据已移除，遗留文件下次安装会被覆盖）。
  列表变更后**先 `notifyListeners`**，再做异步收尾（沙箱销毁 / 删文件 / 落盘），保证 UI 立刻反映
- `void clear()` — **仅内存**清空（测试 / 重置用）
- `Future<void> clearAll()` — 清空内存 + 存储 + 销毁所有运行时
- `dispose()` — 会 fire-and-forget 地 `_manager.disposeAll()` 释放所有沙箱

**示例插件（Phase 3.5 临时功能，Phase 4 完成后删除）**

- 常量 `kExamplePluginId = 'example-plugin'`、`kExamplePluginAssetPath = 'assets/plugins/example.js'`
- `Future<bool> installExamplePluginForDemo()` — 从 assets 读 `example.js` → `installFromAssets` 落盘 →
  `addPlugin`（先以 `enabled: false` 落盘）→ `togglePlugin(id, true)` 启用（复用同一条启停链路，
  避免在这里重写"落盘 + 加载运行时"）。**任何一步失败都不抛异常**，只 `debugPrint` 并返回 `false`，
  由 UI 弹 SnackBar。重复调用安全（同 id 替换 + 覆盖文件）

> **签名变更**：`addPlugin` / `removePlugin` / `togglePlugin` 由 `void` 改为 `Future<void>`，
> 以便调用方 `await` 落盘/加载完成。原签名在 `lib/` 里**没有调用方**（插件管理页仍是占位页），
> 故无破坏性影响。

> **`allCapabilities` vs `loadedCapabilities`**：前者按"已启用"算（Phase 1 起驱动
> `ModuleProvider`），后者按"确实加载成功"算。**目前只有前者接到了 ModuleProvider**——
> 若改用后者，加载失败的插件就不会让模块变可用，但那会改变模块可用性语义，
> 属独立决策，留待后续阶段（见 PROGRESS 阻塞表）。

**存储容错**：没存过 → 空列表；坏 JSON / 非对象 / 缺 `id` / 空串 → 跳过该条；
存储未初始化（`StateError`）→ 按"没有插件"处理。`loadFromStorage` **会替换内存列表**（不是累加）。

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

### `login/webview_login_page.dart` — WebViewLoginPage（Phase 4.1）

**通用** WebView 登录页：打开登录地址 → 判定成功 → 提取 Cookie → pop 返回。
**不硬编码任何学校 URL、不依赖任何学校页面结构**（CONTEXT 3.1）——
登录地址与成功判定条件全部由调用方传入（Phase 4.2 起来自插件的 manifest）。

```dart
const WebViewLoginPage({
  super.key,
  required String loginUrl,
  required String successUrlPrefix,
  String? title,        // 默认「登录」
  String? pluginId,     // 非空时本页负责把 Cookie 落盘
});
```

**顶层纯函数**（便于单测，不需要真的起 WebView）：

- `bool isLoginSuccessUrl(String currentUrl, String successUrlPrefix)` —
  当前 URL 是否以该前缀开头（两侧空白忽略）。**空前缀返回 `false`**，
  语义是"没声明前缀、不靠 URL 判定"，由调用方走 Cookie 兜底

**行为**：

- AppBar：标题（默认「登录」）+ 右侧「刷新」（`controller.reload()`）
- Body：`WebViewWidget` + 加载中显示 `LinearProgressIndicator`
- **判定时机**：`onPageFinished`（`NavigationDelegate`）→ `_maybeFinish(url)`
- **判定规则**（Phase 4.1 决策 1）：
  | 情况 | 结果 |
  |------|------|
  | URL 命中前缀 **且** 拿到非空 Cookie | 成功 → pop(cookie) |
  | URL 命中前缀但 Cookie 为空 | **不算成功**，继续等下一页（没有凭证的"成功"没有意义） |
  | 未声明前缀（空串） | 兜底：拿到非空 Cookie 即视为成功 |
  | 都没命中 | 什么都不做，等用户操作 |
- **Cookie 提取**：`WebViewCookieManager.getCookies(domain:)`（webview_flutter 官方 API，**未加新依赖**）。
  同时查**登录页域名**与**当前页域名**并合并（会话 Cookie 可能落在跳转后的主机上），
  同名以"后查到的"为准；读取失败只记日志、不中断登录流程
- `pluginId` 非空时，返回前 `await CookieService.saveCookie(pluginId, cookie)`
- **用户手动返回** → `pop(null)`，**不写任何东西**（决策 4）
- URL 非法 / 主框架加载失败 → 显示错误文案 + 「重试」按钮（子资源错误忽略，
  判据是 `WebResourceError.isForMainFrame == false`）
- `_finished` 标志防止"多次 `onPageFinished`"导致重复 pop
- 颜色 / 字号 / 圆角全部取自 `AppThemeExtension`

> **注意**：本页在 `flutter test` 里**无法 pump**——`WebViewController()` 需要
> `WebViewPlatform.instance`（测试环境为 `null`）。真实加载只能在真机验证。

## lib/pages/ 其它页面

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

---

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

### `timetable/timetable_view.dart` — TimetableView

课表页（Phase 2.2b 起接入真实数据）。`const TimetableView({super.key})` — 无构造参数，数据全部来自 Provider。

数据来源：`SemesterProvider`（学期/总周数/当前周）、`CourseProvider.visibleCourses`（已过滤隐藏课程）、`SettingsProvider.gestureSwitchWeek`（是否启用滑动切周）、`TimetableLogic`（纯函数）。

**三种状态**（`_buildBody`）：

| 条件 | 展示 |
|------|------|
| `!semester.hasConfig` | `EmptyState(Icons.calendar_today, '还没有配置学期', '配置学期后才能看到课表', '去配置学期')` → **Phase 2.2c.1 起 `Navigator.push(SemesterConfigPage)`**（原为 SnackBar 占位）。**不显示周次选择器**（没有学期时周次无意义） |
| 有学期但 `visibleCourses` 为空 | `EmptyState(Icons.add_circle_outline, '还没有课程', '点击下方按钮添加第一门课', '添加课程')` → **Phase 2.2c.2 起 `_openCourseEdit()`**：有学期则 push `CourseEditPage`，无学期则弹 `SnackBar('请先配置学期')` + `去配置` action |
| 有数据 + `gestureSwitchWeek == true` | `PageView.builder(itemCount: totalWeeks)`，每页一周；`initialPage = _week - 1` |
| 有数据 + `gestureSwitchWeek == false` | 单个 `TimetableGrid`（只能通过顶部周次面板切周） |

**顶部栏（Phase 2.2b.3）** —— 一行日期栏，**不再有 AppBar、也没有常驻的周次 chips 行**：

```dart
SizedBox(
  height: kTopBarHeight,                       // 48
  child: Padding(
    padding: EdgeInsets.symmetric(horizontal: theme.cardPadding),
    child: Row(children: <Widget>[
      Text(formatDateYmd(today)),              // 2026/9/23（yyyy/M/d，不补零）
      SizedBox(width: theme.sectionGap),
      if (config != null)
        InkWell(                               // 可点击 → 周次面板
          onTap: () => _showWeekPicker(config),
          child: Row(children: <Widget>[
            Text('第 $_week 周'), Icon(Icons.arrow_drop_down),
          ]),
        ),
      if (semesterEnded) Text('学期已结束'),      // 灰色小字
      const Spacer(),
      IconButton(icon: Icon(Icons.add), tooltip: '添加课程',
        onPressed: _openCourseEdit),   // 无学期时弹 SnackBar + "去配置"
    ]),
  ),
)
```

- `formatDateYmd(DateTime)` → `yyyy/M/d`（如 `2026/9/23`），不补零、不依赖 `intl` 初始化
- `weekStartDateOf(SemesterConfig, week)` → `startDate + (week - 1) * 7` 天（该周周一），传给 `TimetableGrid.weekStartDate`
- **"学期已结束"** 判定（`_isSemesterEnded`）：`currentWeek(config) == totalWeeks` **且** 今天（只比年月日）晚于 `config.endDate`
- 点击"第 N 周" → `showModalBottomSheet` 弹出 `_WeekPickerSheet`：标题"选择周次" + `Wrap` 的 `ChoiceChip`（1..totalWeeks，当前周选中）+ 右下角 `TextButton.icon('编辑学期')`
  - 面板返回 `int` → 跳到该周；返回 `_WeekPickerResult.editSemester` → `Navigator.push(SemesterConfigPage)`（Phase 2.2c.1）
- 右上角 `+` → `_openCourseEdit()`：**有学期**则 `Navigator.push(CourseEditPage)`；**无学期**则 `SnackBar('请先配置学期')` + `SnackBarAction('去配置')` → 打开 `SemesterConfigPage`（Phase 2.2c.2）

常量：`kTopBarHeight = 48`、`kDefaultSectionTimes`（12 个节次的起止时间，**硬编码**；Phase 4 插件接入后改为从插件的 `sectionTime` 数据读取——各校作息不同，不能长期写死在客户端）
- 点击卡片 → `showCourseDetailSheet(context, course)`
- 长按卡片 → SnackBar `编辑功能待实现（Phase 5）`

**周次双向同步**：`_week` 是**唯一真相源**。PageView 的 `onPageChanged` 与周次面板的选择都只经 `_setWeek(...)` 改 `_week`，再由它把另一侧对齐（`_jumpPageToWeek` / `_animatePageToWeek`）。因此两侧不会互相触发形成循环；`_jumpPageToWeek` 里还有"已在目标页就不动"的判断，避免与手势抢位置。滑动回调用 `animate: false`（页面已滑到位，再动画会打架）。

**边界**：`_setWeek` 用 `clamp(1, totalWeeks)`；PageView 首尾天然停住（实测第 1 周继续右滑仍是第 1 周，不会出现第 0 周）。

> 已移除（Phase 2.2b.3）：`kWeekSelectorHeight` / `kWeekChipExtent` / `_weekScrollController` / `_scrollWeekChipIntoView` —— 常驻 chips 行改为顶部的周次面板后不再需要。

### `timetable/course_detail_sheet.dart` — showCourseDetailSheet

```dart
Future<void> showCourseDetailSheet(BuildContext context, Course course);
```

只读底部弹层（`showModalBottomSheet`，`isScrollControlled: true`）。内容全部取自 `displayXxx`（已叠加用户覆盖层）：

- 拖动条 → 课程名（`displayName`，`titleSize` + `titleFontWeight`）
- **教师（`displayTeacher`，空则显示"未知教师"）** —— 卡片里不显示教师后，这里是**唯一**能看到教师的地方；`N 学分 · 类别`
- "上课时间地点"区块：`displayTimePlaces` 每项一行 →「周一 第3-4节 4,6-14周」+ 下一行教室
  - 节次：单节 `第3节`，连堂 `第3-4节`；周次优先用 `rawWeeksText`，缺单双周标记时按 `weekType` 补 `(单)`/`(双)`
  - 无安排时显示"暂无安排"
- "备注"区块：仅在 `userOverride.note` 非空时显示
- 底部按钮：`编辑`（→ SnackBar `编辑功能待实现（Phase 5）`）、`关闭`（→ `Navigator.pop`）

### `edit/course_edit_page.dart` — CourseEditPage

**添加课程**页（Phase 2.2c.2）。`const CourseEditPage({super.key})` —— 无构造参数；**编辑/删除留到 Phase 5**。

两个入口（课表页顶部 `+`、空态"添加课程"按钮）都先检查 `SemesterProvider.hasConfig`：**没有学期时不跳转**，改弹 `SnackBar('请先配置学期')` 并带 `SnackBarAction('去配置')`（打开 `SemesterConfigPage`）。本页 `_save()` 里还有一次同样的兜底。

`Form` + `ListView` 结构：

| 区块 | 内容 |
|------|------|
| 基本信息 | 课程名（`TextFormField`，`maxLength: 30`，validator 非空）；教师（可选）；学分（`Slider` 0–10 步进 0.5，默认 2）；课程类别（可选，如"专业必修课"）；**课程颜色**（`_ColorPicker`） |
| 上课时间地点 | 标题右侧 `TextButton.icon('添加时间段')`；每个时间段一张 `_TimePlaceCard` |
| 备注 | `TextFormField(maxLines: 3)` |
| 底部 | `OutlinedButton 取消`（`pop(false)`）+ `FilledButton 保存` |

**时间段的临时数据结构** `_TimePlaceDraft`（可变，保存时转 `TimePlace`）：

```dart
class _TimePlaceDraft {
  _TimePlaceDraft({required this.endWeek});   // endWeek 按学期总周数传入
  int day = 1; int startSession = 1; int length = 2;
  int startWeek = 1; int endWeek;
  WeekType weekType = WeekType.all;
  final TextEditingController roomController = TextEditingController();
  void dispose() => roomController.dispose();
}
```

时间段卡片内容：`时间段 N` + 右上角 `IconButton(close, tooltip: '删除该时间段')`、星期（7 个 `ChoiceChip`）、起始节次 / 持续节数（两个 `DropdownButton`，1–12 / 1–4）、教室（可选）、**周次范围**（`RangeSlider`）、单双周（3 个 `ChoiceChip`：每周 / 单周 / 双周）。**至少保留一个时间段**：删到最后一个时弹 `SnackBar('至少保留一个时间段')` 并拒绝。

**周次范围 UX**：用 `RangeSlider(1..totalWeeks, divisions: totalWeeks - 1)` + 上方 `周次：第 X - Y 周` 文案。选它而不是两行数字 chip：总周数最多 30、chip 行会很长，且 `RangeSlider` **天然保证"起始周 ≤ 结束周"**。`totalWeeks <= 1` 时退化为静态"第 1 周"（避免退化区间）。

**保存流程**：`validate()` → 逐时间段校验（`endWeek >= startWeek`；`weeksFromRange` 结果非空，否则该时间段永远不会显示 → 提示"第 N 个时间段的周次与单双周设置组合后为空"）→ 构造 `Course` → `await CourseProvider.saveCourse(course)` → `pop(true)` + `SnackBar('课程已添加')`。

`Course` 的构造：
- `id = 'user_${DateTime.now().microsecondsSinceEpoch}'`
- `sourcePluginId = kUserSourcePluginId`（`'user'`）
- `timePlaces` = 各草稿转换结果
- **颜色存进 `userOverride.customColor`**（`Course` 没有 color 字段，`displayColor` 读的就是它；`saveCourse` 会把覆盖层剥离到 `overrides` Box 持久化）。选了"自动"时 `customColor = null`，由 `TimetableGrid` 按 `course.id` 哈希取色。备注同样存进 `userOverride.note`；两者都为空时 `userOverride` 为 `null`。

纯函数（同文件导出）：`weeksFromRange(int startWeek, int endWeek, WeekType)`、`rawWeeksTextFromRange(int, int, WeekType)`

常量：`kMaxCourseNameLength = 30`、`kMinUnit = 0` / `kMaxUnit = 10` / `kUnitStep = 0.5`、`kMinLength = 1` / `kMaxLength = 4`

### `settings/semester_config_page.dart` — SemesterConfigPage

学期配置页（Phase 2.2c.1）。`const SemesterConfigPage({super.key})` —— 编辑唯一的学期配置。

**三处入口**：设置 → 课表设置 → "学期配置"；课表页无学期时的"去配置学期"按钮；课表页顶部"第 N 周"面板里的"编辑学期"。

- `AppBar`：标题"学期配置"；**已有配置时**右侧显示"重置"（`theme.error` 色）
- Body = `Form`（`_formKey`）内的 `ListView`：

| 字段 | 控件 | 说明 |
|------|------|------|
| 学期名称 | `TextFormField` | label"学期名称"、hint"如：2026-2027学年第一学期"、`maxLength: 30`；**validator**：空（含纯空白）→"请输入学期名称"，超 30 字 → 提示 |
| 开始日期（第 1 周周一） | 可点击行（`_TapField`） | 显示 `2026年9月7日（周一）`；点击 → `showDatePicker` |
| 总周数 | `Slider` | 范围 `kMinTotalWeeks(4)`–`kMaxTotalWeeks(30)`，`divisions` = 26，右侧显示 `N 周` |
| 结束日期 | 只读行（`onTap: null`） | 派生：`startDate + (totalWeeks * 7 - 1)` 天，显示 `2027年1月24日` |
| 备注（可选） | `TextFormField` | `maxLines: 3` |
| 预览 | `_PreviewCard` | 见下 |
| 底部 | `OutlinedButton 取消` + `FilledButton 保存` | 取消 → `pop(false)` |

- 初值（`initState` 里 `context.read<SemesterProvider>().config`）：名称/备注回填；开始日期取已有值，**没有配置时默认"本周一"**；总周数取已有值并 `clamp(4, 30)`（滑杆范围外会被收进区间；下限 4 是为了支持军训 / 小学期等短学期）
- 日期选择器：`showDatePicker(initialDate: _startDate, firstDate: now.year-5, lastDate: now.year+5/12/31, helpText: '选择第 1 周的周一')`；选中后 `dateOnly()` 归一化
- **预览文案**（`_previewText`）：今天 < 开始日 → `学期尚未开始（…起）`；今天 > 结束日 → `学期已结束`；否则 → `当前是第 N 周`（`TimetableLogic.currentWeek`）
- **保存**：`validate()` 通过 → `SemesterProvider.save(...)` → `pop(true)` + SnackBar `学期配置已保存`（messenger/navigator 在 await 前捕获，避免跨异步间隙用 context）
- **重置**：确认框"确定要清除学期配置吗？" → 确认则 `SemesterProvider.clear()` → `pop(true)`

纯函数（同文件导出，便于测试）：`dateOnly(DateTime)`、`mondayOfWeek(DateTime)`、`formatChineseDate(DateTime)`（`2026年9月7日`）、`formatChineseDateWithWeekday(DateTime)`（`2026年9月7日（周一）`）

常量：`kMinTotalWeeks = 4`、`kMaxTotalWeeks = 30`、`kMaxSemesterNameLength = 30`

### `settings/timetable_settings_page.dart` — TimetableSettingsPage（更新）

Phase 2.2b 在"显示周末"开关**上方**新增一行 `ListTile`：

- 标题"学期配置"，副标题 = `SemesterProvider.config?.name ?? '未配置'`（`context.watch` 实时更新）
- 点击 → **Phase 2.2c.1 起改为 `Navigator.push(SemesterConfigPage)`**（原为 SnackBar 占位）

Phase 2.2b.1 又在"显示周末"上方新增 `SwitchListTile`：

- 标题"左右滑动切换周次"，副标题"在课表页左右滑动切换周次"
- 值 = `SettingsProvider.gestureSwitchWeek`，`onChanged` → `setGestureSwitchWeek`（**已持久化**）
- 其余三个控件（显示周末 / 显示节次时间 / 每节高度）仍是内存状态、重启即丢（待迁入 `SettingsProvider`）

---

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

### `settings/plugin_manage_page.dart` — PluginManagePage（Phase 3.5 接入真实数据）

插件管理页。**Phase 1.6 曾是空态占位，Phase 3.5 起列表来自 `PluginProvider.plugins`**。
`const PluginManagePage({super.key})`，`StatelessWidget` + `context.watch<PluginProvider>()`
（插件从 0 个变 N 个或反向时自动重建，空态与列表自动切换）。

- **AppBar**：标题"插件管理"，右侧 `PopupMenuButton`（`Icons.add`），两项：
  - "从文件导入（Phase 6+）" → `SnackBar('从文件导入（Phase 6+ 实现）')`
  - "安装示例插件（Phase 3.5 验证用）" → `PluginProvider.installExamplePluginForDemo()`，
    按成功与否弹不同 SnackBar
- **空列表** → `EmptyState(Icons.extension, '还没有安装插件', '从文件导入或从创意工坊下载', '去创意工坊')`
- **有插件** → `ListView.builder`，每项一张 `_PluginCard`

**卡片布局**（`Card` + `ListTile`）：

| 位置 | 内容 |
|------|------|
| `leading` | 图标：由**第一个能力**经 `_iconNameForCapability` 映射到图标名，再走 `iconFromName`（查不到兜底 `Icons.extension`） |
| `title` | 插件名 + 右侧状态徽章 |
| `subtitle` 第一行 | `版本 x.x.x · 作者`（作者为空显示"未知作者"） |
| `subtitle` 第二行 | 能力标签（`考试 · 作业` 形式，`_capabilityLabel` 中文化；插件自定义能力原样显示 id） |
| `trailing` | `Switch`，值 = `meta.enabled`，`onChanged` → `provider.togglePlugin(id, v)` |
| `onTap` | push `PluginDetailPage(pluginId: meta.id)` |

**状态徽章四态**（抽成公开枚举 + 纯函数，便于单独测试）：

- `enum PluginUiStatus { loaded, failed, enabledNotLoaded, disabled }`
- `PluginUiStatus pluginUiStatusOf({required bool enabled, required bool isLoaded, required bool hasError})`
  — **优先级：失败 > 已加载 > 已启用未加载 > 已停用**。失败优先于成功，因为"失败原因"对用户最有价值
- `Color pluginUiStatusColor(PluginUiStatus status, AppTheme theme)` —
  `loaded → theme.success`（绿）、`failed → theme.error`（红）、
  `enabledNotLoaded → theme.warning`（黄）、`disabled → theme.onBackground.withValues(alpha: 0.3)`（灰）
- `String pluginUiStatusLabel(PluginUiStatus status)` — 已加载 / 加载失败 / 已启用，尚未加载 / 已停用
- 常量 `kPluginStatusDotSize = 10`（徽章圆点直径；`AppTheme` 无徽章尺寸令牌，按 `empty_state.dart` 先例设为组件级常量）

徽章实现为 `Tooltip` + `Semantics` + 圆形 `Container`，**Key 为 `ValueKey('plugin-status-<id>')`**，
便于测试与调试定位；tooltip / 无障碍文案在失败时带上 `loadErrors` 的原因。

### `settings/plugin_detail_page.dart` — PluginDetailPage（Phase 3.5）

```dart
class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({super.key, required this.pluginId});
  final String pluginId;
}
```

- **AppBar**：标题 = 插件名；**`isRemovable == true`** 才显示"卸载"（`Icons.delete_outline`）。
  **Phase 3.5.1 修正**：此前用 `!meta.isBuiltIn` 判断，导致从 assets 安装的示例插件
  （`source == 'builtin'`）看不到卸载入口；现在只看独立的策略字段 `isRemovable`
- 插件不存在（已卸载 / id 失效）→ 显示"插件不存在或已卸载"兜底文案，不崩
- Body = `ListView`，三个分区卡片：

| 分区 | 内容 |
|------|------|
| 基本信息 | 插件 ID / 版本 / 作者 / 描述 / 能力 / 来源（中文）/ **安装路径** / 加载状态（带状态色） |
| 运行时 | 沙箱（可用 / 不可用 / 未创建）、入口函数列表、降级原因（不可用时，红色） |
- **操作** | `SwitchListTile` 启用；"登录"（**Phase 4.1 起接真实 WebView 登录**）、"立即同步"（SnackBar 占位，Phase 4.2/4.3）、"查看日志"（SnackBar 占位） |

- **安装路径**用 `FutureBuilder` 异步读 `PluginStorageService.getPluginJsPath(pluginId)`：
  读取中 → `读取中…`；出错 → `读取失败`；`null` → `未安装（插件目录中找不到 .js 文件）`
- **卸载**：`showDialog` 确认（"确定要卸载插件「X」吗？这会删除插件文件与本地数据。"）→
  确认后 `await provider.removePlugin(id)` → `context.mounted` 检查 → `Navigator.pop()`
- **登录**（Phase 4.1）：读 `handle.manifest?.loginUrl` / `checkUrl`（**插件自己声明**，
  内核不硬编码任何学校 URL）；`loginUrl` 为空 → `SnackBar('该插件未声明登录地址（loginUrl）')`，不跳转；
  否则 push `WebViewLoginPage(pluginId: meta.id, ...)`（由登录页负责落盘），
  返回非空 Cookie → `SnackBar('登录成功（已保存 N 字符的 Cookie）')`，
  返回 `null`/空 → `SnackBar('已取消登录')`
- 辅助私有组件：`_InfoCard`（分区卡片）、`_InfoRow`（标签 : 值，值可换行）、
  `_InstallPathRow`、`_ActionRow`

> **注意（测试相关）**：`_InstallPathRow` 里的 `getPluginJsPath` 是**真实文件 I/O**，
> `testWidgets` 默认的 fake-async **不会推进它**（会永远停在"读取中…"），
> 相关断言必须放在 `tester.runAsync(...)` 里。

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

## lib/runtime/

### 插件上下文（`ctx`）——Phase 3.6

插件在沙箱里拿到的宿主能力，**五类**：

| 面 | API | 本阶段状态 |
|----|-----|-----------|
| HTTP | `ctx.http.get(url, headers)` / `ctx.http.post(url, body, headers)` | ✅ 真发（dio 代理） |
| 私有存储 | `ctx.storage.get(key)` / `set(key, value)` / `remove(key)` | ✅ 真存（Hive `plugin_data`） |
| 日志 | `ctx.log.info(msg)` / `ctx.log.error(msg)` | ✅ → `debugPrint` |
| 通知 | `ctx.notify.schedule(title, body, triggerAtIso)` | ⏳ 占位（只记日志，Phase 7 接真实通知） |
| 凭证 | `ctx.cookie`（属性） | ⏳ 只读；Phase 4 由 WebView 登录写入 |

**不做**：权限系统（所有插件都能用全部 ctx）、网络白名单。

#### ⚠️ 为什么 `ctx.http` 是"登记待办 + 宿主重放"而不是直接同步请求

任务书原设想"Dart 暴露 `__dart_http_get(url, headers) → responseJson`"，但**在当前架构下不可能**：

1. 沙箱跑在**独立 isolate**，`onMessage` 的 Dart 回调是在子 isolate 里执行的闭包，
   而 dio / Hive / secure_storage 都在主 isolate——**闭包跨不了 isolate**；
2. 就算能跨，`sendMessage` 通道要求 Dart 侧**同步**返回，而 dio 是异步的；
3. JS 又**无法挂起**：本库唯一的异步路径（`fetch`/Promise）走 `callFunction`，
   而 QuickJS 后端该方法是 `UnimplementedError`（Phase 3.2a 实测）；
4. 唯一可用的**同步** HTTP 客户端 `sync_http` 用 `RawSynchronousSocket`（**纯 TCP，无 TLS**），
   不能 HTTPS——教务系统全是 HTTPS，等于没用（而且它是 flutter_js 的传递依赖，直接用要改 pubspec）。

因此采用**重放式同步外观**（Phase 3.6 决策 B）：

```
1. 宿主每轮先注入"本轮状态"（HTTP 响应缓存 / storage 快照 / cookie）为 JS 全局
2. 插件照常写 var r = ctx.http.get(url) —— 命中缓存就同步拿到响应
3. 未命中时 ctx.http.get 只把请求登记进待办并返回 {ok:false,error:'pending'}，绝不发网络
4. 宿主读回本轮的待办与副作用
5. 有待办 → 用 dio 取回（真超时）→ 并入缓存 → 重放插件函数
6. 没有待办的那一轮 = 最终轮：提交其 storage / log / notify 副作用并返回
```

**代价与约束（写进文档）**：
- 插件函数会被**执行多次**，所以它必须是幂等的纯计算；
- 副作用**只在最终轮生效**（每轮都从同一 storage 快照开始），中间轮次的 `ctx.storage` 修改被丢弃；
- 顶层（`__plugin` 定义处）调用 `ctx.*` 无意义——那时还没有"轮"，副作用不会被提交；
- 同一轮内对同一 `(method,url,body,headers)` 重复请求只登记一次；跨轮命中缓存。

### `plugin_ctx_script.dart` — ctx 的 JS 侧契约

> # ⚠️ 写插件前必读：入口函数必须幂等
>
> **`ctx.http` 用"登记待办 + 宿主重放"实现，因此插件的入口函数会被宿主执行多次。**
> 三条硬约束（完整说明见 `CONTEXT.md` 3.6）：
>
> 1. **入口函数必须是幂等的纯计算** —— 不要做自增 / 累加 / 发消息这类重复执行会出错的副作用；
> 2. **`ctx.storage` 的修改只在最终轮生效** —— 每轮都从同一快照开始，
>    中间轮次的修改会被丢弃（**同一轮内** `set` 后 `get` 仍然可见）；
> 3. **`ctx.*` 只应在入口函数里使用** —— 顶层（`__plugin` 定义处）调用不会被提交。
>
> 请求去重：同一轮内对同一 `(method, url, body, headers)` 只登记一次，跨轮命中缓存，
> 所以"循环请求同一个 URL"是安全的。轮数上限 8（`PluginContext.kMaxReplayRounds`）。

- `const String kPluginCtxScript` — 预置脚本，定义全局 `ctx` 与内部 primitive
  （`__ctx_http` / `__ctx_storage_get|set|remove`）及本轮状态变量。
  **全部在 JS 侧实现**：未命中缓存只是 `push` 进 `__ctx_http_pending`，不发任何 Dart 通道
- `String buildCtxStateScript({required Map<String,String> httpCache, required Map<String,String> storage, required String cookie})`
  — 构造"本轮状态"脚本，宿主每轮执行插件函数前求值；同时清空待办/日志
- `const String kCtxDumpScript` — 读回本轮副作用，返回
  `{pending, storage, touched, logs, notifies}` 的 JSON
- Dart ↔ JS 边界**只传字符串**：状态与副作用都用 `jsonEncode` 嵌成 JS 字面量 / 用 `jsonDecode` 解析

### `plugin_context.dart` — PluginContext（Phase 3.6）

宿主侧 ctx 实现 + 重放循环。

构造：`PluginContext({required String pluginId, Dio? dio, FlutterSecureStorage? secureStorage})`
（`dio` 可注入，测试用自定义 `HttpClientAdapter` 即可不打真网络）

常量：`kHttpConnectTimeout = 10s`、`kHttpReceiveTimeout = 15s`、`kMaxReplayRounds = 8`、
`kUserAgent = 'MySchedule/0.1'`、`kCookieKeySuffix = ':cookie'`、`kStorageKeySeparator = ':'`

- `Future<JsSandboxResult> execute({required JsSandbox sandbox, required String entryCallScript, Duration timeout = kDefaultJsTimeout})`
  — 驱动重放循环。**只要本轮登记了待办就重放**（无论本轮是成功、抛错还是 `pending`），
  这样插件写不写 `try/catch` 都正确；轮数超过 `kMaxReplayRounds` 返回 `error` 防死循环
- `Future<String> loadCookie()` — 读 `flutter_secure_storage` 的 `<pluginId>:cookie`；
  不存在 / 读取失败（含测试环境无平台通道）一律返回空串，不抛异常
- `Future<Map<String, String>> loadStorageSnapshot()` — 用 `pluginDataBox.toMap()` 一次读整表再按前缀过滤
- `Future<void> commitStorageChanges({required Map<String,String> storage, required List<String> touched})`
  — 只写 `touched` 里的键（存在于 `storage` 则写，否则删）
- `Future<Map<String, String>> performHttpRequests(List<PluginHttpRequest> requests)` — **串行**执行（插件的请求常有先后依赖，且对教务系统更友好）

`PluginHttpRequest`（`@immutable`）：`method` / `url` / `key` / `body` / `headers`，
另有 `static PluginHttpRequest? tryParse(Object? raw)`（缺字段/类型不符返回 `null`，跳过该条）。

**HTTP 响应 JSON（Dart → JS 统一格式）**：

```json
{ "ok": true,  "status": 200, "body": "...", "headers": {"content-type": "..."} }
{ "ok": false, "error": "timeout" }
```

`error` 取值：`timeout`（连接/发送/接收/转换超时）、`connection`、`bad_certificate`、
`cancelled`、`bad_response`、`unknown`；另有内部标记 `pending`（插件在最终轮不会看到）。

- **任何状态码都算"拿到响应"**（`validateStatus: (_) => true`）：4xx/5xx 的正文对插件往往有用
  （教务系统常用 500 返回错误页），由插件自己判断 `status`
- 固定加 `User-Agent: MySchedule/0.1`，便于教务系统识别
- **真失败时 `ctx.http.get` 会抛错**（`error !== 'pending'`），插件可用 `try/catch` 接住；
  也可以不接——那这一轮就是 error 结果

### `js_sandbox.dart` — JsSandbox（Phase 3.2a）

把 flutter_js（QuickJS）包成**不会拖死 UI 线程、不会因插件乱来而崩溃**的执行环境。JS 在**独立 isolate** 里跑，父 isolate 只管计时。

> **为什么必须用独立 isolate（实测结论，不是设计偏好）**：`QuickJsRuntime2.timeout` **实测无法中断死循环**——`while(true){}` 传 `timeout=1000` 与 `timeout=1` 都永久挂住；又因为 `evaluate()` 是**同步 FFI 调用**，主 isolate 被阻塞在原生调用里，Dart 侧的 `Future.timeout` / 测试 `Timeout` **也一并失效**。因此唯一可靠的兜底是"子 isolate 跑 + 到点 `Isolate.kill(priority: immediate)`"。

> **不要传 `memoryLimit`**：`QuickJsRuntime2` 在 `memoryLimit > 0` 时调用 `jsSetMemoryLimit`，而该符号在**两个随包二进制里都不存在**——Windows `quickjs_c_bridge.dll` 抛 `Failed to lookup symbol`（error 127，**未被捕获**、直接打死 isolate）；Android `libfastdev_quickjs_runtime.so`（取自 APK）的符号名不在 `.dynstr` 中。同库的 `jsNewRuntime` / `jsEval` / `jsSetMaxStackSize` / `jsFreeRuntime` 都在。故本沙箱不传 `memoryLimit`，内存失控由"隔离 + 截止时间 kill"兜底。

> **不能用 `getJavascriptRuntime()`**：它只透传 `extraArgs['stackSize']`，**不接受也不转发** `timeout` / `memoryLimit`。故沙箱直接构造 `QuickJsRuntime2`。

常量：

| 常量 | 值 | 说明 |
|------|-----|------|
| `kDefaultJsTimeout` | `1000ms` | 单次执行的默认**墙钟**上限。正常求值实测 <1ms，1000ms 足够宽裕又能掐掉失控脚本 |
| `kJsSandboxCreateTimeout` | `5s` | 创建（isolate 启动 + QuickJS 初始化）等待上限。QuickJS 初始化实测约 22ms |
| `kJsStackSize` | `1MB` | QuickJS 栈上限，沿用 flutter_js 默认值 |
| `kJsNativeTimeoutHintMs` | `1000` | 传给原生 `jsNewRuntime` 的 timeout。**纵深防御**：将来若换到实现了中断的二进制可生效；当前实测无效，**不要依赖它** |
| `kSandboxLogChannel` | `'log'` | 插件日志通道名（`ctx.log` 雏形） |

#### `enum JsSandboxStatus`
取值：`success`（执行成功）、`error`（JS 出错：语法/运行时异常）、`timeout`（执行超时，子 isolate 已被 kill）、`unavailable`（沙箱创建失败或已销毁）。

#### `class JsSandboxResult`（`@immutable`）
所有失败都表现为"带状态的结果对象"，**不抛异常**。

| 成员 | 类型 | 说明 |
|------|------|------|
| `status` | `JsSandboxStatus` | 结果状态 |
| `value` | `String?` | 成功时的 JS 返回值（`JsEvalResult.stringResult`） |
| `message` | `String?` | 失败原因（错误信息 / 超时说明 / 不可用原因） |
| `isSuccess` / `isUnavailable` / `isTimeout` | `bool` | 便捷判定 |

命名构造：`JsSandboxResult.success(String)` / `.error(String)` / `.timeout(String)` / `.unavailable(String)`

#### `class JsSandbox`

生命周期：`create()` → 多次 `execute()` → `dispose()`。**一旦某次执行超时，子 isolate 已被 kill，沙箱即变为不可用**（`isUsable == false`），后续调用返回 `unavailable`；要继续用就重新 `create()`。

- `static Future<JsSandbox> create({int stackSize = kJsStackSize, Duration createTimeout = kJsSandboxCreateTimeout, void Function(String message)? onLog, @visibleForTesting bool simulateCreateFailure = false})` — 创建沙箱。**任何创建失败都降级为不可用沙箱并 `debugPrint` 原因，不抛异常**；调用方先看 `isUsable`，据此把插件标记为"不可用"。
  - 失败来源三类：子 isolate 起不来（`Isolate.spawn` 抛异常）；QuickJS 初始化抛异常（子 isolate 回传 `_WorkerCreateFailed`）；**子 isolate 被原生层静默打死**（如符号缺失，既不发 ready 也不发 failed）——最后一类靠 `createTimeout` 计时器收敛，不会无限等
  - `onLog` 接收插件经 `sendMessage('log', ...)` 打出的日志，在**父** isolate 上回调（可安全更新 UI）
  - `simulateCreateFailure` 仅测试用（验证降级路径）
- `bool get isUsable` — 创建成功且未因超时/`dispose` 失效
- `String? get unavailableReason` — 不可用原因（创建失败 / 超时后销毁 / 已 dispose）；可用时为 `null`。**Phase 3.2b.1 新增**，供 `PluginRuntime` 把"插件不可用"的具体原因透传给用户
- `Future<JsSandboxResult> execute(String script, {Duration timeout = kDefaultJsTimeout})` — 在沙箱里执行 JS。`timeout` 是**墙钟**上限；超时即 kill 子 isolate 并返回 `timeout` 状态
- `Future<void> dispose()` — kill 子 isolate 并关闭端口。**幂等**

内部实现要点：
- **串行化**：`_serialize` 用 Future 链保证同一时刻只有一个求值在飞，请求/应答按单调递增的 `seq` 校验归属，避免错配
- **握手协议**（子 → 父）：`_WorkerReady`（运行时创建成功）→ `SendPort`（请求端口）→ `_EvalReply` / `_LogMessage`；失败为 `_WorkerCreateFailed(reason)`
- 子 isolate 用长驻 `ReceivePort` 接收求值请求，**沙箱可复用**，不必每次重建 isolate

> 本阶段**不做**（留给后续）：权限控制、插件文件加载、`ctx.http` / `ctx.storage` 等跨 isolate 的服务注入、Promise 支持（库的 Promise 路径走 `callFunction`，而 QuickJS 后端该方法是 `UnimplementedError`）。

---

### 插件文件格式（Phase 3.2b.1 定义，最小版）

一个插件由**一个必需文件 + 一个可选文件**组成（同目录、同主名）：

```
demo.js               必需。插件脚本。
demo.manifest.json    可选。元数据。
```

**`<name>.js`（必需）** —— 必须定义全局对象 `__plugin`（常量 `kPluginGlobalName`），
其属性中的**函数**即入口函数：

```js
var __plugin = {
  id: 'demo-course-plugin',        // 必需（或用 manifest 文件提供）
  name: '演示课程插件',
  version: '1.0.0',
  capabilities: ['exam'],
  fetchCourses: function (args) {  // 入口函数，收到一个普通对象
    return { courses: [] };        // 返回值会被 JSON 序列化回 Dart
  }
};
```

**`<name>.manifest.json`（可选）** —— 缺省时元数据从 `__plugin` 的
`id`/`name`/`version`/`author`/`description`/`school`/`capabilities` 推导；
**manifest 文件存在时优先**。键名一律小驼峰（CONTEXT 4.2.1）：

```json
{
  "id": "demo-course-plugin",
  "name": "演示课程插件",
  "version": "1.0.0",
  "author": "",
  "description": "",
  "school": "",
  "capabilities": ["exam", "homework"]
}
```

**加载校验规则**（任一不满足即降级，见下方映射表）：脚本能求值成功（语法合法）→
`__plugin` 存在且为对象 → 至少有一个函数属性 → `id` 非空（manifest 或 `__plugin.id`）。

**数据交换约定**（沿用 3.2a 约束）：入参经 `JSON.parse` 进入 JS、返回值经
JS 侧 `JSON.stringify` 出来、Dart 侧 `jsonDecode` 解析；**不使用 `convertValue`**。

**可用能力（Phase 3.6 起）**：入口函数里可以直接用全局 `ctx`
（`ctx.http` / `ctx.storage` / `ctx.log` / `ctx.notify` / `ctx.cookie`，见下方「插件上下文」一节）。
> ⚠️ 因为 `ctx.http` 用"重放"实现，**入口函数会被执行多次**：
> 它必须是幂等的纯计算；`ctx.storage` 的修改只在最终轮生效。
> 另外 `ctx.*` 只应在**入口函数里**用，顶层调用不会被提交。

**插件文件从哪来**：Phase 3.4 起由 `PluginStorageService` 管理，插件文件位于应用私有目录
`<appDocuments>/plugins/`；`PluginManager.defaultSourceResolver` 按 `meta.id` 现算路径。
**Phase 3.5 起**还支持从 **assets** 安装内置 / 示例插件
（`PluginStorageService.installFromAssets`，见该小节）——读出内容后同样落到插件目录，
因为运行时只从文件系统加载。
> **内置示例插件**：`assets/plugins/example.js`（`pubspec.yaml` 已声明 `assets/plugins/`），
> 由 `PluginProvider.installExamplePluginForDemo()` 安装。**这是临时的**，
> Phase 4 做出真实教务插件后连同该方法一起删除。
>
> **仍未做**："用户从任意文件导入插件"需要文件选择器（`file_picker` 等新依赖），
> 属 Phase 6+，当前 UI 上是 SnackBar 占位。

### `plugin_manifest.dart` — PluginManifest

插件 manifest 模型（插件文件格式的**可选**元数据部分）。**不包含 UI 信息**
（导航栏模块等属 `PluginMeta` / `ModuleInfo` 职责）。

常量：`kPluginManifestSuffix = '.manifest.json'`

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 插件唯一 ID，**必须非空**（由加载器校验） |
| `name` | `String` | 显示名 |
| `version` | `String` | 版本号，默认 `'0.0.0'` |
| `author` / `description` / `school` | `String` | 作者 / 说明 / 适用学校 |
| `capabilities` | `List<String>` | 能力 ID 列表，默认空 |
| `loginUrl` | `String` | **登录页 URL（Phase 4.1 新增）**。空串表示未声明，插件详情页的「登录」会提示用户。各校教务地址不同，由**插件自己声明**（内核不得硬编码，CONTEXT 3.1） |
| `checkUrl` | `String` | **登录成功判定用的 URL 前缀（Phase 4.1 新增）**。登录页里当前 URL 以它为前缀即判定成功；空串表示未声明，登录页退化为"拿到任意 Cookie 即视为成功" |

构造：`const PluginManifest({required id, required name, String version = '0.0.0', String author = '', String description = '', String school = '', List<String> capabilities = const []})`

方法：
- `bool get hasValidId` — `id` 非空且非纯空白
- `bool get hasCapabilities`
- `factory PluginManifest.fromJson(Map<String, dynamic> json)` — 缺失用兜底值、类型不符忽略该项，**不抛异常**（数字/布尔会被转成字符串）
- `Map<String, dynamic> toJson()` — 键名与 `fromJson` 一一对应
- `static PluginManifest? tryDecode(String? raw)` — 空值 / 坏 JSON / 非对象 / **缺 `id` 或 `id` 为空白**一律返回 `null`（供加载器判定"manifest 不可用"，不伪造）

### `plugin_handle.dart` — PluginHandle

一个已加载插件的句柄。**不可变值对象 + 持有独占 `JsSandbox`**。

常量：`kPluginGlobalName = '__plugin'`

顶层函数：`String buildPluginEntryCallScript(String entryFunction, Map<String, dynamic>? args)` —
构造"调用插件入口函数"的 JS 脚本。
- 函数名与参数都用 `jsonEncode` 转成 **JSON 字符串字面量**再嵌入（JSON 转义是 JS 字符串字面义的子集，故 `jsonEncode` 两次得到的 `"{\"a\":1}"` 就是合法 JS 字面量），免去手写转义
- 入口函数不存在时 `throw`，由沙箱捕获成 `error`
- `JSON.stringify(undefined)` 返回 `undefined` 而非字符串，故显式归一为 `'null'`

| 字段 | 类型 | 说明 |
|------|------|------|
| `status` | `JsSandboxStatus` | 加载/运行状态，**复用沙箱四态** |
| `manifest` | `PluginManifest?` | 元数据；降级过早（文件都读不到）时为 `null` |
| `source` | `String` | 插件 JS 源码（读不到时为空串） |
| `entries` | `List<String>` | 发现的入口函数名列表 |
| `sourcePath` | `String?` | 插件文件路径；从 `jsSource` 加载时为 `null` |
| `reason` | `String?` | 降级原因（仅加载失败时有值） |

构造：`const PluginHandle({required status, manifest, source, entries, sourcePath, reason, JsSandbox? sandbox})`
（`sandbox` 存进私有字段；正常由 `PluginRuntime` 创建，业务代码不要自己构造）

方法：
- `bool get isUsable` — **动态判定**：`status == success` **且**底层沙箱仍存活。因此插件某次执行超时（沙箱被 kill）后会自动变 `false`，无需改字段——这也是本类能保持完全不可变的原因
- `bool get isLoaded` — 只看加载结果（不含沙箱后续存活状态）
- `Future<JsSandboxResult> execute(String entryFunction, {Map<String, dynamic>? args, Duration timeout = kDefaultJsTimeout})` — 调用入口函数，返回沙箱四态，**不抛异常**。**Phase 3.6 起**：若句柄持有 `PluginContext`（私有字段 `_context`），会走 `context.execute(...)` 的**重放**流程；否则退化为单次求值（兼容 Phase 3.5 之前的用法与测试）
- `Future<void> dispose()` — 销毁独占沙箱，幂等

> **为什么每插件一个沙箱**：`__plugin` 是全局变量，共用沙箱会让两个插件互相覆盖；
> 独占沙箱还能做到"某个插件死循环只打死它自己的 isolate"，与 3.2a 的隔离设计一致。

### `plugin_runtime.dart` — PluginRuntime

插件运行时骨架：把「插件文件」变成「可执行的 JS」。**不做** `ctx.http` / `ctx.storage`
注入（留给 3.2b.2 / 3.2b.3），**不接 UI**。

构造：`PluginRuntime({Duration loadTimeout = kDefaultJsTimeout, Duration executeTimeout = kDefaultJsTimeout, void Function(String message)? onLog, @visibleForTesting bool simulateSandboxFailure = false, Dio? dio})`

- `dio` 透传给 `PluginContext`（测试注入自定义 adapter 即可不打真网络）
- `loadPlugin` 流程：取源码 → 起沙箱 → **注入 `kPluginCtxScript`（定义全局 `ctx`）** → 顶层求值插件源码 → 校验 `__plugin` → 收集入口函数 → 取/推导 manifest → 创建 `PluginContext` 挂到 handle。
  **注入顺序很重要**：`ctx` 必须先定义好，插件的顶层代码才能引用它

- `Future<PluginHandle> loadPlugin({String? path, String? jsSource, String? manifestPath})` — 加载插件。
  - 源码来源优先级：`jsSource` → `path` 读文件 → 都没有则降级
  - `manifestPath` 不传时，默认在 `path` 同目录找同主名的 `.manifest.json`
  - 流程：取源码 → 起沙箱 → 顶层求值 → 校验 `__plugin` → 收集入口函数 → 取/推导 manifest
  - **任何失败都返回降级 handle**（`isUsable == false` + `reason`），**绝不抛异常**
  - 失败后会立即销毁已建立的沙箱，避免 isolate 泄漏
- `Future<JsSandboxResult> execute(PluginHandle handle, String entryFunction, {Map<String, dynamic>? args, Duration? timeout})` — 调用入口函数，委托给 `PluginHandle.execute`
- `int get handleCount` — 已创建的 handle 数（含降级失败的）
- `Future<void> dispose()` — 销毁所有插件沙箱，幂等
- `void unawaitedDispose(JsSandbox sandbox)`（同文件顶层函数）— 不等待地销毁沙箱，供降级路径使用

**四条错误路径的降级映射**：

| 情况 | `status` | `reason` 含 |
|------|----------|-------------|
| 文件不存在 / 不可读 / 为空 / 两个来源都不给 | `unavailable` | `插件文件不存在或不可读` / `插件文件为空` / `必须提供 path 或 jsSource` |
| 非法 JS（语法错误 / 运行时抛错） | `error` | `插件脚本加载失败` |
| 缺 `__plugin` / 无函数属性 / 缺 id / manifest 坏 | `error` | `未定义全局` / `入口函数` / `缺少 id` / `manifest 解析失败` |
| 顶层死循环（加载时） | `timeout` | `插件脚本加载超时（顶层可能死循环）` |
| 入口函数死循环（执行时） | `timeout` | 沙箱返回的 `执行超时（Nms）` |
| 沙箱创建失败 / 已销毁 | `unavailable` | `JS 沙箱不可用：<原因>` |

> 插件执行超时后该插件的沙箱被 kill，`handle.isUsable` 随之变 `false`，
> 后续调用返回 `unavailable`；要恢复需重新 `loadPlugin`。

---

### `plugin_manager.dart` — PluginManager（Phase 3.3）

多插件管理器：管理"当前已加载的插件运行时句柄"（加载 / 卸载 / 查询 / 能力汇总）。
它把 3.2b.1 的 `PluginRuntime`（只能加载**单个**插件）包成多插件管理。

**本类不继承 `ChangeNotifier`**（无状态服务）：只管资源生命周期，通知 UI 是 `PluginProvider` 的职责。

类型别名：
- `typedef PluginSource = ({String? path, String? jsSource})` — "从哪读插件的 JS"，二者给其一
- `typedef PluginSourceResolver = Future<PluginSource> Function(PluginMeta meta)` — 把 meta 解析成来源。**Phase 3.4 起改为异步**（原为同步 `PluginSource Function(PluginMeta)`）：解析默认要查"插件文件在不在"，本身就是异步 I/O；同步签名只能靠"必须先预热全局缓存、否则静默返回 null"来伪装，那是个容易踩的坑（忘了预热就变成"插件莫名不可用"）。而 `load()` 本来就是 `async`，await 解析器零额外成本

构造：`PluginManager({PluginRuntime? runtime, PluginSourceResolver? sourceResolver})`
- 都不传时自建 `PluginRuntime()` 并使用 [defaultSourceResolver]
- 抽成可注入是为了：① 测试可绕过文件系统直接给 `jsSource`（否则必须往磁盘写 .js 文件）；② 将来换安装位置或加内置插件时只换解析器，本类不用改

- `static Future<PluginSource> defaultSourceResolver(PluginMeta meta)` — **Phase 3.4 起从插件安装目录取 `<id>.js`**（`PluginStorageService.getPluginJsPath(meta.id)`），**不再读 `meta.assetPath`**（安装路径是 id 的纯函数，存进 meta 既冗余、又会在应用容器路径变化后失效）。id 非法或未安装时两者给 `null`，由 `load` 降级为"插件未安装"，**不抛异常**
- `Map<String, PluginHandle> get loadedHandles` — `meta.id → handle`，**不可变视图**。**包含加载失败的降级 handle**（`isUsable == false`），这样调用方既能查到"尝试过"，也能读到失败原因
- `int get loadedCount` — 已成功加载（沙箱可用）的数量
- `int get handleCount` — 全部 handle 数（含降级）
- `Future<PluginHandle> load(PluginMeta meta, {String? jsSource})` — 加载一个插件
  - **已加载且可用** → 直接返回既有 handle（跳过，不重复建沙箱）
  - 既有 handle 是**降级**的（上次失败）→ 先 `dispose` 再重试（降级不算"已加载"）
  - `jsSource` 优先于 `sourceResolver`
  - 没有可加载来源时**不白起沙箱**，直接降级为"插件未安装（在插件目录中找不到 `.js` 文件），或插件 id 非法"
  - 解析器抛异常会被兜住并降级（默认解析器走文件系统，可能因权限失败）
  - 插件自报 `id` 与安装 `id` 不一致时 `debugPrint` 提示，**仍按安装 id 管理**
  - **不抛异常**：任何失败都返回降级 handle
- `Future<void> unload(String pluginId)` — 销毁沙箱并移出映射；找不到该 id 为空操作
- `PluginHandle? getHandle(String pluginId)` — 含降级 handle
- `bool isLoaded(String pluginId)` — 是否已加载**且可用**
- `Set<String> get allLoadedCapabilities` — 已加载（**沙箱可用**）插件的能力并集，已去重。同时取两处来源：`handle.manifest.capabilities` 与 `meta.effectiveCapabilities`（`capabilities` ∪ 各 `modules` 的 `capabilityId`），避免漏掉任一种声明方式。**只统计可用插件**——加载失败的插件不该让模块变成可用
- `Map<String, String> get loadErrors` — 加载失败原因（`id` → 原因），不可变视图
- `Future<void> disposeAll()` — 卸载全部并销毁内部运行时。幂等；销毁后再 `load` 返回降级 handle（`已销毁`）

---

### `plugin_demo.dart` — PluginDemo（**Phase 3.1 临时验证文件**）

flutter_js 集成验证类。**仅用于确认 QuickJS 能在本项目里跑起来**，Phase 3.2 起被正式的 `plugin_runtime.dart` 替代。全部方法为 `static`，纯静态类（`PluginDemo._()` 禁止实例化）。

每个方法都是**自建运行时 → 执行 → `dispose()`** 的独立闭环（finally 里必然释放），因此可重复调用、互不影响。运行时统一用 `getJavascriptRuntime(xhr: false)`——本阶段不测网络，关掉内置 fetch/XHR 扩展；Android / Windows / Linux 走 QuickJS，其他平台走 JavaScriptCore，调用方无需关心平台差异。

| 方法 | 返回 | 说明 |
|------|------|------|
| `static int? evalSimple()` | `2` | 执行 `1 + 1`，验证"能建运行时 + 能执行 + 能取值" |
| `static String? evalWithCallback()` | `'pong\|from-dart'` | 注册 `onMessage('demoEcho', ...)`，JS 侧 `sendMessage('demoEcho', JSON.stringify('ping'))` 取回 Dart 返回值 |
| `static Map<String, dynamic>? evalWithObject()` | 课程对象 Map | JS 构造对象 → `JSON.stringify` → Dart `jsonDecode` |
| `static String? evalInvalid()` | 非空错误串 | 执行非法 JS，验证 `isError == true` 且**不抛异常** |

**失败一律返回 `null` 而非抛异常**，并 `debugPrint` 原因，调用方可据此判断集成是否可用。

私有辅助：`_createRuntime()`、`_asInt(Object?)`（兼容 QuickJS 把数字给成 `int` 或 `double`，`2.0` 也算 `2`）、`_decodeJsonObject(String)`（解析出非对象或坏 JSON 返回 `null`）。

> **两条实测得到的实现约束**（Phase 3.2 必须沿用）：
> 1. QuickJS 后端的 `JavascriptRuntime.jsonStringify` 是 `UnimplementedError`，**不能**用它序列化；要 JSON 就得在 JS 侧调 `JSON.stringify(...)` 再在 Dart 侧 `jsonDecode`。`rawResult` 的 Dart 类型（Map / JSInvokable）不够稳定，也不宜直接依赖。
> 2. `evaluate()` 在 QuickJS 后端是**同步**返回，且**语法错误不抛异常**——错误通过 `JsEvalResult.isError == true` 传递，必须显式检查该标志位。

---

### `main.dart` — 入口

- `Future<void> main()` — `WidgetsFlutterBinding.ensureInitialized()` → `await StorageService.init()` → 依次建 `CourseProvider` / `ModuleProvider` / `SemesterProvider` / `SettingsProvider` / `ThemeProvider` 并各自 `await loadFromStorage()` → **Phase 3.3 起再建 `PluginProvider`，`await loadFromStorage()` + `await loadAllEnabledPlugins()`** → `runApp(buildApp(...))`。**先读数据再起 UI**，避免首帧闪一下默认值（如导航栏先显示默认 4 个模块再跳成用户配置）
  - 插件运行时加载失败只降级、不影响启动（`loadAllEnabledPlugins` 内部逐个 try-catch）
- `Widget buildApp({CourseProvider? courseProvider, ModuleProvider? moduleProvider, SemesterProvider? semesterProvider, SettingsProvider? settingsProvider, ThemeProvider? themeProvider, PluginProvider? pluginProvider})` — 构建完整 App（Provider 树 + `MyApp`）。抽成函数是为了让 widget 测试直接 `pumpWidget(buildApp())`，验证的就是 `main()` 真正使用的那棵树
  - `courseProvider` / `semesterProvider` / `settingsProvider` / `themeProvider` / `pluginProvider` 传入时用 `ChangeNotifierProvider.value`（实例归调用方所有，不随树销毁而 dispose）；不传时内部 `create` 空实例（测试 / 预览用，不访问 Hive）
  - `moduleProvider` 由 `ChangeNotifierProxyProvider` 创建（该 Provider 无 `.value` 变体），注入的实例会被树接管生命周期；**不要**把同一个 `ModuleProvider` 实例同时传给两棵树（先卸载的那棵会 dispose 它）

Provider 顺序（即依赖顺序，被依赖者必须在前）：

| # | Provider | 依赖 |
|---|----------|------|
| 1 | `ChangeNotifierProvider<ThemeProvider>` | 无 |
| 2 | `ChangeNotifierProvider<PluginProvider>` | 无 |
| 3 | `ChangeNotifierProxyProvider<PluginProvider, ModuleProvider>` | PluginProvider |
| 4 | `ChangeNotifierProvider<CourseProvider>` | 无 |
| 5 | `ChangeNotifierProvider<MessageProvider>` | 无 |
| 6 | `ChangeNotifierProvider<SemesterProvider>` | 无 |
| 7 | `ChangeNotifierProvider<SettingsProvider>` | 无 |

> 注：prompt 把 `ModuleProvider` 列在第 2 位、`PluginProvider` 列在最后，但 `ChangeNotifierProxyProvider<PluginProvider, ModuleProvider>` 必须能读到 `PluginProvider`，故两者顺序对调。

> **临时测试数据已移除**：Phase 2.2b 曾在此写入 1 个测试学期与 3 门课供真机验收，
> 已在 Phase 2.2b.1 按计划**全部删除**（`_seedTemporaryTestData` 及其调用与相关 import）。
> 注意：已经写进设备的那些数据仍留在 Hive 里，需要清一次（见 PROGRESS 阻塞表）。

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

### `timetable_grid.dart` — TimetableGrid

课表网格（**纯展示组件**：不读 Provider、不访问存储）。用 `Stack` + `Positioned` 绝对定位，**不用 `Table`**（`Table` 不支持 rowspan，而连上 3 节的课要占 3 格高度）。

```dart
const TimetableGrid({
  super.key,
  required List<List<Course?>> grid,          // (7+1) × (12+1)，索引 0 为占位
  required Map<int, String> sectionTimes,     // {1: '08:30-09:15', ...}
  required int currentWeek,                   // 用于卡片 Key，切周时重建
  void Function(Course course)? onTapCourse,
  void Function(Course course)? onLongPressCourse,
});
```

常量：`kGridHeaderHeight = 34`（表头高度，`AppTheme` 无对应令牌）、`kWeekdayShortLabels`（一…日，表头用）、`kWeekdayLabels`（周一…周日，详情弹层用）、`kCardInset = 2`（卡片外缩进，取 `gridGap / 2`）、`kCardPaddingH = 3` / `kCardPaddingV = 4`（卡片内边距，视觉稿指定）

构造新增参数：`DateTime? weekStartDate`（当前周**周一**；`null` 时不显示日期）

布局与定位（**一屏 7 天，不横向滚动**）：
- 外层 `SingleChildScrollView`（**只纵向**滚动）→ `SizedBox(height: kGridHeaderHeight + 12 * cellHeight)` → `LayoutBuilder`
- 列宽 = `(可用宽度 - theme.timetableTimeColumnWidth) / 可见天数`；可见天数 = `theme.showWeekend ? 7 : 5`。**没有最小列宽、没有横向滚动**（实测 360dp / 480dp 下 7 列铺满、右边缘正好贴屏）
- 表头：
  - 时间列格 = 该周**月份**（`${weekStartDate.month}月`，如 `9月`；取**周一**的月份，跨月周如 9/29–10/5 显示 `9月`）；`weekStartDate == null` 时空白
  - 星期格 = `星期 + 日期`（如 `一 11`、`二 12`）；该列日期 = `weekStartDate + (dayIndex - 1)` 天；**1 号显示 `M/1`**（如 `三 10/1`）以便看出换月
- 12 行：左侧时间列（"第 N 节" + 起止时间，拆上下两行 + `FittedBox` 兜底）+ 右侧空单元格
- 课程卡片：`left = timeColumnWidth + (day-1) * columnWidth + kCardInset`、`top = kGridHeaderHeight + (startSession-1) * cellHeight + kCardInset`、`width = columnWidth - kCardInset*2`、`height = length * cellHeight - kCardInset*2`
  - 卡片 `Key = '<courseId>-<day>-<startSession>-<week>'`

**卡片内容（Phase 2.2b.4）** — 固定字号，**只显示课程名与教室**：

| 内容 | 字号 | 行数 / 溢出策略 |
|------|------|-----------------|
| 课程名 | `theme.bodySize`（14）+ `titleFontWeight` | 最多 3 行，超出**省略号** |
| 教室（`HE-405`） | `theme.captionSize`（12） | 最多 2 行，**允许换行**，超出**裁切**（不省略号） |

按**节数**逐级显示：
- `length >= 2` → 课程名 + 教室
- `length == 1` → 只显示课程名（格子太小放不下教室）

**卡片内不显示教师**（只在详情弹层里）、**不显示 `@校区`**（Phase 2.2b.4：真机反馈窄列宽下教室与校区互相挤到看不清，如 `@曹...HA...`）。

裁切策略：卡片内容用 `ClipRect` + `OverflowBox(maxHeight: infinity)` 包裹 —— `OverflowBox` 让 `Column` 按内容自然排布（因此教室能换行、且不触发 `RenderFlex` 溢出报错），`ClipRect` 把超出卡片高度的部分裁掉。**卡片的 `FittedBox` 已删除**（时间列那一个保留，只服务于 40px 窄时间列）。课程名行数按可用高度精确算出（上限 3 行），课程名优先、教室在后，真放不下时裁掉的是教室。

`splitCampusAndRoom(String raw)` → `({String campus, String room})`：把 `TimePlace.room`（如 `"曹妃甸校区 HE-405"`）按**首个空白**拆成校区与教室；无空白时整串算教室、校区为空。卡片**只用 `.room`**（Phase 2.2b.4 起不显示校区）；`.campus` 目前无调用方，保留供详情弹层将来分开展示、以及 Phase 4 给 `TimePlace` 加独立 `campus` 字段时替换（届时按 CONTEXT 4.2.1 写迁移）。

卡片推导（`_collectPlacements`）：扫描 `grid`，**上一格不是同一实例**的格子即课程块顶部（用 `identical` 比较——`buildGrid` 会把同一实例填进跨节涉及的每一格），再向下数连续同实例格数得到 `length`。教室信息按 `(day, startSession)` 回查 `course.displayTimePlaces`（网格里只有 `Course`，没有 `TimePlace`）。

卡片颜色（`_colorForCourse`）：优先 `course.displayColor`（即 `userOverride.customColor`）；否则 `course.id.hashCode.abs() % theme.courseCardColors.length` —— 同一门课每次渲染颜色一致，不同课程尽量分散。配色池为空时回落 `theme.surface`。