# 学习通（超星）接口测绘记录（Phase 8）

> 本文件记录 `chaoxing` 插件所依赖的**真实接口**，全部由 2026-10-16 在真实账号上抓包得到。
> 按 CONTEXT 3.1，这些 URL / 字段名**只能出现在插件里**，内核不得引用。
>
> 抓包工具：`tools/chaoxing/session.js`（Playwright 驱动真实 Chrome + 全量录制 + 本地控制 API）。

## 0. 前置：登录与凭证

- 登录页：`https://passport2.chaoxing.com/login`
- 登录成功后跳转：`https://i.mooc.chaoxing.com/space/index`
- 凭证：**Cookie**（`JSESSIONID` 等），由内核 WebView 登录页写入 secure storage，插件里用 `ctx.cookie` 读取。
- 站点：本账号为**华北理工大学**，课程站点域名为 `mooc1-2.chaoxing.com`。

## 1. 课程列表

```
GET https://mooc1-2.chaoxing.com/visit/courses/study
```

- **不需要任何参数**（`?s=...` 可省略，实测两者返回一致）。
- 返回**服务端渲染的 HTML**（约 98 KB），不是 JSON。
- 每个课程一个 `<li class="courseItem">`：

```html
<li class="courseItem curFile">
  <input type="hidden" name="courseId" value="267787514" />
  <input type="hidden" name="classId"  value="156498244" />
  <div class="Mcon1img httpsClass">
    <a href='/visit/stucoursemiddle?courseid=267787514&clazzid=156498244&vc=1&cpi=344942005'>
      <img src="https://p.ananas.chaoxing.com/..." />
    </a>
  </div>
  <div class="Mconright httpsClass">
    <h3><a class="courseName" href='...' title="综合评价方法">综合评价方法</a></h3>
    <p title="周丽晖">周丽晖</p>          <!-- 教师 -->
    <p title=""></p>
    <p title="23计3">23计3</p>            <!-- 班级 -->
  </div>
</li>
```

| 字段 | 来源 |
|------|------|
| `courseId` | `input[name=courseId]` 的 value |
| `classId` | `input[name=classId]` 的 value |
| `name` | `a.courseName` 的 `title` |
| `teacher` | 第 1 个 `<p title=...>` |
| `className` | 最后一个非空 `<p title=...>` |
| `cpi` | `href` 里的 `cpi=` |

- 实测本账号返回 **68 门课**（含全部历史学期），无分页。

## 2. 每门课的 `enc`（关键）

```
GET https://mooc1-2.chaoxing.com/visit/stucoursemiddle?courseid={courseId}&clazzid={classId}&vc=1&cpi={cpi}
```

- 该请求 **302 跳转**到 `https://mooc1-2.chaoxing.com/mooc-ans/mycourse/studentcourse?courseId=..&clazzid=..&cpi=..&enc=..&fromMiddle=1&vc=1`。
- ⚠️ **`enc` 是每门课独立的**（实测两门课的 enc 不同），**不是账号级**。
- 正确做法：**跟随跳转后的课程主页 HTML 里，直接抠出「作业」「考试」的完整地址**，
  而不是自己拼参数——自己拼会漏掉 `openc`，被服务端判定无权限（见第 5 节）。

课程主页里的导航项（`<a data="..." title="作业">`）：

```html
<a onclick="rmWorkDot('156498244','work',this);" href="javascript:;"
   data="/work/getAllWork?classId=156498244&courseId=267787514&isdisplaytable=2&mooc=1&ut=s&enc=8c5bde376a4b26d43ff853b6ab4ec6ca&cpi=344942005&openc=cc7cb75739bc35908364474874563502"
   title="作业">作业</a>

<a data="/exam-ans/exam/test?classId=156498244&courseId=267787514&ut=s&enc=8c5bde376a4b26d43ff853b6ab4ec6ca&cpi=344942005&openc=cc7cb75739bc35908364474874563502"
   title="考试">考试</a>
```

**拼接规则（重要，两页前缀不同）：**

