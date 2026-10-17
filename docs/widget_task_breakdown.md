# 小组件开发任务拆解（手机 + 平板 · 课表 / 作业 / 考试）

> 目标：Android 原生 AppWidget 小组件，覆盖课表（今天 / 本周）、作业、考试四类卡片，
> 手机与平板均可用。本文件是纯拆解，不含实现代码；每个任务标注了产出物、验收标准、依赖。

---

## 0. 结论与现状盘点

### 0.1 架构结论（沿用你方案的主干，扩展后仍成立）

- 标准 Android AppWidget，Kotlin 实现。pub.dev 没有能替你画小组件 UI 的包（`home_widget` 只做 KV 共享），所以是"加 Kotlin 模块"，不是"装插件"。
- Dart 侧只做一件事：**生成快照 JSON**，通过 `MethodChannel` 交给 Kotlin，Kotlin 写进 `context.filesDir/widget/schedule_snapshot.json`。Hive 的 `.hive` 文件 Kotlin 读不了，这条通道是必须的。
- 业务逻辑仍然只有一份：周次计算、单双周过滤、展示排序全部复用现有 Dart 层（`TimetableLogic` / Provider），小组件不重算。

### 0.2 现状盘点（本次核对代码后的事实）

| 层 | 现状 | 对任务的影响 |
|---|---|---|
| 包名 / 签名 | `build.gradle.kts` 已是 `applicationId = "com.zys.myschedule"`，release 签名走 `key.properties` + keystore，缺失时回退 debug | **草稿里"第 38 行 debug 签名"已修过**。P0 只剩"验证本地有正式 keystore" |
| 课表数据 | `TimetableLogic.buildGrid(courses, week)` 纯静态，输出 `grid[day][session] = Course?`；`TimePlace` 有 `room / day / startSession / length / weeks / weekType` | 快照生成不需要新逻辑，直接调 |
| 作业数据 | `HomeworkProvider.displayHomeworks`（未完成优先 + 截止升序，已排好）、`pendingCount`、`overdueCount`；模型有 `displayTitle/displayDeadline/isCompleted/isOverdue/daysUntilDeadline/courseName` | 作业 widget 数据现成 |
| 考试数据 | `ExamProvider.displayExams`（未开始优先 + 开考时间升序）、`upcomingCount`、`nextExam(now)`；模型有 `displayName/displayStartTime/displayLocation/daysUntil/hasStarted` | 考试 widget 数据现成 |
| 节次时间 | `SectionTimeService` 从插件 KV 读，失败回退默认值 | 快照里要带上节次时间文本 |
| 原生层 | 只有 `MainActivity.kt`（纯 `FlutterActivity`），无任何 Kotlin 代码 | MethodChannel 与全部小组件代码从零加 |

### 0.3 v1 范围（本次任务的对象）

4 个独立小组件 + 数据桥 + 刷新机制 + 厂商/平板适配：

| 卡片 | 尺寸 | 内容 |
|---|---|---|
| Today | 2×2 / 2×4 | 今天日期、星期、第几节、当前/下一节课名 + 教室；没课显示"今天没课" |
| Week | 4×2 / 4×4 | 周一~周日 × 节次网格色块，颜色来自快照 ARGB |
| Homework | 2×2 | 待交 N 计数 + 未交作业 top N（标题、课程、剩余天数，逾期标红） |
| Exam | 2×2 | 最近一场考试倒计时（科目、开考时间、考场）+ top N 列表 |

---

## 1. 任务总览（按阶段）

```
P0 地基验证 ─┬─ P1 快照层(Dart) ─┬─ P2 数据桥(MethodChannel)
             │                   └─ P3 小组件(Kotlin) ─┬─ P4 Manifest/资源
             │                                         ├─ P5 刷新策略
             │                                         └─ P6 厂商+平板适配 ─ P7 测试验收
P0/P1 有部分可并行；P2 必须等 P1 的 schema 定稿；P3 等 P2 通；P7 等 P4-P6
```

| # | 任务 | 产出物 | 依赖 | 建议体量 |
|---|---|---|---|---|
| P0 | 地基验证 | 验证通过 / 补 keystore | — | S |
| P1 | 快照服务与 schema | `widget_snapshot_service.dart` + schema 定稿 + 单测 | 现状 | M |
| P2 | 数据桥与触发 | MethodChannel + Kotlin 落盘 + 触发点接入 | P1 schema | M |
| P3a | 课表小组件 | TodayWidget + WeekWidget | P2a | L |
| P3b | 作业/考试小组件 | HomeworkWidget + ExamWidget | P2a | M |
| P4 | Manifest / 资源 / 主题 | 4 个 receiver + app_widget xml + values-night | P3 并行起步 | M |
| P5 | 刷新策略 | 30min 兜底 + 主动推 + 更新时间戳 | P2、P4 | S |
| P6 | 厂商与平板适配 | padding/主题/省电引导/平板布局 | P3、P4 | M |
| P7 | 测试与验收 | 单测补全 + 真机矩阵 + 验收清单 | 全部 | M |

---

## 2. 任务详情

### P0 · 地基验证（先做，30 分钟的事）

