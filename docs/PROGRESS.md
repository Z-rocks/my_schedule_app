# 开发进度（PROGRESS）

> 每次完成一个文件或一个任务，勾掉对应项。
> 遇到阻塞，在旁边加 `⚠️` 并说明。
> 本文件是"当前状态"的唯一真相来源。

- 最后更新：2026-09-22

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

## Phase 2：存储与业务（进行中）

- [x] Hive 初始化
- [x] `lib/services/storage_service.dart`
- [x] `lib/services/override_engine.dart`
- [x] `lib/services/timetable_logic.dart`（周次解析、网格构建）— Phase 2.2a
- [x] CourseProvider 接入 Hive
- [ ] 手工塞测试数据，课表能渲染

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

## Phase 3：插件运行时（未开始）

- [ ] flutter_js 集成
- [ ] `lib/runtime/plugin_context.dart`
- [ ] `lib/runtime/plugin_runtime.dart`
- [ ] `lib/runtime/sandbox.dart`
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
| 2026-09-22 | 导航栏配置页需给出"已达上限 5 个"的提示，并显示哪些模块被挤出 | ✅ 已完成（Phase 1.6） |
| 2026-09-22 | ThemeProvider.currentSkinId 暂未落盘，Phase 6 创意工坊时补 | 待处理 |