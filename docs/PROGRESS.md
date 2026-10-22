# 开发进度（PROGRESS）

> 每次完成一个文件或一个任务，勾掉对应项。
> 遇到阻塞，在旁边加 `⚠️` 并说明。
> 本文件是"当前状态"的唯一真相来源。

- 最后更新：2026-10-16

---

## 🚩 当前进度快照

> 给新会话 AI 用。每次阶段切换时更新。

- **最新完成**：**Phase 8（学习通插件 + 作业/考试内核接线）** ——
  `assets/plugins/chaoxing.js` 三个入口（`fetchCourseList` / `fetchHomeworks` /
  `fetchExams`）+ 内核侧 `HomeworkProvider` / `ExamProvider` /
  `PluginEntitySyncService` / "按课程勾选后抓取"页。
  **已在真实账号上跑通**：68 门课程、1 份作业（含 9 题正文、截止
  `2026-10-18T23:29`）、1 场考试（`2026-09-18 09:00`~`2027-01-08 16:00`）。
  **真机验收通过**（小米 13 / Android 16）：登录 → 保存 Cookie → 68 门课 →
  作业同步落盘，真机顺带暴露并修掉 2 个桌面测不出的 bug（明文 HTTP 被拦、
  登录成功判定对 scheme 敏感）。接口测绘见 `docs/chaoxing-api.md`，
  验证见下方 Phase 8 备注与"真机实测"小节。
- **Phase 5.1（课表"没有数据"的真相 + 周次解析加固）** ——
  用户反馈"课表没数据、课程页正常"。**根因不是数据没读到**：课程是 `4,6-14周`
  而当时是第 5 周，**课表第 5 周本来就该是空的**——问题在于页面对此**一个字都不说**。
  已加"本周没有课"说明条 + 跳到最近有课周；顺带修掉全角数字/中文数字
  解析成空导致课程**静默消失**的缺陷；并用 **37 组样本对拍**抓出 Dart↔JS
  的 **6 处分歧**。详见 Phase 5.1 备注。
- **Phase 7（消息模块接真实数据 + `ctx.notify` 落地）** ——
  `MessageProvider` 从纯内存改为 **Hive 持久化**，消息页可用，
  插件通知与同步结果都落地为站内消息。系统通知**有意未做**（见该阶段备注）。
- **Phase 6（皮肤系统 / 创意工坊 / 暗色模式）** —— 暗色配色**推导**（保留皮肤色相），
  明暗三态，4 套内置皮肤 + `assets/skins/`，皮肤预览页。修掉 3 个真实 bug。
- **Phase 5（课程编辑 / 删除 / 隐藏）** —— 编辑两种课程的落点刻意分开，
  新增「已隐藏的课程」恢复页。
- **Phase 4 全部完成**：4.1 ✅ → 4.2 ✅ → 4.2.1 ✅ → 4.2.2 ✅ → 4.3 ✅ →
  4.4 ✅（含真机）→ release 包冒烟 ✅（2026-09-30）
- **代码状态**：Phase 4 `c981efb`；Phase 5 `dbec21a`；Phase 6 `f3412ef`；
  Phase 7 `acce25f`；Phase 5.1 见下
- **Phase 2 全部完成**：Hive 存储 + 课表渲染 + 学期配置 + 添加课程
- **Phase 3 全部完成**：插件运行时（沙箱 → 加载 → 多插件管理 → 文件持久化 → 管理 UI → **ctx**）
- **下一步**：Phase 9（发布打包，**需要用户定图标与签名**）；
  另需用户决定是否引入 `flutter_local_notifications` 做系统通知。
  Phase 8 遗留项见下方 Phase 8 备注的"未做"清单（真机验收 / 定时同步 /
  作业提醒 / 插件文件导入）
- **⚠️ 环境提示（4.3 复验踩到）**：
  ① 设备可能把 App 当**横屏**应用（`uiautomator` 报 `rotation="3"`），
  会让截图旋转 90° 且 `adb input tap` 坐标全落空；
  用 `settings put system accelerometer_rotation 0` + `user_rotation 0` 锁定竖屏。
  ② **判断校园网可达性不要用 `ping`**（Android shell 无 ICMP 权限，必然 100% 丢包），
  要用 `curl` 或 TCP 连接。
  ③ `flutter run` 安装后设备可能掉线（`device 'aacfd78e' not found`），
  `adb kill-server && adb start-server` 可恢复；或直接用
  `adb install -r build\app\outputs\flutter-apk\app-debug.apk` 绕开。
- **✅ 4.3 验证状态（已完成，不需要人工补跑）**：
  `dart analyze`（**整包，含 `test/`**）→ `No issues found!`；
  新增逻辑另用临时测试脚本 **16 组全部通过**（脚本跑完即删）：
  `saveCourse` 覆盖层保留 4 组（含**直接复现修复前的丢数据场景**）、
  `parseCourses` 容错 4 组、`SyncReport`/`SyncOutcome` 语义 5 组、重试策略常量 3 组；
  `node --check` 通过 `ncst-jwxt.js` 与 `example.js` 的 JS 语法检查；
  **真机复验也已完成**（见 4.3 备注开头）。
- **✅ 4.2.2 真机复验已通过（2026-09-30）**：登录页正常打开，无 `ERR_CLEARTEXT_*`。
  并从**装进设备的 APK** 用 `aapt2 dump xmltree` 解出配置确实生效：
  `base-config cleartextTrafficPermitted=false` + 唯一一条
  `domain-config=true`（`xjw1.ncst.edu.cn`，`includeSubdomains=true`）；
  manifest 含 `networkSecurityConfig` 与 `INTERNET`，且**无** `usesCleartextTraffic`。
- **✅ 4.2.1 真机复验已通过（2026-09-30）**：整轮登录无 `ERR_CERT_*`。
  ⚠️ 但本轮教务站**没有报证书错**，所以 `onSslAuthError` 的放行回调**未被触发**——
  结论是"未出现证书失败"，不是"放行回调被验证过"。若将来换学校遇到自签证书，
  仍需按老办法 `adb logcat -d | grep WebViewLoginPage` 确认出现 `SSL 错误放行`。
- **✅ 4.2 真机链路已通（2026-09-30）**：校园 WiFi 下「登录 → 同步 → 课表显示」全通。
  ⚠️ 但**真实教务响应结构只验证到"能解析出 4 门课程"这一层**：
  字段名仍来自抓包结构，本次没逐字段核对课程名/教师/学分的正确性。
  课表页第 5 周出现的「综合评价方法 / HA-303」来自教务数据，属正向证据。
- **⚠️ Phase 4 收尾必做：release 包冒烟**：跑一次 **`flutter build apk --release`**。
  到目前为止**所有网络相关验证都是在 debug 包里做的**（debug/profile manifest 自带 `INTERNET`
  权限），release 包是否有其他权限 / 混淆（R8）问题**完全没有验证过**。3.6 刚发现
  `src/main` 缺 `INTERNET` 就是同类问题——release 冒烟必须真正装到设备上跑通
  "安装插件 → `ctx.http` 拉数据"这条链路。
- **cleartext 问题已定案（4.2.2 ✅ 已修并复验）**：4.2 曾判定"NCST 是 https，不需要 cleartext 配置"
  —— **这个判断被真机推翻了**：登录会从 https **重定向到
  `http://xjw1.ncst.edu.cn/gotoLogin`**，被系统拦成 `net::ERR_CLEARTEXT_NOT_PERMITTED`。
  现已加 `network_security_config.xml` **定向白名单**（base 仍 `false`，
  只放开 `xjw1.ncst.edu.cn` 含子域），**未**用全局 `usesCleartextTraffic="true"`。
  其他学校若仍全程 http，修法相同（追加一条 `domain-config`）。
- **遗留**：ModuleProvider 改用 `loadedCapabilities`；`ctx.notify` 接真实通知（Phase 7）；
  插件管理 UI 的"从文件导入"（Phase 6+）；
  课表显示节次时间（数据已落 `plugin_data`，真机确认 12 条，UI 未接，留 4.4）；
  单页/AJAX 登录（URL 不变）无法自动判定成功（4.1）
- **最近 commit**：`d8be3b3` feat(sync): 数据同步打通（4.3）；
  `6e91145` feat(course-list): 课程列表页接入真实数据；
  `332bfcd` docs: 软件工程七条基本原理学习笔记
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
  - **PluginManager 不继承 ChangeNotifier**（无状态服务），通知 UI 是 PluginProvider 的职责
  - **加载失败原因不落盘**（运行时瞬时状态），只存 `PluginProvider.loadErrors` 内存
  - **插件 id 只允许字母/数字/下划线/横线**（防 `../` 路径穿越），点号也禁止
  - **不把安装绝对路径存进 meta**（iOS 容器 UUID 每次更新会变），一律按 id 现算
  - **UI 颜色一律从 AppTheme 读**（3.5 新增 `success` / `warning` 两个状态令牌，禁止硬编码绿/黄）
  - **"来源"与"策略"必须分开**：`source == 'builtin'` 只表示随 App 打包，**不代表不可卸载**；
    能否卸载只看 `PluginMeta.isRemovable`（3.5.1 修正了这个过度推断）
  - ⚠️ **插件入口函数必须幂等**（Phase 3.6，写 Phase 4 插件时最常引用的一条）：
    `ctx.http` 用"登记待办 + 宿主重放"实现 → **入口函数会被执行多次**；
    `ctx.storage` 的修改**只在最终轮生效**；`ctx.*` **只应在入口函数里用**。
    完整说明见 **CONTEXT.md 3.6**，速查见 **API.md 的 `plugin_ctx_script.dart` 小节**
  - **widget 测试里真实文件 I/O 不会推进**（fake-async），相关断言须放 `tester.runAsync`；
    且**不要在 `runAsync` 里用 `pumpAndSettle`**（会永不返回）
  - **插件函数可能被执行多次**（`ctx.http` 用"重放"实现）：入口函数必须幂等；
    `ctx.storage` 副作用**只在最终轮**提交；`ctx.*` 只应在入口函数里用
  - **`testWidgets`/`TestWidgetsFlutterBinding` 会把 HTTP mock 成 400**：
    要访问真实（含本机 loopback）服务必须 `HttpOverrides.global = null`
  - **WebView 页面无法在 `flutter test` 里 pump**（`WebViewController()` 需要
    `WebViewPlatform.instance`，测试环境为 null）→ 登录页只能真机验证，
    单测覆盖其**纯函数**（`isLoginSuccessUrl`）与构造契约
  - **登录地址/成功判定由插件声明**（`PluginManifest.loginUrl` / `checkUrl`），
    内核**不得硬编码任何学校 URL**（CONTEXT 3.1）
  - **`assets/plugins/` 是目录声明** → 新增插件文件**不用改 pubspec**（4.2）
  - **插件里的工具函数必须放 `__plugin` 外面**：运行时用
    `Object.keys(__plugin).filter(typeof === 'function')` 收集入口函数，
    放进对象会被误报成"入口函数"（4.2 踩到过）
  - **沙箱里调不到 Dart，所以 JS 侧复刻的算法必须逐样本对拍**：
    `ncst-jwxt.js` 的 `__ncst_parseWeeks` 与 `TimetableLogic.parseWeeks`
    用 24 组样本对拍（含全角标点 / 反向区间 / 超大区间 / 乱码）。对拍方式是
    **裸 `JsSandbox` 直接调 JS 函数**，不必为测试往插件里塞调试入口（4.2）
  - **教务系统可能是校园内网地址**（NCST 的 `xjw1.ncst.edu.cn` → `172.20.13.4`）：
    真机验收必须在**校园网 / VPN** 下做，普通外网（含手机热点）不可达（4.2）
  - **`WebViewLoginPage` 对登录 URL 的 host 放行 SSL 证书错误，其他域名仍拒绝**（4.2.1）：
    教务系统常用自签 / 不受信证书 —— 浏览器会提示"继续访问"，**WebView 默认直接拒绝**
    （真机表现就是 `-1` 加载失败，容易被误判成"网络不可达"）。
    放行判定是纯函数 `sslErrorHostToProceedOn`：精确同 host 或其**子域**才放行
    （`xjw1.ncst.edu.cn.evil.com` 这类**前缀伪装不匹配**），解析不出 host 一律**拒绝**（fail closed）。
    ⚠️ **写别的 WebView 页面时不要照抄成全局放行** —— 那等于静默接受任何第三方域名的坏证书
  - **webview_flutter 4.14.1 没有 `onReceivedSslError` / `SslError`**（那是 4.15+ 的 API）：
    4.14.1 的等价回调是 **`NavigationDelegate.onSslAuthError`**，参数是 `SslAuthError`
    （只有 `certificate` / `cancel()` / `proceed()`，描述文案在 `error.platform.description`，
    **不含 URL**，要用 `controller.currentUrl()` 代替）；它由 `webview_flutter` 直接导出
    → **不需要把 `webview_flutter_android` 提为直接依赖**，也不用改平台判断（4.2.1）
  - **`network_security_config.xml` 是"平台配置白名单"，加学校要重新发版**（4.2.2）：
    `base-config` 保持 `cleartextTrafficPermitted="false"`，只给用 http 的域名开
    `domain-config`（NCST 是 `xjw1.ncst.edu.cn`，`includeSubdomains="true"`）。
    ⚠️ **绝不用 `android:usesCleartextTraffic="true"`**（全局放行 = 对所有域名降级）。
    它是**系统级配置**，插件无法在运行时改 → 每新增一个 http 学校都要改文件并重发版；
    其域名白名单属于**平台安全策略**、不算"内核硬编码学校 URL"（CONTEXT 3.1 已加例外说明，v1.5）
  - **明文白名单的生效范围要分清**（4.2.2）：`network_security_config.xml` 的
    `domain-config` **已确认**约束 **WebView**（4.1 真机就是 WebView 报的
    `ERR_CLEARTEXT_NOT_PERMITTED`）；但它对 **`ctx.http`（dio → Dart 侧 socket）**
    是否生效**尚无证据**（4.1 dio 打通 `http://` 本机服务那次用的是 debug 的**全局**
    `usesCleartextTraffic`，不能外推）。
    ⚠️ 复验点：同步报 `{error:'connection'}` 而浏览器能通 → 即此问题，按证据再决策，
    **不要预先加全局 `usesCleartextTraffic="true"`**
  - **`saveCourse` 入参不带覆盖层 ≠ 要删除覆盖层**（4.3 修的真实 bug）：
    覆盖层来源优先级 = 入参自带 > 内存里那条已有 > Box 里存的；
    插件重同步每次传的都是无覆盖层的原始课程，所以这条路径必然被踩到
  - **同步只在"原始字段真的变了"时才落盘**（4.3）：字段指纹**不含 `userOverride`**，
    且 `weeks` 要归一成"去重 + 升序"，否则会把同一份数据误判成"变了"而反复写盘
  - **重试只针对网络类失败**（4.3）：`timeout` / `connection` / `bad_response`，
    或插件显式声明 `retryable: true`。**凭证过期 / 结构异常 / 超时 / 插件不可用都不重试**
  - **`ctx.http` 真失败时是 `throw`**，那一刻插件自己的 `retryable: true` 拿不回来；
    靠宿主 `JsSandboxResult.httpErrors` 兜底（两条路都通，不是二选一）
  - **`JsSandbox.execute()` 不填 `httpErrors`**（沙箱层不认识 HTTP），
    只有经 `PluginContext.execute` 的路径才有值
  - **`sync_report.dart` 的 0 门课是 `success` 不是失败**：这学期确实没选课是合法结果；
    插件坚持"宁可报错也不静默返回空数组"，两侧配合才不会误报
  - **禁止用 PowerShell 的 Get-Content/Set-Content 做文本往返**（会按控制台代码页解码，中文变乱码，见阻塞表）
  - **docs/PROGRESS.md 曾因编码问题损坏**，见阻塞表（编辑该文件时务必确认保存为 UTF-8）
  - **分析器能证明"必定有值"的地方不要写多余判空**（4.3 被 `unnecessary_null_comparison` 抓过）：
    想让"每条路径都赋值"这个不变量显式化，用 `late final X v;` 而不是
    可空类型 + 事后 `if (v == null) return;`
  - **`dart analyze` 有一条 info 也算失败**（4.3 实测：exit code 1）：
    看到"只有 1 条 info"别当成"基本通过"，要当成必须修掉的问题

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

## Phase 3：插件运行时 ✅（收官）

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

> **Phase 3.3**（多插件管理 PluginManager + PluginProvider 接线）：`dart analyze lib` 通过，**未新增依赖**。
> 只动 `lib/runtime/`、`lib/providers/plugin_provider.dart`、`lib/main.dart` 与 `docs/`。
>
> 改动：
> - 新建 `lib/runtime/plugin_manager.dart`：`PluginManager`（**不继承 ChangeNotifier**，无状态服务）
>   - `load(meta, {jsSource})` / `unload(id)` / `getHandle(id)` / `isLoaded(id)` /
>     `loadedHandles` / `loadedCount` / `handleCount` / `allLoadedCapabilities` /
>     `loadErrors` / `disposeAll()`
>   - 新增可注入的 `PluginSourceResolver`（typedef）+ `defaultSourceResolver`：
>     默认用 `PluginMeta.assetPath` 作为文件路径；解析器可注入，**测试就能绕过文件系统直接给 `jsSource`**，
>     且 Phase 3.4 接入 `path_provider` 时只换解析器、本类不用改
> - 改造 `lib/providers/plugin_provider.dart`：
>   - 持有 `PluginManager`（可注入，沿用 `ThemeProvider({ThemeEngine?})` 先例）
>   - **新增持久化**：插件列表存 `plugins` Box，一 id 一 key（`loadFromStorage` /
>     `saveToStorage` / `clearAll`）
>   - 新增 `loadAllEnabledPlugins()` / `loadPlugin(id, {jsSource})` / `unloadPlugin(id)` /
>     `loadedCapabilities` / `loadedHandles` / `loadedCount` / `loadErrors` / `loadErrorOf(id)` /
>     `getHandle(id)` / `isLoaded`
>   - `togglePlugin` 改为异步：改内存 + **立即通知** → 落盘 `enabled` → 加载/卸载运行时 → 再通知
>   - `addPlugin` / `removePlugin` 由 `void` 改为 `Future<void>`（**原签名在 lib/ 里没有调用方**，无破坏性）
> - 改造 `lib/main.dart`：`PluginProvider` 从"树内 create"改为 main() 里建实例并
>   `loadFromStorage()` + `loadAllEnabledPlugins()` 后经 `.value` 传入（`buildApp` 新增可选参数）
>
> **我的决定：不给 `PluginMeta` 加 `lastError` 字段**。理由：
> ① `PluginMeta` 是**持久化模型**，CONTEXT 4.2.1 规定 schema 已冻结，加字段要写迁移；
> ② "加载失败原因"是**运行时瞬时状态**，不是领域数据，持久化它会在重启后显示**过期错误**；
> ③ 放 `PluginProvider.loadErrors`（内存 `Map<id, String>`）即可满足 UI 展示需求，零 schema 成本。
>
> **三个设计取舍**：
> 1. **`load()` 只在"已加载且可用"时跳过**；既有 handle 若是**降级**的（上次失败），
>    会先 dispose 再重试——降级不算"已加载"，否则用户永远没机会重试。
> 2. **`allLoadedCapabilities` 只统计沙箱可用的插件**，且同时取
>    `handle.manifest.capabilities` 与 `meta.effectiveCapabilities`（含 `modules` 的 capabilityId）两处来源，
>    避免漏掉任一种声明方式。加载失败的插件**不会**让模块变可用。
> 3. **加载成功后用插件自报能力补齐 meta 取并集、不替换**：`PluginMeta.modules` 里的
>    `capabilityId` 不在 `PluginManifest.capabilities` 里，替换会丢能力；且只在真的变化时才写盘。
>
> **验证**：临时 `flutter test` 脚本 **29 组全部通过**（真实 Hive + 临时目录），脚本已删除。覆盖：
> 空 Provider 启动不报错、2 个插件加载后 `loadedHandles` 有 2 个且入口函数可调用、
> `allLoadedCapabilities` 去重（A 声明 exam，B 声明 homework+exam → `{exam, homework}`）、
> 未启用插件不加载、**默认解析器走真实 `assetPath` 文件（生产路径）**、
> `assetPath` 为空且无 `jsSource` 时降级且原因明确、
> **禁用→handle 卸载→重新启用→重新加载**、toggle 落盘 enabled 且重建 Provider 后保留、
> **加载失败时 enabled 仍落盘 true**、toggle 找不到 id / 同值为空操作、
> **坏 JS 不影响其他插件加载**且其能力不计入已加载能力、失败插件可重试、
> `loadPlugin` 找不到 id 返回降级 handle、加载成功用自报能力补齐 meta（并集）、
> `disposeAll` 后 `loadedHandles` 为空、`removePlugin` 销毁运行时并删存储、
> 内置插件不可卸载、`unloadPlugin` 不改 enabled、`clearAll` 清内存与存储、
> `disposeAll` 后再 load 降级不抛异常、已加载可用时 load 跳过（返回同一实例）、
> 失败后再次 load 会重试、`loadedHandles`/`loadErrors` 是不可变视图、
> 插件自报 id 与安装 id 不一致仍按安装 id 管理、`unload` 不存在的 id 为空操作、
> 存储容错（坏 JSON / 非对象 / 缺 id / 空串被跳过、存储未初始化不崩）、
> `PluginMeta` 往返存储保持一致。
>
> **真机验证**（Redmi K60；`adb shell getprop ro.product.model` 原始输出 = `2211133C`）：
> 本次未要求真机验证，但因改动了 `lib/main.dart`（App 入口）做了一次**启动冒烟**：
> `flutter run -d aacfd78e` 正常启动、无崩溃、无插件相关报错
> （设备上没有已安装插件，`loadAllEnabledPlugins()` 遍历为空）。
> 仅有的 `Skipped 116 frames!` 是 debug 模式 + Impeller 首帧编译的既有现象（3.1 已确认）。
>
> **测试注意**：JS 相关测试需 `quickjs_c_bridge.dll`（见 `docs/ENV.md`），已拷到项目根目录、跑完已删。