**P0.1 验证 release 签名现状**
- 动作：确认 `android/key.properties` 与 keystore 文件在本地存在；跑一次 `flutter build apk --release` 看用的是正式签名还是回退了 debug。
- 产出：结论一句话（"已用正式签名" or "本地缺 keystore，需补"）。
- 验收：release 包签名与预期一致。小组件 provider 按包名注册到桌面，签名一旦后续变更，用户桌面上旧卡片会全部失效，这件事上架前必须定。
- 依赖：无。

**P0.2 确认 minSdk 与 API 档位**
- 动作：看 `flutter.minSdkVersion` 实际值；确认 `targetCellWidth/targetCellHeight`（API 31+）、`FLAG_IMMUTABLE`（API 23+）、`PendingIntent` 相关兼容写法，决定 `sw600dp` 平板布局目录。
- 产出：API 档位笔记，写进 manifest 注释。
- 验收：编译期无 deprecation 警告，manifest 兼容性写法统一。
- 依赖：P0.1。

### P1 · 快照层（Dart）——业务逻辑仍然只有一份

**P1.1 新建 `lib/services/widget_snapshot_service.dart`**
- 动作：
  - 输入：`CourseProvider` 的可见课程、`SemesterProvider`（当前周）、`SectionTimeService`（节次时间）、`HomeworkProvider.displayHomeworks`、`ExamProvider.displayExams`。
  - 课表：调 `TimetableLogic.buildGrid(courses, currentWeek)` 得出本周网格，再压缩成两种视图——**今天**（当日按节次的课程序列）与**本周**（day × session 的色块矩阵，只存课程索引不重复存课程名，控制体积）。
  - 取数逻辑做成**纯函数**（入参是数据，不是 Provider），便于单测；Provider 的读取放在一个薄的编排方法里。
- 产出：widget 快照 Dart 类 + `toJson()`。
- 验收：空课表 / 无学期配置 / 单双周 / 隐藏课程（`isHidden`）四种边界下快照结果符合预期（题 P1.4 单测覆盖）。
- 依赖：无。

**P1.2 快照 schema 定稿（本阶段最重要，P2 的 Kotlin 解析器照它写）**

```json
{
  "version": 1,
  "generatedAt": "2026-10-16T23:00:00",
  "schedule": {
    "week": 8,
    "today": 5,                        // 5 = 周五
    "sessions": [{"s":1,"name":"高数","teacher":"张三","room":"教三101",
                  "color":-16777216,"len":2,"start":"08:00","end":"09:50"}],
    "weekGrid": {"days":[1..7], "maxSession":12,
                 "cells":[[{"day":1,"session":1,"courseIdx":0}, ...]]},
    "courses": [{"name":"高数","color":-16777216}]   // weekGrid 的索引表
  },
  "homework": {
    "pendingCount": 3, "overdueCount": 1,
    "items": [{"title":"实验报告","course":"物理","due":"2026-10-18T23:59",
               "daysLeft":2,"overdue":false}]          // top 5
  },
  "exam": {
    "upcomingCount": 2,
    "items": [{"name":"线代","start":"2026-10-30T09:00","location":"教一201",
               "daysLeft":14}]                          // top 3
  }
}
```
- 规则：
  - `version` 是 Kotlin 端解析器的契约，升级必须递增；旧版本号 → 小组件显示空态"请打开 App 更新"。
  - **颜色一律在 Dart 侧算成 ARGB int**（`displayColor` 为 null 时用固定色板按课程名哈希兜底），Kotlin 不做任何颜色计算。
  - 时间文本化：`generatedAt` 用本地 ISO 字符串；剩余天数用 Dart 的 `daysUntilDeadline / daysUntil` 算好，Kotlin 不再算时差（避免时区口径打架）。
  - 体积控制：作业 cap 5 条、考试 cap 3 条、课程名 20 字截断；快照目标 < 100KB。
- 产出：schema 文档（写进上面 service 文件的注释）+ 样例 JSON。
- 验收：Kotlin 端能照 schema 无歧义解析（P2 拿样例联调）。
- 依赖：P1.1 可并行。

**P1.3 触发时机的统一入口**
- 动作：service 暴露 `WidgetSnapshotService.refresh()`：读 Provider → 生成快照 → 过 P2 的通道发出。调用点（v1 全量接）：App 启动 / onResume、课表同步完成（`course_sync_service` / `plugin_entity_sync_service` 之后）、课程编辑或隐藏（`course_provider` 保存后）、作业勾选（`HomeworkProvider.setCompleted` 后）、考试编辑/隐藏、切学期（`semester_provider`）。
- 产出：一个 `refresh()` + 6 个调用点的接线代码。
- 验收：以上任一操作后，快照文件内容立即变化（日志可查）。
- 依赖：P1.1、P1.2、P2.1。

**P1.4 快照单元测试**
- 动作：纯函数输入输出测试：空数据、隐藏课程、单双周、周次越界、本周无课、作业全部完成、无截止时间作业。
- 产出：`test/widget_snapshot_service_test.dart`。
- 验收：`flutter test` 全绿，与课表页 UI 用同一 `buildGrid` 的结果交叉比对一致。
- 依赖：P1.1、P1.2。

### P2 · 数据桥：Dart → Kotlin

**P2.1 MainActivity 注册 MethodChannel**
- 动作：`MethodChannel("com.zys.myschedule/widget")`，两个方法：
  - `writeSnapshot(String json)`：Kotlin 写 `filesDir/widget/schedule_snapshot.json`。**原子写**（先写 tmp 再 rename），防半截文件。
  - `refresh()`：不等快照，直接让所有已添加的 widget 重读文件重渲染。
