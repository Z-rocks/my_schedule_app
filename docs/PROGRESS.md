# 开发进度（PROGRESS）

> 每次完成一个文件或一个任务，勾掉对应项。
> 遇到阻塞，在旁边加 `⚠️` 并说明。
> 本文件是"当前状态"的唯一真相来源。

- 最后更新：2026-09-23

---

## 🚩 当前进度快照

> 给新会话 AI 用。每次阶段切换时更新。

- **最新完成**：Phase 3.2b.1（插件文件加载 + PluginRuntime 骨架）
- **代码状态**：dart analyze 全绿，真机验收通过（`getprop ro.product.model` = `2211133C`）
- **Phase 2 全部完成**：Hive 存储 + 课表渲染 + 学期配置 + 添加课程
- **下一步**：Phase 3.2b.2（`ctx.http` 注入：插件跨 isolate 发起网络请求）
- **最近 commit**：feat(plugin): 新增 JS 运行时沙箱与超时兜底
- **关键约束**：
  - testWidgets 不能触发 Hive 写（会卡死）
  - schema 已冻结（改字段要写迁移）
  - 卡片不显示教师和 @校区
  - 一屏 7 天不横向滚动
  - **JS 侧取 JSON 必须用 JS 的 `JSON.stringify`**（QuickJS 的 `jsonStringify` 未实现）
  - **`evaluate()` 语法错误不抛异常**，靠 `JsEvalResult.isError` 判断
  - **JS 必须跑在独立 isolate**（`QuickJsRuntime2.timeout` 实测无法中断死循环，且会连带冻结 Dart 侧超时）
  - **绝不传 `memoryLimit`**（`jsSetMemoryLimit` 在两个随包二进制里都不存在，传了直接打死 isolate）
  - **每插件独占一个 JsSandbox**（`__plugin` 是全局变量，共用会互相覆盖）
  - **docs/PROGRESS.md 曾因编码问题损坏**，见阻塞表（编辑该文件时务必确认保存为 UTF-8）

---

---

## Phase 0：环境搭建 ✅

- [x] Flutter SDK 3.47.5 安装
- [x] Android Studio 安装
- [x] Android SDK Platform 37 安装
- [x] Android SDK Build-Tools 安装
- [x] Android SDK Command-line Tools 安装
- [x] Flutter 镜像配置（PUB_HOSTED_URL / FLUTTER_STORAGE_BASE_URL）
- [x] 项目创建：`my_schedule_app`
- [x] Gradle 镜像配置（腾讯云 + 阿里云）
- [x] 4 Tab 骨架跑通（课表 / 课程 / 考试 / 设置）
- [x] 真机调试跑通（Redmi K60，Android 16）

---

## Phase 1：内核骨架 ✅

### 1.1 数据模型
- [x] `lib/models/course.dart` — Course
- [x] `lib/models/time_place.dart` — TimePlace
- [x] `lib/models/user_override.dart` — UserOverride
- [x] `lib/models/exam.dart` — Exam
- [x] `lib/models/homework.dart` — Homework
- [x] `lib/models/message.dart` — Message + MessageType
- [x] `lib/models/module.dart` — ModuleType + ModuleInfo
- [x] `lib/models/plugin_meta.dart` — PluginMeta
- [x] `lib/models/skin_pack.dart` — SkinPack

> 备注：Phase 1.1 全部 9 个文件由 AI 生成（prompt: `docs/prompts/01-models.md`）。
> 其中 Exam / Homework / Message / ModuleInfo / PluginMeta / SkinPack 的字段为按
> `CONTEXT.md` 规范自行设计。`flutter analyze` 通过，另用临时冒烟脚本验证了
> fromJson 容错（空 JSON、类型错乱）与 toJson/fromJson 往返一致性后已删除脚本。

### 1.2 主题系统
- [x] `lib/theme/app_theme.dart` — AppTheme
- [x] `lib/theme/default_theme.dart` — 默认蓝主题
- [x] `lib/theme/theme_engine.dart` — ThemeEngine
- [x] `lib/theme/theme_extension.dart` — AppThemeExtension

> 备注：Phase 1.2 由 AI 生成（prompt: `docs/prompts/02-theme.md`）。
> `dart analyze lib` 通过。另用临时 `flutter test` 脚本验证了 15 组行为
> （fromJson 兜底、hex 解析、往返一致、merge 只覆盖显式字段、28 个字段逐个
> 防漂移校验、ThemeEngine 皮肤加载/暗色表选择、AppThemeExtension 回退）
> 后已删除脚本。`withBrightness` 与 `lerp` 为 Phase 1 简化实现（返回 `this`），
> 暗色配色留待 Phase 6 由 `SkinPack.darkColors` 提供。

### 1.3 状态管理
- [x] `lib/providers/module_provider.dart` — ModuleProvider
- [x] `lib/providers/course_provider.dart` — CourseProvider
- [x] `lib/providers/theme_provider.dart` — ThemeProvider
- [x] `lib/providers/plugin_provider.dart` — PluginProvider
- [x] `lib/providers/message_provider.dart` — MessageProvider

> 备注：Phase 1.3 由 AI 生成（prompt: `docs/prompts/03-providers.md`）。
> `dart analyze lib` 通过。另用临时 `flutter test` 脚本验证了 27 组行为
> （模块表初值、visibleModules 的 required 优先与 5 个上限、toggle 常驻保护、
> 能力联动、课程隐藏过滤、主题应用/预览、插件能力汇总、消息倒序与 30 天清理、
> 不可变视图、dispose 后调用安全性）后已删除脚本。
> 为满足本阶段表格，Phase 1.1 的 `ModuleInfo` 增补了 `available` 字段；
> Phase 1.2 的 `ThemeEngine` 增补了 `_disposed` 保护（异步方法同款隐患）。

> **Phase 1.3.1 修正**（review 后）：`exam` 初始 `available` 改为 `true`
> （支持手动添加考试，不依赖插件）；`message` 初始 `enabled` 改为 `false`；
> `visibleModules` 输出改为按模块原始顺序（timetable → courseList → exam →
> homework → message → settings），避免 toggle 时导航栏顺序跳动；
> `updateCapabilities` 改为**只调整 `homework`**（`exam` 不再被空能力集关掉，
> 否则 Phase 1.4 联动会隐藏考试模块）；`PluginMeta` 新增 `capabilities`
> 扁平能力字段（与 `modules` 并存，取并集）。
> 修正后全新安装的默认导航栏为 **课表 / 课程 / 考试 / 设置**，
> 与 Phase 1.8 验收标准一致。

### 1.4 App 入口
- [x] `lib/main.dart` — 入口 + MultiProvider
- [x] `lib/app.dart` — MaterialApp + ThemeExtension
- [x] `lib/pages/home_page.dart` — 动态导航栏

> 备注：Phase 1.4 由 AI 生成（prompt: `docs/prompts/04-app-entry.md`）。
> Phase 0 的静态 4-Tab `main.dart` 已整体替换。`dart analyze lib` 通过。
> 另用临时 `flutter test` 脚本验证了 9 组行为（默认导航栏 = 课表/课程/考试/设置、
> 点击切换、PluginProvider→ModuleProvider 的 proxy 联动不产生 build 期通知异常、
> index 越界重置为 0、未越界时保持、主题经 AppThemeExtension 注入并随皮肤更新、
> 占位页样式取自 AppTheme、空模块兜底页、插件模块 type==null 也能显示）后已删除脚本。
> Phase 1.5 的 6 个真实页面尚未生成，`home_page.dart` 内用私有 `_ModulePlaceholder`
> 顶替，Phase 1.5 时按各 case 后的注释逐行替换并删除该私有类。
> 注意 `PluginProvider` 在 `MultiProvider` 中排在 `ModuleProvider` 之前
> （ProxyProvider 需能读到它），与 prompt 列表顺序不同。

> **Phase 1.4.1 修正**（review 后）：导航栏图标改为**完全数据驱动**。
> `ModuleProvider._initialModules` 给 6 个内置模块补上了 `iconName`
> （`calendar_month` / `book_outlined` / `assignment_outlined` / `edit_note` /
> `notifications_outlined` / `settings_outlined`）；`ModuleInfo.fromType`
> 新增可选 `iconName` 参数；`home_page.dart` 删除了 `switch (module.type)`
> 图标映射，统一走 `_iconFromName(module.iconName)`，查不到时兜底
> `Icons.extension`。此后改图标或新增模块不需要动 UI 代码。
> 另用临时 `flutter test` 脚本验证了 6 组行为（6 个内置 iconName 非空且正确、
> 默认 4 项图标解析正确、6 个模块全开时无一回退到兜底图标、
> `fromType`/`fromJson`/`toJson`/`copyWith` 的 iconName 往返与向后兼容、
> 插件模块可带 iconName）后已删除脚本。