| 入口 | 相对地址 | 绝对地址 |
|------|----------|----------|
| 作业 | `/work/getAllWork?...` | `https://mooc1-2.chaoxing.com/mooc-ans/work/getAllWork?...` |
| 考试 | `/exam-ans/exam/test?...` | `https://mooc1-2.chaoxing.com/exam-ans/exam/test?...`（**不带 `/mooc-ans`**） |

> 实测把考试拼成 `/mooc-ans/exam-ans/exam/test` 会 404。

## 3. 作业列表

```
GET https://mooc1-2.chaoxing.com/mooc-ans/work/getAllWork?classId=..&courseId=..&isdisplaytable=2&mooc=1&ut=s&enc=..&cpi=..&openc=..
```

**参数必要性（实测，逐项二分）**：

| 参数组合 | 结果 |
|----------|------|
| `ut=s&enc=..&cpi=..&openc=..` | ✅ 完整页面 |
| `enc=..&cpi=..&openc=..`（无 ut） | ✅ 完整页面 |
| `ut=s&cpi=..` | ❌ 822 字节空壳页 |
| `ut=s&cpi=..&openc=..` | ❌ 822 字节空壳页 |
| `ut=s&openc=..` | ❌ 822 字节空壳页 |
| 裸参数 | ❌ 822 字节空壳页 |

→ **`enc` 是必需的；`ut` 可省；`cpi` / `openc` 单独无用。**
（但既然从课程主页抠完整地址最省事，就照单全收。）

返回 HTML，每条作业：

```html
<li style="padding:30px 0">
  <div class="titTxt" data="0">
    <p class="clearfix">
      <a href="javascript:void(0);" class="inspectTask" data="57058627" data2="0" data3="0"
         title="第一章作业">第一章作业</a>
    </p>
    <span class="pt5"><span class="fl">开始时间：</span>2026-10-16 17:29</span>
    <span class="pt5"><span class="fl">截止时间：</span>2026-10-18 23:29</span>
    <span class="pt5"><span class="fl">作业状态：</span><strong>待做</strong></span>
  </div>
  <div class="titOper">
    <a class="Btn_red_1 fr inspectTask" data="57058627" data2="0" data3="0"><span>做作业</span></a>
  </div>
</li>
```

| 字段 | 来源 |
|------|------|
| `workId` | `a.inspectTask` 的 `data` |
| `title` | `a.inspectTask` 的 `title` |
| `startTime` | `开始时间：` 后的 `YYYY-MM-DD HH:mm` |
| `deadline` | `截止时间：` 后的 `YYYY-MM-DD HH:mm` |
| `status` | `作业状态：` 后 `<strong>` 里的文本（`待做` / `已完成` / …） |

> ⚠️ 列表 HTML 里**没有**作业说明/题目内容，正文要另开页面（见第 5 节）。

## 4. 考试列表

```
GET https://mooc1-2.chaoxing.com/exam-ans/exam/test?classId=..&courseId=..&ut=s&enc=..&cpi=..&openc=..
```

返回 HTML，每条考试：

```html
<li>
  <div class="titTxt" style="height:128px;">
    <p>
      <a href="javascript:void(0)"
         onclick="goTest('267126105',10735748,0,'2027-01-08 16:00:00.0',569018852,false,'dad302d7519539486bb401ead79761e3');"
         title="形势与政策2026年秋">形势与政策2026年秋</a>
    </p>
    <span class="pt5"><span class="fl">考试时间：</span>2026-09-18 09:00 至 2027-01-08 16:00</span>
    <span class="">考试条件：完成任务点80%</span>
    <span class="pt5"><span class="fl">考试状态：</span><strong>待做</strong></span>
  </div>
</li>
```

| 字段 | 来源 |
|------|------|
| `testRelationId` | `goTest()` 第 2 个参数 |
| `name` | `a[title]` |
| `startTime` | `考试时间：` 的 `A 至 B` 中的 A |
| `endTime` | `考试时间：` 的 `A 至 B` 中的 B |
| `condition` | `考试条件：` 后的文本 |
| `status` | `考试状态：` 后 `<strong>` 里的文本 |

无考试时页面出现 `暂无内容`。

## 5. 作业正文（题目 / 作业说明）

> 用户已确认接受"打开作答页会留下开始作答记录"这一副作用，因此正文一起抓。