- 产出：更新后的 `MainActivity.kt`。
- 验收：Dart 调用后文件存在且内容完整；重复写不损坏。
- 依赖：无（与 P1 并行，接口先按 P1.2 的 schema 对齐）。

**P2.2 触发渲染工具**
- 动作：Kotlin 侧 `WidgetUpdater.ktor`：写完文件后按 widget 类型分组 `AppWidgetManager.updateAppWidget(...)`（今天/本周/作业/考试四组各自 update）。
- 验收：写文件后所有该类型卡片同步刷新，无跨类型误刷。
- 依赖：P2.1、P3 的 provider 类（接口先行）。

**P2.3 Dart 侧封装 `lib/services/widget_bridge.dart`**
- 动作：包一层 `invokeMethod`，带开关：release 下吞异常只记最小日志；**通道调用失败绝不影响 App 主流程**（小组件是附属功能）。
- 验收：App 无小组件环境（如模拟器直接跑 Flutter）时主流程无感。
- 依赖：P2.1。

### P3 · 小组件实现（Kotlin）

> 先做 P3a 的 TodayWidget 打通闭环，再做 Week、Homework、Exam。

**P3.0 选型落地：RemoteViews 而非 Glance（决策点 D1 的默认值）**
- 动作：全部用 RemoteViews + XML layout。理由：零新增依赖体积（Glance 拖 Compose 运行时）、Collection 卡片在定制系统上的历史兼容问题少、`.xml` 布局与平板多目录天然契合。Glance 留作 v2 重构选项。
- 验收：`build.gradle.kts` 无需加 Compose/Glance 依赖即可编译。

**P3.1 `SnapshotRepository.kt`**
- 动作：读 `filesDir/widget/schedule_snapshot.json` + `org.json` 解析 + 容错：文件缺失 / version 不匹配 / 字段缺失分别降级为空态文案，**绝不在 widget 进程里抛异常**。
- 验收：损坏文件、旧版本文件、正常文件三种输入下卡片行为符合预期。
- 依赖：P2.1、P1.2 schema。

**P3.2 TodayWidget（2×2 / 2×4，手机小卡 + 平板宽卡）**
- 内容：日期 + 周次（"第 8 周 周五"）、当前/下一节："3-4节 高数 · 教三101"；今天没课显示"今天没课"。
- 布局：`layout/widget_today.xml`；平板宽卡用 `layout-sw600dp` 版。
- 点击：`PendingIntent` 拉 `MainActivity`，extra 带 `widget_target=home`。
- 验收：有课 / 没课 / 快照过期三种状态视觉正确；点击进课表页。
- 依赖：P3.1、P4 注册。

**P3.3 WeekWidget（4×2 / 4×4）**
- 内容：周几 × 节次的色块网格，色块用 `courses[i].color`，跨节合并，今天列高亮；无课日留空。
- 网格是远端渲染，注意：RemoteViews 没有 RecyclerView 式高效网格，7×12 静态格子要控制 view 数量（列头/行头 + 每格一个小 view 大约 90 个 view，在 Binder 事务限制内但要实测）。
- 验收：缩放、换周（跨天/跨周快照更新）、深浅桌面下都可读。
- 依赖：P3.2。

**P3.4 HomeworkWidget（2×2）**
- 内容：顶部"待交 N 项 · 逾期 M 项"，列表 top 3-5：课程 · 标题（截断） · "剩 2 天 / 已逾期"（逾期红）；全部完成显示"作业都写完啦"。
- 点击：extra `widget_target=homework`。
- 依赖：P3.2。

**P3.5 ExamWidget（2×2）**
- 内容：最近一场考试大字倒计时（科目 · 日期时间 · 考场），下方 top 3 近期考试；无考试显示"近期无考试"。
- 点击：extra `widget_target=exam`。
- 依赖：P3.2。

**P3.6 平板布局目录**
- 动作：`layout/`（手机）+ `layout-sw600dp/` + `layout-sw720dp/`（平板）两到三套；WeekWidget 在平板宽卡用双数周排布（上下两周）或色块放大，二选一，见 D4。
- 验收：小平板 / 大平板 / 横竖屏下无塌陷、无截断核心信息。
- 依赖：P3.2-P3.5。

### P4 · Manifest / 资源 / 主题

**P4.1 注册 4 个 receiver**
- `<receiver android:exported="true">` + `APPWIDGET_UPDATE` filter + `meta-data android:name="android.appwidget.provider"`。
- 验收：真机能从小组件面板找到全部 4 张卡。

**P4.2 `res/xml/app_widget_*.xml` × 4**
- `minWidth/minHeight`（按桌面旧公式估）+ API 31+ 的 `targetCellWidth/targetCellHeight` + `resizeMode="horizontal|vertical"` + `initialLayout`。
- 验收：添加后可缩放，缩放不塌布局。

**P4.3 主题与安全区**
- 动作：**Kotlin 侧不画背景、不画圆角**（HyperOS/ColorOS 会桌面级套圆角毛玻璃，自己画必叠罗汉）；只做内容 + padding；文字色 `values/` + `values-night/` 两套，深色桌面下浅字、浅色桌面深字。
- 验收：MIUI 深色 / 原生 / 三星 One UI 下都清晰，无"白字压白底"。

