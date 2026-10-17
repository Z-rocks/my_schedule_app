# 交互逻辑问题汇总（2026-10-17）

> 来源：用户真机使用反馈  
> 范围：插件获取链路、设置页信息、登录流程、插件详情页入口  
> 每条问题均标注了**已核实的代码位置**，便于直接定位修改

## 一、分级定义

| 等级     | 含义                          | 处理要求        |
| ------ | --------------------------- | ----------- |
| **P0** | 逻辑错误 / 死循环 / 明确错误信息，新用户必然踩到 | 必须修，优先于其他工作 |
| **P1** | 功能缺失或误导性入口，可用但别扭            | 本迭代内修       |
| **P2** | 体验优化、占位功能清理                 | 排期处理，可延后    |

本次共 **8 项**：P0 × 3、P1 × 4、P2 × 1。

## 二、速查表

| # | 问题                             | 等级 | 状态         | 主要涉及文件                                                                         |
| - | ------------------------------ | -- | ---------- | ------------------------------------------------------------------------------ |
| 1 | 插件管理空态引导去创意工坊，形成死循环            | P0 | ✅ 已修复      | `lib/pages/settings/plugin_manage_page.dart:129`                               |
| 2 | 创意工坊默认页是皮肤，插件 Tab 不是市场         | P0 | ✅ 已修复      | `lib/pages/settings/workshop_page.dart:47`                                     |
| 3 | 插件管理右上角 `+` 号应移除               | P1 | ✅ 已修复 | `lib/pages/settings/plugin_manage_page.dart:106`                               |
| 4 | 关于页版本号写死 `v0.1.0`，与 pubspec 不符 | P0 | ✅ 已修复      | `lib/pages/settings/settings_page.dart:22`                                     |
| 5 | 无「检查更新」入口，无版本分发机制              | P1 | ✅ 已修复       | 新增能力（`pubspec.yaml` / 关于分组）                                                    |
| 6 | 「登录管理」语义不明，先隐藏                 | P2 | ✅ 已修复       | `lib/pages/settings/settings_page.dart:155`                                    |
| 7 | 华北理工插件登录后需手动点「选课结果」            | P1 | ✅ 已修复       | `assets/plugins/ncst-jwxt.js:36`、`lib/pages/login/webview_login_page.dart:314` |
| 8 | 所有插件都显示「立即同步」，多数插件用不上          | P1 | ⬜ 待做       | `lib/pages/settings/plugin_detail_page.dart:198`                               |

### P0 修复记录（2026-10-17）

| 问题        | 实际改动                                                                                                                                                                                                                              |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P0-1 死循环  | 插件管理空态文案改「去创意工坊的插件市场挑一个装上」/ 按钮「去创意工坊安装」                                                                                                                                                                                           |
| P0-2 插件市场 | 新增 `lib/models/plugin_catalog.dart`（可安装目录）；`PluginProvider.installCatalogPlugin`；创意工坊 Tab 改为 **插件/皮肤** 且 `initialIndex: 0`；插件 Tab 重写为「可安装 + 已安装」两段，卡片内直接安装                                                                        |
| P0-3 版本号  | Android `SystemSettingsBridge.appVersion()`（读 PackageInfo 的 versionName+versionCode）→ `com.zys.myschedule/system` 通道 → `lib/services/app_version.dart`；设置页改 `FutureBuilder` 显示；新增 `test/app_version_test.dart` 校验兜底常量与 pubspec 一致 |

> 说明：原计划用 `package_info_plus`，但当前环境 pub.dev 不可达，改用项目已有的  
> 平台通道读取系统包信息——反而更符合"版本号只有一处真相"（`pubspec.yaml`）。

### P1 / P2 修复记录（2026-10-17 第二批）