> **Phase 3.4**（插件文件持久化 PluginStorageService + path_provider）：`dart analyze lib` 通过。
> **只加了 `path_provider` 一个依赖**（2.1.6；它原本就是 `hive_flutter` 的传递依赖，本次提升为直接依赖）。
> 未接 UI（插件管理页仍是占位）。
>
> 改动：
> - `docs/CONTEXT.md`：技术栈表加 `| 路径获取 | path_provider | ^2.1.4 |`；
>   3.5 存储分离表加"插件文件 → `<appDocuments>/plugins/`"；版本记录加 v1.2；头部版本号改 v1.2
> - `pubspec.yaml`：加 `path_provider: ^2.1.4`
> - 新建 `lib/services/plugin_storage_service.dart`：`PluginStorageService`（纯静态）
>   - 常量 `kPluginsSubdirName`('plugins') / `kPluginJsSuffix`('.js') /
>     `kPluginIdPattern` / `kMaxPluginIdLength`(64)
>   - `getPluginsDir` / `installPlugin` / `uninstallPlugin` / `isInstalled` /
>     `listInstalled` / `getPluginJsPath` / `getPluginManifestPath` / `clearAll` /
>     `isValidPluginId` / `setRootDirForTesting`
> - 改 `lib/runtime/plugin_manager.dart`：`PluginSourceResolver` **改为异步**
>   （`Future<PluginSource> Function(PluginMeta)`）；`defaultSourceResolver`
>   改为从安装目录取 `<id>.js`（不再读 `meta.assetPath`）；解析器调用包 try-catch；
>   降级原因改为"插件未安装（在插件目录中找不到 .js 文件），或插件 id 非法"
> - 改 `lib/models/plugin_meta.dart`：**收窄 `assetPath` 的文档语义**（见下），**代码零改动**
> - `lib/main.dart`：**未改动**（懒加载已足够，理由见下）
>
> **三个需要判断的点，我的决定与理由**：
>
> 1. **`PluginSourceResolver` 改为异步**（而非"保持同步 + 预热全局缓存"）：
>    解析默认要查"文件在不在"，本身就是异步 I/O。同步签名只能靠"必须先预热缓存、
>    否则静默返回 null"来伪装，那是个容易踩的坑（忘了预热 = "插件莫名不可用"，
>    而且失败是静默的）。`PluginManager.load()` 本来就是 `async`，await 解析器零额外成本。
>
> 2. **`PluginMeta.assetPath`：保留键名、不改名、不新增 `installedPath`**。理由：
>    - 安装路径是 **`pluginId` 的纯函数**（`<pluginsDir>/<id>.js`），**不需要持久化**；
>    - 持久化绝对路径反而**会过期**：iOS 应用容器 UUID 每次 App 更新都变，
>      Android 虽稳定但没必要冒这个险。存了就是引入一个 bug。
>    - CONTEXT 4.2.1 规定序列化键名已冻结，改名要写迁移；**收窄语义（只改注释）零迁移成本**。
>    - `assetPath` 的新语义：**打包内置插件**的 asset 路径（相对 `assets/` 根）。
>      那类插件要用 `rootBundle` 读，与文件系统路径是**两种加载方式**，因此保留该字段是合理的，
>      不是"留了个没用的字段"。
>
> 3. **`PluginStorageService` 懒加载，`main.dart` 不改**：首次调用才向 path_provider
>    要目录并缓存。好处是 **path_provider 不可用时只影响插件功能，不影响 App 启动**
>    （与 `StorageService.init()` 失败不崩的原则一致）。预热只会把失败提前到启动路径上，
>    没有实际收益。
>
> **路径安全（重点）**：插件 id 会被直接拼进文件名，因此 `isValidPluginId` 只允许
> **字母、数字、下划线、横线**（`^[A-Za-z0-9_-]+$`，长度 1–64）。**点号也在禁止之列**
> ——`..` 正是路径穿越的核心。约定：**查询类方法**（`isInstalled` / `getPluginJsPath` /
> `getPluginManifestPath`）对非法 id 返回"找不到"（`false` / `null`）；
> **命令类方法**（`installPlugin` / `uninstallPlugin`）抛 `ArgumentError`——非法 id 是
> 调用方的编程错误，不该静默成功。
>
> **两个额外的稳健性设计**：
> - **原子写**：`installPlugin` 先写 `<name>.js.tmp` 再 rename 覆盖，避免写到一半被中断时
>   留下半个文件、把原本能用的插件覆盖成坏文件。
> - **重复安装整体覆盖**：`manifestJson` 为 `null` 时**主动删掉旧的 `.manifest.json`**，
>   否则加载器会读到上次的过期声明。
>
> **验证**：临时 `flutter test` 脚本 **23 组全部通过**，脚本已删除。覆盖：
> 合法 id 接受（含 64 字符边界）、非法 id 拒绝（`../evil` / `..` / `.` / `a/b` / `a\b` /
> `a.b` / `a b` / `a;b` / 空串 / 超长）、**installPlugin 对非法 id 抛 ArgumentError 且不落盘**
> （并确认根目录外没有写出文件）、uninstallPlugin 对非法 id 抛、查询类方法对非法 id 返回
> false/null、install 后 `listInstalled`/`isInstalled` 正确且路径含 `<root>/plugins/`、
> **`getPluginJsPath` 内容 == 传入的 jsSource**、重复安装覆盖、**重复安装无 manifest 时删掉旧 manifest**、
> 带 manifest 安装可读回且 manifest 不计入 `listInstalled`、卸载后文件消失、
> 卸载未安装的是幂等、多插件安装不冲突且 `listInstalled` 升序、
> `clearAll` 后目录为空、**无 `.tmp` 残留**、`getPluginsDir` 缓存、
> `defaultSourceResolver` 已安装→有路径 / 未安装→null、非法 id→返回 null 不抛、
> **解析器不读 `meta.assetPath`**（故意给错路径仍指向真实安装位置）、
> 未安装时 `load` 降级且原因含"未安装"、
> **端到端：installPlugin → 默认解析 → 沙箱执行成功**、
> 覆盖安装后重新加载拿到新版本行为、卸载文件后 load 降级为"未安装"。
>
> **真机验证（✅ 已完成）**：Redmi K60（`adb shell getprop ro.product.model` 原始输出 = `2211133C`，
> Android 16 / arm64-v8a）。**实际插件目录正是预期路径**：
> ```
> [STORAGE-VERIFY] 插件目录: /data/user/0/com.example.my_schedule_app/app_flutter/plugins
> [STORAGE-VERIFY] 目录已创建: true
> [STORAGE-VERIFY] 安装路径: /data/user/0/com.example.my_schedule_app/app_flutter/plugins/verify-storage.js
> [STORAGE-VERIFY] isInstalled=true listInstalled=[verify-storage]
> [PluginRuntime] 插件加载成功：verify-storage，入口函数 [run]
> [STORAGE-VERIFY] 加载: isUsable=true entries=[run] sourcePath=.../app_flutter/plugins/verify-storage.js
> [STORAGE-VERIFY] 执行: status=success value={"ok":true,"from":"device"}
> [STORAGE-VERIFY] 路径安全: 已拒绝非法 id（pluginId）
> [STORAGE-VERIFY] 非法 id 查询: isInstalled=false getPluginJsPath=null
> [STORAGE-VERIFY] 卸载后: isInstalled=false listInstalled=[]
> ```
> 并用 `adb shell run-as com.example.my_schedule_app ls -la app_flutter/plugins` **独立确认**
> 该目录真实存在于设备上（验证代码已卸载插件，故目录为空）。
> 过程中手机曾掉线一段时间，`adb reconnect offline` + 轮询重试后恢复。
>
> **桌面端交叉印证**：同一份验证代码在 Windows 桌面端也跑通
> （`C:\Users\adm\Documents\plugins`，`path_provider` 在桌面同样可用，代码路径完全一致），
> 说明实现不依赖 Android 特性；桌面验证遗留的空目录已删除。
>
> **测试注意**：JS 相关测试需 `quickjs_c_bridge.dll`（见 `docs/ENV.md`），已拷到项目根目录、跑完已删。
> 文件存储测试用 `PluginStorageService.setRootDirForTesting(临时目录)` 绕过 path_provider 平台通道。

> **Phase 3.5**（插件管理 UI 接入）—— **Phase 3 收官**：`dart analyze lib` 通过，**未引入新依赖**。
>
> 改动：
> - 重写 `lib/pages/settings/plugin_manage_page.dart`：空态占位 → 真实列表
>   - 卡片：能力图标 + 插件名 + `版本 x.x.x · 作者` + 能力标签 + 启停 `Switch` + 状态徽章
>   - 状态徽章四态抽成**公开枚举 + 纯函数**（`PluginUiStatus` / `pluginUiStatusOf` /
>     `pluginUiStatusColor` / `pluginUiStatusLabel`），便于单独测试
>   - `+` 改为 `PopupMenuButton`：从文件导入（占位）/ 安装示例插件
> - 新建 `lib/pages/settings/plugin_detail_page.dart`：基本信息 / 运行时 / 操作三个分区卡片
> - 新建 `assets/plugins/example.js` + `pubspec.yaml` 声明 `assets/plugins/`
> - `PluginStorageService` 新增 `installFromAssets`（`rootBundle` 读 → 落盘）
> - `PluginProvider` 新增 `installExamplePluginForDemo()` + 两个常量
> - **`AppTheme` 新增 `success` / `warning` 两个状态色令牌（28 → 30 字段）**，见下
> - `settings_page.dart` 的入口**无需改动**（已指向 `PluginManagePage`）；`main.dart` 也无需改动
>   （3.3 已接好 `loadAllEnabledPlugins`）
>
> **为什么动 AppTheme（超出任务清单，但必要）**：任务要求徽章"加载成功绿色、已启用未加载黄色"，
> 而原主题**没有绿/黄令牌**；CONTEXT 3.2 又明确**禁止 UI 硬编码颜色**。
> 两条约束只有一条出路：把状态色补进主题。故新增
> `success = #43A047`（绿）、`warning = #F9A825`（黄），并同步
> `default_theme.dart` / `fromJson` / `toJson` / `merge` / `toString`。
> `AppTheme` 是启动时构造、**不落盘**，故无迁移成本；皮肤仍可覆盖这两个令牌。
>
> **状态徽章四态判定**（`pluginUiStatusOf`）优先级：**失败 > 已加载 > 已启用未加载 > 已停用**。
> 失败优先于成功，因为"失败原因"对用户最有价值；tooltip / 无障碍文案会带上 `loadErrors` 的原因。
> 徽章 Key 为 `ValueKey('plugin-status-<id>')`，便于测试定位。
>
> **示例插件的生命周期**：`assets/plugins/example.js` 与 `PluginProvider.installExamplePluginForDemo()`
> 都是**临时**的——只为让插件管理页在没有任何真实插件时也能看到"已安装 → 已启用 → 沙箱就绪"的完整效果。
> **Phase 4 做出真实教务插件后一并删除**（已在该文件、方法注释与 API.md 三处标注）。
>
> **验证**：临时 `flutter test` 脚本 **22 组全部通过**，脚本已删除。覆盖：
> 四态判定优先级与四态颜色（含"成功色确实偏绿、警告色确实偏黄橙"的通道断言）、状态文案、
> 空列表显示 EmptyState、有插件显示卡片（名称/`版本 2.1.0 · zys`/能力中文化/两个 Switch）、
> **空列表 → 有插件自动切换**（watch 生效）、开关切换调用 `togglePlugin` 且 enabled 翻转、
> 加载失败时徽章为失败态、点卡片进详情页、`+` 弹出两个菜单项、选"从文件导入"弹 SnackBar、
> 详情页显示元信息（ID/版本/作者/描述/`exam · homework`/三个分区标题/三个占位操作）、
> 插件不存在时的兜底文案、未安装时安装路径显示"未安装"、内置插件不显示卸载按钮、
> **卸载确认框取消则不删除**、**确认后移除并退回列表（回到空态）**、详情页开关也能切换、
> `installExamplePluginForDemo` 后 `plugins` 长度 +1 且已启用且文件已落盘且 `entries=[fetchExams]`、
> 重复安装不产生第二条记录、
> **真实加载后徽章渲染为 `theme.success`（绿）**（用 `runAsync` 跑真实安装 + 真实 JS 沙箱，
> 再断言徽章 `Container` 的实际 `BoxDecoration.color`）。
>
> **真机验证**（Redmi K60；`adb shell getprop ro.product.model` 原始输出 = `2211133C`，Android 16 / arm64-v8a）：
> 为做**可视化**验证，临时把 `app.dart` 的 `home` 改成 `PluginManagePage`、
> 并在 `main.dart` 里装一次示例插件（两处**已用 `git checkout HEAD --` 还原，git diff 为空**）。
> 日志：
> ```
> [PluginRuntime] 插件加载成功：example-plugin，入口函数 [fetchExams]
> [PluginProvider] 示例插件已安装并启用：example-plugin
> [UI-VERIFY] 安装示例插件 ok=true plugins=1
> [UI-VERIFY] enabled=true capabilities=[exam]
> [UI-VERIFY] handle.isUsable=true entries=[fetchExams] reason=null
> [UI-VERIFY] loadErrors={} loadedCapabilities=[exam]
> [UI-VERIFY] 徽章状态=loaded
> ```
> 另用 `adb shell screencap` 抓屏后**逐像素扫描**（`System.Drawing`）独立佐证徽章真的画在屏幕上：
> **成功绿 `#43A047`（容差 12）命中 558 像素，包围盒 (745,345)-(771,371) = 27×27 像素**
> ——正是 10 逻辑像素圆点在 3x 密度下的尺寸与位置（卡片标题行右侧）；
> **失败红 `#E53935` 命中 0 像素**（与"加载成功"一致）。
> 截图留在 `build/ui_verify.png` 供人工查看（在 `build/` 下，`flutter clean` 会清掉）。
>
> **测试注意（新增两条）**：
> ① `_InstallPathRow` 的 `getPluginJsPath` 是**真实文件 I/O**，`testWidgets` 的 fake-async
> **不会推进它**（会永远停在"读取中…"），相关断言必须放 `tester.runAsync(...)`；
> 真实安装 + 真实沙箱同理。
> ② widget 测试**不初始化 Hive**，让落盘走 `StateError` 分支被 try-catch 兜住，
> 从而避开"fake-async 下 Hive 写永不完成"的坑。

> **Phase 3.5.1**（修正：示例插件无法卸载）：`dart analyze lib` 通过，**未加新依赖**。
>
> **问题**：真机验收发现示例插件卸不掉。根因是 **Phase 3.5 把"来源"当成了"策略"**：
> 示例插件从 assets 安装，`source` 标为 `'builtin'`，而 `removePlugin` 与详情页都用
> `isBuiltIn`（即 `source == 'builtin'`）判定"不可卸载" → 用户在详情页看不到卸载入口。
>
> **决策：方案 A —— 新增独立的策略字段 `PluginMeta.isRemovable`（默认 `true`）。** 理由：
> 1. 这是**建模错误**，不是"多了一个判断"：`source`（来源）回答"插件从哪来"，
>    `isRemovable`（策略）回答"能不能卸"。示例插件来源**确实是** builtin（随 App 打包），
>    所以 `source` 并没有标错——错的是从它反推卸载策略。
> 2. 你的要求里明确保留了保护："**只有**硬编码的系统级插件才该禁止卸载"。
>    方案 B（去掉判定、全部可卸）会把这个保护一起删掉，将来还得加回来。
> 3. 向后兼容：缺键回落 `true`，所以**设备上 3.5 装的那个示例插件不用重装**就能卸了
>    （真机已验证，见下）。
>
> 改动：
> - `lib/models/plugin_meta.dart`：新增 `isRemovable`（字段 / 构造 / `fromJson` / `toJson` /
>   `copyWith` / `toString`）；`_asBool` 增加 `fallback` 参数（默认 `false`，
>   `isRemovable` 传 `true`）；**收窄 `isBuiltIn` 的文档语义**为"来源"
> - `lib/pages/settings/plugin_detail_page.dart`：卸载按钮显示条件
>   `!meta.isBuiltIn` → **`meta.isRemovable`**；确认框文案改为
>   "确定要卸载插件「X」吗？这会删除插件文件与本地数据。"
> - `lib/providers/plugin_provider.dart`：`removePlugin` 保护条件改为 `!isRemovable`；
>   示例插件构造时**显式**写 `isRemovable: true`
> - `docs/CONTEXT.md`：4.2.1 补充"**纯新增**字段无需迁移"的例外说明，版本 **v1.2 → v1.3**
>
> **顺带修掉一个真 bug（测试发现的）**：`removePlugin` 此前**只删元数据，不删磁盘文件**，
> 而确认框早已声称"插件文件与运行时都会被移除"——**文案与实现不符**。
> 现已补上 `PluginStorageService.uninstallPlugin(id)` 删除 `<id>.js` / `<id>.manifest.json`
> （失败只记日志不抛）。同时把 `notifyListeners()` 提到异步收尾**之前**，
> 让 UI 立刻反映列表变化（与 `togglePlugin` 同一思路）。
>
> **schema 兼容**：`isRemovable` 是**纯新增**键（不改名、不改已有字段语义、缺键有默认值），
> 按 CONTEXT 4.2.1 的新补充**不需要迁移**。真机上用 3.5 落盘的旧数据验证：
> `source=builtin isBuiltIn=true isRemovable=true` —— 旧数据读出来就是可卸载的。
>
> **验证**：临时 `flutter test` 脚本 **15 组全部通过**，脚本已删除。覆盖：
> `isRemovable` 默认 `true`、**旧数据缺键回落 `true`**（且 `isBuiltIn` 仍为 `true`）、
> 显式 `false` 能读回、宽松写法与坏值（`false`/`"false"`/`"0"`/`0` → 不可卸载；
> `'maybe'`/数组/`null` → 回落 `true`）、`toJson`/`fromJson` 往返、
> `copyWith` 保留与可改、`toString` 含该字段、
> 详情页 `isRemovable==true` 显示卸载按钮 / `false` 不显示 /
> **来源 builtin 但 `isRemovable==true` 仍显示**（本次修正核心）、确认框新文案、
> `removePlugin` 对 `false` 不做任何事 / 对 `true` 正常移除 /
> **builtin 但可卸载的能移除**、
> 示例插件安装后 `isRemovable==true` 且卸载后**文件真的被删除**（`listInstalled` 为空）、
> **完整 UI 链路**：详情页点卸载 → 弹确认框 → 点"卸载" → 插件从列表消失且磁盘文件被删、
> 真实 Hive 往返（`isRemovable` 落盘读回；手写不含该键的旧 JSON 读回为 `true`）。
>
> **真机验证（✅ 全部通过）**：Redmi K60（`adb shell getprop ro.product.model` 原始输出 =
> `2211133C`，Android 16 / arm64-v8a）。设备上正好留着 **3.5 装的那个示例插件**
> （Hive 里**没有** `isRemovable` 键、磁盘上有 `example-plugin.js` 837 字节），
> 是天然的向后兼容样本。
>
> 1. **旧数据兼容**：`[REMOVABLE-VERIFY] id=example-plugin source=builtin
>    isBuiltIn=true isRemovable=true enabled=true` —— 旧数据读出来可卸载 ✅
> 2. **卸载按钮存在且可点**：把 `home` 临时设为详情页，点 AppBar 右上角 (1008,174) 后
>    **整屏平均亮度 248.0 → 134.7**（对话框 scrim 遮罩），且截图**新增 5 个偏蓝文字簇**
>    位于 y≈1395 的 x 580-653 与 x 778-852（即"取消"/"卸载"两个文字按钮）✅
> 3. **点卸载 → 确认 → 插件消失**：点 (815,1395)（右侧那个 = 卸载）后
>    `adb shell run-as ... ls app_flutter/plugins` **目录变空**，`example-plugin.js` 已删除 ✅
> 4. 卸载后 **app 进程仍存活**（pid 7010），logcat 无 FATAL/异常 ✅
>
> 说明：验证时把 `home` 临时设为详情页（该临时改动**已用 `git checkout HEAD --` 还原，
> `git diff` 为空**），因此确认卸载后 `Navigator.pop()` 弹掉了最后一个路由、
> 屏幕变黑（亮度 0.4）——这是临时脚手架的副作用，真实路径下会退回插件列表。
> 另外我当前模型**不能读图**，所以截图验证是靠像素分析（亮度差 / 偏蓝文字簇定位）完成的，
> 反而比目视更客观。