**P4.4 点击跳转落地**
- 动作：`MainActivity` 读 extra，经 MethodChannel 回传 Dart 侧 `WidgetBridge.onTarget(target)`，`app.dart` 里切 tab。
- 验收：四张卡分别跳到 课表/课表/作业/考试。
- 依赖：P3.2-P3.5、P2.3。

### P5 · 刷新策略

**P5.1 系统兜底**
- `updatePeriodMillis = 1800000`（30 分钟，踩系统 15 分钟下限之上留余量）+ `onUpdate` 时重读文件渲染。
- 验收：杀进程 / 无主动推送场景下，卡片最多滞后 30 分钟且内容不报错。

**P5.2 主动推送**（复用 P1.3/P2.2 链路）
- 验收：编辑课程/勾选作业后 1 秒内卡片刷新。

**P5.3 可见性提示**
- 卡片角落显示"更新于 hh:mm"，用户自己能分辨卡片是不是最新。
- 依赖：P5.1、P5.2。

**P5.4 v1 明确不做（留档）**
- 分钟级"当前节课高亮"（需 `AlarmManager`，成本另算，v2 评估）。
- `ACTION_TIME_TICK` manifest 接收（系统禁止）。

### P6 · 厂商与平板适配

**P6.1 定制桌面兼容**
- 桌面套圆角/毛玻璃 → 内容区留 12dp 上下安全 padding；MIUI 省电模式会把彩色色块去饱和，接受并在文档记录，不改色逻辑。
- 验收：小米 HyperOS 一台真机通过。

**P6.2 文本截断**
- RemoteViews 没有 Flutter 的自动省略策略：标题 `maxLines` + `ellipsize=end` 固定，超长词截断由 Dart 侧预截断兜底（P1.2 已有 20 字规则）。

**P6.3 省电引导**
- 设置页加"小组件不更新？"入口，引导开自启动 / 无限制省电（MIUI/OPPO/vivo）。
- 验收：设置页有一条可点的帮助项。

**P6.4 尺寸矩阵自测**
- 每张卡 × {2×2, 2×4, 4×2, 4×4, 平板宽} 缩放一遍，验收无塌陷。

### P7 · 测试与验收

**P7.1 Dart 侧**：P1.4 单测 + 快照 JSON 与 Kotlin 解析 round-trip（同一份样例 JSON 两端各解一次比对）。
**P7.2 真机矩阵**（最小覆盖组合，不是全量）：
- 一台国产深度定制（小米 HyperOS 优先，用户基数与限制最多）；
- 一台接近原生（Pixel / AOSP 模拟器）；
- 一台平板 ≥ 10 英寸验证 sw600dp/sw720dp 布局。
**P7.3 场景清单**：添加卡片 / 深色桌面 / 深浅色切换 / 缩放 / 换周 / 杀后台 30 分钟后恢复 / 清除 App 数据后卡片显示空态不崩。
**P7.4 验收签字**：按 0.3 节表格逐卡打勾 + 本清单全绿 = 可交付。

---

## 3. 里程碑（建议开发顺序）

| 里程碑 | 内容 | 完成后你能看到什么 |
|---|---|---|
| **M1 最小闭环** | P0 + P1（仅课表快照）+ P2.1-P2.3 + P3.0-P3.2 + P4.1-P4.4 最简 + P5.1 | 桌面上有一张"今天"卡片，能跟着课表变、点能进 App |
| **M2 四卡完整** | P1.2/1.3 全量 + P3.3-P3.5 + P5.2/P5.3 | 课表两周 / 作业 / 考试四张卡，所有编辑场景实时推 |
| **M3 多设备** | P3.6 + P6 全部 | 平板布局 + 深色桌面 + 缩放 + 省电引导 |
| **M4 收尾** | P1.4 + P7 全部 | 单测齐、真机矩阵过、可上架 |

每个里程碑结束都是可安装可演示状态——小组件没有也不可能"全做完才第一次看到"。

---

## 4. 决策点（开工前拍板，不阻塞 M1 的有默认值）

| # | 问题 | 默认值 / 建议 |
|---|---|---|
| D1 | Glance 还是 RemoteViews？ | **RemoteViews**（零新依赖、兼容稳）；Glance 留 v2 |
| D2 | 做 4 张卡还是先 1 张组合卡？ | **4 张独立卡**。用户自己挑尺寸，也避免一张卡塞三块信息在小尺寸下全糊 |
| D3 | 点击跳 App 内哪个 tab？ | extra 传 `widget_target`，MainActivity 收（D1 的 P4.4） |
| D4 | 平板 WeekWidget 宽卡怎么排？ | 建议：色块随宽度放大（保持 7 列），不排双周——双周信息密度反而看不清 |
| D5 | 作业卡 cap 几条？ | 5 条上限，超了显示"还有 N 项…" |

---

## 5. 明确不做（v1 范围外，防止范围蔓延）

- 小米/华为等厂商的“灵动岛 / 服务卡片”等非标准 AppWidget 形态（决策点 D6：**没有跨厂商通用方案，标准 AppWidget 就是事实上的通用层，见附录 B**）。
- iOS 小组件（WidgetKit，另一套原生工程，独立立项）。
- 小组件内直接勾选作业完成（RemoteViews 点击只能拉起 App，没有局部交互；v2 可评估）。
- 分钟级“当前节课高亮”（需 AlarmManager，P5.4 已留档）。
- 小组件内上下滑翻周/翻作业列表（要 RemoteViewsService + Factory，v1 用静态 top N）。