| 问题 | 实际改动 |
| --- | --- |
| P1-3 移除 `+` 号 | 删掉 `PopupMenuButton` / `_onAddAction` / `_AddAction`；插件管理页只负责"管理已安装插件"，安装统一走创意工坊插件市场 |
| P1-5 检查更新 | 新增 `lib/services/update_service.dart`：`https://api.github.com/repos/Z-rocks/my_schedule_app/releases/latest`，`isNewerVersion` 纯函数比版本；设置 → 关于 → 「检查更新」，有新版弹对话框（版本号 + Release 正文），「前往下载」经 `SystemBridge.openUrl` 调系统浏览器，打不开则复制链接；新增 `test/update_service_test.dart` |
| P1-7 登录自动跳转 | `PluginManifest` 新增 `postLoginUrl`；登录页新增 `isLoginFormUrl` / `shouldAutoNavigateAfterLogin` 两个纯函数，离开登录表单页后自动导航到 `postLoginUrl`，再由 `checkUrl` 判定成功；`ncst-jwxt.js` 声明 `postLoginUrl`；AppBar 另有「已登录？直接进入下一步」兜底按钮；新增 `test/webview_login_auto_nav_test.dart` |
| P2-6 隐藏登录管理 | 删除「账号 / 登录管理」整个分组（该组仅此一条占位项） |

### 追加修复：隐藏后无法恢复（2026-10-17，用户实测发现）

**现象**：作业点「隐藏」后从列表消失，之后再也找不到，等同于删除。

**根因**：`HomeworkProvider.hiddenHomeworks` / `hiddenCount` 定义了，但**没有任何 UI 消费它们**；
详情弹层的「隐藏」把记录从 `displayHomeworks` 过滤掉之后，页面上没有恢复入口。
课程侧早有 `hidden_courses_page.dart`，作业侧漏了这一环——功能只做了一半。

**修复**：

- 新增 `lib/pages/homework/hidden_homeworks_page.dart`：列出已隐藏作业，每条可「恢复显示」
- 作业页 AppBar 增加「已隐藏」入口（仅 `hiddenCount > 0` 时出现，避免无意义的空入口）
- **全部隐藏时的空态**改为「作业都已隐藏 · 共 N 份，可以随时恢复」+「查看已隐藏」按钮，
  不再误显示「暂无作业」（那会让用户以为数据丢了）
- 详情页隐藏后 SnackBar 提示「可在作业页右上角「已隐藏」里恢复」

**顺带发现考试页有完全相同的缺陷**（`exam_view.dart:312` 隐藏后同样无入口），一并修复：
新增 `lib/pages/exam/hidden_exams_page.dart`，并做同样的入口 / 空态 / 提示处理。

> 这类 bug 的共同模式：**"隐藏"是让数据从界面上消失的操作，必须自带恢复入口**，
> 否则用户无法区分"隐藏"和"删除"。以后新增任何隐藏/归档类功能，都要先问一句"怎么找回"。

**关于 P1-5 的前置条件**：仓库目前若还没有 Release，检查更新会返回「仓库还没有发布过 Release」。
需要先在 GitHub 上打 tag（如 `v0.2.1`）并发布 Release、把 APK 传进 assets，这个功能才会真正有用。

**关于插件市场的数据源**：现阶段 `kPluginCatalog` 是随 App 打包的静态目录（只有内置的两个插件）。
后续要接远端时，把 `kPluginCatalog` 换成从 GitHub 仓库拉取的列表即可（UI 层不用改）——
`UpdateService` 里的 `kUpdateRepoOwner` / `kUpdateRepoName` 可直接复用为插件源坐标。

### 追加修复：桌面小组件（2026-10-17 第三批，用户实测发现）

**现象**

| # | 现象 | 等级 |
| - | --- | -- |
| 9 | 当天有考试时，考试卡变成黑色 + 「载入窗口小部件时出现问题」；作业卡同样（课表卡可能同因） | P0 |
| 10 | 「本周课表」是 7×12 色块网格，只有颜色没有课程名，看不出"第几节上什么" | P1 |
| 11 | 「今天课表」2×2 最多塞 4 行，一天的课显示不全 | P1 |
| 12 | 两张课表卡职责重叠（都在画"今天"），大卡的信息密度反而更低 | P2 |

