# 项目宪法（CONTEXT）

> 本文件是项目的"根本大法"，所有 AI 协作和人工开发都必须遵守。
> 每次生成代码前，必须把本文件内容作为前置上下文提供给 AI。
> 本文件一旦确定，不轻易改动；如需修改，请更新版本号并说明原因。

- 版本：v1.4
- 最后更新：2026-09-23

---

## 1. 项目定位

一款**插件驱动、皮肤装扮、数据本地**的个性化课表 App。

- **插件**（`.js` 文件）扩展数据能力：拉取教务系统的课程、考试、作业等数据
- **皮肤**（`.skin.json` 文件）扩展视觉表现：颜色、字体、圆角、布局
- **数据全部本地存储**：无服务器、无隐私风险、无账号托管
- **可编辑**：用户可修改任意课程信息，通过"覆盖层"保存，不污染原始数据
- **动态导航**：底部导航栏的模块由用户决定，最多 5 个

### 目标用户
- 主要：本人 + 同校同学
- 次要：愿意自己写插件的其他学校学生

### 核心价值
| 价值点 | 说明 |
|--------|------|
| 插件化 | 不同学校不改 App，写/下一个插件即可 |
| 数据本地 | 无服务器、无隐私风险 |
| 可编辑 | 教务数据 + 用户覆盖层 |
| 可装扮 | 创意工坊提供皮肤 |
| 动态导航 | 用户决定底部显示哪些模块 |

---

## 2. 技术栈

| 用途 | 库 | 版本 |
|------|-----|------|
| 框架 | Flutter | 3.47.x |
| 语言 | Dart | 3.x |
| 状态管理 | provider | ^6.1.1 |
| 本地存储 | hive / hive_flutter | ^2.2.3 / ^1.1.0 |
| 路径获取 | path_provider | ^2.1.4 |
| 安全存储 | flutter_secure_storage | ^9.0.0 |
| 网络 | dio | ^5.4.0 |
| 路由 | go_router | ^13.0.0 |
| WebView | webview_flutter | ^4.7.0 |
| JS 引擎 | flutter_js | 后续引入 |
| 本地通知 | flutter_local_notifications | ^16.3.0 |
| 时间格式化 | intl | ^0.19.0 |

### 环境约束
- Android 最低版本：API 26（Android 8.0）
- 目标版本：API 34（Android 14）
- 打包产物：APK（暂不做 iOS）

---

## 3. 架构原则

### 3.1 插件与内核边界
- **内核不知道任何具体学校的 URL、字段名、接口路径**
- 插件通过注入的 `ctx` API（http / storage / notify / log）与外界交互
- 插件**不接触** UI、文件系统、原生 API
- 插件输出统一模型（Course / Exam / Homework），由内核消费

### 3.2 UI 与主题
- 所有 UI 组件**必须**从 `AppThemeExtension` 读样式
- **禁止**硬编码颜色、圆角、间距、字体
- 主题支持明暗双模式，通过 `AppTheme.withBrightness()` 切换

### 3.3 数据与编辑
- 原始数据（来自插件）+ 覆盖层（来自用户）分离存储
- 展示时通过 `displayXxx()` 函数叠加：`override?.customXxx ?? original.xxx`
- 同步时**保留覆盖层**，只更新原始字段
- 删除教务课程只能"隐藏"或"永久忽略"，不能真删

### 3.4 模块系统
- 模块由**能力（Capability）**驱动
- 能力来自内置或插件声明
- 底部导航栏最多 5 个模块
- 课表、设置**不可关闭**
- 用户改动后导航栏**立即刷新**

### 3.5 存储分离
| 数据类型 | 存储位置 |
|----------|----------|
| 课程/考试/作业/消息 | Hive Box |
| 用户覆盖层 | Hive Box（key = 课程 ID） |
| 模块配置/用户偏好 | Hive Box `settings` |
| Cookie / Token | flutter_secure_storage（按插件 ID 分 key） |
| 当前皮肤 ID | Hive Box `settings` |
| 插件文件（`.js` / `.manifest.json`） | 应用私有目录 `<appDocuments>/plugins/`（`PluginStorageService` 管理） |
| 插件私有 KV | Hive Box `plugin_data`（key = `<pluginId>:<userKey>`） |

### 3.6 插件入口函数幂等约定（Phase 3.6）

> **写插件（尤其 Phase 4 的 NCST 插件）前必读。插件的入口函数会被宿主执行多次，
> 因此必须写成幂等的纯计算。**

原因：`ctx.http` 在 JS 侧**无法同步等待**——沙箱跑在独立 isolate（Dart 回调闭包跨不过去）、
`sendMessage` 通道要求 Dart 侧同步返回、QuickJS 后端不支持 async（`callFunction` 未实现）、
且唯一的同步 HTTP 客户端不支持 HTTPS。所以宿主用"**登记待办 + 宿主重放**"来实现同步外观：

1. 每轮开始前，宿主把"本轮状态"（HTTP 响应缓存 / storage 快照 / cookie）注入成 JS 全局；
2. 插件的 `ctx.http.get(url)` **命中缓存就直接返回**；未命中只把请求登记进待办并返回
   `{ok:false,error:'pending'}`，**绝不发网络**；
3. 宿主读回待办，用 dio 取回（可超时），并入缓存，然后**重放**入口函数；
4. **没有待办的那一轮就是最终轮**。

由此产生三条**硬约束**：