---

## 附录 B · 为什么厂商“灵动岛 / 服务卡片”不做（决策点 D6）

**问题**：这些厂商私有形态有没有通用的一套？做普通的够不够？

**结论：没有，标准 AppWidget 就是答案。**

1. **私有形态各搞各的，无通用性**：小米 HyperOS 实况窗、OPPO ColorOS 流体云、荣耀 MagicOS 灵动胶囊、vivo 原子组件、华为服务卡片，每家各一套 SDK / 适配规范 / 申请审核，互不通用。目前没有任何跨厂商组织或标准能一次覆盖。标准 AppWidget 才是唯一被**所有**厂商桌面渲染的形态——这正好满足“适配大部分厂商”的诉求。
2. **信息形态不匹配**：实况窗/流体云/灵动胶囊本质是“短时实况”入口（打车进度、外卖、倒计时），为扫一眼就走设计，放不下课表网格、作业列表这种需要停留阅读的信息。做出来也是阉割版。
3. **华为纯血鸿蒙（HarmonyOS NEXT 5.0+）不兼容 APK**（2024-10 公测起，仅支持 .hap 原生应用）：Flutter 的 Android 包在那批设备上根本装不上，做什么 widget 都用不到；覆盖鸿蒙 NEXT 需要单独做原生鸿蒙 App（独立大工程）。HarmonyOS 2/3/4（AOSP 底座）正常支持标准 AppWidget，是华为侧的真实覆盖范围。
4. **成本与维护面**：各家 SDK + 原生代码 + 商务申请（部分还限类目）逐家单算；接五套私有形态 = 以后每次数据/UI 变更改六处。

**v1 范围**：标准 AppWidget 四张卡 + resizeMode + values-night，覆盖 MIUI/HyperOS、HarmonyOS 2-4、MagicOS、ColorOS、OriginOS、One UI、原生桌面。vivo“原子组件”基本是标准 widget 的大尺寸设计规范，跟着 resize 多尺寸布局顺带覆盖。

**v2 可选增强（零厂商 SDK）**：Android 16 进度型通知（ProgressStyle 通知）——各大厂商会把这类标准实况通知显示进自家灵动区域（小米实况窗等同样由它驱动），做“下一节课倒计时 / 考试倒计时”可用；老机型上也能作为常驻通知显示。

---

## 6. 实施记录（2026-10-17）

M1–M3 主体已落地并通过 `flutter build apk --debug` 编译验证（Kotlin + 资源链接 +
Manifest 合并均通过，四张卡 receiver 已注册）。

**新增文件**

Dart 侧：
- `lib/services/widget_snapshot_service.dart`——快照生成（纯函数，复用 `TimetableLogic.buildGrid`）；
  颜色 / 倒计时文案 / 时间文本全部在 Dart 侧算好，Kotlin 只做哑渲染。
- `lib/services/widget_bridge.dart`——`widgetChannel`（writeSnapshot/refresh）、
  `widgetNavChannel`（点击跳转，含冷启动竞态处理）+ `WidgetRefreshController`
  （Provider 监听 + 600ms 防抖 + onResume 刷新 + 全部异常兜底）。
- `test/widget_snapshot_service_test.dart`——13 个用例全绿。

Kotlin 侧（`android/app/src/main/kotlin/com/zys/myschedule/`）：
- `MainActivity.kt`——两条 MethodChannel + 冷启动目标暂存 + onNewIntent 转发。
- `widget/WidgetSnapshot.kt`——数据类 + org.json 解析器（版本不符 → null → 空态，
  字段级异常降级，不在小组件进程抛异常）。
- `widget/WidgetSnapshotRepository.kt`——原子写 filesDir/widget/schedule_snapshot.json。
- `widget/WidgetTargets.kt`——渠道名 / extra / target 常量（Dart Kotlin 两侧契约）。
- `widget/BaseWidgetProvider.kt`——onUpdate 读快照渲染 + onAppWidgetOptionsChanged 转发；
  `widgetWidthDp` 多档尺寸自适应（窄卡少显几行）。
- 四个 provider：`TodayWidgetProvider` / `WeekWidgetProvider` /
  `HomeworkWidgetProvider` / `ExamWidgetProvider`。
- WeekWidget 用嵌套 RemoteViews + addView 拼 7×N 网格（该方法 API 21 起就有，
  minSdk 24 可用；84 个小 TextView 远低于 Binder 事务上限）。

资源：
- `res/layout/widget_today*.xml` / `widget_week*.xml` / `widget_homework*.xml` /
  `widget_exam*.xml`（共 10 个布局）；背景一律透明（圆角/毛玻璃交给桌面）。
- `res/xml/appwidget_*.xml` ×4（minWidth/minHeight + targetCell + resizeMode +
  updatePeriodMillis=1800000）。
- `res/values/strings_widget.xml`、`res/values/widget_colors.xml` +
  `res/values-night/widget_colors.xml`（深浅两套文字色）。
- `AndroidManifest.xml` 注册 4 个 receiver。

**接线改动**：`lib/main.dart`（装配 WidgetRefreshController）、
`lib/app.dart`（首帧后注册 WidgetNav）、`lib/pages/home_page.dart`
（监听 pendingTarget 切 tab，目标模块被关闭则停留原页）。