**根因**

- #9 **根因已定位（真机 + 字节码双向验证）**：`RemoteViews` 的布局**只能用带
  `@RemoteViews$RemoteView` 注解的控件**——`RemoteViews` 自己实现了
  `LayoutInflater.Filter.onLoadClass()` 做白名单校验，不在白名单里的控件会在
  **桌面进程**里 inflate 时抛 `InflateException`，桌面随即把整张卡换成黑色占位
  （「载入窗口小部件时出现问题」是系统文案，不是 App 写的）。
  而 `android.view.View` **恰恰不在白名单里**：

  ```
  $ unzip -p android.jar android/view/View.class      | strings | grep RemoteView   # 无
  $ unzip -p android.jar android/widget/TextView.class | strings | grep RemoteView
  'Landroid/widget/RemoteViews$RemoteView;'
  ```

  所以行布局里的 `<View>`（色条 / 状态点）就是真凶：
  - `widget_homework_row.xml` 的 `<View id=hw_dot>` → **有作业就黑**
  - `widget_today_row.xml` 的 `<View id=color_bar>` → **有课就黑**

  **空态不 inflate 行布局**，所以「空态一切正常、一有数据就黑」——
  与用户描述的触发条件完全吻合。修法：`<View>` 全部换成 `<TextView>`
  （不需要文字，只借它的背景色）。另外补一层 try/catch 兜底，
  避免将来出现别的渲染异常时又是一张黑卡。
- #10：`WeekWidgetProvider` 逐列 `addView` 拼 7×12 个纯色格子，
  格子里**没有课程名**——颜色只能区分"这门课和那门课不同"，不能回答"上什么课"。
  而 4×3 的卡面本来也画不下整周。
- #11：`TodayWidgetProvider` 是"今天全部课程"的缩略列表，窄卡限 4 行、宽卡 6 行，
  超出的部分只能补一行"等 N 节课"，等于没显示。

**修复（按职责重分两张卡）**

| 卡片 | 原来 | 现在 |
| --- | --- | --- |
| 小卡（2×2，`widget_today`） | 今天全部课程（最多 4 行） | **下一节课**：课程名 + 节次时间 + 地点；正在上课时右上角标「进行中」 |
| 大卡（4×3，`widget_week`） | 本周 7×12 色块网格 | **今日课程**列表：一行一门课（节次时间 + 课程 + 地点），行数按卡高自适应 |

- **快照 v2**：`schedule.nextSession`（`courseIdx` / `sectionText` / `state` / `label`）。
  `state` 四态 `ongoing` / `upcoming` / `finished` / `unknown`，判定全在 Dart 侧
  （`WidgetSnapshotService._nextSessionJson`，按 `SectionTimes` 的起止分钟数比当前时间），
  小组件只按 `state` 选颜色，不解析时间——保持"哑渲染"。
  版本号两端必须同改：`kWidgetSnapshotVersion`（Dart） ↔ `WidgetSnapshotContract.VERSION`（Kotlin）。
- 今天上完课时不拿最后一门课冒充"下一节"，改显示「今天的课都上完了」。
- 行数算式：`(卡高 - 表头 - 上下内边距) ÷ 行高`，表头高度与行高都是 dimens，
  手机 / 平板两套字号各自成立；被截断时表头右侧「共 N 节」仍给出当日总数。
- 渲染兜底：`BaseWidgetProvider.onUpdate` 逐卡 `try/catch`，
  失败时记 `Log.e("WidgetRender", "渲染失败 provider=... appWidgetId=... snapshotNull=...")`
  并渲染 `widget_error.xml`（「小组件加载失败 / 点一下打开 App 试试」）。
  **宁可少显示内容，也不要一张黑卡**。

**以后再遇到黑卡怎么定位**：

```
adb logcat -s WidgetRender
```

日志里会带 provider 类名和 `snapshotNull`，堆栈直接指向抛异常的那一行。
另外记住一条硬约束：**小组件布局里不要出现 `android.view.View`、`Space`、
`ScrollView`、`ViewStub`、`CardView` 等非白名单控件**——它们编译期不报错，
只在桌面渲染时炸。