> **Phase 3.6**（PluginContext）：`dart analyze lib` 通过，**未加新依赖**。
>
> ⚠️ **任务书里的 `ctx.http` 设计在当前架构下不可能实现，我改用了"重放式同步外观"**
> （你已在决策点确认选方案 B）。三条硬证据：
>
> 1. **沙箱在独立 isolate**（3.2a 的设计），`onMessage` 的 Dart 回调是**子 isolate 里的闭包**，
>    而 dio / Hive / secure_storage 都在主 isolate——**闭包跨不了 isolate**。
>    所以"Dart 暴露 `__dart_http_get`"这条路本身就断了。
> 2. 就算能跨，`sendMessage` 通道要求 Dart 侧**同步**返回，而 dio 是异步的；
>    JS 又**无法挂起**（本库唯一的异步路径 `fetch`/Promise 走 `callFunction`，
>    而 QuickJS 后端该方法是 `UnimplementedError`，3.2a 实测）。
> 3. 唯一可用的**同步** HTTP 客户端 `sync_http`（flutter_js 的传递依赖）用
>    `RawSynchronousSocket`——**纯 TCP，import 列表里没有 `SecureSocket`**，
>    **不能 HTTPS**。教务系统全是 HTTPS，等于没用；而且直接用要改 pubspec（违反"不加新依赖"）。
>
> **方案 B 的做法**（`plugin_ctx_script.dart` 顶部有完整说明）：
> ctx **全部用 JS 实现**，宿主每轮注入"本轮状态"（HTTP 响应缓存 / storage 快照 / cookie）为 JS 全局；
> `ctx.http.get` 命中缓存就同步返回，未命中只把请求 `push` 进待办并返回
> `{ok:false,error:'pending'}`（**绝不发网络**）；宿主读回待办后用 **dio**（真超时）取回、
> 并入缓存、**重放**插件函数；没有待办的那一轮就是最终轮，只提交**最终轮**的
> storage / log / notify 副作用。
> 好处：插件写的是自然同步代码（就是任务书想要的样子），而网络仍由 dio 发（可超时、可审计），
> 且**不需要给 js_sandbox 加任何协议**。
>
> **改动**：
> - 新建 `lib/runtime/plugin_ctx_script.dart`：`kPluginCtxScript`（JS 侧 `ctx` + primitive）、
>   `buildCtxStateScript(...)`（本轮状态）、`kCtxDumpScript`（读回副作用）
> - 新建 `lib/runtime/plugin_context.dart`：`PluginContext`（宿主侧五类能力 + 重放循环）+
>   `PluginHttpRequest`
> - `lib/runtime/plugin_runtime.dart`：构造加 `Dio? dio`；`loadPlugin` 在求值插件源码**之前**
>   先注入 `kPluginCtxScript`；加载成功后创建 `PluginContext` 挂到 handle
> - `lib/runtime/plugin_handle.dart`：新增私有 `_context`，`execute` 有 context 时走重放
> - `lib/services/storage_service.dart`：**新增 `plugin_data` Box（8 → 9 个）**，
>   key 格式 `<pluginId>:<userKey>`
> - `assets/plugins/example.js`：新增 `testCtx` / `testHttp` 两个入口用于验证
> - `android/app/src/main/AndroidManifest.xml`：**补 INTERNET 权限**（见下）
>
> **顺带发现并修掉一个真 bug（会影响 Phase 4 与发布）**：
> Flutter 模板只在 `src/debug` 与 `src/profile` 的 manifest 里声明了 `INTERNET`
> （那是给 hot reload 用的），**`src/main` 里没有**——也就是说 **release APK 默认没有网络权限**，
> 插件的 `ctx.http` 在正式包里会直接失败。已在 `src/main/AndroidManifest.xml` 补上。
>
> **7 个设计决策**：
> 1. **ctx 是全局变量**（不是参数传入）：每个插件独占沙箱，全局不会冲突；
>    而且参数传入会破坏现有 `function(args)` 签名与 `buildPluginEntryCallScript`。
> 2. **HTTP 在 Dart 侧代理**：沙箱内**完全没有网络能力**，JS 只能"登记待办"。
> 3. **storage 用一个 Box + `<pluginId>:<userKey>` 前缀隔离**：不用"每插件一个 Box"，
>    因为 `StorageService` 是固定 Box 列表、动态开 Box 会打乱它；而插件 id 只允许
>    `[A-Za-z0-9_-]`（3.4 的路径安全校验），所以 `:` 作分隔符不会歧义。
> 4. **HTTP 超时**：dio `connectTimeout 10s` / `receiveTimeout 15s` / `sendTimeout 10s`，
>    并映射成 `error:'timeout'` 返回（不是抛异常）——**这条任务书要的 dio 超时做到了**。
> 5. **错误返回格式**：统一 `{ok:true,status,body,headers}` / `{ok:false,error}`；
>    **任何状态码都算拿到响应**（4xx/5xx 正文对插件有用），由插件判断 `status`。
> 6. **cookie 从 `flutter_secure_storage` 读 `<pluginId>:cookie`**，不存在/失败返回空串；
>    本阶段只读不写（Phase 4 由 WebView 登录写入）。
> 7. **notify 只 debugPrint**，但签名保持最终形态 `schedule(title, body, triggerAtIso)`。
>
> **验证**：临时 `flutter test` 脚本 **26 组全部通过**，脚本已删除。覆盖：
> `ctx.log.info/error` → debugPrint、**重放时只输出最终轮日志**（不刷屏）、
> `storage` set→get 同轮可见且未设置键返回空串、**set 真的落到 Hive**（key 格式正确）、
> `remove` 真的删键、**两个插件 storage 命名空间隔离**、storage 跨执行持久化、
> 值被转成字符串、
> `ctx.http.get` 成功（本机 loopback 服务，ok/status/body 正确）、`post` 带 body 原样送达、
> `post` 传对象自动 JSON 序列化、**4xx/5xx 也算拿到响应**、
> **多个不同请求都被取回且去重**（服务端只收到 2 次）、
> **超时 → `error:'timeout'` 且确认超时配置真的传给了 dio**、连接失败 → `error:'connection'`、
> 真失败时 `ctx.http.get` 抛错（插件可 try/catch 接住）、
> **插件 try/catch 吞掉中间轮也不影响重放正确性**、不碰 http 时只跑一轮、
> `ctx.cookie` 未设置返回空串且是字符串、`ctx.notify.schedule` 只记日志不崩、
> **沙箱被 kill 后 ctx 调用降级为 unavailable**、ctx 抛错不影响沙箱存活、
> 无 Hive 时 storage 读写不崩、example.js 的 `testCtx` / `testHttp` 端到端、
> `PluginHttpRequest.tryParse` 容错。
>
> **测试踩到的两个坑（已写进关键约束）**：
> ① `TestWidgetsFlutterBinding` 会安装 `HttpOverrides` 把**所有 HTTP mock 成 400**——
> 一开始 6 个 HTTP 用例全挂在"status 400"，排查后加 `HttpOverrides.global = null` 解决；
> ② 同一轮内对同一 URL 重复请求会被登记两次（缓存只在轮与轮之间填充），
> 已改为**同时对"待办列表"去重**。
>
> **真机验证（✅ 通过）**：Redmi K60（`getprop ro.product.model` = `2211133C`，
> Android 16 / arm64-v8a）：
> ```
> [CTX-VERIFY] 插件: id=example-plugin isUsable=true entries=[fetchExams, testCtx, testHttp]
> [Plugin:example-plugin] 测试 ctx.log：插件 example-plugin 开始
> [Plugin:example-plugin][notify] 计划提醒「测试提醒」（2026-09-25T08:00:00Z）：来自示例插件 —— Phase 7 接真实通知
> [CTX-VERIFY] testCtx: status=success value={"counter":"42","missingIsEmpty":true,"cookie":"","cookieIsString":true}
> [Plugin:example-plugin] 第 1 轮登记了 1 个 HTTP 请求，取回后重放
> [CTX-VERIFY] testHttp(https://example.com/): status=success value={"ok":true,"status":200,"bodyLen":559}
> [CTX-VERIFY] Hive example-plugin:counter = 42
> ```
> 这一次**真的发了 HTTPS**（`https://example.com/`，200 / 559 字节），
> 一次性验证了：Android 网络权限、TLS、dio、以及**重放链路**（日志里那句"取回后重放"）；
> `ctx.storage` 也确实落到了 Hive。**这是 Phase 4 能跑通的前置条件。**
>
> **测试注意**：JS 相关用例需 `quickjs_c_bridge.dll`（见 `docs/ENV.md`），已拷到项目根目录、跑完已删。

- [x] flutter_js 集成（Phase 3.1，仅验证可用性）- [x] JS 运行时沙箱与兜底（Phase 3.2a，`lib/runtime/js_sandbox.dart`）
- [x] 插件文件加载 + PluginRuntime 骨架（Phase 3.2b.1：`plugin_manifest.dart` /
      `plugin_handle.dart` / `plugin_runtime.dart`）
- [x] 多插件管理（Phase 3.3：`plugin_manager.dart` + `PluginProvider` 接线 + 持久化）
- [x] 插件文件持久化（Phase 3.4：`plugin_storage_service.dart` + `path_provider`）
- [x] 插件管理 UI 接入真实数据（Phase 3.5：`plugin_manage_page.dart` 重写 +
      `plugin_detail_page.dart` + 示例插件 + `AppTheme` 状态色）
- [x] 修正示例插件无法卸载（Phase 3.5.1：`PluginMeta.isRemovable` +
      真正删除插件文件）
- [x] `lib/runtime/plugin_context.dart`（Phase 3.6：`ctx.http` / `ctx.storage` /
      `ctx.log` / `ctx.notify` / `ctx.cookie`，含重放机制）

---

## Phase 4：第一个插件（进行中）

> ⚠️ **写 NCST 插件前先读 `CONTEXT.md` 3.6「插件入口函数幂等约定」**——
> 入口函数会被执行多次，必须幂等；`ctx.storage` 只在最终轮生效。

- [x] WebView 登录页（Phase 4.1：`pages/login/webview_login_page.dart`，通用组件）
- [x] Cookie 提取（Phase 4.1：`services/cookie_service.dart` + `WebViewCookieManager`）
- [x] NCST 插件（Phase 4.2：`assets/plugins/ncst-jwxt.js`，声明 `loginUrl` / `checkUrl` + `fetchCourses`）
- [x] 同步接线（Phase 4.2：详情页「立即同步」→ `fetchCourses` → `saveCourse` 落盘）
- [x] **WebView 登录页 SSL 证书放行 + 诊断日志**（Phase 4.2.1：只放行登录 host；真机复验见备注块）
- [x] **Android 明文流量定向白名单**（Phase 4.2.2：`network_security_config.xml`，
      只放开 `xjw1.ncst.edu.cn`；**需重装 APK 才能生效**，真机复验见备注块）
- [x] **真机跑通"登录 → 同步 → 课表显示"** —— **2026-09-30 复验通过**：
  校园 WiFi 下登录页正常打开（无 `ERR_CERT_*` / `ERR_CLEARTEXT_*`）→ 提取 3 个 Cookie →
  同步解析 4 门课程 + 12 条节次时间 → 课表渲染 → `force-stop` 冷启动后仍在。
  详见下方 **4.3 备注开头的"真机复验已完成"** 一节
- [x] **数据同步的增量/覆盖策略与失败重试（Phase 4.3）** ——
      `services/course_sync_service.dart` + `models/sync_report.dart`；
      增量（未变不写盘）、覆盖层保留（含 `saveCourse` 内存侧修正）、
      网络类失败指数退避重试（最多 3 次）、结果分类 + 常驻结果卡片。
      **已 `dart analyze` 全绿 + 临时脚本 16 组通过 + 真机复验通过**
- [ ] 课表显示节次时间（**Phase 4.4 ✅ 已完成并真机验证**：
      `SectionTimeService` 从 `plugin_data.section_times` 读插件真实作息，
      课表回退逻辑见 4.4 备注。真机确认第 11/12 节显示插件的
      `20:50-21:35` / `21:40-22:25`，而非硬编码的 `20:40-21:25` / `21:30-22:15`）
- [x] 同步进度 UI（**Phase 4.3**：转圈 + 阶段文案 + 常驻结果卡片；
      **Phase 4.4** 又在课表页顶部加了同步入口 ⟳）
- [x] **⚠️ 收尾必做：`flutter build apk --release` 发布包冒烟** ✅ **2026-09-30 通过**：
  打包 56.7 MB → 装真机 → 插件加载（QuickJS 三个 ABI 的 .so 齐全，R8 未破坏 FFI）
  → 登录 → `ctx.http` 拉回 4 门课程。详见下方"Phase 4 收尾：release 包冒烟"。
  ⚠️ 过程中踩到：MIUI 需开「USB 调试（安全设置）」才能 adb 装包；
  且 debug/release 签名不同必须先卸载，**卸载会清掉应用数据**

### Phase 5.1 备注（课表"没有数据"的真相 + 周次解析加固）

> **起因**：用户反馈"课表页没有数据，但课程页数据是正确的"，
> 并提供了两份早期 Python 脚本（`generate_schedule.py` / `test.py`）作为参考。
>
> **先说结论：这不是数据没读到，而是"有课程但本周没课"这个状态此前不可见。**

> **排查过程（值得复用）**：
> 1. 两个页面用的是**同一个数据源**（`CourseProvider.visibleCourses`），
>    所以"课程页有、课表页没有"不可能出在数据层——只可能在**周次过滤**上。
> 2. 课程详情页显示的是 `rawWeeksText`（原始文本），课表画的是
>    `weeks` + `hasClassInWeek`——两者是**两条独立的展示路径**。
> 3. 用户课程页上可见的原始文本是 **`4,6-14周`**，而当时是**第 5 周**。
>    这个字符串字面意思就是"跳过第 5 周" → 课表第 5 周本来就该是空的。
> 4. 写了复现脚本（13 组）把这条钉死：第 5 周网格为 0 格、第 4/6 周非空。
>    **过滤逻辑是对的。**

> **🔴 真正的问题：UI 不说人话**
>
> 课表页此前只有两种空态：`还没有配置学期` / `还没有课程`。
> 于是"**有课程、但本周恰好全空**"落到第三种情况——**画一片空白网格，一个字都不说**。
> 用户看到空白，自然会推断"数据没同步进来"，再去课程页确认——课程页又是对的，
> 于是变成一个看起来自相矛盾的 bug。

> **修复 1：本周为空时给出说明（UX）**
>
> 新增 `_EmptyWeekNotice`（网格上方，用 `theme.warning` 令牌，不硬编码黄色）：
> - 有周次信息但不含本周 → `第 5 周没有课` +
>   `本学期有课的周次：第 4,6-14 周（最近有课：第 4 周）` + **「跳到第 4 周」按钮**
> - 完全没有周次信息（教务没给 / 解析不出）→ 明确提示
>   `课程缺少周次信息，无法判断它们在第几周上课。请到「课程」页检查…`
>
> 配套在 `TimetableLogic` 加了三个纯函数：
> `hasAnyClassInWeek` / `weeksWithClass` / `nearestWeekWithClass`
> （平局取**更早**的周——用户更可能想回看而不是跳未来）。

> **🔴 修复 2：周次解析的静默失效（数据健壮性）**
>
> 写测试时顺带发现：`parseWeeks` 对**全角数字**（`"１－１６周"`）与
> **中文数字**（`"四至十四周"`）都解析成 `[]`，而 `weeks` 为空意味着
> **该课程在课表上永远不显示、但课程页却正常**——正是用户描述的那个症状，
> 只是触发条件不同。中文教务系统出现这两种写法并不罕见。
>
> 新增归一化 `normalizeWeekText` + `chineseToArabic`，把全角数字与中文数字
> （含十位组合）都转成半角阿拉伯数字。
>
> ⚠️ **这里踩了一个自己挖的坑**：第一版把 `"十"` 当成值 `10` 逐字替换，
> 于是 `"十六"` → `"1"+"10"+"6"` = `"106"` → 冲出 `kMaxWeekNumber` → 空结果。
> **"十"是位权不是值**。改成逐字符扫描后才正确：扫描点永远落在
> "可能是一个数字的开头"，所以 `"第十六周"` 里的 `'第'` 被原样跳过、
> 随后从 `'十'` 识别出 16。

> **🔴 修复 3：Dart↔JS 对拍暴露的 6 处分歧（最值得记的一条）**
>
> `__ncst_parseWeeks` 是 `TimetableLogic.parseWeeks` 的 JS 复刻
> （沙箱里调不到 Dart）。此前只靠"人工看两边代码像不像"，
> 这次用 **37 组样本在 Node 里直接调用插件的那几个函数**与 Dart 逐条对拍，
> 一次抓出 **6 处分歧**：
>
> | 输入 | Dart | 修复前的 JS |
> |------|------|-------------|
> | `"4,6-14周"` | `[4,6..14]` | **`[4,6..60]`** ← 最严重 |
> | `"１－１６周"` | `[1..16]` | `[1..60]` |
> | `"第十六周"` | `[16]` | `[]` |
> | `"第二十周"` | `[20]` | `[]` |
> | `"第二十五周"` | `[25]` | `[]` |
> | `"第十四周"` | `[14]` | `[]` |
>
> 第 1 行最严重也最隐蔽：Dart 侧我把归一化写成**逐字符**处理，
> 而 JS 侧还是**逐条 `replace` 链**——两边顺序与语义都对不上了。
> 结论：**跨语言复刻不能靠肉眼比对，必须有可执行的逐条对拍。**
> 两边现在在 37 组样本上逐条一致（含标准 / 全角 / 中文数字 / 坏数据 / 超大区间）。

> **验证状态（自验证，未用实体机）**：
> - ✅ `dart analyze`（整包）→ `No issues found!`
> - ✅ 临时脚本 **35 组全部通过**：
>   - 归一化 9 组（全角数字、中文数字、十位组合、`至`/`到`、中文逗号）
>   - 回归 4 组（标准写法结果不变、坏数据仍被拒、超上限截断、单双周识别不受影响）
>   - 工具函数 6 组（`weeksWithClass` 合并与裁剪、`hasAnyClassInWeek`、
>     `nearestWeekWithClass` 平局取更早、空列表、隐藏课程不计入）
>   - **UI 3 组**（有课但本周空 → 提示 + 跳转；本周有课 → 不提示；
>     无周次信息 → 提示去检查）
>   - **端到端复现 13 组**（把"第 5 周为空是正确行为"钉进测试）
>   - **Dart↔JS 对拍 1 组 × 37 样本**
> - ✅ `node --check` 通过插件 JS 语法
> - ✅ **Windows 桌面实跑**：构建 + 启动无异常