- **入口函数必须幂等**：不要在里面做"自增 / 累加 / 发消息 / 写外部状态"这类
  重复执行会出错的副作用；
- **`ctx.storage` 的修改只在最终轮生效**：每轮都从同一快照开始，
  中间轮次的修改会被丢弃（**同一轮内** `set` 后 `get` 仍然可见）；
- **`ctx.*` 只应在入口函数里使用**：顶层（`__plugin` 定义处）调用不会被提交，
  那时还没有"轮"的概念。

请求去重：**同一轮内**对同一 `(method, url, body, headers)` 只登记一次；
**跨轮**命中缓存。因此"循环请求同一个 URL"是安全的。
轮数上限 8（`PluginContext.kMaxReplayRounds`），超过即报错，不会无限循环。

---

## 4. 代码规范

### 4.1 命名
- 类名：大驼峰 `UserOverride`
- 变量/方法：小驼峰 `fetchCourses()`
- 常量：`k` 前缀小驼峰 `const kMaxModules = 5;`
  （避免触发 `constant_identifier_names` lint，符合 Dart 事实标准）
- 文件名：小写下划线 `user_override.dart`
- 私有成员：下划线前缀 `_currentTheme`

### 4.2 数据类型
- 所有类字段用 `final`，不可变
- 使用 Dart 空安全，禁止滥用 `dynamic`
- `fromJson` 必须处理 `null` 和类型转换（用 `as` 前先判空）
- 时间字段用 `DateTime`，不用字符串
- 颜色用 `Color`，JSON 中存 hex 字符串（如 `"#1E88E5"`）

### 4.2.1 序列化字段冻结
- **Phase 2 落盘后，所有模型的 JSON 键名视为契约，不得随意改动。**
  需要改时必须写迁移逻辑（读旧键 → 写新键 → 删除旧键）。
- 键名统一为小驼峰（`sourcePluginId`，不是 `sourcePluginID`），
  同一含义在所有模型中必须用同一个键名。
- `fromJson` 读取的键与 `toJson` 写入的键必须一一对应，
  新增字段时两处同步修改。
- **新增字段的例外（Phase 3.5.1 补充）**：**纯新增**字段
  （不改名、不改已有字段的语义、且 `fromJson` 对"缺该键"有向后兼容的默认值）
  **不需要写迁移逻辑**——旧数据读出来就是默认值，写回时自然带上新键。
  需要迁移的只有两种情况：**键改名**、**已有键的语义变化**。
  例：`PluginMeta.isRemovable`（缺键回落 `true`）属纯新增，无需迁移。
- Box 名称同样是契约，见 `lib/services/storage_service.dart` 的
  `kXxxBoxName` 常量。
- 存储层一律使用 `Box<String>` + 手写 JSON，**不使用**
  `TypeAdapter` / `build_runner`（见第 6 节禁止事项）。

### 4.3 文件结构
- 每个文件顶部加一行用途注释
- import 顺序：dart → package → 相对路径
- 每个类最多一个文件，不写多个 public 类

### 4.4 异步与错误
- 所有异步方法用 `async/await`
- 网络请求必须有 try-catch
- 错误用 `debugPrint` 输出，**不用 `print`**
- 用户可见错误用 SnackBar

### 4.5 状态管理
- 所有 Provider 继承 `ChangeNotifier`
- Provider 之间不直接互相引用，通过 ProxyProvider 联动
- 不要用 `setState` 管理跨页面状态

---

## 5. 目录结构（最终形态）
```
    lib/
    ├── main.dart
    ├── app.dart
    ├── models/ # 数据模型
    ├── runtime/ # 插件运行时
    ├── theme/ # 主题系统
    ├── providers/ # 状态管理
    ├── services/ # 业务服务
    ├── pages/ # 页面
    │ ├── home_page.dart
    │ ├── timetable/
    │ ├── course_list/
    │ ├── exam/
    │ ├── homework/
    │ ├── message/
    │ ├── edit/
    │ └── settings/
    └── widgets/ # 通用组件
```

---

## 6. 禁止事项

- ❌ 不引入未在本文档"技术栈"中声明的依赖
- ❌ 不在 UI 层直接发起 HTTP 请求
- ❌ 不硬编码任何学校 URL、字段名、接口路径
- ❌ 不硬编码颜色/尺寸/字体（必须从 AppTheme 读）
- ❌ 不使用 `print`，用 `debugPrint`
- ❌ 不写单元测试（Phase 1-5 阶段不写，Phase 6 后再说）
- ❌ 不使用代码生成器（build_runner、freezed 等），手写 fromJson/toJson
- ❌ 不在主分支上做破坏性重构

---

## 7. 版本记录

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0 | 2026-09-21 | 初始版本 |
| v1.1 | 2026-09-22 | 4.1 常量命名改为 `k` 前缀小驼峰（避免 `constant_identifier_names` lint）；新增 4.2.1 序列化字段冻结 |
| v1.2 | 2026-09-23 | Phase 3.4 引入 path_provider，支持插件文件持久化 |
| v1.3 | 2026-09-23 | Phase 3.5.1 补充 4.2.1：**纯新增**字段（不改名、不改语义、缺键有兼容默认值）无需迁移，只有键改名 / 语义变化才要迁移 |
| v1.4 | 2026-09-23 | Phase 3.6 新增 **3.6 插件入口函数幂等约定**（`ctx.http` 用"登记待办 + 宿主重放"实现，入口函数会被执行多次）；3.5 存储分离表补插件私有 KV（`plugin_data`） |