**清理**：删除 `widget_today_row.xml` / `widget_week_cell.xml` / `widget_week_column.xml` /
`widget_week_day_header.xml` 及对应的 `widget_week_cell_*`、`widget_row_*` 旧 dimens。

> ⚠️ **升级提醒**：快照 schema 从 v1 升到 v2，升级后**旧快照会被判为版本不匹配**，
> 四张卡在 App 第一次启动（`onResume` 推送新快照）之前会显示「打开 App 刷新一下」。
> 这是预期行为，不是 bug。
>
> ⚠️ 四张卡的 `previewImage`（`widget_preview_*.xml`）还是旧设计的示意图，
> 与小卡/大卡的新内容不一致，需要重画（未做）。

---

## 三、问题详情

### P0-1　插件管理空态引导去创意工坊，形成死循环

**现象**

1. 插件管理页一个插件也没有 → 空态按钮「去创意工坊」。
2. 跳进创意工坊 → 插件 Tab 空态 → 按钮「去插件管理安装」。
3. 跳回插件管理 → 又是空态 → 再次「去创意工坊」。

用户在两个空页面之间来回弹，**永远装不上任何插件**。

**根因**

- `plugin_manage_page.dart:129-140`：空态 `actionLabel: '去创意工坊'`、`subtitle: '从文件导入或从创意工坊下载'`。
- `workshop_page.dart:452-484`：插件 Tab 空态只做「已装插件概览 + 跳插件管理」，本身**不提供任何安装动作**（注释里明确写了"刻意不复刻插件商店/安装流程"）。
- 真正能装的入口藏在插件管理右上角的 `+` 菜单里，而空态引导恰好把人引走了。

**期望**

插件获取只有一个入口且能真正装上东西：创意工坊 → 插件 Tab（市场）。

**方案**

与 P0-2 合并解决：创意工坊插件 Tab 改为真正的市场列表（含未安装插件），空态引导指向该市场；插件管理空态文案改为「去创意工坊安装」，且**不再依赖 `+` 菜单**。

**影响面**：`plugin_manage_page.dart`、`workshop_page.dart`

---

### P0-2　创意工坊默认页应是插件市场，而不是皮肤

**现象**

- 进入创意工坊，默认停在「皮肤」Tab，用户要装插件得先切 Tab。
- 切过去之后，插件 Tab 只有"已安装 N 个插件"，没有任何可安装列表。

**根因**

- `workshop_page.dart:47-57`：`tabs: [Tab('皮肤'), Tab('插件')]`，`DefaultTabController` 未指定 `initialIndex`，默认 0 = 皮肤。
- `_PluginsTab`（`workshop_page.dart:443-525`）只读 `provider.plugins`（**已安装**列表），没有"可安装"概念。
- 可安装清单目前硬编码为两个安装函数：`PluginProvider.installNcstPlugin()` / `installChaoxingPlugin()`（`plugin_provider.dart:346/364`，对应 `assets/plugins/ncst-jwxt.js`、`assets/plugins/chaoxing.js`），只被 `+` 菜单调用。

**期望**

1. 创意工坊默认停在「插件」Tab，皮肤退居第二。
2. 插件 Tab 即**插件市场**：列出所有可安装插件，每个卡片有「安装 / 已安装（去管理）」两态。
3. 已安装插件仍可在此查看与进入详情。

**方案**

1. `DefaultTabController` 增加 `initialIndex: 0`，并把 Tab 顺序调整为 `插件 / 皮肤`。
2. 在 `PluginProvider` 里抽一个**静态可安装目录**（catalog）：`id / name / 简介 / 学校 / 能力 / assetPath / installer`。把现有两个安装函数收进目录条目，市场卡片按 `provider.getById(id) == null` 判定未安装。
3. 市场卡片点击「安装」→ 调目录里的 installer → 成功后原地变为「已安装」，无需跳页。
4. 后续若接入远端插件源，只替换 catalog 的数据来源，UI 不动。