> **⚠️ 顺带记一次操作事故**：我一度用 PowerShell 的
> `Set-Content -Encoding UTF8` / 追加写往 `timetable_logic.dart` 塞代码，
> **中文被控制台代码页转成了乱码**（`'一'` → `'涓€'`）。
> 这正是 PROGRESS 阻塞表 2026-09-23 记过的那条坑，我又踩了一次。
> 修复：用 `write` 工具整体重写该文件（显式 UTF-8）。
> **教训：给已有文件追加中文内容，不要走 PowerShell 的编码参数，
> 一律用文件编辑工具。**

### Phase 5 备注（课程编辑 / 删除 / 隐藏）

> **验证状态（自验证，未用实体机）**：
> - ✅ `dart analyze`（整包）→ `No issues found!`
> - ✅ 临时脚本 **12 组全部通过**（真实 Hive + 临时目录）：
>   - 编辑插件课程：改名只写 `customName`、原始 `name` 保持教务值；
>     落盘后重建 Provider 覆盖层与原始值都在；**重同步不冲掉编辑结果**；
>     学分/类别不被写进 `Course`
>   - 编辑自建课程：改名/教师/学分/类别都落到原始字段
>   - 隐藏/恢复：`visibleCourses` 过滤正确、原始数据仍在、
>     `hiddenCount`/`hiddenCourses` 正确、**隐藏不清掉颜色/备注/改名**、
>     **隐藏后编辑不会让它复活**（`hidden` 保留）、不存在的 id 返回 `false`、
>     隐藏状态能持久化
>   - 删除自建课程：真删且清掉覆盖层（不留孤儿）
> - ✅ 临时 **widget 测试 6 组全部通过**（UI 层）：
>   新增模式标题/无删除按钮；编辑自建课程标题/字段回填/删除图标/学分可拖；
>   编辑插件课程**滑块禁用 + 类别只读 + 只读说明**；已改名课程回填覆盖层值；
>   `HiddenCoursesPage` 空态与列表
> - ✅ **Windows 桌面实跑**：`flutter build windows --debug` 成功，
>   应用启动无异常（9 个 Hive Box 正常建立，Dart VM service 起得来）

> **改动清单**：
>
> | 文件 | 改动 |
> |------|------|
> | `lib/pages/edit/course_edit_page.dart` | 加 `course` 参数支持编辑模式；`_buildOverride` 统一构造覆盖层；`_TimePlaceDraft.fromTimePlace` 反填；删除/隐藏按钮 + `_confirmDelete`；`_ReadOnlyNotice`；学分/类别在插件课程下只读 |
> | `lib/pages/settings/hidden_courses_page.dart` | **新建**：已隐藏课程列表 + 恢复 |
> | `lib/pages/settings/timetable_settings_page.dart` | 新增「已隐藏的课程」入口（带数量副标题） |
> | `lib/pages/timetable/course_detail_sheet.dart` | 「编辑」接真实编辑页（先取 Navigator 再 pop） |
> | `lib/pages/timetable/timetable_view.dart` | 长按进编辑页；`_openCourseEdit` 加可选 `course` 参数 |
> | `lib/providers/course_provider.dart` | 新增 `setHidden` / `hiddenCourses` |

> **🔑 本阶段最关键的设计决定：编辑两种课程的**落点是不同的**
>
> | 课程来源 | 保存到哪 | 为什么 |
> |----------|----------|--------|
> | 自建（`sourcePluginId == 'user'`） | `courses` Box 的**原始字段** | 这条数据本来就是用户的 |
> | 插件同步来的 | `overrides` Box 的**覆盖层** | 原始字段是教务权威数据，重同步会覆盖它 |
>
> 如果偷懒让两种都写原始字段，插件课程的用户修改会在下次同步时**静默消失**——
> 正是 4.3 修掉的那类 bug 换个入口再来一次。
> 测试里专门有一条"重同步不冲掉编辑结果"盯着这个不变量。

> **⚠️ 一个刻意的功能缺口：插件课程的「学分 / 类别」不可改**
>
> `UserOverride` **没有** `customUnit` / `customCategory` 字段。硬写进 `Course`
> 会被下次同步冲掉，所以这两个字段在编辑插件课程时**只读**，
> UI 上直接说明"学分与类别来自教务系统，暂不支持修改"。
>
> 要真正支持需要给 `UserOverride` 加 `customUnit` / `customCategory`：
> 按 CONTEXT 4.2.1 属**纯新增**（缺键有兼容默认值）→ 不需要迁移逻辑。
> 但那会让 `Course.displayUnit` / `displayCategory` 以及所有读 `unit`/`category`
> 的地方都要跟着改（课表卡片、列表页、详情弹层），属于独立改动，
> 本阶段**选择不做**而不是做一半。

> **4 条覆盖层构造规则**（`_buildOverride`，每条都有测试盯着）：
> 1. 颜色始终按表单值写；
> 2. 名称/教师**只在改过时**才写（改回原值不留空覆盖）；
> 3. 时间地点**只在真的改过时**才写 `customTimePlaces`
>    ——没改就继续跟教务走，不该被一次无意义的"保存"冻结；
> 4. **`hidden` 必须保留** ——否则"隐藏后顺手编辑一下"会让课程复活。

> **顺带清理**：`timetable_view.dart` 与 `course_detail_sheet.dart` 里两个
> 只服务于 Phase 5 占位的 `_showSnack` 变成死代码，已删除。


> **目标**：课表左侧时间列改显示**插件同步下来的真实作息**，不再用硬编码的
> `kDefaultSectionTimes`；顺带把同步入口补到课表页。

> **验证状态**：
> - ✅ `dart analyze`（整包）→ `No issues found!`
> - ✅ 临时脚本 **13 组全部通过**（`parseSessionNumber` 键解析 / `parse` 整份 /
>   `SectionTimes` 派生成员 / 能力契约常量），跑完即删
> - ✅ 临时脚本 **5 组全部通过**：真实 Hive（临时目录）下"未写入 → null"、
>   "写入 → 读到 4 条"、"同步覆盖写入 → 重读拿到新值"、"未启用 → null"、
>   "未声明能力 → null"，跑完即删
> - ✅ **真机验证**：见下方"真机证据"

> **改动清单**：
>
> | 文件 | 改动 |
> |------|------|
> | `lib/services/section_time_service.dart` | **新建**：`SectionTimes` + `SectionTimeService` |
> | `lib/pages/timetable/timetable_view.dart` | `_sectionTimes` + 签名刷新；网格用插件作息（回退默认）；**顶部栏新增同步按钮 ⟳**；`_syncNow` 复用 `CourseSyncService` |
>
> `kDefaultSectionTimes` **保留但降级为兜底值**（新用户没装插件时时间列不能空着）。

> **真机证据（关键）**：插件写入的真实作息与硬编码默认值在第 11/12 节**不同**，
> 屏幕上显示的是**插件那份**：
>
> | 节次 | 插件真实值（屏幕显示） | 硬编码默认值 |
> |------|------------------------|--------------|
> | 11 | **20:50-21:35** | 20:40-21:25 |
> | 12 | **21:40-22:25** | 21:30-22:15 |
>
> 截图：`docs/verify/4.4-section-times-from-plugin.png`
>
> ⚠️ **排查过程记一笔（值得复用）**：前 9 节的真实值与默认值**恰好完全相同**
> （那些默认值本来就是照这所学校抄的），所以我第一次看截图误判成"没生效"。
> 后来把解析结果**逐条打日志**，才看出第 11/12 节不同——**"肉眼看不出区别"
> 不等于"功能没生效"**，要拿数据对照，别只比前几项。

> **多插件策略**：多个插件都声明 `timetable` 且都有作息时，
> 取**第一个能解析出非空作息**的那份，**不混合**——
> 混起来会得到"第 3 节 10:25，第 5 节却是另一个学校的时间"这种错乱结果。
> 课表页顶部只在**恰好一个**候选插件时显示同步按钮；多个候选时课表页放不下
> "选哪个"，引导去插件管理页。

### Phase 4 收尾：release 包冒烟（✅ 2026-09-30 通过）

> 3.6 起就挂着的待办："此前所有网络验证都在 debug 包上做的，
> release 是否有权限 / 混淆（R8）问题完全没验证过"。**现已完成。**

> **包内容检查**（`aapt2` + 直接读 zip 条目）：
>
> | 检查项 | 结果 |
> |--------|------|
> | `libfastdev_quickjs_runtime.so` | ✅ arm64-v8a / armeabi-v7a / x86_64 **三个 ABI 齐全**（插件运行时必需） |
> | `android.permission.INTERNET` | ✅ 在 |
> | `android:networkSecurityConfig` | ✅ 在 |
> | `android:usesCleartextTraffic` | ✅ **无**（确认没做全局明文放行） |
> | 构建产物 | `app-release.apk` 56.7 MB，`assembleRelease` 206s |
>
> **设备实测**（真机装 release 包，`setprop log.tag.Flutter VERBOSE`
> 让 release 下的 `debugPrint` 也落 logcat）：
>
> ```
> [JsSandbox] 子 isolate 就绪
> [PluginRuntime] 插件加载成功：ncst-jwxt，入口函数 [fetchCourses]
> [PluginProvider] 内置插件已安装并启用：ncst-jwxt
> [WebViewLoginPage] 提取到 3 个 Cookie，拼接后 96 字符
> [Plugin:ncst-jwxt] 第 1 轮登记了 1 个 HTTP 请求，取回后重放
> [Plugin:ncst-jwxt] 第 2 轮登记了 1 个 HTTP 请求，取回后重放
> [Plugin:ncst-jwxt] NCST 同步：解析出 4 门课程，节次时间 12 条
> [CourseSyncService] ncst-jwxt 同步完成：新增 4、更新 0、未变 0、跳过 0
> ...
> [CourseSyncService] ncst-jwxt 同步完成：新增 0、更新 0、未变 4、跳过 0
> ```
>
> 结论：**R8 没有破坏 QuickJS 的 FFI 绑定与 `.so` 加载**；
> `ctx.http` 在 release 下能真发请求并拿到数据；**明文白名单在 release 同样生效**
> （同步成功即证明，因为部分请求走 http）。
>
> 上面第二条同步（`未变 4`）是用户在**课表页顶部 ⟳**触发的，
> 说明 release 包下 ① 4.4 新增的同步入口可用、② **增量策略同样成立**
> （4 门课原始字段与库中一致 → 全部跳过落盘）。
> 这比 debug 包那次更有价值：debug 下多一层校验，release 下才是真实运行形态。
>
> 截图：`docs/verify/4.4-release-smoke.png`（该图是**卸载重装后**的状态，
> 所以显示"还没有配置学期"——学期配置也在卸载时被清掉了）

> ⚠️ **踩到的坑：MIUI 会拦 adb 安装**
> `adb install` 报 `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`，
> 需在手机 **开发者选项 →「USB 调试（安全设置）」** 打开后才能装 release 包。
>
> ⚠️ **卸载会清数据**：debug 与 release 签名不同，必须先 `adb uninstall` 再装，
> 而卸载会**连应用数据一起清掉**（课程、学期配置、Cookie 全没）。
> 以后做这类验证前要先告知用户，或用 `adb install -r` 配相同签名。

### Phase 4.3 备注（数据同步打通：增量 / 覆盖层保留 / 失败重试）


> ## ✅ 真机复验已完成（2026-09-30，Redmi K60 / `2211133C` / Android 16）
>
> **环境**：手机连校园 WiFi（`10.128.182.173`），`xjw1.ncst.edu.cn` 解析到 `172.20.13.4`。
> ⚠️ **`ping` 是假阴性**：设备上 `ping -c 2 xjw1.ncst.edu.cn` 显示 100% 丢包，
> 但 `curl` 实测 **302、`time_connect=0.021s`** —— Android shell 无权限发 ICMP。
> **以后不要用 ping 判定校园网可达性，要用 `curl` 或 TCP 连接。**
>
> **复验证据链**（`adb logcat -s flutter:V`）：
>
> ```
> [WebViewLoginPage] 提取到 3 个 Cookie，拼接后 82 字符
> [WebViewLoginPage] 已保存 ncst-jwxt 的 Cookie（82 字符）
> [Plugin:ncst-jwxt] 第 1 轮登记了 1 个 HTTP 请求，取回后重放
> [Plugin:ncst-jwxt] 第 2 轮登记了 1 个 HTTP 请求，取回后重放
> [Plugin:ncst-jwxt] NCST 同步：解析出 4 门课程，节次时间 12 条
> [CourseSyncService] ncst-jwxt 同步完成：新增 0、更新 0、未变 4、跳过 0、其中带用户修改 0
> ```
>
> 且全量 logcat 中**无** `ERR_CERT` / `ERR_CLEARTEXT` / `加载失败`。
>
> | 项 | 结论 | 依据 |
> |----|------|------|
> | **4.1** 登录 + Cookie | ✅ | 提取 3 个 Cookie / 82 字符并保存 |
> | **4.2.1** SSL 放行 | ✅ 生效 | 登录页全程打开无 `ERR_CERT_*`。⚠️ 本轮**未走到**错误放行回调（教务站本次没报证书错），所以是"未出现失败"而非"回调被触发" |
> | **4.2.2** 明文白名单 | ✅ 生效 | 登录页能打开（明文 HTTP 已被放行）**且** `aapt2 dump xmltree` 从**装进设备的 APK** 解出：`base-config cleartextTrafficPermitted=false` + `domain-config=true`/`xjw1.ncst.edu.cn`/`includeSubdomains=true`；`AndroidManifest.xml` 含 `networkSecurityConfig` 与 `INTERNET`，且**无** `usesCleartextTraffic` |
> | **4.2** NCST 插件 + 同步接线 | ✅ | 解析出 4 门课程 + 12 条节次时间 |
> | **4.3** 增量 / 覆盖层 / 重试 / 进度 | ✅ | `未变 4` 正是增量策略：4 门课原始字段与库中完全一致 → **全部跳过落盘**；且**这是第二次同步**（首次是上一轮会话做的），说明字段指纹稳定、没有把同一份数据反复判成"变了" |
> | **4.3** 冷启动持久化 | ✅ | `am force-stop` 后重启，课表第 5 周仍显示「综合评价方法 / HA-303」（周二 7-8 节）。证明 Hive 落盘 + `saveCourse` 修复未破坏持久化 |
>
> **证据截图**：`docs/verify/4.3-timetable-after-cold-restart.png`
>
> **顺带修掉的一个环境问题**：复验前设备把 App 当**横屏**应用
> （`uiautomator` 报 `rotation="3"`、根节点 `[0,0][2400,1080]`），
> 导致截图旋转 90° 且坐标点击全部落空。
> 已 `settings put system accelerometer_rotation 0` + `user_rotation 0` 锁定竖屏。
> **若以后截图看起来"躺倒"，先查这两项。**
>
> **仍未覆盖**：release 包冒烟（`flutter build apk --release`）——
> 本轮所有验证都在 **debug** 包上做的，与 3.6 记的"release 有独立权限/混淆风险"一致，仍需单独做一次。

> **目标**（原文）："数据同步的增量/覆盖策略与失败重试"。
> 同时把 4.2 遗留的三个问题一起解决：同步逻辑写死在页面里无法复用、
> 失败原因无法判断该不该重试、UI 拿不到进度。

> **⚠️ 验证状态（先说清楚做了什么、没做什么）**：
> - ✅ **`dart analyze` 全绿**：整包（含 `test/`）`No issues found!`。
>   过程中分析器抓出 2 处我写的多余判空（`unnecessary_nullable_for_final_variable_declarations`
>   → `unnecessary_null_comparison`），已改用 `late final SyncReport report`
>   把这个"try/catch 各赋一次"的不变量表达在类型里，两处告警消失。
> - ✅ **新增逻辑用临时测试脚本 16 组全部通过**（脚本跑完即删，遵守 CONTEXT 6 不保留测试）：
>   `saveCourse` 覆盖层保留 4 组（含**直接复现修复前的丢数据场景**）、
>   `parseCourses` 容错 4 组、`SyncReport`/`SyncOutcome` 语义 5 组、重试策略常量 3 组。
>   其中"只有 `networkError` 可重试"是遍历全部 8 个枚举值断言的。
> - ✅ **JS 语法检查**：`node --check` 对 `ncst-jwxt.js` 与 `example.js` 均通过。
> - ❌ **没有真机验证**（需要校园网 + 人工凭据，与 4.2 同一阻塞项）
> - 注：`docs/ENV.md` 记的"`flutter.bat` 在沙箱挂死"依然成立，
>   本次统一走 `dart.exe <flutter>/bin/cache/flutter_tools.snapshot` 调用

> **改动清单（6 个文件）**：
>
> | 文件 | 改动 |
> |------|------|
> | `lib/models/sync_report.dart` | **新建**：`SyncOutcome` 枚举（8 态）+ `SyncReport`（13 字段 + 4 派生 getter + `failure` 工厂） |
> | `lib/services/course_sync_service.dart` | **新建**：同步编排 + 增量落盘 + 重试 + 结果分类（629 行） |
> | `lib/providers/course_provider.dart` | **修 bug**：`saveCourse` 不再冲掉内存里的覆盖层 |
> | `lib/runtime/plugin_ctx_script.dart` | `ctx.lastHttpError` + `__ctx_note_http_error` + `__ctx_http_errors` + dump 带 `httpErrors` |
> | `lib/runtime/plugin_context.dart` | `_CtxRound.httpErrors` + 跨轮累积 + 挂到返回结果（四条返回路径全覆盖） |
> | `lib/runtime/js_sandbox.dart` | `JsSandboxResult.httpErrors` 字段 + `withHttpErrors()` |
> | `lib/pages/settings/plugin_detail_page.dart` | 改 `StatefulWidget`；接 `CourseSyncService`；新增 `_SyncProgressTile` / `_SyncResultTile`；`_ActionRow.onTap` 可空（禁用态）；删掉 4.2 的临时诊断日志 |
> | `assets/plugins/ncst-jwxt.js` | `__ncst_netFail()` 给网络类失败标 `retryable: true` |
>
> （表里 8 行：其中 2 个是新建，其余为改动。）

> **🐛 本阶段修掉的真实 bug（值得单独记一条）**：
> `CourseProvider.saveCourse` **只保护了落盘数据、没保护内存视图**。
> 它把"原始数据（剥离覆盖层）"写 `courses` Box、覆盖层写 `overrides` Box，
> 这部分是对的；但最后 `_upsert(c)` 用的是**入参 c**（插件给的、不带覆盖层），
> 于是列表里那条**带覆盖层**的课程被整体替换 → 用户在本次会话内改过的课程名
> **当场消失**，重启后又从 Box 读回来（表现为"改完当场丢、重启复活"）。
> 插件重同步每次都传入无覆盖层的原始课程，所以这条路径**必然被踩到**。
> 修法：覆盖层来源优先级 = 入参自带的 > 内存里那条已有的 > Box 里存的，
> 挂回去之后再 `_upsert`。**内存优先**是有意的——它一定是最新的，
> 而 `OverrideEngine.getOverride` 依赖 Hive 已初始化，内存查不到才值得读盘。

> **增量策略（"增量/覆盖"的落地）**：
>
> | 情况 | 计数 | 动作 |
> |------|------|------|
> | 库里没有该 `id` | `added` | 写入 |
> | 有且原始字段**一致** | `unchanged` | **跳过落盘**（省一次 Hive 写 + 一次 `notifyListeners`） |
> | 有且原始字段不同 | `updated` | 覆盖写入 |
> | 解析失败 / 重复 `id` | `skipped` | 跳过并 `debugPrint` |
>
> 两个设计要点：
> 1. **字段指纹不含 `userOverride`**。否则用户每改一次课名，下次同步都会被判成
>    `updated` 而多写一次盘——"教务数据没变"和"用户改过"是两件事。
> 2. **`weeks` 归一为"去重 + 升序"**。教务系统两次返回的周次顺序可能不同，
>    直接比列表会把"同一份数据"误判成"变了"。
>
> **"覆盖"的边界**（CONTEXT 3.3）：只覆盖**原始**字段，
> **不删除任何课程**。教务系统里消失的课程同样保留，只能由用户显式隐藏——
> 因为"教务系统这次没返回"和"这门课被删了"在内核看来无法区分，
> 贸然删除会连用户的备注和自定义颜色一起丢掉。