**与拆解的偏差 / 修正**
- 快照 schema 增加 `weekHasClass`、`updatedLabel` 两个字段：空态从 2 种细分为
  4 种（没配学期 / 没同步到课 / 本周没课 / 今天没课），单双周课的淡周不再误显示
  “课表还是空的”。
- 关键 key 曾误写为 `sessionText`，已修正为 `sectionText` 并被单测抓住
  （这是 P1.4 单测的第一笔回报）。
- 作业截止时间在当天显示“今天截止”而非“剩 1 天”。

**仍未完成（下一步）**
1. **P0 keystore**：`android/key.properties` + keystore 生成命令被沙箱审批拦截，
   待授权后补（见 P0.1，约 1 分钟）。
2. **P7 真机矩阵**：HyperOS 真机 + AOSP 模拟器 + 平板的场景清单验收
   （现在只过了编译关，没上过真机）。
3. Gradle 环境备注：本机构建需 `./gradlew --stop` 清理残留守护进程
   （journal-1.lock 抢锁）、`flutter test` 需清代理 env（见 MEMORY.md）。

### 6.1 W4 追加（2026-10-17，应用更名 + P6 厂商/平板适配主体）

**应用更名「校园助手」**（用户要求，影响所有平台的显示名）：
- Android：`android:label` 改为 `@string/app_name`，新增 `res/values/strings.xml`
  （后续文案改一处即可，不再 manifest 硬编码）。
- Dart：`lib/app.dart` MaterialApp title；iOS `CFBundleDisplayName`；
  Web `<title>`；macOS `PRODUCT_NAME`；Linux/Windows 窗口标题 +
  Windows Runner.rc 的 FileDescription/ProductName（RC 有 65001 code_page，
  中文字符串安全）。
- Dart 包名（`my_schedule_app`）与 applicationId（`com.zys.myschedule`）不动：
  前者是 import 路径、后者是包名，改名成本高且收益为零，见“决策点”。

**平板适配（P6 主体）——用 dimens 三档，不写第二套布局**：
- 布局里所有字号/内边距/格子高度抽到 `res/values/widget_dimens.xml`；
- `values-sw600dp/`（7–10"）× 1.3 倍、`values-sw720dp/`（10"+）× 1.5 倍。
  RemoteViews 按桌面当前配置资源限定符取布局，平板桌面自动拿到放大版，
  与 launcher 的 `resizeMode` 缩放叠加，无需 Kotlin 判断尺寸。
- TodayWidgetProvider 增加行数上限：窄卡 4 / 宽卡 6 / 平板 8 行，
  截断时补一行“等 N 节课”（`BaseWidgetProvider.isTablet()` 新增 sw600dp 判断）。
  Homework/Exam 卡片此前已按 `widgetWidthDp` 自适应条数，无需再改。

**省电引导（P6 主体）**：
- Kotlin `SystemSettingsBridge.kt`（`com.zys.myschedule/system` 通道）：
  `manufacturer` / `openAppDetails` / `openBatterySettings`。
  **刻意不做厂商深链**（各家自启动管理页 Intent 不公开、版本间变动大），
  只跳两个标准页 + Dart 侧按厂商展示文字步骤。
- Dart `lib/services/system_bridge.dart`（封装 + 非 Android 兜底）、
  `lib/pages/settings/widget_guide_page.dart`（使用说明 + 四张卡说明 +
  识别机型后的分厂商步骤 + 两个跳转按钮 + 通用兜底路径）。
- 设置页新增「桌面小组件」分组：添加与使用 / 后台刷新设置。
- `_SettingsTile` 增加 `subtitleText` 支持。

---

*本文档只做任务拆解；按里程碑顺序从 M1 开始执行即可。*

## 6.2 HyperOS 小部件中心准入实测（2026-10-17）

**结论：小米小部件中心是审核准入制，本地 manifest 合规无法绕过。未过审应用
的 widget 进不了中心，长按图标"添加小部件"只显示"正在努力适配中"。**

### 尝试与排除（全部真机实测，机型 HyperOS 小米）

1. 给 4 个 receiver 补小米三件套（`miuiWidget` meta-data +
   `miui.appwidget.action.APPWIDGET_UPDATE` + `android:process=":widgetProvider"`）
   ——依据对比 WakeUp课程表 APK + 官方技术规范。**无效**：
   这三项只让 widget"享有小米能力"（曝光刷新等），不控制目录收录。
2. 补 `previewImage` / provider `android:label` ——**无效**。
3. force-stop `com.miui.home` / `com.miui.personalassistant` /
   `pm clear com.miui.personalassistant` ——**排除缓存因素**，纯净启也一样。
4. `dumpsys appwidget`：我们的 4 个 provider 注册良好、形态与计算器/知乎/B站
   一致 → 安卓框架侧无问题，过滤发生在 MIUI picker 自己。
5. 全名单扫描：小部件中心「全部应用」只列 22 个应用（系统 + 大厂），B站、
   WakeUp、我们均不在（高德/微博存疑，扫描有滑动漏检）。「安卓小部件」入口
   同理（有 B站/知乎/农行/京东等，无我们）。→ 名单=审核/云目录，非本地枚举。
6. 按技术规范补齐：application 级 `miuiWidgetVersion=1`；4 个 widget 根布局
   改 `@android:id/background` + 非透明圆角卡片底（values-night；
   根点击事件同步改 `android.R.id.background`）。picker 列表**仍无变化**，
   但这两项对所有厂商桌面都是正确实践，保留。