**影响面**：`workshop_page.dart`、`plugin_provider.dart`（新增 catalog）

**备注**：当前 catalog 只有 2 个内置插件，市场页面看起来会偏空，但比"死循环"好；文案上可以说明"更多插件陆续上架"。

---

### P0-3　关于页版本号 `v0.1.0` 明显错误

**现象**

设置 → 关于 → 版本号显示 `v0.1.0`。

**根因**

`settings_page.dart:22` 硬编码常量：

```dart
const String kAppVersion = 'v0.1.0';
```

而 `pubspec.yaml:20` 实际是 `version: 0.2.0+2`。注释里也承认"两处目前各自维护"，属于典型的双份真相漂移。

**期望**

版本号与安装包一致，且**只有一处真相**。

**方案（二选一）**

- **推荐**：引入 `package_info_plus`，`FutureBuilder` 读 `PackageInfo.fromPlatform()`，显示 `v{version}+{buildNumber}`。这是 Flutter 的标准做法，也顺带为 P1-5（检查更新）提供基建。
- **过渡**：暂时改为 `v0.2.0` 并在 `pubspec.yaml` 旁加注释提醒，同时在测试里加一条断言，防止再次漂移（成本低，但治标）。

**实际实现（2026-10-17）**

`package_info_plus` 需要联网 `pub get`，当前环境 pub.dev 不可达，改为**复用项目已有的平台通道**（`com.zys.myschedule/system`，原本用于省电引导跳转）：

- Kotlin `SystemSettingsBridge.appVersion()` 读 `PackageInfo` 的 `versionName` + `versionCode`，返回 `"0.2.0+2"`；
- Dart `SystemBridge.appVersion()` → `lib/services/app_version.dart`（缓存 Future，永不抛）；
- 设置页 `FutureBuilder` 显示 `v0.2.0+2`，读不到时显示「读取中…」；
- 非 Android 平台用 `kFallbackAppVersion`，由 `test/app_version_test.dart` 断言与 `pubspec.yaml` 一致。

好处是版本号的真相链只有一条：`pubspec.yaml` → 构建写入 AndroidManifest → 系统 PackageInfo → UI。比额外维护一个 Dart 常量（或依赖第三方包读同一份系统信息）更直接。

**影响面**：`settings_page.dart`、`system_bridge.dart`、`SystemSettingsBridge.kt`、`MainActivity.kt`

---

### P1-3　插件管理右上角 `+` 号应移除

**现象**

插件管理页右上角有个 `+`，点开是三个菜单项：

- 安装 NCST 教务插件
- 安装学习通（超星）插件
- 从文件导入（Phase 6+）← 占位，点了只弹 SnackBar

**根因**

`plugin_manage_page.dart:106-127`（`PopupMenuButton`）+ `152-182`（`_onAddAction`）+ `190`（`_AddAction` 枚举）。

**为什么该移除**

- 插件管理是"管理已装插件"的页面，安装入口应统一收敛到创意工坊市场（P0-2）。
- 同一件事两个入口，必然漂移：市场里加了新插件，`+` 菜单不会自动同步。
- 第三项是纯占位，属于"看起来能用其实不能用"。

**方案**

删除 `PopupMenuButton`、`_onAddAction`、`_AddAction` 枚举；`installNcstPlugin` / `installChaoxingPlugin` 的调用方迁移到市场卡片。

**依赖**：必须在 P0-2 完成**之后**再删，否则安装入口彻底消失。

**影响面**：`plugin_manage_page.dart`

---

### P1-5　没有推送最新版本 / 检查更新的地方

**现象**

设置里找不到「检查更新」，App 也不会提示新版本。

**根因**

全仓搜索无 `package_info_plus`、无更新检查逻辑、无版本清单接口。这是**功能尚未实现**，不是 bug。

**方案（需先定分发渠道）**