> **失败重试：只重试网络类失败**。
> 判定顺序（从最可靠到最兜底）：
> 1. 插件显式声明 `retryable: true`（4.3 起的约定，插件最清楚自己失败在哪一层）；
> 2. 宿主的 HTTP 错误类别（`JsSandboxResult.httpErrors`）是
>    `timeout` / `connection` / `bad_response` —— 给没升级契约的老插件兜底；
> 3. 都没有 → **不重试**（保守：宁可让用户手动重试，也不自动空转）。
>
> 参数：`kMaxAttempts = 3`、退避 `600ms → 1500ms`。
> **凭证过期、响应结构异常、插件不可用、执行超时一律不重试** ——
> 重试只会让用户多等一轮还得到同样结果。
>
> ⚠️ 一个容易误判的点：`ctx.http.get` 在**真失败**时会 `throw`，
> 而 throw 会让那一轮的执行结果变成 `error`，插件自己的 `retryable: true`
> **拿不回来**。所幸宿主仍会把错误短标识放进 `result.httpErrors`，
> 所以第 2 条兜底**能救回这种情况**——两条路都通，不是二选一。

> **`ctx.lastHttpError` 与"内核不认识学校字段"的关系**（CONTEXT 3.1 自查）：
> 新增的 `httpErrors` / `errorKind` 全部是**宿主自己的错误枚举**
> （`timeout` / `connection` / `bad_certificate` / `bad_response` / `cancelled` / `unknown`），
> 插件侧只把它当不透明字符串回传。**全程不解析任何响应正文**，
> 所以内核里依然一个学校字段都没有。

> **`_looksLikeAuthProblem` 为什么要靠中文关键词**：
> `fetchCourses` 在 Cookie 为空时**根本不发请求**（NCST 插件第 33 行），
> 所以宿主侧没有任何 HTTP 错误可依据，只能看插件给的那句话。
> 它**只影响提示文案与是否重试**，不影响数据正确性；匹配不到就归为
> `protocolError`（同样不重试）。这是一处有意的、有界的启发式，不是遗漏。

> **进度 UI**：`_SyncProgressTile`（转圈 + 阶段文案）+ `_SyncResultTile`（常驻结果卡片）。
> 结果卡片里有一行 **"其中 N 门保留了你的修改"**——这是"用户改动没被同步冲掉"的
> 可见证据，比埋在日志里更有意义。颜色只用 `theme.success` / `warning` / `error`
> （CONTEXT 3.2 禁止硬编码绿/黄/红）。
> 页面不再用 `static bool _syncing` 闩锁（那样跨实例泄漏状态、且没法显示结果）。

> **顺带清理**：
> - 删掉 4.2 留在 `_syncNow` 里的 `[Sync诊断]` 临时日志块（当时用于排查
>   "同步成功但课表空白"，现已由 `CourseSyncService` 的结构化日志取代）
> - `plugin_detail_page.dart` 不再需要 `dart:convert` / `models/course.dart` /
>   `models/time_place.dart` / `runtime/js_sandbox.dart` 的 import（解析逻辑已搬走）
> - **删掉 `timetable_view.dart` 里整块 `[Timetable诊断]` / `[Timetable分支]` 日志**
>   （上一轮排查同一个"课表空白"问题时加的，注释写着"定位后删除"但一直没删；
>   共 5 处 `debugPrint` + 一个 `_dumpTimetableDiagnostics` 方法 + 一条只为它存在的
>   `models/time_place.dart` import）。**删完后该文件与 HEAD 完全一致**
>   （`git diff` 为空）——说明它本来就是纯诊断改动，还原后不影响 Phase 2 已交付行为
> - `test/tmp_phase_4_3_test.dart` **已删除**（Phase 4.3 早期的临时脚本，
>   Phase 4.3 完成时作废）。`test/` 目录现在是空的 —— 这是符合项目惯例的状态
>   （CONTEXT 6：Phase 1-5 不写单元测试；验证脚本跑完即删）
> - ⚠️ **`lib/pages/course_list/course_list_view.dart` 的改动是上一轮就有的**
>   （课程列表页接真实数据，188 行），不是本次新增；它同样未提交，
>   同属 Phase 4.3 这条工作线

> **未做（留给后续）**：
> - 课表页的同步入口（4.4；`CourseSyncService` 已经是可复用的，加个按钮即可）
> - "教务系统里消失的课程"的提示（需要产品决策：是提醒、自动隐藏，还是不管）
> - 同步结果的历史记录（现在只保留"上一次"）

### Phase 4.2.2 备注（Android 明文流量定向白名单）

> **问题（4.2.1 修复后的真机复验）**：SSL 放行生效后，登录页**仍打不开**，
> 但错误换了一条 ——
> ```
> [WebViewLoginPage] 加载失败: code=-1
>   desc=net::ERR_CLEARTEXT_NOT_PERMITTED
>   url=http://xjw1.ncst.edu.cn/gotoLogin
> ```
> **根因**：教务系统登录会从 `https://xjw1.ncst.edu.cn/` **重定向到 http**
> （`http://xjw1.ncst.edu.cn/gotoLogin`），而 targetSdk 34 起 Android **默认禁止明文流量**。
> 这正好印证了 4.1 真机就确认过的那条风险（当时留作"待拿到真实教务地址后决定"），
> 而 **4.2 快照里"NCST 是 https，不需要 cleartext 配置"的判断被推翻了** ——
> 入口是 https，但**跳转链里有 http**。

> **改动**（**未加新依赖**、**未改任何 Dart 代码**）：
> - 新建 `android/app/src/main/res/xml/network_security_config.xml`：
>   `base-config cleartextTrafficPermitted="false"` + 一条 `domain-config true`
>   （`<domain includeSubdomains="true">xjw1.ncst.edu.cn</domain>`）
> - `android/app/src/main/AndroidManifest.xml`：`<application>` 新增
>   `android:networkSecurityConfig="@xml/network_security_config"`
>   （放在 `main` 里 ⇒ **debug / profile / release 三个变体都生效**；
>   debug 变体的 manifest 只额外声明 `INTERNET`，不含网络策略）
> - **没有**加 `android:usesCleartextTraffic="true"`（那是全局放行，等于对所有域名降级）
> - `docs/CONTEXT.md`：3.1 小节新增**例外说明** + 版本 **v1.4 → v1.5** + 版本记录一行
>
> 其他地方**一个都没动**：`lib/` 零改动（`dart analyze lib` 仍全绿）、pubspec 未改、
> `debug/AndroidManifest.xml` 未改、其他 Android 配置未改。

> **为什么两个修复都要保留（互补，不是二选一）**：
> | 修复 | 拦的是 | 表现 |
> |------|--------|------|
> | 4.2.1 `onSslAuthError` | **证书不受信**（`net::ERR_CERT_*`） | WebView 对自签证书默认直接拒绝 |
> | 4.2.2 `network_security_config` | **明文 HTTP**（`net::ERR_CLEARTEXT_NOT_PERMITTED`） | 系统层拦掉 http 请求 |
> 两者是**不同层**的拦截：一个是 TLS 校验，一个是传输层策略。
> 教务系统"自签证书 + https→http 跳转"同时踩中两条，所以缺一不可。

> **⚠️ 影响面：WebView 已确认受益，`ctx.http`（dio）待真机确认**：
> - ✅ **已确认**：4.1 真机上报 `net::ERR_CLEARTEXT_NOT_PERMITTED` 的就是 **WebView**，
>   所以登录页这条链路一定受这份配置影响
> - ❓ **未知**：`ctx.http` 走 **dio → Dart 侧 socket**。Android 原生的
>   `usesCleartextTraffic`（全局开关）对 Flutter Dart 侧 HTTP 是生效的，
>   但**"按域白名单"（`domain-config`）是否被 Dart 侧尊重，本项目没有证据** ——
>   4.1 的真机记录里 dio 确实打通了 `http://` 本机服务，但那一次是临时在
>   **debug** manifest 开了 cleartext（**全局开关**，且只影响 debug），
>   **不能**据此推断本配置对 dio 生效
> - ⚠️ **由此产生一个明确的复验项**：登录成功后点「立即同步」，
>   若 `fetchCourses` 报 `{error:'connection'}`（而浏览器 / curl 能通），
>   基本就是"dart 侧不被按域白名单放行"。届时按证据再决策
>   （**不预先全局放行**：那会把安全策略降级到所有域名）

> **验证（做过的 / 没做的，说清楚）**：
> - ✅ **XML 良构性 + 关键节点/属性**用 .NET `XmlDocument` 解析校验：
>   `base-config` 的 `cleartextTrafficPermitted="false"`、恰好 **1** 条 `domain-config`、
>   domain = `xjw1.ncst.edu.cn`、`includeSubdomains="true"`、
>   manifest 上 `networkSecurityConfig='@xml/network_security_config'`、
>   **`usesCleartextTraffic` 属性为空**（确认没做全局放行）、`INTERNET` 权限仍在
> - ✅ `dart analyze lib` 全绿（证明 `lib/` 未受影响）
> - ❌ **没有写新单测**：这是 Android 平台配置，Dart 测试**看不到**它
>   （`flutter test` 跑在 Windows 宿主 Dart VM 上，连 Android 都不涉及）
> - ❌ **没有跑 gradle 构建**（耗时且本阶段重点是配置正确性）；
>   真正的"资源引用有效 + 策略生效"**只能靠重装 APK 真机验收**：
>   若 `@xml/` 引用写错，构建期就会失败（`resource xml/network_security_config not found`），
>   这一点下次 `flutter run` 会立刻暴露，属可接受的验证缺口

### Phase 4.2.1 备注（WebView 登录页 SSL 证书放行 + 诊断日志）

> **问题（真机 4.2 验收）**：点插件详情页「登录」→ WebView 打开登录页报**加载失败 `-1`**；
> 而**手机系统浏览器访问同一地址能正常打开**。
> **推断即根因**：教务系统用的是**不受信 / 自签证书** —— 浏览器会提示"继续访问"，
> **WebView 默认直接拒绝**。这正是 4.2 真机"登录链路走不通"的真正原因之一
> （当时只归因为"校园内网不可达"，那条**依然成立**，但 WebView 侧是另一个独立故障）。

> **改动**：只动 `lib/pages/login/webview_login_page.dart`（`dart analyze lib` 通过，
> **未加新依赖**、未改 pubspec、未碰其他文件）。
>
> - 新增 `NavigationDelegate.onSslAuthError` → `_onSslAuthError(SslAuthError)`
> - 新增**顶层纯函数** `sslErrorHostToProceedOn({loginUrl, errorUrl})`：返回放行后允许的 host，
>   `null` = 拒绝。精确同 host / 互为子域才放行，`xjw1.ncst.edu.cn.evil.com` 这类
>   前缀伪装不匹配，解析不出 host 一律拒绝（fail closed）
> - 新增私有 `_hostOf(url)`：兼容绝对 URL 与裸主机名，统一小写去空白
> - `onWebResourceError` 日志补全为 `code / desc / type / mainFrame / url`，
>   且**子资源错误也打日志**（原先直接 return，等于丢掉线索）
> - 新增 `_sslProceedHost` 状态：放行后 Body 顶部显示黄色警告条
>   （`theme.warning` + `Icons.warning_amber_rounded`，文案"该网站使用了不受信任的证书（已放行）"），
>   并**抑制同一 host 紧随其后的 `onWebResourceError` 报错页**（放行后 WebView 常会为
>   同一次导航再报一次错，那时页面其实能用）；`onPageStarted` 重置
> - 私有字段 `_error` 更名 `_loadError`：`_onSslAuthError` 的参数名是 `error`，
>   原来的字段名会被遮蔽（可读性坑，不是 bug）
> - `_load()` / `_maybeFinish()` / `_collectCookieString()` / 构造签名**均未改动**
>   （4.1 已验收的契约保持不变）

> **⚠️ 任务书里的 API 在 4.14.1 不存在（重要，属"未经核实的技术前提"）**：
> 任务书给的是 `onReceivedSslError: (WebViewController controller, SslError error)`、
> `error.url` / `error.errorCode`。实测 **webview_flutter 4.14.1（本项目实际锁定版本）
> 的 `NavigationDelegate` 没有 `onReceivedSslError`，也没有 `SslError` 类型**——
> 那是 **4.15+** 才加的 API。4.14.1 的等价能力是
> **`NavigationDelegate(onSslAuthError: (SslAuthError error) => …)`**
> （`SslAuthError` 由 `webview_flutter` 直接导出，见 `lib/src/navigation_delegate.dart`，
> 内部把平台层的 `PlatformSslAuthError` 包起来，`proceed()` / `cancel()` 都转发）。
> 代价只有一个：**`SslAuthError` 不含 URL**，所以用 `controller.currentUrl()` 作为
> "出错页面地址"的等价信息源 —— 判定失败的代价只是**拒绝**，不会误放行别的域名。
> 之所以不去 cast `AndroidSslAuthError`（它**有** `url` 字段）拿 URL：
> 那要求把 `webview_flutter_android` 提为**直接依赖**（当前只是传递依赖），
> 违反本次"不加新依赖"的约束。
> **结论**：用框架层 API + `currentUrl()`，既有 host 限制又有诊断日志，
> 且零依赖改动。若将来升到 4.15+，可平滑换成 `onReceivedSslError` 并直接拿 `error.url`。

> **为什么不做弹窗确认**：自签证书是教务系统常态，每次登录都弹窗很烦；
> 本次做"**自动放行 + 警告条 + 日志**"。若要弹窗，在 `_onSslAuthError` 的放行分支前
> 插一个 `showDialog` 即可，纯函数判定不用动。

> **验证**：临时 `flutter test` 脚本 **19 组全部通过**，脚本已删除。覆盖：
> 放行（精确同 host / 带端口 / 带 query / 子域 / 反向子域 / 大小写与空白归一 /
> 登录 URL 带路径端口）、
> 拒绝（不同域名 / 兄弟域 `jwxt.other.edu.cn` / 前缀伪装 `xjw1.ncst.edu.cn.evil.com` /
> 后缀伪装 `evilncst.edu.cn` / 账号混淆 `xjw1.ncst.edu.cn@evil.com` /
> 登录 URL 为空·空白·`about:blank`·`https:///no-host` 时一律拒绝 /
> `errorUrl` 为空·相对路径时拒绝）、
> 裸主机名能识别（是登录 host 则放行、否则拒绝）、
> `isLoginSuccessUrl` 4 组回归、`WebViewLoginPage` 构造契约 2 组（必填 + 默认值、
> title/pluginId/key）、加载失败日志 5 个字段齐全、
> **源码钩子冒烟**（确实挂了 `onSslAuthError`、源码里 `proceed()` 只出现一次 =
> 不存在无条件放行路径）。

> **⚠️ 真实 SSL 错误无法在 `flutter test` 里覆盖**（两条硬原因）：
> ① `WebViewController()` 需要 `WebViewPlatform.instance`，测试环境为 `null` → 本页 pump 不起来；
> ② `SslAuthError` 的构造函数是私有的（`SslAuthError._fromPlatform`）→ 测试里造不出实例。
> 因此**只能真机验收**：真机上出现 `[WebViewLoginPage] SSL 错误放行: …` 即修复生效。

### Phase 4.2 备注（NCST 教务插件 + 同步接线）

> **Phase 4.2**：`dart analyze lib` 通过，**未加新依赖**，**未改 pubspec**
> （`assets/plugins/` 是**目录**声明，新增插件文件自动包含）。
>
> **改动**：
> - 新建 `assets/plugins/ncst-jwxt.js`：第一个真实插件
> - `lib/providers/plugin_provider.dart`：抽出通用 `installBuiltinPlugin(...)`；
>   新增常量 `kNcstPluginId` / `kNcstPluginAssetPath` 与 `installNcstPlugin()`；
>   `installExamplePluginForDemo()` 改为它的薄封装
> - `lib/pages/settings/plugin_manage_page.dart`：`+` 菜单新增「安装 NCST 教务插件」
> - `lib/pages/settings/plugin_detail_page.dart`：「立即同步」接真实逻辑（`_syncNow`）
>   + 常量 `kSyncJsTimeout = 5s`
>
> **NCST 具体 URL / 字段名只出现在 `ncst-jwxt.js` 里**，Dart 侧一个都没有（CONTEXT 3.1）——
> 可用 `grep -r "ncst\|xjw1" lib/` 自查（结果应为空）。
>
> **插件关键设计**：
> - 入口函数**只有 `fetchCourses`**：周次解析等工具函数放在 `__plugin` **外面**
>   （运行时会用 `Object.keys(__plugin).filter(typeof === 'function')` 收集入口函数，
>   放进去会被误报成入口）
> - **结构校验优先**：顶层非对象 / 是数组 / 缺 `dateList` / `dateList` 非数组 /
>   某项缺 `selectCourseList` → 一律 `{error:'响应结构异常：…'}`。
>   **宁可报错也不静默返回空数组**（空数组会被误当成"这学期没课"）
> - `dateList` 为**空数组**是合法的（真的没选课）→ 返回 0 门课
> - 节次时间失败**不影响课程**，只进 `warnings`（`data.sectionTime` 是 JSON 字符串，二次解析）
> - `ctx.cookie` 为空 → 直接 `{error:'未登录…'}`，**不发任何网络请求**
> - 全部 `ctx.http` 调用都包 `try/catch`，把异常转成 `{error}`（不 throw 污染结果）
>
> **JS 侧周次解析**：`__ncst_parseWeeks` / `__ncst_parseWeekType` 是 Dart 版
> `TimetableLogic.parseWeeks` / `parseWeekType` 的复刻，**24 组样本逐一对拍通过**。
>
> **验证**：临时 `flutter test` 脚本 **20 组全部通过**，脚本已删除。覆盖：
> 插件能被 `PluginRuntime` 加载、manifest 的 `loginUrl`/`checkUrl`/`capabilities`、
> `entries == ['fetchCourses']`、无 Cookie 时报"未登录"且不发请求、
> **规格响应下返回的 `{courses}` 能被 `Course.fromJson` 逐字段解析**
> （id/teacher trim/unit/category/sourcePluginId/两个 timePlace 的 day/startSession/length/
> room/rawWeeksText/weeks/weekType）、**两个接口各只真实调用一次**（证明重放去重）、
> **节次时间二次解析后落盘 `plugin_data`**（`"0830"→"08:30"`）、
> 节次时间失败只记 warning、
> **7 种响应结构异常各自给出可读 error**（HTML/缺 dateList/非数组/缺 selectCourseList/
> 顶层数组/HTTP 401）、空 dateList 合法返回 0 门、缺课程号的条目跳过并计 warning、
> **24 组样本 JS↔Dart 周次对拍**、单双周对拍、`installNcstPlugin` 安装并启用 + 重复安装不重复。
>
> **真机验证（⚠️ 卡在网络可达性，需人工介入）**：Redmi K60
> （`getprop ro.product.model` = `2211133C`，Android 16 / arm64-v8a）。
> 日志：
> ```
> [NCST-VERIFY] 安装=true isUsable=true entries=[fetchCourses]
> [NCST-VERIFY] loginUrl=https://xjw1.ncst.edu.cn/
> [NCST-VERIFY] checkUrl=https://xjw1.ncst.edu.cn/student/courseSelect/courseSelectResult/index
> [NCST-VERIFY] 无Cookie: status=success value={"error":"未登录：Cookie 为空，请先点「登录」完成教务系统登录"}
> [Plugin:ncst-jwxt] 第 1 轮登记了 1 个 HTTP 请求，取回后重放
> [Plugin:ncst-jwxt] HTTP GET https://xjw1.ncst.edu.cn/... 失败：DioExceptionType.connectionError
> [NCST-VERIFY] 假Cookie: status=success value={"error":"拉取课程列表失败：connection"}
> [NCST-VERIFY] Hive 课程数=3
> ```
> **结论与卡点**：
> - ✅ **安装成功、插件可用、入口函数正确、manifest 正确**
> - ✅ **无 Cookie 时命中插件侧守卫且不发网络**（符合设计）
> - ✅ **假 Cookie 时真的发出了 HTTPS 请求到真实主机**（走了完整重放链路），
>   且失败被优雅转成 `{error}`、**没有崩溃**
> - ❌ **连接失败：`connectionError`**。排查后确认是**网络不可达，不是代码问题**：
>   - `xjw1.ncst.edu.cn` 解析到 **`172.20.13.4`（校园内网地址，RFC1918）**
>   - 本机（在校园网内）TCP 443 可达 ✅
>   - 手机在 `192.168.137.196`（**PC 的热点**，ICS 网段），`ping 172.20.13.4` **100% 丢包** ❌，
>     而同一次 `ping example.com` 正常 ✅（说明手机本身有网）
> - **因此"登录 → 同步 → Hive 落盘 → 课表渲染"这四步我无法在本次环境验证**，
>   需要：① 手机连**校园 WiFi 或校园 VPN**；② **人工输入学号密码**（我没有凭据，也不该有）。
>
> **临时改动已还原**：`lib/main.dart` / `lib/app.dart` 的验证脚手架已用
> `git checkout HEAD --` 恢复，`git diff` 为空。