### 1.5 页面骨架（空态）
- [x] `lib/widgets/empty_state.dart` — EmptyState（6 个页面共用，由 1.5 提前实现）
- [x] `lib/pages/timetable/timetable_view.dart`
- [x] `lib/pages/course_list/course_list_view.dart`
- [x] `lib/pages/exam/exam_view.dart`
- [x] `lib/pages/homework/homework_view.dart`
- [x] `lib/pages/message/message_view.dart`

> 备注：Phase 1.5 由 AI 生成（prompt: `docs/prompts/05-pages.md`）。
> `dart analyze lib` 通过。`home_page.dart` 的 `_ModulePlaceholder` 与
> `_NoModuleScaffold` 两个私有占位类已**完全删除**，`_buildPage` 的 switch
> 已改为返回真实页面；尚未实现的 `settings`（Phase 1.6）与插件模块（Phase 3）
> 改用私有方法 `_pendingPage` + `EmptyState` 兜底，不再单写占位类。
> `_iconFromName` 按约定保留在 `home_page.dart`（Phase 1.7 再抽到 `lib/widgets/`）。
> 另用临时 `flutter test` 脚本验证了 16 组行为（真实页面渲染、空态文案/图标、
> 两个 SnackBar、周次选择器 20 项/默认第 1 周/点击切换/滚动到第 20 周/
> 切标签后保留、5 个上限挤出 message、样式全部取自 AppTheme、字重换算兜底）
> 后已删除脚本。

### 1.6 设置页
- [x] `lib/pages/settings/settings_page.dart`
- [x] `lib/pages/settings/module_config_page.dart`
- [x] `lib/pages/settings/plugin_manage_page.dart`
- [x] `lib/pages/settings/workshop_page.dart`
- [x] `lib/pages/settings/timetable_settings_page.dart`
- [x] `lib/widgets/module_icon.dart`（计划外：为配置页抽出图标解析，见下）

> 备注：Phase 1.6 由 AI 生成（prompt: `docs/prompts/06-settings.md`）。
> `dart analyze lib` 通过。`home_page.dart` 的 `settings` case 已替换为
> `const SettingsPage()`（`_pendingPage` 保留给 Phase 3 的插件模块）。
> 另用临时 `flutter test` 脚本验证了 15 组行为（设置页 6 分组 12 条目齐全、
> 版本号不可点击、4 个跳转入口、清理缓存确认框的取消/确定分支、
> 插件管理空态与"去创意工坊"、创意工坊双 Tab、课表设置开关与滑块、
> 配置页必需/未激活开关禁用、toggle 真正改动 Provider、两个上限场景、样式取自 AppTheme）
> 后已删除脚本。
>
> **上限提示的处理**（对应阻塞表 2026-09-22 那条）：
> `visibleModules` 按设计**永远不会超过 5**（Provider 内部已截断），
> 所以 prompt 里"切换后判断 `length > 5` 再回滚"是死代码。实际实现了两种情形：
> ① 新模块**挤不进去** → 回滚并提示"最多显示 5 个模块，请先关闭其他模块"；
> ② 新模块**顶掉了别的已显示模块** → 放行并提示被挤出的模块名
> （如 `"消息" 已被移出导航栏`）。采用"先应用、再看结果、必要时回滚"，
> 直接复用 Provider 里那套唯一的截断算法，避免在本页复制顺序/优先级规则。
> 该阻塞项已可标记为完成。

### 1.7 通用组件
- [x] `lib/widgets/empty_state.dart`（已在 Phase 1.5 完成）
- [x] `lib/widgets/module_icon.dart`（已在 Phase 1.6 完成）
- [ ] `lib/widgets/course_card.dart`（预留，推迟到 Phase 5）
- [ ] `lib/widgets/week_selector.dart`（预留，推迟到 Phase 2）

> 备注：course_card.dart 与 week_selector.dart 推迟到 Phase 2/5（当前没有数据源可填充）。empty_state.dart 和 module_icon.dart 已在 Phase 1.5/1.6 提前完成。

### 1.8 验收标准
- [x] App 能运行，底部导航显示 4 个模块（课表/课程/考试/设置）
- [x] 所有页面显示空态，无崩溃
- [x] 设置 → 导航栏配置能勾选/取消模块
- [x] 导航栏改动实时生效
- [x] 设置 → 插件管理/创意工坊能进入占位页

> 验收完成日期：2026-09-22。真机（Redmi K60）验收通过。

---

## Phase 2：存储与业务 ✅

- [x] Hive 初始化
- [x] `lib/services/storage_service.dart`
- [x] `lib/services/override_engine.dart`
- [x] `lib/services/timetable_logic.dart`（周次解析、网格构建）— Phase 2.2a
- [x] CourseProvider 接入 Hive
- [x] 手工塞测试数据，课表能渲染 — Phase 2.2b

> **Phase 2.2b**（课表网格渲染）：`dart analyze lib` 通过，未新增依赖。
>
> 改动：
> - 新建 `lib/widgets/timetable_grid.dart`：`Stack` + `Positioned` 绝对定位的网格，
>   表头 / 时间列 / 空单元格 / 课程卡片四层；跨节卡片高度 = 节数 × 单元格高度；
>   颜色优先 `userOverride.customColor`，否则按 `course.id` 哈希从
>   `theme.courseCardColors` 取；`showWeekend == false` 时只渲染周一到周五
> - 新建 `lib/pages/timetable/course_detail_sheet.dart`：只读底部弹层
>   （课程名 / 教师 / 学分类别 / 全部时间地点 / 备注 + 编辑·关闭按钮）
> - 改造 `lib/pages/timetable/timetable_view.dart`：三种状态（未配学期 /
>   有学期无课程 / 有数据）、周次选择器默认选中 `currentWeek`、
>   点击卡片开弹层、长按提示 Phase 5；**移除了 `totalWeeks` / `initialWeek`
>   构造参数**（改由 `SemesterProvider` 驱动，单一数据源）
> - 改造 `lib/pages/settings/timetable_settings_page.dart`：新增"学期配置"入口行
> - `lib/main.dart`：新增 `_seedTemporaryTestData`（标记 `TODO(Phase 2.2c): 删除`），
>   写入 1 个测试学期（起始日 = 今天 - 14 天 → 第 3 周）与 3 门课
>
> **验证**：临时 `flutter test` 脚本 28 组全部通过（本阶段无需 Hive，测试文件
> 全程不初始化 Hive，避免 fake-async 卡死），覆盖：空网格 / 单课 / 跨节高度与
> 位置 / 点击与长按回调 / 无回调不崩 / `showWeekend=false` / 自定义色 / 哈希取色
> 稳定性 / 课名 2 行截断、TimetableView 三种状态与两个 SnackBar / 隐藏课程不显示、
> 默认选中第 3 周 / 切周后单周课与双周课的出现与消失 / 第 5 周不在周次内不显示 /
> 选择器长度 = totalWeeks、弹层内容完整性 / 关闭 / 编辑 SnackBar / 备注有无 /
> 一课多安排列出两条 / 独立调用 / `displayXxx` 覆盖生效。脚本已删除。
>
> **过程中发现并修复 2 个真实布局 bug**（单元测试直接抓出 RenderFlex overflow）：
> ① 时间列宽仅 40px，`"08:30-09:15"` 会换行撑破单元格（溢出 27px）→ 改为上下
> 两行显示并套 `FittedBox(scaleDown)`；② 单节卡片（56px 高）放不下"2 行课名 +
> 教师 + 教室"→ 卡片内容套 `FittedBox(scaleDown)`。
> 这两处在真机上表现为黄色黑条纹溢出警告，属于必须修的问题。
>
> **待办**：`main.dart` 的临时测试数据必须在 Phase 2.2c 删除（已用 TODO 标记）。
> —— 已在 **Phase 2.2b.1 提前删除**（见下）。