1. **基建**：引入 `package_info_plus`（与 P0-3 共用）。
2. **版本源**：三选一，取决于分发方式
   - GitHub Release（`/releases/latest` JSON）—— 免费、适合内测分发
   - 自建静态 JSON（`{version, buildNumber, url, changelog, force}`）—— 最可控
   - 应用市场（酷安 / 应用宝）—— 需上架，且多数无公开查询接口
3. **UI**：关于分组新增「检查更新」，显示当前版本 + 检查结果（已是最新 / 发现 vX.Y.Z + 更新说明 + 下载按钮）。
4. **可选**：启动时静默检查一次（仅在发现新版本时提示），避免每次启动打扰。

**待确认**：分发渠道尚未确定，建议先只做「手动检查更新」，把自动检查留到渠道定了之后。

**影响面**：新增 service（如 `lib/services/update_service.dart`）、`settings_page.dart`

---

### P1-7　华北理工插件登录后需手动点「选课结果」

**现象**

在插件详情页点「登录」→ WebView 打开教务系统 → 输入账号密码验证码 → 登录成功，页面停在教务首页 → **登录页不返回**，用户必须自己点进「选课结果」菜单，URL 命中判定条件后才算登录成功并退回 App。

**根因**

- `assets/plugins/ncst-jwxt.js:36-37`：
  - `loginUrl: 'https://xjw1.ncst.edu.cn/'`
  - `checkUrl: 'https://xjw1.ncst.edu.cn/student/courseSelect/courseSelectResult/index'`
- `webview_login_page.dart:314-338`（`_maybeFinish`）：**只有当前 URL 命中 `checkUrl` 前缀**才判定成功。
- 登录成功后跳转的是教务首页，不匹配 `checkUrl` → 判定不触发 → 页面停在首页等用户手动导航。

**期望**

用户只需输入账号密码验证码，登录成功即自动完成后续跳转并返回 App，不需要再手动点菜单。

**方案**

给 manifest 增加一个可选字段 `postLoginUrl`（登录成功后自动导航到的地址），内核在检测到"已离开登录表单、登录态建立"后，自动 `loadRequest(postLoginUrl)`，再由既有的 `checkUrl` 判定收尾。

判定"登录成功"的通用信号（内核不硬编码学校 URL，符合 CONTEXT 3.1）：

- 当前 URL 仍在 `loginUrl` 的 host 内，但**已不是登录表单页**（例如从 `/login` 跳到 `/`）；或
- 已拿到非空 Cookie 且 URL 发生了 host 内的导航。

落地时更稳妥的做法：**在 `checkUrl` 之外新增 `postLoginUrl`，一旦 `postLoginUrl` 声明了就无条件在登录后自动跳转**，不依赖模糊的"表单页"判断——模糊判断容易在个别学校误触发。

对 NCST 插件即：`postLoginUrl` 与 `checkUrl` 同值（`.../courseSelect/courseSelectResult/index`），登录成功后自动跳过去，`checkUrl` 命中即返回。

**注意**

- `PluginManifest`（`lib/runtime/plugin_manifest.dart`）需要新增字段并处理缺省（为空则行为完全不变，向后兼容老插件）。
- 自动跳转失败（如教务系统有中间确认页）要能降级：显示"若未自动跳转，请手动进入选课结果"，不能让用户卡死。

**影响面**：`plugin_manifest.dart`、`webview_login_page.dart`、`assets/plugins/ncst-jwxt.js`

---

### P1-8　并非每个插件都需要「立即同步」

**现象**

每个插件详情页都有一行「立即同步」，但学习通插件的能力是 `['homework', 'exam']`（`assets/plugins/chaoxing.js:43`），**没有课程同步能力**。点下去只会得到「该插件不支持课程同步」。

**根因**

`plugin_detail_page.dart:198-206` 无条件渲染 `_ActionRow(icon: Icons.sync, label: '立即同步')`，`_syncNow`（`:270`）走的是 `CourseSyncService`——即**只处理课程同步**，不看插件能力声明。

**期望**

入口按插件实际能力显示：能同步课程的才给「立即同步」；作业 / 考试类插件给对应的「抓取作业」「抓取考试」，或者干脆不显示。