### Phase 4.1 备注（WebView 登录页 + Cookie 提取）

> **Phase 4.1**（通用 WebView 登录页 + Cookie 提取）：`dart analyze lib` 通过，**未加新依赖**。
>
> **改动**：
> - 新建 `lib/pages/login/webview_login_page.dart`：`WebViewLoginPage` +
>   顶层纯函数 `isLoginSuccessUrl`
> - 新建 `lib/services/cookie_service.dart`：`CookieService`（save / load / clear / formatCookies）
> - `lib/runtime/plugin_manifest.dart`：新增 **`loginUrl` / `checkUrl`**（见下）
> - `lib/runtime/plugin_runtime.dart`：`_deriveManifest` 从 `__plugin` 里一并推导这两个字段
> - `lib/pages/settings/plugin_detail_page.dart`：「登录」从 SnackBar 占位改为
>   push 真实登录页（`_openLogin`）
>
> **`loginUrl` / `checkUrl` 放在 `PluginManifest` 而不是 `PluginMeta`**（任务书让判断）：
> `PluginMeta` 存在 Hive 里、受 CONTEXT 4.2.1 约束，加字段要写迁移；而
> **`PluginManifest` 是运行时从插件 JS / `.manifest.json` 解析出来的、根本不落盘**，
> 所以加字段**零迁移成本**。而且这正是任务书说的"从插件的 manifest 读"，
> Phase 4.2 的 NCST 插件只需在 `__plugin` 里写两个字段即可。
>
> **5 个设计决策**：
> 1. **登录成功判定：URL 前缀匹配为主（方案 A）**，理由：通用、不需要知道任何学校的
>    页面结构、失败模式可预期。**fallback 是"Cookie 出现"（方案 C）**——当
>    `successUrlPrefix` 为空串时，退化为"拿到非空 Cookie 即视为成功"。
>    **明确不用方案 B（页面元素）**：它需要学校特定的 CSS 选择器，会违反"通用组件"约束。
>    另加一条规则：**URL 命中但 Cookie 为空不算成功**（没有凭证的"成功"没有意义）。
> 2. **Cookie 提取用官方 `WebViewCookieManager.getCookies(domain:)`**（webview_flutter
>    4.14.1 **已有**该 API），**未加新依赖**。同时查登录页域名与当前页域名并合并。
>    ⚠️ **能否拿到 HttpOnly Cookie 待真机确认**，见阻塞表。
> 3. **存储格式** `name1=value1; name2=value2`（HTTP 头标准写法），key = `<pluginId>:cookie`
>    —— 插件侧可直接 `ctx.http.get(url, { Cookie: ctx.cookie })`。
> 4. **用户取消** → `pop(null)`，不写任何东西、不做破坏性操作。
> 5. **登录 URL 来源**：构造函数参数（由调用方传入）；Phase 4.2 起由插件的
>    `__plugin.loginUrl` 提供。
>
> **验证**：临时 `flutter test` 脚本 **26 组全部通过**，脚本已删除。覆盖：
> `isLoginSuccessUrl`（命中 / 未命中 / 域名不同 / 空前缀恒 false / 两侧空白）、
> `PluginManifest` 的 `loginUrl`/`checkUrl`（缺键回落空串、JSON 往返、`tryDecode`、
> **真实沙箱里从 `__plugin` 推导出来**、未声明时为空串）、
> `CookieService.formatCookies`（正常拼接 / 同名后者覆盖 / 空列表 / 跳过空名与含 `;`、换行的值 /
> 空值合法 / 分隔符是 `"; "`）、
> `CookieService` 存取（save→load 往返、未登录返回空串、clear、空串等价清除、
> **不同插件互不干扰**、**存储 key 确为 `<pluginId>:cookie`**）、
> `WebViewLoginPage` 构造契约（字段与默认值 / 可传 title 与 pluginId / 空前缀合法）、
> 详情页「登录」：**未声明 loginUrl → SnackBar 且不跳转**、「立即同步」仍是占位、
> 端到端（插件声明的 `checkUrl` 直接喂给 `isLoginSuccessUrl`，含 JSON 往返后仍可用）。
>
> **测试注意（新增）**：
> ① `WebViewLoginPage` **无法在 `flutter test` 里 pump**——`WebViewController()` 需要
> `WebViewPlatform.instance`（测试环境为 null），所以只测纯函数与构造契约，真实加载只能真机验证；
> ② `flutter_secure_storage` 用官方测试替身 `FlutterSecureStorage.setMockInitialValues`，
> 这样 save/load 往返是真的（不 mock 的话 `MissingPluginException` 会让读回空串）；
> ③ 详情页较长，默认 800×600 视口下「登录」点不到（`tap` 会报 hit-test 警告），需高视口。
>
> **真机验证（✅ 已完成）**：Redmi K60（`adb shell getprop ro.product.model` 原始输出 =
> `2211133C`，Android 16 / arm64-v8a）。为了一次性回答两个关键未知，临时在**应用内**起了一个
> 本机 HTTP 登录服务（`/login` → 302 → `/index`，并在 `/index` 同时下发一个普通 Cookie 与一个
> **HttpOnly** Cookie），并把 `WebViewLoginPage` 推起来。
>
> **阶段 1：本机 HTTP（含 HttpOnly）—— 完全通过**：
> ```
> [LOGIN-VERIFY] 本机服务收到 GET /login
> [LOGIN-VERIFY] 本机服务收到 GET /index
> [WebViewLoginPage] 提取到 2 个 Cookie，拼接后 29 字符
> [WebViewLoginPage] 已保存 example-plugin 的 Cookie（29 字符）
> [LOGIN-VERIFY] 阶段1 返回="normal=xyz; JSESSIONID=ABC123"
> [LOGIN-VERIFY] 阶段1 落盘 Cookie="normal=xyz; JSESSIONID=ABC123"
> ```
> **★ 结论：`WebViewCookieManager.getCookies` 能拿到 HttpOnly Cookie**（`JSESSIONID` 就是
> HttpOnly 的）——**不需要引入第三方 cookie 包**，阻塞表那条已关闭。
> 同时验证了：302 跳转跟得上、URL 前缀命中、Cookie 拼接格式正确、
> **落盘到 `flutter_secure_storage` 成功**（`CookieService.loadCookie` 读回一致）、
> 且插件侧 `ctx.cookie` 会读到同一个值（两边共用 `:cookie` 后缀）。
>
> **阶段 2：公网 HTTPS**：
> ```
> [WebViewLoginPage] 提取到 0 个 Cookie，拼接后 0 字符
> [WebViewLoginPage] URL 已匹配前缀但未拿到 Cookie，继续等待：https://example.com/
> ```
> HTTPS 页面**加载正常**、前缀匹配生效；`example.com` 不下发 Cookie，所以按规则
> **没有误判成功**（这正是"URL 命中但 Cookie 为空不算成功"那条规则在起作用）。
>
> **⚠️ 另一次运行（未开 cleartext）暴露了一个真实风险**：WebView 打开 `http://` 地址时
> ```
> [WebViewLoginPage] 加载失败：-1 net::ERR_CLEARTEXT_NOT_PERMITTED
> ```
> 即 **targetSdk 34 默认禁止明文 HTTP**，而**不少学校教务仍是 http://** ——
> 若是，WebView 登录与 `ctx.http` 都会被系统拦掉。已记入阻塞表，待 Phase 4.2
> 拿到真实教务地址后用 `networkSecurityConfig` 定向放行（**不推荐**全局
> `usesCleartextTraffic`）。顺带说明：本次验证为了访问本机 http 服务，
> **临时**在 `android/app/src/debug/AndroidManifest.xml` 开了 cleartext，
> **验证完已还原**（只影响 debug、从未进 release）。
>
> **临时改动已全部还原**：`lib/main.dart`、`lib/app.dart`（本机服务 + 登录页脚手架）与
> `debug/AndroidManifest.xml` 都用 `git checkout HEAD --` 恢复，`git diff` 为空。

---

## Phase 5：课表渲染 + 编辑（✅ 完成）

> 说明：Phase 5 原计划里的"课表渲染"与"详情弹层"在 Phase 2.2b 就提前做完了
> （见 Phase 2 备注），所以本阶段实际只做**编辑 / 删除 / 隐藏**。

- [x] `lib/widgets/timetable_grid.dart`（网格布局）—— Phase 2.2b 提前完成
- [x] 课程详情底部弹层 —— Phase 2.2b 提前完成
- [x] `lib/pages/edit/course_edit_page.dart` —— Phase 2.2c.2 建页，**Phase 5 加编辑模式**
- [x] 添加/编辑/删除课程 —— **Phase 5**：编辑 + 删除（自建）+ 隐藏（教务）
- [x] 覆盖层生效 —— **Phase 5**：编辑教务课程写覆盖层，原始数据不动
- [x] **`lib/pages/settings/hidden_courses_page.dart`**（Phase 5 计划外）：
      隐藏的配套恢复入口——没有它，"隐藏"对用户就等同于删除

> 自验证：`dart analyze` 全绿 + 临时脚本 12 组 + widget 测试 6 组 + Windows 桌面实跑。
> 详见上方 **Phase 5 备注**。

---

## Phase 6：创意工坊 + 皮肤（✅ 完成）

- [x] SkinPack 模型接入 —— Phase 1.1 已有，Phase 6 起真正被使用
- [x] ThemeEngine 加载皮肤 —— Phase 1.2 已有；**Phase 6 加明暗合成与"记住皮肤"**
- [x] `lib/pages/settings/skin_preview_page.dart` —— **Phase 6 新建**
- [x] 下载 / 应用 / 切换皮肤 —— **Phase 6**：应用 / 切换 / 恢复默认 / 撤销
- [ ] ~~GitHub 索引拉取~~ —— **有意不做**，理由见 Phase 6 备注
- [x] **`lib/theme/default_skins.dart`**（计划外）：4 套内置皮肤
- [x] **`assets/skins/sunset.skin.json`**（计划外）：随包皮肤 + 格式示例
- [x] **暗色模式真实现**（计划外，Phase 6 补完）：`withBrightness` 真实推导 +
      亮色/暗色/跟随系统三态

> 自验证：`dart analyze` 全绿 + 临时脚本 28 组 + widget 测试 10 组 + Windows 桌面实跑。
> 详见下方 **Phase 6 备注**。

---

### Phase 6 备注（皮肤系统 / 创意工坊 / 暗色模式）

> **目标**：把 Phase 1 就搭好骨架但一直没接线的皮肤系统跑通——
> 创意工坊从空态变成能选、能预览、能应用；暗色模式从"返回 `this` 的空实现"
> 变成真能用的东西。

> **验证状态（自验证，未用实体机）**：
> - ✅ `dart analyze`（整包）→ `No issues found!`
> - ✅ 临时脚本 **28 组全部通过**：
>   - 明暗推导 9 组：背景确实变暗、正文比背景亮、卡片比背景略亮（有层次）、
>     强调色**一律保留**（皮肤色相不变）、课程卡片配色池也变暗、
>     暗色阴影更明显、非颜色令牌不受影响、`onPrimary` 恒为黑或白
>   - 内置皮肤 3 组：4 套、id 唯一、必备令牌齐全
>   - 三态与合成 10 组：默认跟随系统、`themeMode` 解析、
>     `system` 跟随/非 `system` 忽略、应用皮肤后主色变化、暗色用暗色表、
>     **切明暗不丢皮肤**、`mode:dark` 皮肤强制暗色、`resetTheme`、
>     `previewSkin` 不改状态、`decodeBrightness` 旧语义
>   - 持久化 6 组（真实 Hive）：mode 往返、皮肤 id 往返 + 恢复、
>     **皮肤不见了会静默回默认并清记录**、旧数据（只有 light/dark）可读、坏值不崩
> - ✅ 临时 **widget 测试 10 组全部通过**：创意工坊皮肤列表（4 套 + 按钮）、
>   应用后"使用中/正在使用/恢复默认"、预览跳转不改状态、插件 Tab 空态、
>   预览页三段内容 + 取消不改状态 + 应用生效（暗色偏好下用暗色表）、
>   设置页显示当前偏好与皮肤名、明暗弹层三个选项 + 系统亮度说明
> - ✅ **Windows 桌面实跑**：`flutter build windows --debug` 成功，启动无异常，
>   **无皮肤加载报错**（说明 `assets/skins/` 的目录级声明与 `AssetManifest` 读取正常）

> **改动清单**：
>
> | 文件 | 改动 |
> |------|------|
> | `lib/theme/app_theme.dart` | `withBrightness` **真实实现**（推导另一套明暗配色）+ 8 个公开常量 + 3 个私有颜色助手 |
> | `lib/theme/theme_engine.dart` | 记住当前皮肤、`setBrightness`、`_compose`（合成两步）、色表选择纳入 `mode` |
> | `lib/theme/default_skins.dart` | **新建**：4 套内置皮肤 + 8 个令牌名常量 |
> | `lib/providers/theme_provider.dart` | `ThemeBrightnessMode` 三态、`themeMode`、`_resolvedBrightness`、`restoreStoredSkin`、`loadAssetSkins`、皮肤 id 落盘 |
> | `lib/services/storage_service.dart` | 新增 `kThemeSkinIdKey` |
> | `lib/app.dart` | 改 `StatefulWidget`：`didChangePlatformBrightness`、`theme`/`darkTheme`/`themeMode`、显式 `brightness` 的 `ColorScheme` |
> | `lib/main.dart` | 启动时 `restoreStoredSkin()` |
> | `lib/pages/settings/workshop_page.dart` | 重写：皮肤列表（内置 + assets）、色板、应用/预览、当前状态、插件 Tab |
> | `lib/pages/settings/skin_preview_page.dart` | **新建**：局部 `Theme` 套用候选皮肤，课表/组件效果预览，应用/取消 |
> | `lib/pages/settings/settings_page.dart` | 外观分组两行接真实数据 + 明暗三选一弹层 |
> | `pubspec.yaml` | 声明 `assets/skins/`（目录级） |
> | `assets/skins/sunset.skin.json` | **新建**：随包皮肤 + 皮肤格式示例 |

> **🔑 最关键的设计决定：暗色配色是"推导"出来的，不是写死的常量**
>
> 皮肤只提供一套（或明暗两套）色表。如果 `withBrightness` 里写死一套暗色常量，
> **皮肤的颜色就会被常量覆盖掉——那就不叫皮肤了**。
> 所以实现是从已有令牌**推导**：保留色相、只调明度。
> 效果：蓝色皮肤暗色下还是蓝的，抹茶皮肤暗色下还是绿的，而
> 背景深 / 文字浅 / 卡片分层的明暗关系始终正确。
>
> 被推导的只有"明暗相关"的令牌（背景、表面、前景、课程卡片、阴影）；
> **强调色（primary/secondary/error/success/warning）一律不动**——
> 那是皮肤的身份。

> **⚠️ 有意不做的两件事（不是遗漏）**：
>
> 1. **GitHub 远程皮肤索引**：原计划写的是"GitHub 索引拉取"。
>    要落地就得在**内核里硬编码一个仓库地址**，而那个仓库并不存在——
>    写进去就是一条永远返回失败的代码路径，还会让"创意工坊"看起来像坏了。
>    取而代之的是**两条真实可用的皮肤来源**：代码内置 4 套 + `assets/skins/`
>    目录（新增皮肤文件**不用改代码、不用改 pubspec**，与 `assets/plugins/` 同一约定）。
>    将来真有了索引仓库，`SkinPack.fromJson` 已经就绪，
>    只需加一个"下载 → 存 → 走同一套解析"的服务，UI 不用改。
> 2. **`AppThemeExtension.lerp` 仍是返回 `this`**：明暗/皮肤切换是瞬时的，
>    没有渐变过渡。正确插值要逐字段处理 30 个令牌（含 `List<Color>`），
>    收益只是"切换时有淡入"，优先级低于功能本身。

> **🐛 本阶段实测抓到的 3 个真实 bug**（都是"写了测试才暴露"的类型）：
>
> 1. **`mode: 'dark'` 的皮肤在亮色偏好下变成了亮色**。`_compose` 无条件用
>    用户偏好去 `withBrightness`，把皮肤声明的暗色又推回亮色。
>    修法：`_effectiveBrightnessFor(skin)` —— 皮肤 `mode` 优先于用户偏好。
> 2. **`saveToStorage` 写的是引擎的 id 而不是用户的皮肤 id**。
>    `resetTheme()` 清的是 `_skinId` 字段，但落盘读的是 `_engine.currentSkinId`，
>    于是"恢复默认"之后又把旧皮肤 id 写了回去 → 重启后皮肤回来了。
>    修法：落盘只用 `_skinId` 字段。
> 3. **`restoreStoredSkin` 清记录时是 fire-and-forget**，
>    调用方（`main`）与测试都无法确定它写完了。修法：改成 `await`。
>    （这条是"竞态"而不是"错误"，但同样会让行为不可预测。）

> **暗色模式的行为约定**：
> - **默认"跟随系统"**（不是默认亮色）——这是绝大多数用户的期望
> - 系统切换深色时通过 `MyApp.didChangePlatformBrightness` +
>   `syncSystemBrightness` 立刻生效（非 `system` 模式不受影响）
> - `ColorScheme.fromSeed` 的 `brightness` 必须**显式传**，
>   不能用 `theme.brightness` 推断：否则"暗色模式 + 亮色皮肤"会得到一个
>   声明亮色、实际配深色文字的 `colorScheme`，对话框 / SnackBar 的默认配色就会错
> - `scaffoldBackgroundColor` 显式取自主题令牌，避免 Material 默认背景
>   在暗色下与 `theme.background` 不一致（页面切换时会闪一下白）


---

## Phase 7：通知 + 消息（✅ 完成，系统通知除外）

- [ ] `lib/services/notify_service.dart` —— **有意不做**，理由见 Phase 7 备注
- [x] 消息模块接入真实数据 —— **Phase 7**：Hive 持久化 + 列表 UI + 已读/删除
- [x] `MessageProvider` 落盘（计划外但必需）：CONTEXT 3.5 早就规定消息存 Hive，
      而它在此之前一直是**纯内存**，重启即丢
- [x] `ctx.notify.schedule` 落地为**站内消息**（计划外）：之前只打一行日志
- [x] 同步结果沉淀成消息（计划外）：SnackBar 一闪而过，消息页能回头查

> 自验证：`dart analyze` 全绿 + 临时脚本 22 组（含真实 Hive + widget 测试）+
> Windows 桌面实跑。详见下方 **Phase 7 备注**。

---

### Phase 7 备注（消息模块接真实数据）

> **目标**：`ctx.notify` 从"只打日志"变成用户真的能看到；消息模块从空态变成可用。

