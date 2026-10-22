# 校园助手 · Campus Assistant

> 一款**插件驱动、皮肤装扮、数据全本地**的 Android 课表应用。
> 不连服务器、不上传任何数据，换一所学校只需要换一个插件。

**Flutter 3.47** ｜ **Android 7.0+** ｜ **当前版本 v0.4.1** ｜ **MIT License**

> **QQ 交流群：982872765** ｜ 用出问题、想要新功能、或者你写了别的学校的插件，都欢迎进群说。

> 仓库有两份：Gitee 是主仓库（国内快，Release 也以这里为准），GitHub 是备份。
> 本文档里的截图还没补，先用文字把功能说清楚。

---

## 目录

- [它解决什么问题](#它解决什么问题)
- [功能](#功能)
- [下载安装](#下载安装)
- [首次使用](#首次使用)
- [桌面小组件](#桌面小组件)
- [插件开发](#插件开发)
- [技术栈](#技术栈)
- [项目结构](#项目结构)
- [本地运行](#本地运行)
- [常见问题](#常见问题)
- [路线图](#路线图)
- [参与贡献](#参与贡献)
- [开源协议](#开源协议)
- [联系作者](#联系作者)

---

## 它解决什么问题

学校教务系统只给你一个**网页版课表**：要登录、要层层点菜单、手机上排版稀碎、断网就什么都没有。
第三方的课表 App 又要你把学号密码交给他们的服务器。

这个项目换了个思路：**把「怎么取数据」做成插件，让数据只待在你手机里。**

| | 说明 |
|---|---|
| **插件化** | 教务系统的 URL、字段名、接口路径全部写在 `.js` 插件里，内核不认识任何一所学校。换学校 = 换插件，不用改 App |
| **数据本地** | Hive 存课表、`flutter_secure_storage` 存 Cookie，**没有后端、没有账号体系**，App 里也没有任何上报代码 |
| **可编辑** | 教务拉下来的数据是"原始层"，你手动改的走"覆盖层"单独存；两者合并展示，重新同步也不会把你的修改冲掉 |
| **可装扮** | 皮肤是 `.skin.json`，颜色 / 圆角 / 字体 / 间距都能换，不需要重新编译 |
| **动态导航** | 底部导航栏显示哪几个模块由你决定，最多 5 个（课表和设置不可关闭） |

---

## 功能

### 课表

- **周视图网格**：一屏看清一周，左右滑动切周，顶部显示当前是第几周（滑动可关，改成只点击切周）
- **单双周**：`all` / `odd` / `even` 三种类型，按周次过滤后再渲染，不会把单周课画到双周上
- **点击课程**弹详情，支持编辑名称、教师、地点、节次、周次
- **节次时间跟着插件走**：插件同步时把你们学校的真实作息（第 3 节是 10:25 还是 10:30）写进自己的私有 KV，
  课表左侧时间列直接用它——不是写死在客户端里的默认值
- **学期配置**：开学日期 + 总周数，之后所有"第几周"都由它推算
- **隐藏课程**：不想看到的课可以隐藏，`课表设置 → 已隐藏的课程` 里随时恢复

### 模块（底部导航）

内置 6 个模块，默认开启 课表 / 课程 / 考试 / 设置：

| 模块 | 作用 | 能否关闭 |
|---|---|---|
| 课表 | 周视图网格 | 否 |
| 课程 | 本学期课程列表，按课程聚合 | 是 |
| 考试 | 考试安排 + 倒计时 | 是 |
| 作业 | 作业列表、截止时间、完成状态 | 是 |
| 消息 | 教务通知 / 插件推送的消息 | 是 |
| 设置 | 全部配置入口 | 否 |

插件还可以声明**自定义模块**（比如"成绩查询"），装上插件后就能出现在导航栏配置里。

### 插件

- 插件是单个 `.js` 文件，跑在 `flutter_js`（Android 用 QuickJS）沙箱里
- 宿主提供 `ctx.http` / `ctx.storage` / `ctx.cookie` / `ctx.log` 等能力，插件**拿不到文件系统、拿不到其他插件的数据**
- 创意工坊（皮肤）+ 插件市场（插件）两个入口，安装即用
- 内置两个真实插件：
  - **华北理工大学教务系统**：拉取本学期课表
  - **学习通（超星）**：拉取作业、考试

### 桌面小组件

4 张原生 AppWidget，数据由 Dart 侧算好写成快照，Kotlin 侧只负责画：

| 卡片 | 内容 |
|---|---|
| 下一节课（2×2） | 课程名 + 第几节 + 时间 + 地点，正在上课时标「进行中」 |
| 今日课程（4×3） | 今天所有课的列表，行数随卡片高度自适应 |
| 作业 | 最近几条未完成作业 + 截止时间 |
| 考试 | 最近几场考试 + 倒计时 |

### 其他

- **检查更新**：Gitee 镜像优先、GitHub 兜底，直接读 Release 里的 APK
- **深色模式**：跟随系统 / 强制浅色 / 强制深色
- **课表显示偏好**：左右滑动切周 / 点击切周，按自己的习惯选

---

## 下载安装

**推荐从 Gitee 镜像下载**（GitHub 在国内经常连不上，这也是做镜像的原因）：

| 渠道 | 地址 |
|---|---|
| **Gitee（主）** | <https://gitee.com/zrocks/my_schedule_app/releases> |
| GitHub（备用） | <https://github.com/Z-rocks/my_schedule_app/releases> |

在最新 Release 的 **Assets** 里挑一个：

| 文件 | 大小 | 适合谁 |
|---|---|---|
| `app-release.apk` | ≈ 58 MB | **通用包**，arm64 / armv7 / x86_64 都在里面，不确定就选这个 |
| `app-arm64-v8a-release.apk` | ≈ 20 MB | 近几年的手机基本都是 arm64，省 38 MB |

**环境要求**

- Android 7.0（API 24）及以上
- 无需 root、无需 Google 服务

**覆盖安装说明**

- 包名 `com.zys.myschedule` 和签名从 0.2.0 起没变过，**直接覆盖安装即可，不用卸载、不会丢数据**
- 只有一种情况需要卸载：你自己用 Android Studio 跑过 debug 版（签名不同），两者不能共存

---

## 首次使用

1. 打开 App → **设置 → 学期配置**：填开学日期和总周数（之后所有"第几周"都靠它算）
2. **插件管理** → 找到你学校的插件 → 安装
3. 进入插件详情 → **登录**：内置 WebView 打开教务系统，你正常输入账号密码验证码
4. 登录成功后点 **立即同步**，课表、考试、作业就进来了
5. 回到课表，觉得哪里不对就点开那门课改——改动存在覆盖层，下次同步不会丢

> 课表左侧的节次时间不用手动填：插件同步时会把你们学校的真实作息一起带下来。
> 如果你用的插件没提供，会退回一份默认作息（每节 45 分钟），这时左侧时间只能当参考。

> 没有你学校的插件？自己写一个，见 [插件开发](#插件开发)。插件就是一段 JS，不需要会 Flutter。

---

## 桌面小组件

添加方式：**长按桌面空白处 → 添加小部件 → 找到「校园助手」**。

几个可能踩到的坑：

- **小米 / 红米（MIUI / HyperOS）**：如果长按桌面找不到「校园助手」，或者点了没反应，需要去
  `设置 → 应用设置 → 应用管理 → 校园助手 → 权限管理 → 其他权限 → 桌面快捷方式`，改成「始终允许」。
  这是 MIUI 的一道独立权限，App 里没法自己申请，只能手动开。
- 卡片数据由 App 计算后写入快照文件，所以**刚装完 App 要打开一次**，卡片才会有内容。
- 从 0.2.0 升级到 0.3.x 后，卡片会先显示「打开 App 刷新一下」，打开一次就恢复（快照格式升级了，不是 bug）。

---

## 插件开发

插件是一个 `.js` 文件，导出两个东西：一个 `__plugin` 元信息对象，若干入口函数。

### 最小例子

```js
var __plugin = {
  id: 'my-school',
  name: '我们学校教务系统',
  version: '1.0.0',
  author: '你的名字',
  description: '从教务系统拉取本学期课表',
  capabilities: ['timetable'],
  school: 'XX 大学',
  loginUrl: 'https://jw.example.edu.cn/',
  checkUrl: 'https://jw.example.edu.cn/course/list',
};

function fetchCourses(args) {
  var cookie = ctx.cookie;
  if (!cookie) return { error: '未登录：请先在插件详情页点「登录」' };

  var res;
  try {
    // 第二个参数是 headers 对象（不是 options）
    res = ctx.http.get('https://jw.example.edu.cn/api/courses', {
      Cookie: cookie,
    });
  } catch (e) {
    // ctx.http 在「真失败」时抛错，e.message 是宿主的错误短标识
    // 网络类失败标 retryable，宿主才会自动重试
    return { error: '拉取失败：' + String(e.message || e), retryable: true };
  }

  // 没命中缓存：这一轮还拿不到响应，直接返回，宿主会带着真响应重放
  if (!res.ok) return { error: 'pending' };
  if (res.status !== 200) {
    return { error: 'HTTP ' + res.status + '（Cookie 可能已过期，请重新登录）' };
  }

  var list = JSON.parse(res.body);
  var courses = list.map(function (it) {
    return {
      id: 'my-school:' + it.courseId,
      name: it.courseName,
      teacher: it.teacher,
      unit: Number(it.credit) || 0,
      category: it.category || '',
      sourcePluginId: 'my-school',
      timePlaces: [
        {
          day: it.weekday,             // 1=周一 … 7=周日
          startSession: it.start,      // 从第几节开始
          length: it.length,           // 连上几节
          room: it.room || '',
          weeks: [1, 2, 3, 4],         // 生效周次（基础周次，不含单双过滤）
          rawWeeksText: '1-4周',       // 原始文本，只用于展示
          weekType: 'all',             // all | odd | even
        },
      ],
    };
  });

  return {
    courses: courses,
    sectionTimes: 12,   // 你们学校一天有多少节
  };
}
```

### `__plugin` 字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | 是 | 唯一标识，小写字母 + 连字符 |
| `name` / `version` / `author` / `description` | 是 | 展示用 |
| `capabilities` | 是 | 声明这个插件提供什么能力，如 `timetable` / `homework` / `exam` |
| `school` | 否 | 学校名，用于市场里分组 |
| `loginUrl` | 否 | 点「登录」时 WebView 打开的地址 |
| `checkUrl` | 否 | 判断"登录是否还有效"的地址 |
| `postLoginUrl` | 否 | 登录成功后自动跳转的地址（省得用户自己点菜单） |
| `campusProbeUrl` | 否 | 校园网探测地址；声明后登录页会先判断"校内 / 校外" |
| `offCampusHost` | 否 | 校外网关主机名；探测跳转到它（含子域）即判为校外 |
| `offCampusUserAgent` | 否 | 校外登录用的桌面 UA；很多学校 CAS 只对桌面 UA 展示二维码 |
| `qrLogin` | 否 | CAS 二维码定位配置 `{ host, containerSelector, imageSelector, uuidSelector }`；声明后校外可"保存二维码 → 微信扫一扫" |

> **校外扫码登录（Phase 4.4）**：内置的 NCST 插件已经声明了这四个字段。
> 校园网下仍然直接显示账号密码表单；校外会换桌面 UA 打开 CAS 二维码页，
> 并把二维码保存到相册、拉起微信扫一扫（同机扫码）。
> 二维码是临时登录凭证，登录成功后 App 会自动从相册删除。
>
> ⚠️ 内置插件是**安装到应用私有目录**的，App 升级不会自动覆盖已安装的 `.js`。
> 更新 App 后如果校外扫码入口没出现，请到「插件管理」重新安装一次对应插件
>（会覆盖旧文件，已登录的 Cookie 不受影响）。

### 宿主能力（`ctx`）

| 能力 | 说明 |
|---|---|
| `ctx.http.get(url, headers)` | GET。命中缓存返回 `{ok, status, body, headers}`；**真失败抛 Error**；未命中返回 `{ok:false, error:'pending'}` |
| `ctx.http.post(url, body, headers)` | POST。`body` 传对象会自动 `JSON.stringify`，返回同上 |
| `ctx.cookie` | 当前插件的登录 Cookie 字符串（未登录为空串） |
| `ctx.storage.get(key)` / `ctx.storage.set(key, value)` / `ctx.storage.remove(key)` | 插件私有键值存储，别的插件读不到；值统一按字符串存 |
| `ctx.log.info(msg)` / `ctx.log.error(msg)` | 写入 App 内的插件日志，排查问题就看这里 |
| `ctx.notify.schedule(title, body, triggerAtIso)` | 登记一条通知（当前版本只记录，尚未真正弹出） |
| `ctx.lastHttpError` | 本轮最后一次失败的短标识：`timeout` / `connection` / `bad_response` / `bad_certificate` / `cancelled` / `unknown` |

### 必须遵守的两条约定

1. **入口函数会被执行多次**（因为 `ctx.http` 是"登记请求 → 宿主重放"实现的）。
   所以函数体必须是**纯计算**，副作用只允许 `ctx.storage.set`。
   不要在入口里做自增、累加、发消息这类"跑第二遍就出错"的事。
2. **失败就报错，不要静默返回空数组**。
   返回 `courses: []` 会被上层当成"这学期没课"，比报错危险得多。
   网络类失败请标 `retryable: true`，宿主才知道该重试。

完整的接口测绘、踩坑记录、参数实验见 [`docs/chaoxing-api.md`](docs/chaoxing-api.md)，
内核架构约束见 [`docs/CONTEXT.md`](docs/CONTEXT.md)。

### 开发与调试

```bash
# 内置插件放在 assets/plugins/ 下，pubspec 用目录级声明，新增文件不用改 pubspec
cp my-plugin.js assets/plugins/

# 重新跑起来就能在「插件管理」里看到
flutter run
```

---

## 技术栈

| 用途 | 选型 | 为什么 |
|---|---|---|
| 框架 | Flutter 3.47 / Dart 3.x | 一套代码 + 自绘 UI，课表网格这种高密度布局好控制 |
| 状态管理 | `provider` | 够用且轻，没有引入 codegen |
| 本地存储 | `hive` + `hive_flutter` | 纯 Dart、无原生依赖、读写快 |
| 敏感存储 | `flutter_secure_storage` | Cookie 走系统 Keystore，不落明文 |
| 网络 | `dio` | 拦截器、超时、错误分类比 `http` 好写 |
| 路由 | `go_router` | 声明式，深链好接 |
| WebView | `webview_flutter` 4.7 | 登录必须用真浏览器内核（验证码、JS 跳转） |
| JS 运行时 | `flutter_js` | Android 用 QuickJS，iOS/macOS 用 JavaScriptCore |
| 桌面小组件 | 原生 Kotlin `RemoteViews` | 小组件不能跑 Flutter，只能原生画 |

**平台**：只发布 Android（`minSdk 24` / `targetSdk 36`）。`ios/` `macos/` `windows/` `linux/` `web/` 目录是 `flutter create` 生成的，目前没维护。

---

## 项目结构

```
lib/
├── main.dart / app.dart        入口、路由、Provider 装配
├── models/                     纯数据模型（Course / Exam / Homework / Module …）
├── providers/                  ChangeNotifier 状态层
├── services/                   业务服务（同步、存储、覆盖层、小组件快照、更新检查）
├── runtime/                    ★ 插件运行时：沙箱、上下文、清单校验、调度
├── pages/                      页面（课表 / 课程 / 考试 / 作业 / 消息 / 设置 / 登录 / 同步）
├── theme/                      主题引擎 + 内置皮肤
└── widgets/                    复用组件（课表网格、空态、模块图标）

android/app/src/main/kotlin/com/zys/myschedule/
├── MainActivity.kt             通道桥接（系统设置、小组件、版本号）
├── SystemSettingsBridge.kt     厂商权限引导、包信息
└── widget/                     ★ 4 个 AppWidgetProvider + 快照仓库

assets/
├── plugins/                    内置插件（.js）
└── skins/                      内置皮肤（.skin.json）

docs/
├── CONTEXT.md                  项目宪法：架构约束（改代码前必读）
├── CONTRIBUTING.md             提交规范、分支策略
├── API.md                      已实现接口清单
├── ENV.md                      环境与依赖说明
├── chaoxing-api.md             学习通接口测绘记录
├── ux_issues_summary.md        交互问题汇总与修复记录
└── widget_task_breakdown.md    小组件任务拆解与实施记录
```

---

## 本地运行

### 环境

- Flutter **3.47.x**（`flutter --version` 确认）
- Dart 3.x（随 Flutter 带）
- Android SDK：`compileSdk 36`、`build-tools 36+`
- JDK **17 或以上**（Gradle 9 要求；推荐直接用 Android Studio 自带的 JBR）

### 跑起来

```bash
git clone https://gitee.com/zrocks/my_schedule_app.git
cd my_schedule_app
flutter pub get
flutter run                    # 连真机 / 模拟器
```

### 打包

```bash
# 通用包（推荐分发）
flutter build apk --release

# 分架构包（体积小，但不能跨架构安装）
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`。

> **签名**：release 签名读 `android/key.properties` + keystore 文件，两者都已 gitignore。
> 没有它们时 `flutter build apk --release` 会失败——这是有意的，防止误发未签名包。
> 自己 fork 后想打包，请生成一套自己的 keystore 并写 `key.properties`。
> ⚠️ 换签名后无法覆盖安装旧版本，必须卸载重装。

### 测试

```bash
flutter test
```

### 几个真实踩过的坑

| 现象 | 原因 / 解决 |
|---|---|
| `flutter test` 报 `Invalid WebSocket upgrade request` | 代理环境变量污染了 flutter_tester。清掉再跑：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy flutter test` |
| Gradle 报 `journal-1.lock (拒绝访问)` | 上一个 Gradle 守护进程还占着锁：`cd android && ./gradlew --stop`，再重新构建 |
| Gradle 报一堆假的 `Unresolved reference 'run' / 'file'` | `JAVA_HOME` 指到了太老的 JDK。Gradle 9 的 Kotlin DSL 脚本需要 JDK 17+，建议指向 Android Studio 的 `jbr` |
| 改完 Kotlin 能编译，但小组件还是黑卡 | 资源校验（aapt2）查不出运行时问题。**改完 Kotlin 一定要真跑一次 `flutter build apk`**，并在真机上看卡片 |

---

## 常见问题

**Q：覆盖安装会不会丢课表 / Cookie？**
不会。课表在 Hive、Cookie 在 Keystore，都不随 APK 安装包走。只要包名和签名不变，覆盖安装等同于换了个壳。

**Q：为什么只支持 Android？**
小组件、教务 WebView 登录、Cookie 读取都深度依赖 Android 原生能力。iOS 版短期内不做。

**Q：我的学校没有插件怎么办？**
插件就是一段 JS，见 [插件开发](#插件开发)。写完欢迎提 PR 或发给我，我把它放进插件市场。

**Q：教务系统登录失败 / 同步回来是空的？**
按顺序排查：
1. 先点「登录」在 WebView 里确认网页版能正常进去（验证码、密码错误都会卡在这一步）
2. 网页版能进但同步失败 → 多半是 Cookie 过期，重新登录一次
3. 还是不行 → 看「插件管理 → 插件日志」，里面会有具体报错

**Q：小米手机添加不了小组件？**
见 [桌面小组件](#桌面小组件) 里的 MIUI 说明，需要手动打开「桌面快捷方式」权限。

**Q：会收集我的数据吗？**
不会。App 没有任何上报接口，没有后端服务器。唯一的对外请求是：教务系统（你自己的学校）+ 检查更新（读 Release 的 JSON）。两者都可以在代码里搜到，全部在 `lib/services/` 下。

---

## 路线图

已经能用但还不完整的地方，列出来免得你以为是 bug：

| 功能 | 现状 |
|---|---|
| 数据导出 / 导入 | 入口在「设置 → 数据」，**尚未实现**（点了会提示待实现） |
| 清理缓存 | 入口在，尚未真正清理 |
| 自定义节次时间 | 目前只能由插件提供，App 内还不能手动改 |
| 课表设置里的「显示周末」「显示节次时间」「每节高度」 | 开关在，尚未接上 |
| 平板适配 | 小组件做了三档尺寸，主界面还没专门适配大屏 |
| iOS / 桌面端 | 不做，目录留着但不维护 |

---

## 参与贡献

欢迎 Issue 和 PR。提交前请先读 [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)，核心就两条：

- **提交信息**用 Conventional Commits：`<type>(<scope>): <中文简述>`
  例：`fix(widget): 修掉行布局里 View 导致的黑卡`
- **改代码前先读 [`docs/CONTEXT.md`](docs/CONTEXT.md)**。它规定了架构红线，
  比如"内核不得硬编码任何学校的 URL / 字段名"——这条被破坏，插件化就没意义了

提交 PR 时如果能附上"改之前什么现象、改之后什么现象"，会快很多。

---

## 开源协议

本项目采用 [MIT License](LICENSE)。

简单说：可以自由使用、修改、分发、商用，**但必须保留版权声明**，且作者不承担任何责任。

---

## 联系作者

| | |
|---|---|
| **QQ 交流群** | **982872765** |
| **QQ** | 151392970 |
| **Gitee** | <https://gitee.com/zrocks> |
| **GitHub** | <https://github.com/Z-rocks> |
| **Issue** | <https://gitee.com/zrocks/my_schedule_app/issues> |

用出问题、想要新功能、或者你写了别的学校的插件，都欢迎直接找我，或者直接进 **QQ 群 982872765** 聊。

---

## 免责声明

- 本项目是**个人学习项目**，与任何学校、教务系统厂商、超星/学习通均无关联，不是官方客户端。
- 插件拉取的数据仅供**个人查看自己的课表**使用。请勿用于批量爬取、商业分发或任何违反学校规定的用途。
- 使用本软件产生的任何后果由使用者自行承担。
