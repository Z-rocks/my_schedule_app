# 开发进度（PROGRESS）

> 每次完成一个文件或一个任务，勾掉对应项。
> 遇到阻塞，在旁边加 `⚠️` 并说明。
> 本文件是"当前状态"的唯一真相来源。

- 最后更新：2026-09-21

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

## Phase 1：内核骨架（进行中）

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
- [ ] `lib/pages/settings/settings_page.dart`
- [ ] `lib/pages/settings/module_config_page.dart`
- [ ] `lib/pages/settings/plugin_manage_page.dart`
- [ ] `lib/pages/settings/workshop_page.dart`
- [ ] `lib/pages/settings/timetable_settings_page.dart`

### 1.7 通用组件
- [x] `lib/widgets/empty_state.dart`（已在 Phase 1.5 完成）
- [ ] `lib/widgets/course_card.dart`（预留）
- [ ] `lib/widgets/week_selector.dart`（预留）

### 1.8 验收标准
- [ ] App 能运行，底部导航显示 4 个模块（课表/课程/考试/设置）
- [ ] 所有页面显示空态，无崩溃
- [ ] 设置 → 导航栏配置能勾选/取消模块
- [ ] 导航栏改动实时生效
- [ ] 设置 → 插件管理/创意工坊能进入占位页

---

## Phase 2：存储与业务（未开始）

- [ ] Hive 初始化
- [ ] `lib/services/storage_service.dart`
- [ ] `lib/services/override_engine.dart`
- [ ] `lib/services/timetable_logic.dart`（周次解析、网格构建）
- [ ] CourseProvider 接入 Hive
- [ ] 手工塞测试数据，课表能渲染

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
| 2026-09-21 | `AppTheme.explicitKeys` 因 Dart 私有命名参数限制只能公开，建议加 `@protected` | 待处理 |
| 2026-09-22 | `ModuleType` 枚举不携带默认 iconName，保持不依赖 Flutter 的纯净性（现状接受） | 已决定 |
| 2026-09-22 | `CONTEXT.md` 常量命名规范已从 `MAX_MODULES` 改为 `kMaxModules` | ✅ 已完成 |
| 2026-09-22 | home_page._iconFromName 建议 Phase 1.7 抽到 lib/widgets/ 复用 | 待处理 |
| 2026-09-22 | 导航栏配置页需给出"已达上限 5 个"的提示，并显示哪些模块被挤出 | 待处理 |