> **验证状态（自验证，未用实体机）**：
> - ✅ `dart analyze`（整包）→ `No issues found!`
> - ✅ 临时脚本 **22 组全部通过**：
>   - `Message.fromSyncReport` 文案 6 组：成功有变化 / 无变化 / 0 门课（说"没课"而不是失败）/
>     失败带原因与尝试次数 / 跳过与用户修改与警告都体现 / **同秒调用 id 相同**（重试不刷屏）
>   - 内存语义 2 组：倒序 + 未读计数 + 全部已读、同 id 覆盖
>   - **Hive 持久化 9 组**：落盘后重建能读回（含已读状态）、删除同时清存储、
>     全部已读落盘、**过期消息载入时被丢弃并清出 Box**、
>     `clearOldMessages` 同时清两边、`clearAll`、
>     坏数据跳过不影响整次载入、**没有 id 的消息视为坏数据**
>   - 插件 notify 适配 1 组：字段与 JSON 往返
>   - **MessageView widget 测试 5 组**：空态、列表 + 未读计数 + 点卡片标已读、
>     全部已读按钮、**左滑删除**、不同类型显示不同标签与图标

> **改动清单**：
>
> | 文件 | 改动 |
> |------|------|
> | `lib/providers/message_provider.dart` | Hive 读写（`loadFromStorage` / `*Persisted` / `clearAll`）、`isLoaded`、载入时清过期 |
> | `lib/pages/message/message_view.dart` | 重写：真实列表、未读高亮、全部已读、左滑删除、下拉刷新 |
> | `lib/models/message.dart` | `Message.fromSyncReport` 工厂 |
> | `lib/runtime/plugin_context.dart` | `PluginNotifyHandler` + `onNotify`，`_emitNotifies` 真正落地 |
> | `lib/runtime/plugin_runtime.dart` | 透传 `onNotify` |
> | `lib/providers/plugin_provider.dart` | 接 `onNotify` 并用它构造 `PluginRuntime` |
> | `lib/services/course_sync_service.dart` | `SyncReportCallback` + `sync({onReport})`（拆出 `_sync` 以便统一回调） |
> | `lib/pages/settings/plugin_detail_page.dart` | 同步结果写成消息 |
> | `lib/pages/timetable/timetable_view.dart` | 同上（课表页同步入口） |
> | `lib/main.dart` | 接 `MessageProvider`（预加载 + 传进 `buildApp`）、插件 notify → 消息 |

> **⚠️ 有意不做：系统通知（`flutter_local_notifications`）**
>
> 原计划的 `notify_service.dart` 需要 `flutter_local_notifications ^16.3.0`——
> 它出现在 CONTEXT 技术栈表里，**但 `pubspec.yaml` 里从来没有**，代码也从未用过。
> 而 CONTEXT 第 6 节禁止"引入未在本文档技术栈中声明的依赖"。
>
> 判断：**加依赖是架构决定，应该由项目所有者批准**，不该由我在"自主推进"里顺手做掉。
> 所以本阶段把 `ctx.notify` 落地为**站内消息**——用户已经真的能看到，
> 只是"App 不在前台时弹不出来"。要补系统通知，只需：
> ① `pubspec.yaml` 加依赖（CONTEXT 表已列，属"已声明但未安装"）；
> ② 新建 `NotifyService`，把 `main.dart` 里那个 `onNotify` 回调改成
>    "写消息 **+** 排系统通知"两件事。**其余代码不用动**。

> **`onReport` 回调为什么要拆出 `_sync`**：
> `sync()` 原本有 7 个 `return`（成功 / 各类失败 / 重试耗尽 / 兜底）。
> 如果逐个 `return` 前加回调，**必然会漏掉某条失败路径**。
> 所以把主体拆成 `_sync()`，`sync()` 只做"调用 + 统一回调 + 返回"——
> 结构上保证不可能漏。

> **消息 id 的幂等设计**：
> - 同步消息：`sync_<pluginId>_<秒级时间戳>`。`CourseSyncService` 会重试，
>   但重试都在同一次点击内（同一秒），所以只得到一条消息而不是三条。
> - 插件通知：`notify_<pluginId>_<triggerAtIso>`。插件入口函数会被执行多次
>   （CONTEXT 3.6），但 `ctx.notify` 的副作用**只在最终轮提交**，
>   加上同 id 覆盖，双保险。

> **`clearOldMessages` 从"纯内存"改成"同时落盘"**：
> 原来只从内存删——**下次启动过期消息又从 Box 读回来了**。
> 顺手把 `loadFromStorage` 也改成"载入时直接丢弃过期的并清出 Box"，
> 这样历史数据不会一直堆着。

- [ ] WorkManager 定时任务
- [ ] 上课/考试/作业提醒

---

## Phase 8：学习通插件（✅ 完成，真机验收通过）

- [x] 学习通登录 —— 复用 Phase 4.1 的通用 `WebViewLoginPage`；
      登录地址与成功判定由插件声明（`loginUrl` / `checkUrl`），内核不硬编码
- [x] 课程列表抓取（`fetchCourseList`）—— 供"勾选要抓哪几门课"用，**不落盘**
- [x] 作业拉取（`fetchHomeworks`，**含正文题目**）
- [x] 考试拉取（`fetchExams`）
- [x] 作业模块激活 —— `HomeworkProvider` + `homework_view.dart` 接真实数据
- [x] 考试模块接真实数据 —— `ExamProvider` + `exam_view.dart`
- [x] "按课程勾选后抓取"页（作业 / 考试共用一个页面）
- [x] 插件安装入口（插件管理页 `+` 菜单）
- [x] 真机验收 —— **2026-10-16 在小米 13（Android 16 / HyperOS V816）上通过**：
      登录 → 自动返回并保存 Cookie（19 个 / 1231 字符）→ 课程列表 68 门 →
      作业同步（含正文）→ 落盘 `homeworks.hive`。详见下方"真机实测"小节
- [ ] 定时自动同步（WorkManager）
- [ ] 作业 / 考试提醒（依赖系统通知）

> 自验证：`flutter analyze` 全绿 + `flutter test` **29 组全部通过** +
> `node --check` 插件语法 + **真实账号端到端跑通**。详见下方 **Phase 8 备注**。

---

### Phase 8 备注（学习通插件 + 作业/考试内核接线）

> **目标**：用户能"先爬取所有课程 → 勾选 → 抓取作业与考试 → 在 App 里看到
> 作业正文与截止时间"。

> **验证状态（已在真实账号上跑通，未用真机 App）**：
> - ✅ `flutter analyze`（整包，含 `test/`）→ `No issues found!`
> - ✅ `flutter test` → **29 组全部通过**（`test/chaoxing_kernel_wiring_test.dart`）
> - ✅ `node --check assets/plugins/chaoxing.js` 语法通过
> - ✅ **真实账号端到端**（`tools/chaoxing/test-plugin.js`，浏览器内驱动）：
>   - `fetchCourseList` → **68 门课程**，2 轮重放
>   - `fetchHomeworks`（含正文）→ 1 份作业、**9 题正文**、截止 `2026-10-18T23:29`，
>     5 轮重放（上限 8，余量充足）
>   - `fetchExams` → 1 场考试 `2026-09-18 09:00 ~ 2027-01-08 16:00`，3 轮重放
> - ✅ **UI 渲染佐证**（用**真实插件返回值**做夹具渲染，非手绘）：
>   `docs/verify/8-homework-list.png`（作业列表，含"还剩 2 天"倒计时）、
>   `docs/verify/8-homework-detail.png`（详情弹层，**9 题正文完整渲染**）、
>   `docs/verify/8-exam-list.png`（考试列表，含"已开考"状态）。
>   渲染脚本是**临时文件**（跑完即删）——golden 截图依赖系统字体与渲染后端，
>   换机器必然失败，不适合进 CI；真正的回归保障是那 29 组单元测试。

> **改动清单**：
>
> | 文件 | 改动 |
> |------|------|
> | `assets/plugins/chaoxing.js` | **新增**。三个入口 + 一套解析工具；学习通 URL / 字段名只在这里 |
> | `lib/models/plugin_course_ref.dart` | **新增**。插件课程引用（**不透明对象**，内核不认识学校字段） |
> | `lib/services/plugin_entity_sync_service.dart` | **新增**。列表型实体的通用同步（重试 / 归类 / 增量落盘），作业与考试共用 |
> | `lib/providers/homework_provider.dart` | **新增**。Hive 读写 + 覆盖层保留 + 展示排序 |
> | `lib/providers/exam_provider.dart` | **新增**。同上（按开考时间排序） |
> | `lib/pages/sync/plugin_entity_sync_page.dart` | **新增**。"勾选课程 → 抓取"页，作业/考试共用 |
> | `lib/pages/homework/homework_view.dart` | 空态骨架 → 真实列表 + 详情弹层 + 抓取入口 |
> | `lib/pages/exam/exam_view.dart` | 空态骨架 → 真实列表 + 详情弹层 + 抓取入口 |
> | `lib/models/exam.dart` | 新增 `note` / `courseName` 字段与 `displayNote` |
> | `lib/models/message.dart` | `Message.fromSyncReport` 新增 `itemLabel` / `itemUnit`（默认值不变，课程文案零变化） |
> | `lib/providers/plugin_provider.dart` | `firstEnabledWithCapability` / `firstUsableWithCapability` / `installChaoxingPlugin` |
> | `lib/pages/settings/plugin_manage_page.dart` | `+` 菜单加"安装学习通（超星）插件" |
> | `lib/main.dart` | 注册两个新 Provider + 启动时载入 |
> | `test/chaoxing_kernel_wiring_test.dart` | **新增**。项目首个测试文件，用**真实插件输出**做夹具 |
> | `tools/chaoxing/` | **新增**（开发工具，非交付物）：Playwright 会话、重放机制模拟器 |
> | `docs/chaoxing-api.md` | **新增**。接口测绘（7 节，含参数必要性实验与踩坑） |

> **关键技术结论**：
>
> 1. **重放机制决定插件写法**：`ctx.http` 是"登记待办 + 宿主重放"，入口函数会
>    被执行多次（上限 `kMaxReplayRounds = 8`）。因此每个入口都必须**先批量登记
>    同一层的请求、再统一检查**——写成"循环里请求完立刻用结果"会让每轮只推进
>    一个请求，勾 5 门课就超轮数。本插件最深 5 轮。
> 2. **`enc` / `openc` 是"每门课"的，不是账号级的**：必须从课程主页 HTML 里
>    抠出完整 URL，手工拼参数会漏 `openc` 而被判无权限
>    （`[3003] 您长时间没有操作，或没有此页面访问权限`）。
> 3. **作业正文是 4 级链路**：课程主页 → 作业列表（拿 `enc`）→ `isExpire`
>    （拿 `standardEnc`）→ `doHomeWorkNew`（正文）。少任何一级都拿不到题目。
> 4. **学习通有反爬**：实测 12 秒内 136 个请求触发
>    `【9010】操作异常，请输入图片中的验证码`。因此内核侧**只抓用户勾选的课程**、
>    严格串行、超过 5 门就在界面上警告。
> 5. **内核不知道学校字段**（CONTEXT 3.1）：`PluginCourseRef` 把插件给的课程对象
>    当作**不透明 Map** 原样存、原样回传，内核只读 `id` / `name` / `teacher` /
>    `className` 四个约定展示字段（缺失即空串，不影响功能）。
> 6. **覆盖层内联存储**：课程的覆盖层在独立的 `overrides` Box（由 `OverrideEngine`
>    管），作业 / 考试**内联在各自的 JSON 里**。原因是 `overrides` Box 的键空间是
>    "课程 ID"，而作业 / 考试 ID 与课程 ID 都可能形如 `chaoxing:<数字>`，
>    共用会撞号（表现为"改作业勾选把课程颜色改了"）。
> 7. **`PluginEntitySyncService` 而不是泛型化 `CourseSyncService`**：两者共享 90%
>    流程，但课程有 `sectionTimes` / `allUnits` 两个回传字段。选"抽出通用服务、
>    课程服务一行不改"，避免动 Phase 4.3 已交付且带测试的代码。
> 8. **模拟器抓到一个真 bug**：`__cx_splitLi` 原先按 `/<li[^>]*>/` 切块会**丢掉
>    起始标签**，而 `class="courseItem"` / `class="inspectTask"` 恰好写在标签上 →
>    一个都匹配不到。改为捕获标签并保留（并加 `(?:\s[^>]*)?` 避免误匹配 `<link>`）。

> **未做（有意）**：
> - **考试链路的真机验收**：真机上作业链路已完整跑通，但 `fetchExams`
>   还没在真机上点过（桌面已验证 3 轮重放返回 1 场考试）。预计风险很低——
>   它和作业走同一套 `ctx.http` / 重放 / 落盘管线，且不再有登录障碍。
> - **定时同步 / 作业提醒**：依赖 WorkManager 与系统通知，属 Phase 7 的遗留
>   （系统通知有意未做），本阶段不引入。
> - **插件文件导入**：仍然只有"内置插件 + 创意工坊"两条安装路径。
> - **`tools/chaoxing/` 的脚本部分入库**（重放机制模拟器 `test-plugin.js` 等），
>   但**抓取产物一律 ignore**——`courses.json` / `out/` / `raw-*.html` 是
>   真实账号的个人数据（同学姓名、课表、作业正文），`.profile/` 是登录态。

---

### Phase 8 真机实测（2026-10-16，小米 13 / Android 16 / HyperOS V816）

> **结论：主链路通过，且真机暴露了 2 个桌面永远测不出来的 bug。**
>
> 环境：设备 `2211133C`（小米 13），Android 16 / API 36，arm64-v8a，1080×2400 @440dpi。
> 构建：`flutter build apk --debug --target-platform android-arm64` → `adb install -r -t`。

> **实测日志原文（adb logcat）**：
> ```
> [WebViewLoginPage] 提取到 19 个 Cookie，拼接后 1231 字符
> [WebViewLoginPage] 已保存 chaoxing 的 Cookie（1231 字符）
> [Plugin:chaoxing] 第 1 轮登记了 1 个 HTTP 请求，取回后重放
> [Plugin:chaoxing] 学习通：解析出 68 门课程
> [PluginEntitySyncService] chaoxing 列出 68 门课程
> [Plugin:chaoxing] 第 1 轮登记了 2 个 HTTP 请求，取回后重放
> [Plugin:chaoxing] 第 2 轮登记了 2 个 HTTP 请求，取回后重放
> [Plugin:chaoxing] 第 3 轮登记了 1 个 HTTP 请求，取回后重放
> [Plugin:chaoxing] 第 4 轮登记了 1 个 HTTP 请求，取回后重放
> [Plugin:chaoxing] 学习通：解析出 1 份作业（含正文）
> [PluginEntitySyncService] chaoxing 作业同步完成：新增 1、更新 0、未变 0、跳过 0
> ```
> 落盘佐证：`homeworks.hive` 0 → 1391 字节；安全存储出现 `chaoxing:cookie`；
> `messages.hive` 出现同步报告消息。**作业页在真机上显示真实作业（第一章作业，9 题正文）。**

> **真机暴露的 2 个 bug（均已修复 + 回归测试）**：
>
> | # | 现象 | 根因 | 修复 |
> |---|------|------|------|
> | 1 | 登录后显示「页面加载失败」 | 学习通登录成功后 **302 到 `http://i.mooc.chaoxing.com/`（明文 HTTP）**，被 Android 网络策略拦成 `net::ERR_CLEARTEXT_NOT_PERMITTED`。**此前"学习通全是 https"的推测被证伪**——这类平台策略只有真机能暴露，桌面浏览器不受它约束 | `network_security_config.xml` 白名单追加 `chaoxing.com`（`includeSubdomains`）。仍是定向放行，`base-config` 保持 `false` |
> | 2 | （修完 1 后会撞上）登录成功但页面不自动返回 | `isLoginSuccessUrl` 用 `startsWith` 字面匹配，插件声明 `checkUrl=https://...`，实际落地是 `http://...`，**scheme 不同导致永远匹配不上**；且因为没走到成功分支，Cookie 也不会落盘 | 改为 **scheme 不敏感**：先原样比，不中再剥掉 `http(s)://` 比一次。只匹配开头，`https://evil.com/?next=https://i.mooc...` 不会误判 |
>
> 附加改进：`loadErrorHint()` 把 WebView 的英文报错翻译成"该改哪里"的人话
> （如明文被拦会直接提示去改 `network_security_config.xml`）。
> 回归保障：新增 `test/webview_login_success_test.dart`，共 18 组；
> `flutter analyze` 无问题、`flutter test` **47 组全部通过**。

> **真机验收的元教训**：`docs/chaoxing-api.md` 是用桌面浏览器（Playwright）测绘的，
> 那份记录里"登录后跳转 https://i.mooc.chaoxing.com/space/index"是对的，
> 但**没有记录中间那跳 302 落在 http**——桌面浏览器不会套用 Android 的网络策略，
> 所以根本看不到这一步会失败。**"浏览器跑通了"不能替代真机验收。**

---

### Phase 8.1：发版准备（2026-10-16，真机验收通过后）

> **目标**：把 App 从"开发者的玩具"变成"能发出去的东西"。四件事都是发版前
> 成本最低的时机——尤其包名，**发出去之后就再也改不了**。

| 项 | 之前 | 现在 | 为什么必须现在改 |
|----|------|------|------------------|
| `applicationId` | `com.example.my_schedule_app` | **`com.zys.myschedule`** | Flutter 模板默认值；一旦发出去就**永远是这个身份**，应用商店也不收 `com.example.*` |
| `namespace` / Kotlin 包 | `com.example.my_schedule_app` | `com.zys.myschedule`（`MainActivity.kt` 已随目录迁移） | 与包名保持一致，避免"运行时代码叫 A、安装身份叫 B"的困惑 |
| `android:label` | `my_schedule_app` | **`我的课表`** | 桌面图标下显示的就是这个 |
| 版本号 | `0.1.0+1` | **`0.2.0+2`** | 语义上"功能成型、未到 1.0"；且与已废弃的旧草稿插件 v0.1.0 区分开 |
| 签名 | `signingConfigs.getByName("debug")`（gradle 里写着 TODO） | **正式 keystore** `android/key/myschedule-release.jks`（RSA 2048 / 10000 天 / alias `myschedule`），凭据在 `android/key.properties` | debug 密钥不可控，发出去就没法发更新。`build.gradle.kts` 读 `key.properties`，**没有该文件时回退 debug 签名**，保证别人 clone 下来也能 build |
| 示例插件 | `assets/plugins/example.js` + `installExamplePluginForDemo()` | **已删除**，`+` 菜单从 4 项变 3 项 | Phase 4 就约定了；之前留着是因为它是唯一能验证"装上→启用→详情页→同步"的用例，现在学习通插件已经真机跑通，它没有存在价值了 |

> ⚠️ **备份清单（用户必须自己做，我没法替你备份）**：
> `android/key/myschedule-release.jks` + `android/key.properties`（含密码），
> 离线存两份（网盘 + 移动硬盘）。**这两份文件丢了，已装用户就永远收不到更新**，
> 而且没有找回的办法——Android 的签名校验只认这对密钥。
> 两份文件都已加入 `.gitignore`，**不会也不会**被提交到 GitHub。

> ⚠️ **换包名的代价**：`com.zys.myschedule` 对设备而言是一个**全新的 App**，
> 旧包 `com.example.my_schedule_app` 里的课表 / 作业 / Cookie **不会**迁移过来
> （Hive 数据在应用私有目录，按包名隔离）。重新装新包、重新登录、重新同步即可。

> 顺带清理：`plugin_storage_service.dart` / `pubspec.yaml` 里指向
> `example.js` 的注释同步更新。



---