> **Phase 2.2c.1**（学期配置页）：`dart analyze lib` 通过，未新增依赖。
>
> 用户第一需求是**能编辑学期开始日期**，本页满足；添加课程页留给 2.2c.2。
>
> 改动：
> - 新建 `lib/pages/settings/semester_config_page.dart`（`SemesterConfigPage`）：
>   `Form` + `TextFormField`（学期名称，validator 非空 + 最多 30 字）、
>   开始日期（可点击 → `showDatePicker`，范围过去 5 年~未来 5 年，无配置时默认"本周一"）、
>   总周数（`Slider` 10–30 —— **已在同阶段修正中放宽为 4–30**，见下方修正块，右侧显示 `N 周`）、结束日期（只读，派生显示）、
>   备注（`maxLines: 3`）、预览（尚未开始 / 当前第 N 周 / 学期已结束）、
>   底部"取消 / 保存"；AppBar 右侧"重置"（仅已有配置时显示，带确认框）
> - 导出纯函数便于测试：`dateOnly` / `mondayOfWeek` / `formatChineseDate` /
>   `formatChineseDateWithWeekday`；常量 `kMinTotalWeeks`(10) / `kMaxTotalWeeks`(30) /
>   `kMaxSemesterNameLength`(30)
> - `timetable_settings_page.dart`：学期配置入口从 SnackBar 改为 push 真实页面
> - `timetable_view.dart`：空态"去配置学期"按钮改为 push 真实页面；
>   周次面板底部新增 `TextButton.icon('编辑学期')`，面板返回
>   `_WeekPickerResult.editSemester` 时打开配置页（选周仍返回 `int`）
> - `StorageService.kSemesterConfigKey` 注释补充：由哪个页面编辑、解析要走 `tryDecode`
>
> 验证：临时 `flutter test` 脚本 **28 组全部通过**，脚本已删除。覆盖：
> `mondayOfWeek`（含周日、带时分秒）/ `dateOnly` / 两种中文日期格式、
> 结束日期派生（2026-09-07 + 20 周 → 2027-01-24，差值 139 天）、
> 页面字段齐全、无配置时默认本周一与 20 周、有配置时回填 + 显示重置、
> 超出 10–30 的历史周数被收进范围、名称 `maxLength` = 30、
> 表单验证（空 / 纯空白被拦、填了名称后保存成功并 `pop(true)` + SnackBar）、
> 点击开始日期弹出 `DatePickerDialog`、结束日期只读不弹、
> 滑杆拖到 30/10 周时结束日期同步、预览三种状态（进行中第 3 周 / 已结束 / 尚未开始）、
> 重置确认框（取消不清除、确定清除并返回）、取消按钮 `pop(false)` 且不改数据、
> **三处入口都能跳转**、面板选周仍有效、保存后课表页从"没有配置学期"切到"还没有课程"。
>
> **测试注意**：表单页较长，默认 800×600 视口下底部"保存/取消"在屏幕外点不到，
> 需用高视口（500×1600）；另外页面底部与确认框都有"取消"，`find.text('取消')` 有歧义，
> 需 `find.descendant(of: find.byType(AlertDialog), …)` 限定。

> **Phase 2.2c.1 修正**：总周数滑杆下限由 **10 放宽到 4**（`kMinTotalWeeks`），
> 以支持军训 / 小学期 / 暑期课程等短学期；`divisions` 随之由 20 变为 26（每档仍 1 周）。
> 效果：8 周、5 周这类配置进页面后**不再被顶成 10 周**（低于 4 或高于 30 的仍会收进区间）。
> 验证：临时 `flutter test` 脚本 **10 组全部通过**，脚本已删除。覆盖：
> 常量值（4 / 30）、滑杆 min/max/divisions、拖到下限显示"4 周"且结束日期派生为
> `2026年10月4日`（2026-09-07 + 27 天）、保存 4 周配置进 Provider、
> 8 周与 5 周原样保留、3 周收进 4 周、40 周收进 30 周、默认仍 20 周、
> 短学期（4 周、起始日很久以前）预览显示"学期已结束"。

> **Phase 2.2c.2**（添加课程页）：`dart analyze lib` 通过，未新增依赖。
> 本次只做**添加**，编辑/删除留给 Phase 5。
>
> 改动：
> - 新建 `lib/pages/edit/course_edit_page.dart`（`CourseEditPage`，无参构造）：
>   `Form` 表单含 基本信息（课程名 / 教师 / 学分 Slider 0–10 步进 0.5 / 类别 / 颜色）、
>   上课时间地点（可增删的多个时间段卡片）、备注、底部取消 + 保存
> - 时间段用可变临时类 `_TimePlaceDraft`（day / startSession / length /
>   startWeek / endWeek / weekType / roomController），保存时转成 `TimePlace`；
>   `endWeek` 按学期总周数传入，避免默认值超出学期范围
> - 时间段卡片：星期 7 个 ChoiceChip、起始节次与持续节数两个 Dropdown、
>   教室输入、**周次范围用 `RangeSlider`**（1..totalWeeks）、单双周 3 个 ChoiceChip、
>   右上角删除；**至少保留一个**（删最后一个时提示并拒绝）
> - 颜色选择 `_ColorPicker`：预设色（`theme.courseCardColors`，默认选中第一个）
>   + "自动"选项（`null` → 交给哈希分配）
> - 颜色与备注存进 `userOverride`（`Course` 没有 color 字段，`displayColor`
>   读的是 `userOverride.customColor`；`saveCourse` 会把覆盖层剥离到
>   `overrides` Box 持久化）；两者都为空时 `userOverride` 为 null
> - `timetable_view.dart`：顶部 `+` 与空态"添加课程"都改为 `_openCourseEdit()` ——
>   **无学期时不跳转**，弹 `SnackBar('请先配置学期')` + `SnackBarAction('去配置')`
> - 导出纯函数 `weeksFromRange` / `rawWeeksTextFromRange`；常量
>   `kMaxCourseNameLength`(30) / `kMinUnit`(0) / `kMaxUnit`(10) / `kUnitStep`(0.5) /
>   `kMinLength`(1) / `kMaxLength`(4)
>
> 验证：临时 `flutter test` 脚本 **33 组全部通过**，脚本已删除。覆盖：
> 周次转换（全部 1-16 → [1..16]、单周 → 奇数周、双周 → 偶数周、反向区间 → 空、
> 单周 + 无奇数周区间 → 空）、`rawWeeksText`（三种单双周 + 起止相同写成"9周"）、
> 页面字段齐全、默认一个时间段且周次覆盖整学期（短学期下不超过总周数）、
> 颜色默认选中第一个预设色 + 有"自动"、课程名空/纯空白被拦、`maxLength` = 30、
> 时间段可增可删、**删到最后一个被拦下**、保存后 `sourcePluginId == 'user'` 且
> `id` 以 `user_` 开头且 `timePlaces` 长度 = 时间段数、20 周生成 20 个周次、
> 单双周影响 weeks 与 rawWeeksText、颜色存入 `userOverride.customColor`、
> 选"自动"时 `displayColor` 为 null、教师/类别/教室/备注都被保存、
> 取消返回 false 且不保存、**无学期时保存被兜底拦下**、
> 两个入口（有学期跳转 / 无学期弹 SnackBar 且不跳转 / "去配置"能打开学期配置页 /
> 添加课程后课表页不再显示空态）。
>
> **测试注意**：本页比学期配置页更长，需高视口（500×2400）才能点到底部按钮与
> 第二个时间段卡片。

> **Phase 2.2b.4**（真机反馈"卡片信息太挤"）：`dart analyze lib` 通过，未新增依赖。
>
> 问题：窄列宽（约 46px）下同时显示教室与 `@校区`，两个都被截断成
> `@曹...HA...` 这种看不清的形式。用户要求**去掉 @校区，只显示教室名**。
>
> 改动（仅 `lib/widgets/timetable_grid.dart` 的卡片部分）：
> - **删除 `@校区` 那一行**，卡片只显示：课程名（`bodySize` 14 加粗，最多 3 行省略号）
>   + 教室（`captionSize` 12，**最多 2 行、允许换行、超出裁切不用省略号**）
> - 显示规则改为按**节数**：`length >= 2` 显示课程名 + 教室；`length == 1` 只显示课程名
>   （原为按块高度 1.5 / 2.5 格的三档）
> - 裁切实现：`ClipRect` + `OverflowBox(maxHeight: infinity)` 包裹 Column ——
>   `OverflowBox` 让 Column 按内容自然排布（教室可换行且不触发 `RenderFlex` 溢出报错），
>   `ClipRect` 裁掉超出卡片高度的部分
> - 课程名行数改为只按可用高度算（不再为 meta 预留），课程名优先、教室在后，
>   真放不下时裁掉的是教室
> - `splitCampusAndRoom()` **保留**：卡片仍需它把 `"曹妃甸校区 HE-405"` 的校区前缀去掉、
>   只取 `HE-405`；`.campus` 暂无人用但保留（详情弹层将来可分开展示，Phase 4 换独立字段）
>
> 验证：临时 `flutter test` 脚本 **18 组全部通过**（360dp 窄屏为主），脚本已删除。覆盖：
> 卡片内无任何 `@` 开头文本、无"曹妃甸校区"、只显示 `HE-405`（含 4 节空间充足时）、
> 1 节仅课名 / 2 节课名+教室 / 3 与 4 节同样 / 教室为空不显示空文本、
> `HE-405` 在 45.71px 列宽下完整显示且 `maxLines=2` / `overflow=clip` / `softWrap=true`、
> 无空格长教室名整串换行 2 行、课程名 3 行省略号、
> 320/360/480dp × 1/2/3/4 节共 12 种组合均无溢出、40px 极小单元格不溢出、
> 卡片内确有 `ClipRect`+`OverflowBox` 且无 `FittedBox`、`splitCampusAndRoom` 4 种输入行为不变。