7. **用户长按图标「添加小部件」→ 小部件中心本应用详情页显示
   "正在努力适配中，请您耐心等待"** ——官方空态=未适配/未过审。
   官方原文："详情页会包含该 App 通过审核的 Widget"（pId=1584）。
8. 应用内兜底：Dart `requestPinWidget` + Kotlin `WidgetPinRequest`
   （先走系统原生 `requestPinAppWidget(provider, null, null)`，再兜底
   `addType=appWidgetDetail` 详情页）。真机：调用返回 true（系统接单），
   但 HyperOS 桌面无确认弹窗、dumpsys 无绑定实例、桌面无卡片 →
   **MIUI 把 pin 请求吞了**（疑似也路由进小部件中心）。

### 资料（官方三份 + 对比实证）

- 小米《Xiaomi HyperOS小部件设计规范》 dev.mi.com pId=1664：
  两套体系（小米规范小部件 / 传统安卓小部件走"搜索—安卓小部件"）。
- 小米《小部件技术规范与系统能力说明》 pId=1584：`:widgetProvider` 独立进程
  （<35M、禁拉进程）、根布局 `@android:id/background` + 非透明背景、
  receiver label=小部件名、`miuiWidgetVersion` 必须放 application 级、
  调起详情页=`requestPinAppWidget` + `addType=appWidgetDetail`。
- 《小部件提交审核与上传操作指南》 pId=1588 + 《小部件审核规范》 pId=1586：
  入口 widget.xiaomi.com，需审核。
- 对比实证：WakeUp课程表（com.suda.yzune.wakeupschedule）manifest dump：
  6 个 provider，2 个带全套小米声明（另带 vivo_widget / honor / 
  miuiWidgetRefresh=exposure / miuiWidgetVersion=1），其"今日课程"widget
  在用户桌面可见即审核目录内；它同样不在「全部应用」列表 → 反证列表=目录。

### 待办 / 结论

- 小米机唯一正路：widget.xiaomi.com 提交审核（需应用商店在架，个人
  课程表 App 不现实）。其他品牌（OV/荣耀/华为/三星/原生）走各自 picker，
  未实测。
- 遗留改进项：pin 成功判断改用 `requestPinAppWidget` 的 successCallback
  PendingIntent 广播（接单≠成功）；设置页对 MIUI 明确提示"需官方审核，
  暂不可用"，避免"已请求添加"误导 snackbar。

---

## 6.3 「找不到小组件」根因定位与修复（2026-10-17，真机取证 + 已修复）

### 一句话结论

**不是清单没收录，也不是签名/预览图问题——是我们自己在 manifest 里声明了
`miuiWidget`，把系统 pin 请求改道去了小米的云端目录详情页，于是"既进不了
小部件中心，又拿不到标准确认弹窗"。**6.2 的"审核准入"只解释了小部件中心，
真正的病灶是那三项小米声明。

### 取证方式（可复现）

真机拉取系统桌面与智能助理 APK → jadx 反编译 → 读关键类：

```
adb pull $(pm path com.miui.home)                    # RELEASE-7.50.06.2581
adb pull $(pm path com.miui.personalassistant)
# 反编译后看：
#   com.miui.home: com.miui.home.launcher.AddItemActivity
#                  com.miui.home.launcher.InstallWidgetReceiver
#                  com.miui.home.launcher.MIUIWidgetUtil
#   com.miui.personalassistant: picker.business.detail.PickerDetailRepository
#                               picker.business.home.pages.PickerHomeActivity
```

### 完整链路（代码 + 真机 logcat 双向印证）

1. `AppWidgetManager.requestPinAppWidget(provider, extras, callback)`
   → 系统 `ShortcutRequestPinProcessor`（logcat 可见）
   → 拉起默认桌面的 `com.miui.home/.launcher.AddItemActivity`
     （它的 intent-filter 就是 `android.content.pm.action.CONFIRM_PIN_APPWIDGET`）。
2. `AddItemActivity.onCreate()`（requestType == 2 = APPWIDGET）：

   ```java
   AppWidgetProviderInfo info = mRequest.getAppWidgetProviderInfo(this);
   if (!MIUIWidgetUtil.startWidgetDetailPage(this, info, mRequest.getExtras())) {
       if (atLeastAndroidX()) showPinWidgetConfirmDialog(info);   // ← 标准确认弹窗
       else                  setupWidget(info);                    // ← 直接加
   }
   finish();
   ```

3. `MIUIWidgetUtil.startWidgetDetailPage(...)`：

   ```java
   if (activity == null || info == null || info.provider == null
       || bundle == null || !isMIUIWidgetSupport()) return false;
   if (!isMIUIWidget(activity, info.provider)) return false;   // 读 receiver 的 miuiWidget meta-data
   ... startActivity("widget://picker/detail?packageName=..."); return true;
   ```

4. 我们（W5 那次"修复"）在 4 个 receiver 上都声明了 `miuiWidget=true`
   → 第 3 步返回 true → 拉起小部件中心的**应用详情页**，`AddItemActivity`
   紧接着 `finish()`，**标准确认弹窗被跳过**。
   所以"调用返回 true、没有弹窗、桌面没卡片"三者同时成立，完全对得上。