## Phase 9：打包发布（准备就绪，待构建分发）

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
| 2026-09-23 | **`ModuleProvider` 仍由 `allCapabilities`（按"已启用"算）驱动，未改用 `loadedCapabilities`（按"加载成功"算）**：结果是"插件启用了但加载失败"时，其声明的模块仍会变成可用。改用后者语义更正确，但会改变模块可用性行为，属独立决策 | ⚠️ 待处理 |
| 2026-09-23 | 3.3 给 `PluginProvider` 加了 `plugins` Box 持久化（一 id 一 key，值为 `PluginMeta` JSON）。**该存储格式此后即契约**，改动需写迁移 | 已决定 |
| 2026-09-23 | 3.3 未做插件管理 UI 接线（`PluginManagePage` 仍是占位页），`togglePlugin` 等新方法暂无 UI 调用方 | 待处理 |
| 2026-09-23 | 3.4 的真机验证**已完成**：Redmi K60（`2211133C`）上 `installPlugin` → 默认解析 → 沙箱执行 → 路径安全 → 卸载全部通过，实际目录 `/data/user/0/com.example.my_schedule_app/app_flutter/plugins` 已用 adb 独立确认 | ✅ 已完成 |
| 2026-09-23 | 3.4 未做"插件安装 UI / 安装流程"：用户还不能从任意文件导入插件（需文件选择器，属新依赖）。3.5 把入口做成 `+` 菜单并给了 SnackBar 占位 + 内置示例插件，**真实文件导入仍是 Phase 6+** | 待处理 |
| 2026-09-23 | **禁止用 PowerShell 的 `Get-Content`/`Set-Content` 做文本往返**：本机控制台代码页非 UTF-8，会按 GBK 解码后再以 UTF-8 写出，**中文全部变乱码且行结构被破坏**。3.5 期间我用它改一行测试代码，整个测试文件的中文被毁（与 `f2cad97` 那次 PROGRESS.md 损坏同源）。**必须用文件编辑工具，或 `[System.IO.File]::ReadAllText/WriteAllText` 显式指定 UTF-8** | 已决定 |
| 2026-09-23 | `assets/plugins/example.js` 与 `PluginProvider.installExamplePluginForDemo()` 是**临时**验证代码，**Phase 4 完成后必须删除**（已在该文件、方法注释、API.md 三处标注） | 待处理 |
| 2026-09-23 | 3.5.1 修正了"示例插件无法卸载"：根因是把 `source == 'builtin'`（来源）当成卸载策略。现由 `PluginMeta.isRemovable` 独立决定；**目前没有任何插件设为 `false`**（留给将来的硬编码系统级插件） | ✅ 已完成 |
| 2026-09-23 | 3.5.1 顺带修掉：`removePlugin` 此前**不删磁盘插件文件**，与确认框文案不符。现已真正删除 `<id>.js` / `<id>.manifest.json` | ✅ 已完成 |
| 2026-09-23 | **3.6 发现：release APK 没有网络权限**。Flutter 模板只在 `src/debug` / `src/profile` 声明 `INTERNET`，`src/main` 没有 → 正式包里插件的 `ctx.http` 会直接失败。已在 `src/main/AndroidManifest.xml` 补上 | ✅ 已完成 |
| 2026-09-23 | 3.6 的 `ctx.http` 用**重放**实现，因此**插件入口函数会被执行多次**：插件必须是幂等的纯计算，`ctx.storage` 副作用只在最终轮提交。这是写 Phase 4 插件时必须遵守的约定 | 已决定 |
| 2026-09-23 | `plugin_data` Box（key = `<pluginId>:<userKey>`）此后即**契约**，改动需写迁移 | 已决定 |
| 2026-09-23 | 3.6 未做：权限系统（所有插件都能用全部 ctx）、网络白名单；`ctx.notify` 仍是占位（Phase 7）；`ctx.cookie` 只读（Phase 4 才写入） | 待处理 |
| 2026-09-24 | **4.1 已验证 ✅：`WebViewCookieManager.getCookies` 在 Android 上能拿到 HttpOnly Cookie**。真机用本机服务同时下发 `normal=xyz`（普通）与 `JSESSIONID=ABC123; HttpOnly`，提取结果为 `"normal=xyz; JSESSIONID=ABC123"` —— **HttpOnly 也在内**（Android 的 `CookieManager.getCookie(url)` 返回的是"会随请求发送的 Cookie"）。所以**不需要**引入 `webview_cookie_manager` 等第三方包 | ✅ 已完成 |
| 2026-09-24 | **4.1 已验证并确认为真实风险：Android 明文 HTTP（cleartext）被拦**。真机上 WebView 打开 `http://127.0.0.1:.../login` 直接失败：`net::ERR_CLEARTEXT_NOT_PERMITTED`（targetSdk 34 默认禁 cleartext）。**不少学校教务仍是 http://** —— 若是，则 **WebView 登录与 `ctx.http` 都会被系统拦掉**。修法二选一：① `networkSecurityConfig` 只对具体域名放行（推荐，安全）；② `usesCleartextTraffic="true"`（全放开，不推荐）。**待 Phase 4.2 拿到真实教务地址后决定** | ✅ 已完成（Phase 4.2.2：采用方案①，`network_security_config.xml` 只放行 `xjw1.ncst.edu.cn` 含子域，`base-config` 仍为 `false`；**待真机复验**） |
| 2026-09-24 | **4.1 已知局限：登录成功后 URL 不变的站点（单页 / AJAX 登录）无法自动判定成功**。当前主方案是 URL 前缀匹配；若学校登录后不跳转，`checkUrl` 永远不命中 → 只能用户手动返回（那样按规范不保存 Cookie）。4.1 真机验证里也顺带确认了相反方向的规则是对的：`https://example.com/` 命中前缀但**没有 Cookie 时不会误判成功** | 待处理 |
| 2026-09-24 | **4.2 真机验证卡在网络可达性（非代码问题）**：`xjw1.ncst.edu.cn` → `172.20.13.4`（校园内网）。本机可达，但手机经 PC 热点上网时 `ping` 100% 丢包（example.com 正常）。**需手机连校园 WiFi / VPN + 人工输入学号密码**，才能验证登录 → 同步 → 课表渲染 | ⚠️ 待人工验收 |
| 2026-09-25 | **4.2.1 已诊断并修复（待复验）：WebView 打开登录页报 `-1`，而系统浏览器能打开** —— 根因是**不受信 / 自签证书**（WebView 默认拒绝，浏览器给"继续访问"）。已加**只对登录 host** 的 SSL 放行 + 诊断日志 + 警告条；真实证书错误在 `flutter test` 里造不出来（`SslAuthError` 构造私有、`WebViewController()` 测试环境起不来），**需真机看 `SSL 错误放行` 日志确认** | ⚠️ 待真机复验（Phase 4.2.1） |
| 2026-09-25 | **webview_flutter 4.14.1（本项目锁定版本）没有 `onReceivedSslError` / `SslError`**（4.15+ 才有），等价 API 是 `NavigationDelegate.onSslAuthError(SslAuthError)`；该 `SslAuthError` **不含 URL**（描述在 `error.platform.description`），故用 `controller.currentUrl()` 兜。若将来升级到 4.15+ 可换成 `onReceivedSslError` 直接取 `error.url` | 已决定（Phase 4.2.1） |
| 2026-09-25 | 4.2.1 只做了"**自动放行 + 警告条**"，**未做放行前弹窗确认**（自签证书是教务常态，每次弹窗烦人）。将来若要弹窗，在 `_onSslAuthError` 放行分支前插 `showDialog` 即可 | 已决定（Phase 4.2.1） |
| 2026-09-25 | **4.2.2 已修（待复验）：登录从 https 重定向到 http，被 Android 拦成 `net::ERR_CLEARTEXT_NOT_PERMITTED`**（`url=http://xjw1.ncst.edu.cn/gotoLogin`）。已加 `network_security_config.xml` 定向白名单（`base-config` 仍 `false`，只放开 `xjw1.ncst.edu.cn` 含子域）并在 manifest 引用；**需重装 APK** 才能生效。**已确认**约束 WebView；对 **`ctx.http`（dio → Dart 侧 socket）是否生效尚无证据**（4.1 dio 打通 http 本机服务那次用的是 debug 全局 `usesCleartextTraffic`，不能外推）→ 同步报 `{error:'connection'}` 而浏览器能通即为此问题 | ⚠️ 待真机复验（Phase 4.2.2） |
| 2026-09-25 | **4.2 快照里"NCST 是 https，不需要 cleartext 配置"的判断已被真机推翻**：入口是 https，但**登录跳转链里有 http**。教训：涉及网络策略的结论必须等真机完整跑过跳转链再定 | ✅ 已更正（Phase 4.2.2） |
| 2026-09-25 | `network_security_config.xml` 是**系统级配置**，插件无法在运行时修改 → **每新增一个使用 http 的学校都要改文件并重新发版**。若将来要免发版，只能全局 `usesCleartextTraffic="true"`（**不采用**，等于对所有域名降级明文） | 已决定（Phase 4.2.2） |
| 2026-09-24 | **4.2 未验证：真实教务响应是否与规格一致**。插件里的字段名（`coureNumber` 等）来自你之前提供的抓包结构，**我无法在未登录状态下验证真实响应**。插件已按"结构不符就报 `响应结构异常：…`"处理——真机登录后若报错，把 error 文案发我即可定位 | ⚠️ 待人工验收 |
| 2026-09-24 | 4.2 未做：同步的增量/覆盖策略（现有 `saveCourse` 按 id 覆盖，插件的 `id = coureNumber_coureSequenceNumber` 天然稳定）、失败重试、同步进度 UI —— 留给 Phase 4.3 / 4.4 | 待处理 |
| 2026-09-23 | `PluginStorageService` 的目录布局（`<appDocuments>/plugins/<id>.js` + `<id>.manifest.json`）此后即**契约**：已装插件的文件名/后缀改动需写迁移（重命名旧文件） | 已决定 |
| 2026-09-23 | PluginProvider 用 allCapabilities（enabled）驱动模块可用性，插件加载失败时模块仍在——Phase 3.5 在插件详情页显示 loadErrors | 待处理 |
| 2026-09-24 | 插件安装 UI（文件选择器）暂不做，Phase 4 从 assets 内置插件加载 | 已决定 |
| 2026-09-24 | 插件目录布局 `<id>.js` / `<id>.manifest.json` 是契约，改动需写迁移 | 已决定 |
| 2026-09-24 | 示例插件 Phase 4 完成后删除（assets/plugins/example.js + installExamplePluginForDemo） | 待处理 |
| 2026-09-24 | isRemovable 当前无 false 使用者，留给将来系统级插件 | 已决定 |
| 2026-10-16 | **学习通有反爬（Phase 8 实测）**：12 秒内 136 个请求触发 `【9010】操作异常，请输入图片中的验证码`，HTTP 202 + 跳 `antispiderShowVerify.ac`。**因此内核只抓用户勾选的课程、严格串行、一次建议 ≤5 门**（超了只在界面警告，不硬拦）。若用户撞上，需先在浏览器里过一次验证码 | ✅ 已规避（写进插件与 UI） |
| 2026-10-16 | **`enc` / `openc` 是每门课的，不是账号级的**：用 A 课的 `enc` 去请求 B 课的作业会拿到 822 字节的空壳。**必须从课程主页 HTML 里抠出完整 URL**，手工拼参数必错 | ✅ 已决定（写进插件注释） |
| 2026-10-16 | **作业正文的 4 级链路**：课程主页 → 作业列表（`enc`）→ `isExpire`（`standardEnc`）→ `doHomeWorkNew`（正文）。少任何一级都拿不到题目；未完成章节任务点时服务端不给 `standardEnc`，此时**不是错误**，只是没有正文 | ✅ 已实现 |
| 2026-10-16 | **抓作业正文会在学习通留下"已开始作答"记录**（用户已知情并接受）。UI 上给了开关 `withContent`，只关心截止时间时可以关掉 | 已决定（用户确认） |
| 2026-10-16 | **内核不认识学校字段（CONTEXT 3.1）的落地方式**：`PluginCourseRef` 把插件给的课程对象当**不透明 Map** 原样存、原样回传；内核只读 `id`/`name`/`teacher`/`className` 四个约定展示字段（缺失即空串）。因此 `courseId`/`classId`/`cpi` **不出现在内核任何判断里** | ✅ 已决定 |
| 2026-10-16 | **作业 / 考试的覆盖层内联存储，不进 `overrides` Box**：`overrides` 的键空间是"课程 ID"，而作业/考试 ID 与课程 ID 都可能形如 `chaoxing:<数字>`，共用会撞号（表现为"改作业勾选把课程颜色改了"）。`Homework` / `Exam` 模型本来就带 `userOverride` 且 `toJson` 会序列化它，因此**内联零成本**；代价是同步落盘时必须把已有覆盖层重新挂回去（已实现并有用例） | ✅ 已决定 |
| 2026-10-16 | **未泛型化 `CourseSyncService`**：作业/考试另起 `PluginEntitySyncService`（课程服务一行不改）。共享 90% 流程但课程有 `sectionTimes`/`allUnits` 两个专属回传字段，泛型化要动 Phase 4.3 已交付且带测试的代码 | ✅ 已决定 |
| 2026-10-16 | `Message.fromSyncReport` 新增 `itemLabel`/`itemUnit`（默认 `课程`/`门`），**课程文案与 Phase 7 逐字一致**（已加回归用例锁定） | ✅ 已决定 |
| 2026-10-16 | **Phase 8 未做真机验收**：本次是桌面 Node + Playwright 浏览器跑通的插件链路，**没有在 Android 上跑 App**。`network_security_config`（学习通是 https，理论不需要放行）与 WebView 登录需实体机确认 | ✅ 已验收（当晚补上，且真机推翻了"学习通是 https"的推测——见 Phase 8 真机实测小节） |
| 2026-10-16 | **真机暴露 bug 1（明文 HTTP）**：学习通登录成功后 302 到 `http://i.mooc.chaoxing.com/`，被 Android 拦成 `net::ERR_CLEARTEXT_NOT_PERMITTED`，界面显示「页面加载失败」。请求根本没发出去，**不存在 HTTP 状态码** | ✅ 已修复（`network_security_config.xml` 放行 `chaoxing.com` 整域） |
| 2026-10-16 | **真机暴露 bug 2（scheme 敏感）**：`isLoginSuccessUrl` 字面匹配 `checkUrl=https://...`，而实际落地是 `http://...`，永远命中不了 → 登录成功却不返回、Cookie 不落盘 | ✅ 已修复（剥掉 scheme 再比一次；新增 18 组回归测试） |
| 2026-10-16 | **设备上残留旧草稿插件 `xuexitong`（v0.1.0）**：插件改名后，旧 id 会作为"另一个插件"留在用户设备上（Hive + `app_flutter/plugins/xuexitong.js`），与新插件并存造成困惑 | ⚠️ 已在真机上手动卸载；**插件 id 一旦发布就不要再改**（改了也没法通知已装用户） |
| 2026-10-16 | **`tools/chaoxing/` 的抓取产物是个人数据**：`courses.json`（68 门课+教师+班级）、`out/`（14 个页面 HTML）、`raw-*.html`（含登录后的个人主页）、`.profile/`（32MB 浏览器登录态）。已全部加入 `.gitignore`，**只有脚本（21 个 .js）入库** | ✅ 已规避 |
| 2026-10-16 | `tools/chaoxing/` 是**开发工具**（Playwright 会话、重放机制模拟器），内含 `.profile/`（浏览器登录态）与 `netlog-*.jsonl`（抓包记录）。已加 `.gitignore`，**不要提交** | 已决定 |
| 2026-10-16 | 插件管理页的 `+` 菜单现在有 4 项（NCST / 学习通 / 文件导入 / 示例）。`assets/plugins/example.js` 与 `installExamplePluginForDemo()` 仍是**临时验证代码**，按 Phase 4 的约定应删除——本次**未删**，避免与学习通插件的验收混在一起 | ⚠️ 待处理 |
| 2026-10-16 | **本机 `flutter test` 的两个坑**：① 环境有 `http_proxy=127.0.0.1:54682`，会让 `flutter_tester` 的本地 WebSocket 握手走代理而报 `Invalid WebSocket upgrade request` → 必须 `env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY flutter test`。② 用 `RepaintBoundary.toImage` 截图时，**图能正常写出，但测试进程在第一个用例结束后不会退出**（一直挂着直到被杀）→ 想连出多张图就得分文件或用 `--plain-name` 一个一个跑。这两点都只影响**临时验证脚本**，不影响 29 组常驻单元测试 | 已规避 || 2026-10-22 | **Phase 9（大物实验）**：新增插件 `ncst-phylab`，数据源 `http://phylab.ncst.edu.cn:8100/`。登录**不做在插件里**——该站密码要过 `AES-128-ECB(key=1234567891234567)` 再 base64，且成功后还要 `GetRoleUser` 写 Session，沙箱实现等于把密码留在本地；统一走 WebView 登录，插件只消费 Cookie | ✅ 已实现 |
| 2026-10-22 | **实验时段和教务节次对不齐**：实验系统每段 **2h15**（上午 10:15-12:30 / 下午一 14:00-16:15 / 下午二 16:30-18:45），教务是 45 分钟一节。方案：`TimePartName` 优先查表（→ 3-4 / 5-6 / 7-8 节），`StartTime` 兜底，真实钟点写进 `TimePlace.rawWeeksText`（该字段内核只用于展示，不参与周次解析） | ✅ 已决定（写进插件注释与 API.md） |
| 2026-10-22 | **会话失效不是 401 而是 302**：ASP.NET 过期后 `LoadTableInfo` 302 到 `/Index/Redirect/`，宿主 `followRedirects:true` 拿到 HTML → `JSON.parse` 失败即"登录已过期" | ✅ 已按此实现 |
| 2026-10-22 | **课表页同步按钮的"恰好一个插件"假设被打破**：`_syncablePlugin` 原来只在**唯一**一个 `timetable` 插件时返回，装了实验插件后与教务插件并存 → 按钮直接消失。改为 `_syncablePlugins`（列表）+ 多候选时弹底部选择器 | ✅ 已修复 |
| 2026-10-22 | **实验系统是 http + 8100**：`network_security_config.xml` 追加 `phylab.ncst.edu.cn` 明文放行（`domain-config` 只管域名，端口不参与匹配）。**必须重新打包安装**才生效 | ⚠️ 待真机复验（Phase 9） |
| 2026-10-22 | **Phase 9.1（按日期导入）**：`LoadTableInfo` 除了 `Weeks`/`WeekID` 还有 `ClassDate`（`2026/9/14 0:00:00`）。改为**以日期为准**换算 `(week, day)`——周次是相对量，两边学期起点差一周就整体错周且看不出来；日期是绝对的，除以用户学期起点必然落到课表正确那一列 | ✅ 已实现 |
| 2026-10-22 | **插件拿不到学期起点**：`ctx` 只有 cookie/storage/http/log/notify，没有学期。新增 `ctx.semester = {startDate:'YYYY-MM-DD', totalWeeks}`，由 `CourseSyncService.sync(semester:)` → `handle.execute(semester:)` → `buildCtxStateScript` 逐层注入。没配学期时为 `null`，插件自行降级 | ✅ 已实现（4 个文件接线） |
| 2026-10-22 | **日期换算必须用 `Date.UTC`**：`new Date('2026/9/14')` 按本地时区解析，夏令时/时区会让"天数差 ÷ 7"不是整数，整批错一周。统一 `Date.UTC(y,m-1,d)` 毫秒差 | ✅ 已按此实现 |
| 2026-10-22 | **同一实验多场时 id 会随返回顺序互换**：原实现只给"第二次出现"加后缀，顺序一变用户改过的名字/颜色就错位。改为**预扫描计数，多场时每一场都带日期后缀** | ✅ 已修复 |
| 2026-10-22 | **降级不静默**：没配学期 / 日期超出学期范围 / 日期周次与系统周次不一致，三种情况都出 warning（差异只列前 3 条），用户能看出"这次是按什么排的" | ✅ 已实现 |
| 2026-10-22 | **"装通用包就更新通用包"**：更新默认按设备 ABI 挑裁剪包（省一半流量），但会把用户的包悄悄换成"只认 arm64"。新增 `SystemSettingsBridge.installedIsUniversalApk()`——读本 APK 的 `lib/` 目录，≥2 个 ABI 子目录即通用包；`UpdateService.check` 据此把 `preferUniversal` 传下去，通用包用户继续拿通用包。探测失败一律按 `false`（退回原行为），不会把包选错 | ✅ 已实现 + 5 个新测试 |
| 2026-10-22 | **澄清一个误解**：通用包 ↔ 单架构包**本来就能互相覆盖安装**（只要求包名/签名/versionCode 兼容，ABI 不同不拦），不需要卸载。真正需要卸载重装的只有 debug→release（签名不同），这一点写进了 v0.5.0 发布说明 | ✅ 已写进 Release 说明 |
| 2026-10-22 | **v0.5.0+3003 发布**：大物实验插件 + `ctx.semester` 注入 + 按日期导入 + 通用包保持 + 修"多插件时课表页同步按钮消失"。四个 APK 共用 versionCode 3003 | 🚀 发行中 |