> **Phase 2.2b.3**（参照主流课表 App 的视觉重构）：`dart analyze lib` 通过，未新增依赖。
>
> ⚠️ **前提更正**：任务书说"删除 Phase 2.2b.2 的横向滚动逻辑 / `kMinDayColumnWidth`"，
> 但**代码里从来没有这些东西**——`TimetableGrid` 从 Phase 2.2b 起就是
> `列宽 = (可用宽度 - 时间列宽) / 天数` 的一屏 7 天布局，只做纵向滚动。
> （"横向滚动 + 最小列宽"只是我在 Phase 2.2b.1 汇报里提的**建议**，并未实施。）
> 因此本次**没有可删除的横向滚动代码**，只做了实测确认（360dp/480dp 下 7 列铺满、右边缘贴屏）。
>
> 改动：
> - `lib/widgets/timetable_grid.dart`：
>   - 新增参数 `weekStartDate`（该周周一）
>   - 表头：时间列格显示**该周月份**（`9月`，取周一的月份，跨月周 9/29–10/5 显示 `9月`，
>     `null` 时空白）；星期格改为 `星期 + 日期`（`一 11`、`二 12`），1 号显示 `M/1`（`三 10/1`）
>   - 卡片内容重排：课程名（`bodySize` 14 加粗，最多 3 行省略）+ 教室 + `@校区`
>     （均 `captionSize` 12）；**不显示教师**；按块高度 `≥2.5 格` 显示三项、
>     `≥1.5 格` 显示两项、否则只显示课程名
>   - **删除卡片上的 `FittedBox` 与 Phase 2.2b.1 的字号分档/行数预算**（改为固定字号 +
>     按可用高度精确算课程名行数，上限 3 行）；**时间列的 `FittedBox` 保留**
>     （只服务于 40px 窄时间列，与卡片无关）
>   - 卡片外缩进改为 `kCardInset = 2`（原为 `gridGap = 4`）→ 卡片"占满格子"；
>     内边距 `kCardPaddingH = 3` / `kCardPaddingV = 4`（视觉稿指定）
>   - 新增 `splitCampusAndRoom()`：把 `room`（`"曹妃甸校区 HE-405"`）按首个空白拆成
>     校区 + 教室（模型只有 `room` 一个字段，属展示层权宜做法，Phase 4 应加 `campus` 字段）
> - `lib/pages/timetable/timetable_view.dart`：
>   - **删除 AppBar 与常驻周次 chips 行**，改为一行日期栏
>     `[2026/9/23] [第 N 周 ▾] (学期已结束) ... [+]`
>   - 点击"第 N 周"弹出 `_WeekPickerSheet`（标题"选择周次" + `Wrap` chips），选中即跳周
>   - 新增 `formatDateYmd()`（`yyyy/M/d` 不补零）、`weekStartDateOf()`、`_isSemesterEnded()`
>   - 删除 `kWeekSelectorHeight` / `kWeekChipExtent` / `_weekScrollController` /
>     `_scrollWeekChipIntoView`（chips 行没了就不需要）
>   - `gestureSwitchWeek` 的 PageView 滑动切周**保留**（任务书未要求删除，且是 2.2b.1 已验收功能）
> - `lib/pages/timetable/course_detail_sheet.dart`：**无需改动**——教师本来就在弹层里显示
>   （`person_outline` 图标 + `displayTeacher`，空值显示"未知教师"），已用测试确认；
>   仅在文档里注明"卡片不显示教师后这里是唯一入口"
>
> 验证：临时 `flutter test` 脚本 **36 组全部通过**（首轮即全绿），脚本已删除。覆盖：
> 360dp/480dp 下每列宽 == `(屏宽 - 时间列宽)/7` 且右边缘贴屏、网格仅纵向滚动、
> 表头 `一 11`/`二 12` 格式、月份格（9月/12月/跨月周取周一月份/null 空白/10月1日）、
> 卡片 1 节仅课名 / 2 节课名+教室 / 3 节与 4 节完整、无空格时校区为空、
> 长课名 3 行省略、meta 字号 = captionSize、卡片铺满格子（宽高 = 列宽/块高 - 2×inset）、
> 四档高度均无溢出、卡片内无 `FittedBox`、`splitCampusAndRoom` 5 种输入、
> 顶部栏日期与周次、无常驻 chips、周次面板弹出与选中跳周、学期已结束判定（正反两例）、
> 无学期时的空态、滑动后顶部同步、`weekStartDateOf` 与 `formatDateYmd` 计算、
> 详情弹层显示教师（含空值"未知教师"与用户改过的教师名）。

> **Phase 2.2b.1**（真机验收反馈的两项体验修正）：`dart analyze lib` 通过，未新增依赖。
> 真机（Redmi K60）反馈：①课程卡片字体太小，不点详情看不清；②不能左右滑动切周，只能点数字。
>
> 改动：
> - `lib/widgets/timetable_grid.dart`：卡片字号由固定 `captionSize`(12) 改为**随可用高度
>   （`timetableCellHeight × length`）分档**：<60 → `titleSize-4`、60~119 → `titleSize-2`、
>   120~179 → `titleSize`、≥180 → `titleSize+2`；meta（教师/教室）统一 `-3`。
>   默认主题下单节 16、两节 18、三节 20。
> - 新增**行数预算**：至少 1 行课名，剩余高度给 meta（教师 → 教室，最多 2 行）；
>   **只有在 meta 也放得下的前提下**课名才占 2 行——否则课名 1 行省略也要保住教室。
> - `lib/theme/default_theme.dart`：`timetableCellHeight` **64 → 72**（对已交付 Phase 1.2
>   的小修正；`AppTheme` 启动时构造、不落盘，不影响已有数据）。
> - 新增 `kGestureSwitchWeekKey = 'gesture_switch_week'`（`StorageService`）。
> - **新增 `lib/providers/settings_provider.dart`（`SettingsProvider`）**：管 UI 偏好，
>   目前只有 `gestureSwitchWeek`（默认 `true`，坏数据回落 `true`）。
> - `lib/pages/timetable/timetable_view.dart`：开关开启时用 `PageView.builder`
>   （`initialPage = week-1`、`itemCount = totalWeeks`）左右滑动切周；关闭时维持点数字。
>   `_week` 为唯一真相源，滑动与点击都经 `_setWeek` 单向同步另一侧，避免循环。
>   chip 列表改为固定 `itemExtent = 48` 并把选中 chip 自动滚进视野。
> - `lib/pages/settings/timetable_settings_page.dart`：新增"左右滑动切换周次"开关（已持久化）。
> - `lib/main.dart`：**删除 Phase 2.2b 的全部临时测试数据**（`_seedTemporaryTestData`
>   及其调用，以及随之无用的 `models/*` / `timetable_logic` import），并接入 `SettingsProvider`。
>
> 验证：临时 `flutter test` 脚本 34 组全部通过（Hive 用例用普通 `test()`，UI 用例所在
> group 不初始化 Hive），覆盖：6 档 cellHeight 的字号（含跨节 2/3 节）、meta 字号、
> 行数预算（单节显示课名+教师+教室、跨节课名 2 行、40px 极矮不溢出）、
> PageView 开关/滑动 ±1/首周不越界/点击同步跳页/反复点击无循环/关闭时无 PageView
> 且仍可点选/chip 固定宽度、设置页开关读写、`SettingsProvider` 落盘重建一致/
> 默认 true/7 种坏数据回落/宽松写法/decodeBool 规则/未初始化不崩/与其他键互不干扰。
> 脚本已删除。
>
> **过程中发现并修复 2 个问题**：① 原 `FittedBox(scaleDown)` 兜底会把放大的字号又缩回去，
> 等于没放大——改为按可用高度精确计算行数，`FittedBox` 只作病态主题兜底；
> ② 首版预算在 72px 下让课名占 2 行从而**挤掉了教室**，改为"meta 放得下才给课名 2 行"。