**两步**：

### 5.1 取 `standardEnc`（每份作业独立）

```
GET https://mooc1-2.chaoxing.com/mooc-ans/work/isExpire?classId=..&workRelationId=..&cpi=..&courseId=..
```

返回 JSON（`Content-Type: text/html;charset=UTF-8`，但正文是 JSON）：

```json
{"standardEnc":"98c69cf1536938a94c3ee43e65117dbd","finishStandard":0,"notShowLastAnswer":0,"status":0}
```

- `standardEnc` **每份作业不同**，是打开正文的必要参数。
- `finishStandard` = 完成度百分比要求（`status=1` 表示"章节任务点未完成 N%，不能做作业"）。

### 5.2 打开作业正文

```
GET https://mooc1-2.chaoxing.com/mooc-ans/work/doHomeWorkNew
      ?courseId=..&classId=..&workId=..&workAnswerId=0
      &isdisplaytable=2&mooc=1&enc=..&workSystem=0&cpi=..&openc=..&standardEnc=..
```

- ⚠️ 这里的 `enc` **不是课程主页那个 enc**，而是**作业列表页内嵌的 enc**
  （在 `/work/getAllWork` 返回的 HTML 里，形如 `...&enc=<32位hex>&workSystem=0...`）。
- 不带 `standardEnc` 会返回 913 字节的 `提交失败` 页。
- 返回 HTML（约 77 KB 源码 / 197 KB 渲染后），结构：

```html
<!-- 大题分组 -->
<div class="Cy_TItle1"><h2>一.简答题<em>（共3 题,65.0分）</em></h2></div>

<!-- 单题 -->
<div class="TiMu singleQuesId" data="215486643">
  <div class="Zy_TItle clearfix ">
    <i class="fl">1</i>
    <div class="clearfix fontLabel">
      <p>简述多指标综合评价方法所具备的特点。<br></p>
      （10.0分）
    </div>
  </div>
  <ul class="Zy_ulTk"> ... 作答区（编辑器 / 选项） ... </ul>
</div>
```

| 字段 | 来源 |
|------|------|
| 大题标题 | `div.Cy_TItle1 > h2` 的文本（含"（共N题,M分）"） |
| 题目 ID | `div.TiMu` 的 `data` |
| 题号 | `div.Zy_TItle > i.fl` |
| 题干 | `div.Zy_TItle > div.fontLabel` 的 HTML（含 `<p>` 题干与 `（X分）`） |

- 作业元信息在页面顶部：`题量：9` / `满分：100.0 分` / `创建者：周丽晖` / `截止时间：2026-10-18 23:29`。
- ⚠️ 题目顺序可能被随机化（`randomOptions=true`），两次加载的题序/分值组合可能不同。

## 6. 踩坑记录

1. **必须从课程主页抠完整地址**：只带 `enc` 请求考试接口会被拒（错误页 `[3003] 您长时间没有操作，或没有此页面访问权限`）。
   带上课程主页里那串 `openc` 后，全部课程正常返回。
2. **考试页 URL 前缀与作业不同**（见第 2 节表格）。
3. **`workTestPendingNew` 不适用**：`POST /mooc-ans/api/workTestPendingNew`（body `classIds=...`）
   只返回"待办"，实测本账号返回空数组，即使存在待做作业。故不用它。

## 7. 风控（最重要）

- 2026-10-16 抓包时，**12 秒内连续 136 个请求**直接触发风控：
  后续请求全部返回 **HTTP 202 + 提示页**，浏览器跳转到
  `https://mooc1-2.chaoxing.com/antispiderShowVerify.ac`，文案
  `【9010】操作异常，请输入图片中的验证码`。
- **结论：插件必须限速**。建议：
  - 严格串行，不并发；
  - 每次请求之间加固定间隔（≥ 800 ms）；
  - 单次同步的课程数由用户勾选决定，不默认全量 68 门；
  - 一旦收到 202 或响应里出现 `antispider` / `9010`，立即停止并提示用户"先去浏览器过验证码"。
- 响应编码为 `text/html;charset=utf-8`，中文可正常解码（无需 GBK 处理）。
