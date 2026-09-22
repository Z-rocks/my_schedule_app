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
- [ ] `lib/main.dart` — 入口 + MultiProvider
- [ ] `lib/app.dart` — MaterialApp + ThemeExtension
- [ ] `lib/pages/home_page.dart` — 动态导航栏

### 1.5 页面骨架（空态）
- [ ] `lib/pages/timetable/timetable_view.dart`
- [ ] `lib/pages/course_list/course_list_view.dart`
- [ ] `lib/pages/exam/exam_view.dart`
- [ ] `lib/pages/homework/homework_view.dart`
- [ ] `lib/pages/message/message_view.dart`

### 1.6 设置页
- [ ] `lib/pages/settings/settings_page.dart`
- [ ] `lib/pages/settings/module_config_page.dart`
- [ ] `lib/pages/settings/plugin_manage_page.dart`
- [ ] `lib/pages/settings/workshop_page.dart`
- [ ] `lib/pages/settings/timetable_settings_page.dart`

### 1.7 通用组件
- [ ] `lib/widgets/empty_state.dart`
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
| - | - | - |