**方案**

1. `PluginDetailPage` 依据 `meta.effectiveCapabilities` 条件渲染：
   - 含 `timetable` 或 `courseList` → 显示「立即同步」（课程）
   - 含 `homework` → 显示「抓取作业」
   - 含 `exam` → 显示「抓取考试」
   - 都不含 → 不显示同步类入口，只保留登录 / 查看日志
2. 若短期内不想做作业/考试的独立抓取入口，**最小改动**是：仅当含 `timetable`/`courseList` 时显示「立即同步」，其余隐藏。

**影响面**：`plugin_detail_page.dart`

**备注**：作业/考试的抓取入口目前可能挂在作业页/考试页上，需确认后再决定详情页是否重复提供。

---

### P2-6　「登录管理」语义不明，先隐藏

**现象**

设置 → 账号 → 登录管理，点进去只有一句「登录管理（待实现）」的 SnackBar。用户不知道这个功能要做什么。

**根因**

`settings_page.dart:155-164`：`onTap: () => _showSnack(context, '登录管理（待实现）')`，纯占位。

**方案**

- 直接隐藏该条目。
- **注意**：它是「账号」分组下唯一一条，隐藏后会出现一个只有标题、没有内容的空分组 → 连「账号」分组标题一起隐藏。
- 后续真正做登录态管理（查看各插件 Cookie 是否有效、一键重新登录、退出登录）时再放出来。

**影响面**：`settings_page.dart`

---

## 四、建议实施顺序

```
第一批（P0，互相咬合，一次改完）
  P0-2 创意工坊改插件市场 + 默认 Tab
   └→ P1-3 移除插件管理 + 号（依赖 P0-2）
   └→ P0-1 空态引导改指向市场（依赖 P0-2）
  P0-3 版本号（引入 package_info_plus）

第二批（P1，独立）
  P1-7 NCST 登录后自动跳转（涉及插件协议字段，需与插件一起改）
  P1-8 同步入口按能力显示
  P1-5 检查更新（依赖 P0-3 的 package_info_plus）

第三批（P2）
  P2-6 隐藏登录管理
```

## 五、涉及文件清单

| 文件                                           | 涉及问题                           |
| -------------------------------------------- | ------------------------------ |
| `lib/pages/settings/plugin_manage_page.dart` | P0-1、P1-3                      |
| `lib/pages/settings/workshop_page.dart`      | P0-1、P0-2                      |
| `lib/providers/plugin_provider.dart`         | P0-2（新增可安装目录）                  |
| `lib/pages/settings/settings_page.dart`      | P0-3、P1-5、P2-6                 |
| `pubspec.yaml`                               | P0-3、P1-5（`package_info_plus`） |
| `lib/pages/settings/plugin_detail_page.dart` | P1-8                           |
| `lib/pages/login/webview_login_page.dart`    | P1-7                           |
| `lib/runtime/plugin_manifest.dart`           | P1-7（新增 `postLoginUrl`）        |
| `assets/plugins/ncst-jwxt.js`                | P1-7                           |
| `lib/services/update_service.dart`（新增）       | P1-5                           |

## 六、待确认事项

1. **插件分发渠道** ✅ 已确认（2026-10-17）：**暂用本地内置目录**（`kPluginCatalog`），
   后续做成从**远端 GitHub 仓库**拉取。届时只替换 catalog 的数据来源，UI 不动。
2. **版本分发渠道** ✅ 已确认：**GitHub Releases**（`Z-rocks/my_schedule_app`），
   已由 `UpdateService` 实现；需要在仓库里发 Release 才会真正生效。
3. **作业与考试的抓取入口**：是否已存在于作业页 / 考试页？若已有，插件详情页不必重复提供（P1-8）。
4. **插件协议变更**：`postLoginUrl`（P1-7）属于插件 manifest 字段扩展——已实现为**可选字段**，
   未声明时行为与以前完全一致，因此不影响已发布的第三方插件。