> **Phase 2.2a**（学期配置 + 周次解析 + 数据模型扩展）：
> `dart analyze lib` 通过，未新增依赖。本次为 **2.2 的第一部分，不做 UI**。
>
> 改动：
> - `lib/models/time_place.dart`：新增 `WeekType` 枚举（`all`/`odd`/`even`）
>   与 `TimePlace.weekType` 字段（JSON 键 `weekType`，存 `'all'/'odd'/'even'`）
> - 新建 `lib/models/semester_config.dart`：`name` / `startDate` / `totalWeeks` /
>   `description`，`endDate` 为派生 getter（不落盘），另有 `tryDecode` 用于存储层
> - 新建 `lib/services/timetable_logic.dart`：纯函数 `parseWeeks` /
>   `parseWeekType` / `currentWeek` / `hasClassInWeek` / `buildGrid` /
>   `courseAt` / `filledCellCount` / `formatWeeks`
> - 新建 `lib/providers/semester_provider.dart`：单学期配置，存 `settings` Box
>   的 `semester_config`（常量 `kSemesterConfigKey` 已加入 `StorageService`）
> - `lib/main.dart`：`SemesterProvider` 与其他 Provider 一起预加载
>
> **schema 说明**：`TimePlace` 新增 `weekType` 属 CONTEXT 4.2.1 的冻结例外——
> 当前无任何已落盘课程（编辑入口在 Phase 5），故无需迁移逻辑；
> 旧数据缺 `weekType` 键时回落 `WeekType.all`（已测试）。
>
> **规格矛盾（已按自洽方案实现）**：prompt 的 `parseWeeks` 文档示例写
> `"4,6-14周(单)" → [5,7,9,11,13,15]`，但按"解析基础周次再取奇数"应为
> `[7,9,11,13]`，而 `[5,7,...,15]` 对应的是"1-16 的奇数"。同时
> `hasClassInWeek` 的规格明确把单双周过滤放在它内部。故实现为：
> `parseWeeks` 只出**基础周次**（不过滤）、`parseWeekType` 单独识别、
> `hasClassInWeek` 负责过滤——三者职责不重叠，周次数据只存一份。
>
> 验证：临时 `flutter test` 脚本 52 组全部通过（涉及 Hive 的用普通 `test()`），
> 覆盖 parseWeeks 的 4 种 prompt 格式 + 乱码 + 标点/空白 + 反向区间 +
> 超大区间截断 + 升序去重、parseWeekType 单/双/无标记/单双周、
> currentWeek 早于/首日/第7天/跨周/超出/时分秒/非法 totalWeeks、
> hasClassInWeek 三种 weekType、buildGrid 空列表/单课/跨节/单周过滤/
> 不在本周/隐藏课程/越界 day-session/同格冲突/displayTimePlaces 覆盖/
> 一课多安排/courseAt 越界、SemesterConfig 的 endDate 派生与 toJson 不含
> endDate 与往返与 tryDecode 的 9 种拒绝情形、SemesterProvider 的
> save→重建→load 一致/不 await 也立即更新内存/clear/坏 JSON/缺关键字段/
> 未初始化存储/通知行为/与其他键互不干扰、以及"学期 + 网格"端到端。脚本已删除。

> 备注：Phase 2.1 由 AI 生成（prompt: Phase 2.1）。
> `dart analyze lib` 通过。用 `Box<String>` + 手写 JSON，**未**引入 `TypeAdapter`
> 或 `build_runner`，未新增依赖。
> 另用临时 `flutter test` 脚本（真实 Hive + 临时目录）验证了 20 组行为：
> 8 个 Box 名称与可用性、重复 init、覆盖层 save/get/remove/getAll、
> 坏数据跳过、saveCourse 落盘后重启可加载、原始数据与覆盖层分离存储、
> **重新同步不冲掉覆盖层**、deleteCourse 清理孤儿覆盖层、
> 同 id 覆盖、clearAll、未初始化时抛 StateError 且 Provider 不崩、
> 全模型 JSON 键名往返与命名规范（无下划线/无连续大写/小写开头）、
> 时间存 ISO8601、颜色存 hex。脚本已删除。
>
> **Schema 冻结检查结果**：9 个模型的 JSON 键名全部为小驼峰，
> `fromJson` 读取键与 `toJson` 写入键一一对应，**未发现不一致**
> （无 `sourcePluginID` / `start_time` 之类问题），无需修正。
> 已把契约写入 CONTEXT.md 4.2.1（CONTEXT 版本随之升到 v1.1）。

> **Phase 2.1.5 修正**（review 发现的真实缺口）：`ModuleProvider` 的 `enabled` 原本
> 是纯内存状态，用户在"导航栏配置"里取消勾选的模块**重启后会复原**，违反
> CONTEXT 3.5「模块配置/用户偏好 → Hive Box settings」。现已修复：
> `ModuleProvider` 新增 `loadFromStorage()` / `saveToStorage()`，
> 状态以 `{"<capabilityId>": bool}` 存在 `settings` Box 的 `module_enabled_state`，
> `toggle()` 与 `resetToDefaults()` 成功后自动落盘（fire-and-forget，不阻塞 UI）；
> `ThemeProvider` 的明暗偏好一并落到 `theme_brightness`；
> `main.dart` 在起 UI 前依次预加载三个 Provider。
> 另用临时 `flutter test` 脚本（真实 Hive + 临时目录）验证了 23 组行为，
> 含**直接复现上报场景**（取消勾选课程/考试 → 重建 Provider → 配置保留）、
> 坏 JSON / 非对象 / 空串 / 值类型不符 / 部分缺失 / 未知模块 ID /
> required 强制 true / available 不受影响 / 未初始化存储不崩溃 /
> 明暗偏好往返 / 导航栏按状态渲染，脚本已删除。
>
> **测试注意**：Hive 的异步写入在 `testWidgets` 的 fake-async 时区里**永远不会完成**，
> 只要在 `testWidgets` 内触发一次写（如 `toggle`），随后的 `pumpAndSettle` 会卡死
> 直到 10 分钟超时。因此涉及 Hive 的用例一律写成普通 `test()`。
> 后续阶段写测试时需沿用这条规则。

---

## Phase 3：插件运行时（进行中）