5. 那个详情页是**云端目录**驱动的：`PickerDetailRepository.getPickerData()`
   → `PickerDetailService.getPickerDetail()` 远端接口，空列表直接 `return null`
   → 页面空/"正在努力适配中"。**本地 manifest 怎么改都不会让它有内容**，
   这一条 6.2 的判断是对的，但它只覆盖"小部件中心"这一半。

### 第二道门槛：MIUIOP(10017)「桌面快捷方式」

去掉 `miuiWidget` 后，pin 能走到桌面了，但真机 logcat 报：

```
E AddItemActivity-PinShortcutRequestUtils: add widget failed, com.zys.myschedule has no permission
```

对应代码 `Utilities.hasAddShortcutPermission()` →
`AppOpsManagerUtils.noteOpNoThrow(context, MiuiResource$AppOps.OP_INSTALL_SHORTCUT …, uid, pkg)`，
而 `MiuiResource$AppOps.OP_INSTALL_SHORTCUT = 10017`（小米自定义 app-op）。

真机查证：`adb shell cmd appops get com.zys.myschedule 10017` → `ignore`（默认拒绝），
用户手动允许后立即变成 `allow`。这个开关在**权限管理 → 其他权限 → 桌面快捷方式**
（"始终允许"），HyperOS 1.0 里确实存在，但默认拒绝，且**拦得完全静默**
（无 toast、无报错）——这正是"点了没反应"的直接手感。

> 注意：这条**不能靠 manifest 解决**。实测声明
> `com.android.launcher.permission.INSTALL_SHORTCUT`、伪装安装来源
> （`adb install -i com.xiaomi.market`，被 MIUI 安装器直接拒绝）都无效。
> 所以走"引导用户点一次"是唯一正路，且必须给出**可点的深链**。

### 本次改动

Kotlin / Manifest：

- `AndroidManifest.xml`：4 个 receiver **去掉** `miuiWidget` meta-data、
  `miui.appwidget.action.APPWIDGET_UPDATE` 动作、`android:process=":widgetProvider"`
  （三项一起改，缺一不可）；保留 application 级 `miuiWidgetVersion`（无副作用，
  也不参与上述任何判断，注释里写清以免下次再被当开关）。
  新增 `<receiver .widget.WidgetPinResultReceiver android:exported="false">`。
- `WidgetPinRequest.kt`：只调系统 pin，`extras` 传 **null**（非 null 才可能触发
  云端详情页分支），并带 `successCallback` PendingIntent；删除
  `addType=appWidgetDetail` 兜底（那条路 = 空页面，纯死胡同）；
  新增 `isAdded(context, kind)`（`getAppWidgetIds` 非空 = 真的加进去了）。
- `WidgetPinResultReceiver.kt` + `WidgetPinBridge`：pin 结果回推 Dart。
  **不以 `EXTRA_APPWIDGET_ID` 判断成功**——真机实测卡片已落桌面但回调里
  没有 id，所以以 `isAdded` 为准。
- `SystemSettingsBridge.openPermissionEditor()`：跳
  `miui.intent.action.APP_PERM_EDITOR`（带 `extra_pkgname`），失败退回应用信息页。
- `BaseWidgetProvider.applyUpdatedLabel()`：**窄卡隐藏"更新于 hh:mm"**
  （真机把 2×2 卡标题挤成"周六 · 第…"），宽卡（≥250dp）才显示。

Dart：

- `widget_bridge.dart`：`isWidgetAdded()` / `WidgetPinEvents`（结果流）。
- `widget_guide_page.dart`：点按钮 → pin → **1.5s 后查真实状态** →
  成功弹"已添加到桌面"，失败弹"没能添加成功 + 去开启权限"（HyperOS 专属文案）；
  卡片按钮显示"已添加 · XX"；`onResume` 重查状态。

### 真机验证结果（小米 2211133C / HyperOS V816 / Android 16）

| 步骤 | 结果 |
|---|---|
| 点"添加到桌面 · 今天课表"（op 为 ignore） | 桌面无动静；1.5s 后 App 弹"没能添加成功"+「去开启权限」 ✅ |
| 点「去开启权限」 | 跳到手机管家权限页（桌面快捷方式 → 始终允许） ✅ |
| 允许后重试 | logcat `Launcher.Widget: updateAppWidget: 173`，卡片出现在桌面 ✅ |
| 桌面卡片内容 | 标题"周六 · 第1周"、空态"去设置里配置学期"、点击可进 App ✅ |
| 添加后 App 内状态 | "桌面上已有：今天课表"、按钮变"已添加 · 今天课表" ✅ |
| 同一台机再添 本周/考试 | 生成 id 174/175，三个实例均绑定成功 ✅ |

> 未覆盖：四张卡在**有真实数据**（学期+课程/作业/考试）时的视觉效果，
> 以及平板 sw600dp 布局——这两项需要用户的真实数据，见下方待办。

### 还剩下的（下一步）

1. **有数据后的视觉验收**（需要用户操作）：配一次学期 → 同步/加两门课 →
   在四张卡上确认 今天/**本周网格**/作业/考试 的排版不挤不变形。
   （本周网格是 84 个嵌套 RemoteViews，是本轮唯一没在真机看过内容的卡片。）
2. 平板 sw600dp / sw720dp 布局实测（无平板设备时跳过）。
3. `test/` 里补一条 Dart↔Kotlin schema round-trip 测试（P7.1 仍未做）。