> **Phase 3.1**（flutter_js 集成 + 最小 demo）：`dart analyze lib` 通过，**只加了 1 个依赖**。
> 本次仅做**集成验证**，不做沙箱、不做 PluginRuntime、不做插件文件加载（留给 3.2+）。
>
> 改动：
> - `pubspec.yaml`：新增 `flutter_js: ^0.8.7`（pub.dev 实际最新稳定版；
>   提示词里写的 0.8.2 已过期，0.8.7 的 SDK 约束 `>=3.0.0 <4.0.0` 与本项目 Dart 3.13.4 兼容）
> - 新建 `lib/runtime/plugin_demo.dart`（`PluginDemo`）：4 个静态方法
>   `evalSimple()` / `evalWithCallback()` / `evalWithObject()` / `evalInvalid()`，
>   每个方法自建运行时、`finally` 里 `dispose()`，失败一律返回 `null` 而非抛异常
> - `main.dart` 临时加验证行 → 真机确认后**已删除**（`PluginDemo` 文件保留，供 3.2 参考）
>
> **两条实测得到的关键约束**（Phase 3.2 必须沿用，已写入 API.md）：
> 1. QuickJS 后端的 `JavascriptRuntime.jsonStringify` 是 `UnimplementedError`，
>    **不能**用它序列化；要 JSON 必须在 JS 侧调 `JSON.stringify(...)`、Dart 侧 `jsonDecode`。
>    `rawResult` 的 Dart 类型（Map / JSInvokable）不够稳定，也不宜直接依赖。
> 2. `evaluate()` 在 QuickJS 后端**同步**返回，且**语法错误不抛异常**——
>    错误通过 `JsEvalResult.isError == true` 传递，必须显式检查该标志位。
>
> **平台差异（重要）**：Android 的 QuickJS **不是**本项目自己编译的——插件
> `android/build.gradle` 里 `externalNativeBuild` 的 CMake 构建被注释掉了
> （注释说明 "crashing with SEGV_MAPERR on ARM based devices"），改用 JitPack 预编译库
> `com.github.fast-development.android-js-runtimes:fastdev-jsruntimes-quickjs:0.3.6`。
> 即 Android 侧依赖 **JitPack 网络仓库**，构建机需能访问 jitpack.io。
> 已确认产物中带 `lib/<abi>/libfastdev_quickjs_runtime.so`（arm64-v8a / armeabi-v7a / x86_64）。
>
> **`flutter test` 的坑（新增，务必记牢）**：`flutter test` 跑在 **Windows 宿主的 Dart VM** 上，
> 而 QuickJS 需要 `quickjs_c_bridge.dll` 在 DLL 搜索路径里；插件只为 **Flutter Windows 应用构建**
> 拷贝该 DLL，**不为 `flutter test` 拷贝**。因此直接跑测试会失败于
> `Failed to load dynamic library 'quickjs_c_bridge.dll'`（error code 126）。
> 解决：把 `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\flutter_js-0.8.7\windows\shared\quickjs_c_bridge.dll`
> 拷到项目根目录（或设 `PATH`）即可。**这不影响 Android**（QuickJS 走 JitPack 的 .so）。
>
> 验证：临时 `flutter test` 脚本 **5 组全部通过**，脚本已删除。覆盖：
> `evalSimple() == 2`、`evalWithCallback()` 拿到 Dart 函数返回值 `'pong|from-dart'`
> （日志可见 JS 传回的参数 `ping`）、`evalWithObject()` 解析出含中文/浮点/数组/嵌套对象的 Map、
> 非法 JS 返回非空错误串且 `isError == true` 不崩、连续多次创建运行时互不影响。
> 另跑了一次**耗时基准**（脚本已删）：首次 `evalSimple()` **22ms**、第二次 **0ms**。
>
> **真机验证**：Redmi K60（2211133C，Android 16 / arm64）`flutter run` 输出
> `I/flutter: JS 1+1 = 2`，App 正常启动。Windows 桌面端（同一套 `QuickJsRuntime2` 后端）
> 同样输出 `JS 1+1 = 2`，交叉印证。
>
> **本阶段的环境问题（与代码无关，但会卡住后续阶段）**：
> ① `flutter.bat` 在本机 DSH 沙箱里**永远挂死**（无输出直到超时）——原因是该批处理检测到
> PATH 里有 `pwsh` 后会 `call pwsh` 重新起一个 shell 来跑工具，嵌套 shell 在沙箱里被卡住。
> 绕开办法：直接用 `dart.exe <flutter>/bin/cache/flutter_tools.snapshot <args>` 调用，
> 或给 `flutter.bat` 传 `--no-version-check`。**后续所有 flutter 命令都建议走 snapshot 方式。**
> ② Flutter SDK 缓存里残留过 `flutter.bat.lock` / `lockfile`（零字节、无进程持有），
> 会让后续 flutter 命令无限等待，已删除。
> ③ `flutter run` 期间手机曾掉线一次（`device 'aacfd78e' not found`），重连后正常。

> **Phase 3.2a**（JS 运行时沙箱与兜底）：`dart analyze lib` 通过，**未新增依赖**。
> 只动 `lib/runtime/`，未碰业务页面。
>
> 改动：
> - 新建 `lib/runtime/js_sandbox.dart`：`JsSandbox` + `JsSandboxStatus` + `JsSandboxResult`
>   - **JS 跑在独立 isolate**，父 isolate 只计时；到点 `Isolate.kill(priority: immediate)`
>   - 常量：`kDefaultJsTimeout`(1000ms) / `kJsSandboxCreateTimeout`(5s) /
>     `kJsStackSize`(1MB) / `kJsNativeTimeoutHintMs`(1000) / `kSandboxLogChannel`('log')
>   - 串行化执行（Future 链 + `seq` 校验归属）；子 isolate 长驻，沙箱可复用
>   - 创建失败（isolate 起不来 / 初始化抛异常 / **被原生层静默打死**）一律降级为
>     不可用沙箱 + `debugPrint`，不抛异常；`onLog` 接收插件 `sendMessage('log', ...)`
>   - `dispose()` 幂等
>
> ⚠️ **必须记牢的三条实测结论（与任务书假设不符，已按证据调整实现）**：
>
> 1. **`getJavascriptRuntime()` 无法满足"显式传 timeout 和 memoryLimit"**：
>    它只透传 `extraArgs['stackSize']`，`timeout` / `memoryLimit` **既不在参数表里、
>    也不被转发**。故沙箱**直接构造 `QuickJsRuntime2`**，绕开该工厂函数。
>
> 2. **`QuickJsRuntime2.timeout` 实测无法中断死循环**：探针里
>    `while(true){}` 传 `timeout=1000` **与** `timeout=1` 都**永久挂住**
>    （两个探针进程都是手动 kill 的）。更麻烦的是 `evaluate()` 是同步 FFI 调用，
>    主 isolate 被阻塞在原生调用里，**Dart 侧的 `Future.timeout` 与测试 `Timeout` 也一起失效**
>    （探针设的 30s / 25s 测试超时同样没能触发）。
>    → 结论：**唯一可靠的兜底是独立 isolate + 父侧墙钟 kill**。这正是本阶段的核心设计。
>    原生 `timeout` 参数仍照传（纵深防御），但文档里明确标注"实测无效，不要依赖"。
>
> 3. **`memoryLimit` 传了就崩，两个平台都一样**：`QuickJsRuntime2` 在
>    `memoryLimit > 0` 时调用 `jsSetMemoryLimit`，而该符号
>    **不在任何随包发布的二进制里**：
>    - Windows `quickjs_c_bridge.dll` → `Failed to lookup symbol 'jsSetMemoryLimit'`（error 127），
>      抛的是**未被捕获**的 FFI 异常，直接把子 isolate 打死（探针4 复现：父 isolate 只等到超时）
>    - Android `libfastdev_quickjs_runtime.so`（从 APK 的 `lib/arm64-v8a/` 取出后检查）
>      → 符号名字符串**不在** `.dynstr` 中；同库的 `jsNewRuntime` / `jsEval` /
>      `jsSetMaxStackSize` / `jsFreeRuntime` **都在**
>    → 结论：**不传 `memoryLimit`**。内存失控改由"隔离 + 截止时间 kill"兜底
>    （内存炸弹测试已验证：疯狂分配也会被截止时间掐掉，父 isolate 不受影响）。
>    *残留风险*：没有内存硬上限，原生层 OOM 仍可能打死子 isolate（父 isolate 靠
>    `createTimeout` / `execute` 超时能收敛，但无法保证进程级内存安全）。已记入阻塞表。
>
> 验证：临时 `flutter test` 脚本 **12 组全部通过**，脚本已删除。覆盖：
> 正常路径（`1+1` → `'2'`、同沙箱复用三次、JS 出错返回 `error` 且之后仍可用）、
> **死循环被掐断**（800ms 截止 → `timeout`，耗时 <4s，父 isolate 未被阻塞）、
> **超时后沙箱标记不可用**且后续调用降级 `unavailable`、
> **内存炸弹**（疯狂分配 → `timeout`/`error`，绝不挂住）、
> **创建失败降级**（`simulateCreateFailure` → `unavailable`，`message` 含"创建失败"，不抛异常）、
> 不可用沙箱 `dispose` 幂等、**onMessage 桥穿过 isolate 边界**
> （JS `sendMessage('log','hello-from-js')` → 父 isolate 收到）、
> `dispose` 后执行降级且幂等、**并发 `execute` 串行化不错配**（`2`/`4`/`6`）。
>
> **真机验证**（Redmi K60，Android 16 / arm64）三条路径全部符合预期：
> ```
> [JS-VERIFY] 正常路径: status=success value=2
> [JS-VERIFY] UI tick @200ms（主 isolate 未被阻塞）   ← 死循环期间仍按时打印
> [JS-VERIFY] 死循环: status=timeout 耗时=804ms isUsable=false
> [JS-VERIFY] 创建失败: status=unavailable isUsable=false msg=运行时创建失败：...
> ```
> 其中 **200ms 的 tick 在 800ms 超时之前打印**，是"UI 线程确实没被 JS 阻塞"的直接证据。
>
> **测试注意**：JS 相关测试需 `quickjs_c_bridge.dll`（见 `docs/ENV.md`），
> 已拷到项目根目录；跑完已删除。

> **Phase 3.2b.1**（插件文件加载 + PluginRuntime 骨架）：`dart analyze lib` 通过，**未新增依赖**。
> 只动 `lib/runtime/` 与 `docs/`，未碰业务页面。**不做** `ctx.http` / `ctx.storage` 注入（留给 3.2b.2 / 3.2b.3），不接 UI。
>
> **插件文件格式（最小版，已写入 API.md）**：一个必需 + 一个可选，同目录同主名
> - `<name>.js`（必需）：必须定义全局 `__plugin`（常量 `kPluginGlobalName`），
>   其属性中的**函数**即入口函数，如 `fetchCourses: function (args) { return {...}; }`
> - `<name>.manifest.json`（可选）：`id`/`name`/`version`/`author`/`description`/`school`/`capabilities`，
>   键名小驼峰（CONTEXT 4.2.1）。缺省时元数据从 `__plugin` 推导；**文件存在时优先**
> - 校验链：脚本能求值 → `__plugin` 是对象 → 至少一个函数属性 → `id` 非空
> - 数据交换：入参 `JSON.parse` 进 JS、返回值 JS 侧 `JSON.stringify` 出、Dart 侧 `jsonDecode`；
>   **不用 `convertValue`**（沿用 3.2a 约束 3）
>
> 改动（按 CONTEXT 4.3「一个文件一个 public 类」拆成三个文件）：
> - 新建 `lib/runtime/plugin_manifest.dart`：`PluginManifest`（+ `kPluginManifestSuffix`）。
>   `tryDecode` 对空值/坏 JSON/非对象/**缺 id 或 id 为空白**一律返回 `null`，不伪造
> - 新建 `lib/runtime/plugin_handle.dart`：`PluginHandle`（+ `kPluginGlobalName`、
>   顶层函数 `buildPluginEntryCallScript`）
> - 新建 `lib/runtime/plugin_runtime.dart`：`PluginRuntime`（+ 顶层 `unawaitedDispose`）
> - 改 `lib/runtime/js_sandbox.dart`：**新增 `JsSandbox.unavailableReason` getter**，
>   让上层能把"插件不可用"的具体原因透传给用户（原来只能拿到笼统的"创建失败"）
>
> **两个值得记下的设计决定**：
> 1. **每插件独占一个 `JsSandbox`**。`__plugin` 是全局变量，若共用沙箱两个插件会互相覆盖
>    （已用测试证实：A 插件调 `who` 报错、B 插件调 `ping` 报错，各自只看得到自己的全局）。
>    独占沙箱还让"某个插件死循环只打死它自己的 isolate"，与 3.2a 的隔离设计一致。
> 2. **`PluginHandle` 保持完全不可变，`isUsable` 动态判定**：
>    `status == success && _sandbox.isUsable`。插件某次执行超时后沙箱被 kill，
>    `isUsable` 自动变 `false`，无需改任何字段——避免了"为了标记失效而破坏不可变性"。
>
> **入口函数调用脚本的转义做法**（`buildPluginEntryCallScript`）：函数名与参数都用
> `jsonEncode` 转成 JSON 字面量再嵌入——`jsonEncode` 一次得到 `"fetchCourses"`，
> **两次**得到 `"{\"a\":1}"`，而 JSON 字符串转义是 JS 字符串字面义的子集，
> 所以后者直接就是合法 JS 字面量，免去手写转义（手写转义在参数含引号/换行/中文/反斜杠时极易出错）。
> 另：`JSON.stringify(undefined)` 返回 `undefined` 而非字符串，脚本里显式归一为 `'null'`。
>
> **四条错误路径全部降级为带状态的 handle（不抛异常）**：
> | 情况 | status | 
> |------|--------|
> | 文件不存在/不可读/为空/两来源都不给 | `unavailable` |
> | 非法 JS（语法错误/运行时抛错） | `error` |
> | 缺 `__plugin`/无函数属性/缺 id/manifest 坏 | `error` |
> | 顶层死循环（加载时） | `timeout` |
> | 入口函数死循环（执行时） | `timeout` |
> | 沙箱创建失败/已销毁 | `unavailable` |
>
> 失败后会**立即销毁已建立的沙箱**，避免 isolate 泄漏。
>
> **验证**：临时 `flutter test` 脚本 **21 组全部通过**，脚本已删除。覆盖：
> 从文件加载（manifest 从 JS 推导 + `entries` 收集正确）、无参入口、
> **参数往返含引号/换行/中文/反斜杠**（转义正确性）、manifest 文件优先于 JS 推导、
> 重复调用、文件不存在 / 空文件 / 两来源都不给、语法错误、缺 `__plugin`、
> 无函数属性、缺 id、manifest 坏（不静默忽略）、**顶层死循环 → timeout**、
> **入口函数死循环 → timeout 且句柄随之不可用**、调用不存在的入口函数 → error 且插件仍可用、
> 沙箱创建失败 → unavailable、dispose 幂等且之后降级、
> **多插件独占沙箱互不干扰**、`PluginManifest.tryDecode` 容错、脚本转义。
>
> **真机验证**（Redmi K60；`adb shell getprop ro.product.model` 原始输出 = `2211133C`）：
> ```
> [PLUGIN-VERIFY] 临时目录: /data/user/0/com.example.my_schedule_app/code_cache/plugin_verify_QISTPE
> [PLUGIN-VERIFY] 正常加载: isUsable=true id=verify-plugin entries=[fetchCourses]
> [PLUGIN-VERIFY] 正常执行: status=success value={"ok":true,"echo":{"term":"2026-1"},"count":2}
> [PLUGIN-VERIFY] 非法JS: status=error isUsable=false
> [PLUGIN-VERIFY] 超时插件加载: isUsable=true
> [PLUGIN-VERIFY] 超时执行: status=timeout isUsable=false
> [PLUGIN-VERIFY] 沙箱不可用: status=unavailable isUsable=false reason=JS 沙箱不可用：...
> ```
> 其中"正常执行"的返回值证明**参数往返在真机上正确**（`{"term":"2026-1"}` 原样到达 JS 并返回）。
>
> **插件文件来源（本阶段的取舍）**：只支持调用方给 `path` 或 `jsSource`，
> 真机验证用 `Directory.systemTemp`（Android 上即应用私有 `code_cache`），
> **不改 `pubspec.yaml`**（因此没用 assets）。后续做"从文件安装插件"需二选一：
> 引入 `path_provider`（CONTEXT 技术栈**未声明**，须先改 CONTEXT）或改用 assets（须改 pubspec）。
>
> **测试注意**：JS 相关测试需 `quickjs_c_bridge.dll`（见 `docs/ENV.md`），已拷到项目根目录、跑完已删。

- [x] flutter_js 集成（Phase 3.1，仅验证可用性）
- [x] JS 运行时沙箱与兜底（Phase 3.2a，`lib/runtime/js_sandbox.dart`）
- [x] 插件文件加载 + PluginRuntime 骨架（Phase 3.2b.1：`plugin_manifest.dart` /
      `plugin_handle.dart` / `plugin_runtime.dart`）
- [ ] `lib/runtime/plugin_context.dart`（`ctx.http` / `ctx.storage` 注入）
- [ ] `lib/runtime/plugin_manager.dart`
- [ ] `lib/runtime/package_manager.dart`
- [ ] 插件管理 UI 接入真实数据

---

## Phase 4：第一个插件（未开始）

- [ ] WebView 登录页
- [ ] Cookie 提取
- [ ] NCST 插件（`ncst-jwxt.js`）
- [ ] 数据同步打通
- [ ] 从插件拉取课程并存入 Hive

---

## Phase 5：课表渲染 + 编辑（未开始）

- [ ] `lib/widgets/timetable_grid.dart`（网格布局）
- [ ] 课程详情底部弹层
- [ ] `lib/pages/edit/course_edit_page.dart`
- [ ] 添加/编辑/删除课程
- [ ] 覆盖层生效

---

## Phase 6：创意工坊 + 皮肤（未开始）

- [ ] SkinPack 模型接入
- [ ] ThemeEngine 加载皮肤
- [ ] `lib/pages/settings/skin_preview_page.dart`
- [ ] GitHub 索引拉取
- [ ] 下载/应用/切换皮肤

---

## Phase 7：通知 + 消息（未开始）

- [ ] `lib/services/notify_service.dart`
- [ ] 消息模块接入真实数据
- [ ] WorkManager 定时任务
- [ ] 上课/考试/作业提醒

---

## Phase 8：学习通插件（未开始）

- [ ] 学习通登录
- [ ] 作业/考试拉取
- [ ] 作业模块激活

---

## Phase 9：打包发布（未开始）

- [ ] 应用图标
- [ ] 启动页
- [ ] 签名 APK
- [ ] 分发给同学

---

## 阻塞与备注

（当遇到卡住的问题时，在这里记录）

| 日期 | 问题 | 状态 |
|------|------|------|
| 2026-09-21 | AppTheme 与 default_theme 存在循环 import，Phase 6 皮肤系统时考虑改为单向依赖 | 待处理 |
| 2026-09-21 | 皮肤令牌 `divider` 在 AppTheme 中无对应字段，需要时补 | 待处理 |
| 2026-09-22 | `AppTheme.explicitKeys` 因 Dart 私有命名参数限制只能公开，建议加 `@protected` | ✅ 已完成（Phase 2.1，`@protected` 无 lint 报错） |
| 2026-09-22 | `ModuleType` 枚举不携带默认 iconName，保持不依赖 Flutter 的纯净性（现状接受） | 已决定 |
| 2026-09-22 | `CONTEXT.md` 常量命名规范已从 `MAX_MODULES` 改为 `kMaxModules` | ✅ 已完成 |
| 2026-09-22 | home_page._iconFromName 建议 Phase 1.7 抽到 lib/widgets/ 复用 | ✅ 已完成（Phase 1.6） |
| 2026-09-22 | 课表设置页滑块默认 60，而 AppTheme.timetableCellHeight 默认 64；Phase 2 接存储时需统一取值来源 | ✅ 已完成（Phase 1.6.1：滑块初值改从 AppTheme 读取） |
| 2026-09-22 | `CourseProvider.deleteCourse` 已由同步改为异步（写 Hive）；Phase 5 编辑页调用时需 `await` | 待处理 |
| 2026-09-22 | 课程/考试/作业/消息 Provider 目前只有 CourseProvider 接了 Hive，其余待 Phase 2.2 接入 | 待处理 |
| 2026-09-22 | `settings` Box 的键名（`module_enabled_state` / `theme_brightness` / `semester_config`）已写入 API.md，属契约；改动需写迁移逻辑 | 已决定 |
| 2026-09-22 | `TimePlace` 新增 `weekType` 字段（Phase 2.2a），因当时无落盘课程故未写迁移；此后改 schema 必须写迁移 | 已决定 |
| 2026-09-22 | `SemesterProvider.loadFromStorage` 读到相同配置也会通知一次（`SemesterConfig` 无 `==`）；启动只调一次，暂不优化 | 待处理 |
| 2026-09-22 | `main.dart` 的 `_seedTemporaryTestData`（Phase 2.2b 临时测试数据）必须在 Phase 2.2c 删除 | ✅ 已完成（Phase 2.2b.1 提前删除） |
| 2026-09-22 | 设备上已写入的测试学期与 3 门测试课程仍留在 Hive 里（代码已删，数据还在）；需 `CourseProvider.clearAll()` 或清除应用数据一次 | 待处理（**真机已清空数据，见 Phase 2.2b 系列验收记录**；后续无需再处理） |
| 2026-09-22 | `TimetableSettingsPage` 的"显示周末/显示节次时间/每节高度"仍是内存态、重启即丢，待迁入 `SettingsProvider` | 待处理 |
| 2026-09-22 | 卡片字号分档依赖 `timetableCellHeight`；若用户在课表设置里改每节高度，字号会自动跟随（该设置持久化后需回归验证） | ✅ 已作废（Phase 2.2b.3 改为固定字号，不再分档） |
| 2026-09-22 | `TimePlace` 只有 `room` 一个字段（常含"校区 + 教室"），卡片靠 `splitCampusAndRoom` 按空白取教室；Phase 4 定下插件契约后应加独立 `campus` 字段（需迁移） | 待处理 |
| 2026-09-22 | 卡片已不显示校区（Phase 2.2b.4），校区信息目前只在详情弹层的教室串里；若将来要分开展示需用 `splitCampusAndRoom().campus` | 已决定 |
| 2026-09-22 | 学期配置页的总周数滑杆范围固定 10–30；若插件/历史数据给出该范围外的周数，进页面后会被收进区间（保存即改动原值） | ✅ 已完成（Phase 2.2c.1 修正：下限放宽到 4，军训等短学期不再被顶成 10 周） |
| 2026-09-22 | 学期配置页只在"已有配置"时显示"重置"；清除后没有再次进入的入口提示（需重新从空态/设置页进入） | 待处理 |
| 2026-09-22 | `weeksFromRange` 按提示词要求**预先过滤**单双周（单周 → 只有奇数周），而 `TimetableLogic.parseWeeks` 保留基础周次、由 `hasClassInWeek` 叠加过滤。两者界面表现等价，但 `weeks` 值形态不一致（自建课程 vs 插件课程） | 待处理 |
| 2026-09-22 | 添加课程页的时间段默认 `length = 2`（连堂），且未限制"起始节次 + 持续节数 ≤ 12"；越界部分会被 `buildGrid` 静默忽略 | 待处理 |
| 2026-09-22 | 添加课程页的课程 id 用 `user_${microsecondsSinceEpoch}`，理论上同一微秒内两次保存会撞 id（UI 操作不可能达到，暂不处理） | 待处理 |
| 2026-09-22 | 添加课程页颜色默认选中第一个预设色（按提示词）；从"配色分散"角度，默认选"自动"更好，待确认 | 待处理 |
| 2026-09-22 | 窄屏（360dp）下每列约 46px，教室用 `maxLines: 2` + 裁切；很长的教室名（如 `教学楼A HE-405`）第 2 行仍可能被裁掉尾部 | 待处理 |
| 2026-09-22 | `kDefaultSectionTimes` 硬编码 12 个节次时间，Phase 4 插件接入后需改为从插件数据读取 | 待处理 |
| 2026-09-22 | 课表网格的星期表头不显示日期 | ✅ 已完成（Phase 2.2b.3：表头显示"一 11"并在时间列显示月份） |
| 2026-09-22 | 导航栏配置页需给出"已达上限 5 个"的提示，并显示哪些模块被挤出 | ✅ 已完成（Phase 1.6） |
| 2026-09-22 | ThemeProvider.currentSkinId 暂未落盘，Phase 6 创意工坊时补 | 待处理 |
| 2026-09-23 | `QuickJsRuntime2.timeout` 实测无法中断死循环，且会连带冻结 Dart 侧 `Future.timeout`；JS 必须跑独立 isolate（3.2a 已按此实现） | 已决定 |
| 2026-09-23 | `jsSetMemoryLimit` 符号在 Windows DLL 与 Android .so 中均不存在，**不能传 `memoryLimit`**；因此**没有 JS 内存硬上限**，原生 OOM 仍可能打死子 isolate（父 isolate 可靠超时收敛，但非进程级内存安全） | ⚠️ 待处理 |
| 2026-09-23 | `getJavascriptRuntime()` 不转发 `timeout`/`memoryLimit`，沙箱改为直接构造 `QuickJsRuntime2`；若将来改用该工厂函数需重审 | 已决定 |
| 2026-09-23 | flutter_js 的 Promise 路径走 `callFunction`，而 QuickJS 后端该方法是 `UnimplementedError`；3.2b 若插件需要异步需自行设计（不依赖库的 Promise 支持） | ⚠️ 待处理 |
| 2026-09-23 | 3.2a 的 `kDefaultJsTimeout`(1000ms) 是按"单次求值"设的；3.2b 拉取大表数据时可能需放宽，需实测后定 | 待处理 |
| 2026-09-23 | **`docs/PROGRESS.md` 被编码损坏**：commit `f2cad97` 里的该文件不是合法 UTF-8（1057 处三字节序列的第三字节被替换成 `?`，如 `EF BC 88`→`EF BC 3F`，即全角标点变乱码），且混入 `0A 0D 0A` 混合换行。`1224163` 及更早的版本都是合法 UTF-8，两者 diff 为 545 增 545 删（**同样的行被重新编码，无内容改动**）。已 `git checkout 1224163 -- docs/PROGRESS.md` 恢复。**疑似编辑器以非 UTF-8 编码保存所致**；`f2cad97` 与 `1224163` 是同一 commit message 的重复提交 | ✅ 已恢复（但 `f2cad97` 仍留在历史里） |
| 2026-09-23 | 插件"从文件安装"需要应用私有目录：引入 `path_provider` 需先改 CONTEXT 技术栈（当前**未声明**该依赖），或改用 assets（需改 pubspec）。3.2b.1 未做，等后续阶段定 | 待处理 |