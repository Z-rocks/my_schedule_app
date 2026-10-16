// 学习通（超星）插件（Phase 8）
//
// ⚠️ 这是**唯一**允许出现学习通 URL / 字段名的地方（CONTEXT 3.1：
//    内核不得硬编码任何学校 URL / 字段名 / 接口路径）。
//
// ## 接口测绘
// 全部 URL 与字段结构由 2026-10-16 在真实账号上抓包得到，
// 完整记录见 `docs/chaoxing-api.md`（含参数必要性实验与踩坑）。
//
// ## 幂等约定（CONTEXT 3.6，必读）
// 入口函数会被宿主**执行多次**：`ctx.http` 用"登记待办 + 宿主重放"实现，
// 命中缓存才拿得到响应，未命中时返回 `{ok:false,error:'pending'}` 并排队。
// 因此本插件的每个入口都遵循同一套写法：
//   ① 先把**同一层**的请求全部发出去（登记），
//   ② 再统一检查有没有非 ok 的（含 pending）——有就立刻返回，
//      宿主会带着真响应重放；
//   ③ 全部 ok 才解析，并登记下一层的请求。
// 这样"一层一轮"，整个流程的轮数 = 层数 + 1，必须 ≤ `kMaxReplayRounds`(8)。
// 本插件最深的 `fetchHomeworks` 是 5 轮（课程主页 → 作业列表 → isExpire →
// 作业正文 → 收尾），留有足够余量。
//
// ⚠️ **同一层必须批量登记**：若写成"循环里请求完立刻用结果"，每轮只能推进
//    一个请求，选 5 门课就会超出 8 轮上限。
//
// ## 返回约定
// 成功：`{ courses | homeworks | exams: [...], warnings: [...] }`
// 失败：`{ error: '人话原因' }` —— **宁可报错也不静默返回空数组**
//       （空数组会被上层当成"确实没有作业"，比报错危险得多）。
// 网络类失败标 `retryable: true`（Phase 4.3 契约，宿主据此自动重试）。
//
// ## 风控（务必保留）
// 学习通有反爬：实测 12 秒内 136 个请求会触发
// `【9010】操作异常，请输入图片中的验证码`。因此：
//   - 所有请求**严格串行**（宿主保证）；
//   - 单次只抓用户**勾选**的课程，绝不默认全量；
//   - 识别到拦截页立刻返回可读错误，不要继续打。
var __plugin = {
  id: 'chaoxing',
  name: '学习通',
  version: '1.0.0',
  author: 'MySchedule',
  description: '从学习通（超星）拉取课程列表、作业与考试（需先在详情页登录）',
  capabilities: ['homework', 'exam'],
  school: '通用（超星学习通）',
  loginUrl: 'https://passport2.chaoxing.com/login',
  checkUrl: 'https://i.mooc.chaoxing.com/',

  // ───────────────────── 入口 1：课程列表 ─────────────────────
  //
  // 只发 1 个请求，返回全部课程（含历史学期），供用户在 App 里勾选。
  // 实测本账号返回 68 门，无分页。
  fetchCourseList: function (args) {
    var cookie = ctx.cookie;
    if (!cookie) return __cx_authError();

    var resp = __cx_get(__CX_HOST + '/visit/courses/study', { 'Cookie': cookie });
    var bad = __cx_check(resp, '拉取课程列表');
    if (bad) return bad;

    var courses = __cx_parseCourseList(resp.body);
    if (courses === null) {
      return { error: '课程列表结构无法识别（多半是登录已过期，请重新登录）' };
    }
    ctx.log.info('学习通：解析出 ' + courses.length + ' 门课程');
    return { courses: courses, warnings: [] };
  },

  // ───────────────────── 入口 2：作业 ─────────────────────
  //
  // args: { courses: [{ courseId, classId, cpi, name }], withContent: true }
  // 返回: { homeworks: [...], warnings: [...] }
  fetchHomeworks: function (args) {
    var cookie = ctx.cookie;
    if (!cookie) return __cx_authError();

    var list = (args && args.courses) || [];
    if (!list.length) {
      return { homeworks: [], warnings: ['未选择任何课程'] };
    }
    var withContent = !(args && args.withContent === false);
    var headers = { 'Cookie': cookie };
    var warnings = [];
    var i, j, bad;

    // ── 第 1 层：课程主页（拿作业入口地址；enc/cpi/openc 都在里面）──
    var mid = [];
    for (i = 0; i < list.length; i++) {
      mid.push(__cx_get(__CX_HOST + '/visit/stucoursemiddle?courseid=' +
        encodeURIComponent(list[i].courseId) + '&clazzid=' +
        encodeURIComponent(list[i].classId) + '&vc=1&cpi=' +
        encodeURIComponent(list[i].cpi), headers));
    }
    for (i = 0; i < mid.length; i++) {
      bad = __cx_check(mid[i], '打开课程「' + list[i].name + '」');
      if (bad) return bad;
    }

    var entries = [];
    for (i = 0; i < mid.length; i++) {
      var e = __cx_extractWorkEntry(mid[i].body);
      if (!e) {
        warnings.push('课程「' + list[i].name + '」没有找到作业入口，已跳过');
        entries.push(null);
        continue;
      }
      e.course = list[i];
      entries.push(e);
    }

    // ── 第 2 层：作业列表 ──
    var workResps = [];
    for (i = 0; i < entries.length; i++) {
      workResps.push(entries[i]
        ? __cx_get(__CX_HOST + entries[i].workUrl, headers)
        : null);
    }
    for (i = 0; i < workResps.length; i++) {
      if (!workResps[i]) continue;
      bad = __cx_check(workResps[i], '拉取作业列表');
      if (bad) return bad;
    }

    var works = [];
    for (i = 0; i < entries.length; i++) {
      if (!workResps[i]) continue;
      var parsed = __cx_parseWorkList(workResps[i].body);
      var workEnc = __cx_extractWorkEnc(workResps[i].body);
      for (j = 0; j < parsed.length; j++) {
        parsed[j].course = entries[i].course;
        parsed[j].entry = entries[i];
        parsed[j].workEnc = workEnc;
        works.push(parsed[j]);
      }
    }

    if (!withContent || !works.length) {
      return __cx_finishHomeworks(works, warnings, false);
    }

    // ── 第 3 层：isExpire（取每份作业的 standardEnc）──
    var expireResps = [];
    for (i = 0; i < works.length; i++) {
      expireResps.push(__cx_get(__CX_HOST + '/mooc-ans/work/isExpire?classId=' +
        encodeURIComponent(works[i].course.classId) + '&workRelationId=' +
        encodeURIComponent(works[i].workId) + '&cpi=' +
        encodeURIComponent(works[i].course.cpi) + '&courseId=' +
        encodeURIComponent(works[i].course.courseId), headers));
    }
    for (i = 0; i < expireResps.length; i++) {
      bad = __cx_check(expireResps[i], '获取作业参数');
      if (bad) return bad;
    }

    // ── 第 4 层：作业正文（题目）──
    var detailResps = [];
    for (i = 0; i < works.length; i++) {
      var std = __cx_parseStandardEnc(expireResps[i].body);
      if (!std) {
        // 未完成章节任务点时服务端不给 standardEnc，正文自然拿不到；
        // 这不是错误，只影响"作业内容"，元信息照常保留。
        detailResps.push(null);
        continue;
      }
      detailResps.push(__cx_get(__cx_buildWorkDetailUrl(works[i], std), headers));
    }
    for (i = 0; i < detailResps.length; i++) {
      if (!detailResps[i]) continue;
      bad = __cx_check(detailResps[i], '打开作业正文');
      if (bad) return bad;
    }

    for (i = 0; i < works.length; i++) {
      if (!detailResps[i]) continue;
      var content = __cx_parseWorkContent(detailResps[i].body);
      if (content) works[i].content = content;
    }

    return __cx_finishHomeworks(works, warnings, true);
  },

  // ───────────────────── 入口 3：考试 ─────────────────────
  //
  // args: { courses: [{ courseId, classId, cpi, name }] }
  fetchExams: function (args) {
    var cookie = ctx.cookie;
    if (!cookie) return __cx_authError();

    var list = (args && args.courses) || [];
    if (!list.length) {
      return { exams: [], warnings: ['未选择任何课程'] };
    }
    var headers = { 'Cookie': cookie };
    var warnings = [];
    var i, bad;

    // ── 第 1 层：课程主页 ──
    var mid = [];
    for (i = 0; i < list.length; i++) {
      mid.push(__cx_get(__CX_HOST + '/visit/stucoursemiddle?courseid=' +
        encodeURIComponent(list[i].courseId) + '&clazzid=' +
        encodeURIComponent(list[i].classId) + '&vc=1&cpi=' +
        encodeURIComponent(list[i].cpi), headers));
    }
    for (i = 0; i < mid.length; i++) {
      bad = __cx_check(mid[i], '打开课程「' + list[i].name + '」');
      if (bad) return bad;
    }

    var entries = [];
    for (i = 0; i < mid.length; i++) {
      var e = __cx_extractExamEntry(mid[i].body);
      if (!e) {
        warnings.push('课程「' + list[i].name + '」没有找到考试入口，已跳过');
        entries.push(null);
        continue;
      }
      e.course = list[i];
      entries.push(e);
    }

    // ── 第 2 层：考试列表 ──
    var examResps = [];
    for (i = 0; i < entries.length; i++) {
      examResps.push(entries[i]
        ? __cx_get(__CX_HOST + entries[i].examUrl, headers)
        : null);
    }
    for (i = 0; i < examResps.length; i++) {
      if (!examResps[i]) continue;
      bad = __cx_check(examResps[i], '拉取考试列表');
      if (bad) return bad;
    }

    var exams = [];
    for (i = 0; i < entries.length; i++) {
      if (!examResps[i]) continue;
      var parsed = __cx_parseExamList(examResps[i].body);
      for (var k = 0; k < parsed.length; k++) {
        parsed[k].course = entries[i].course;
        exams.push(parsed[k]);
      }
    }

    var out = [];
    for (i = 0; i < exams.length; i++) out.push(__cx_toExamJson(exams[i]));
    ctx.log.info('学习通：解析出 ' + out.length + ' 场考试');
    return { exams: out, warnings: warnings };
  }
};

// ───────────────────────── 常量 ─────────────────────────
//
// 放在 `__plugin` 外面：运行时用 `Object.keys(__plugin).filter(typeof === 'function')`
// 收集入口函数，工具函数/常量放进对象会被误报成入口函数。

/// 学习通课程站点（本账号实测域名；学习通按学校分配 mooc1-N，此域名可用）。
var __CX_HOST = 'https://mooc1-2.chaoxing.com';

/// 单条文本字段的最大长度，防止异常页面把超长串塞进模型。
var __CX_MAX_TEXT = 4000;

/// 单份作业正文最多保留的题目数（防超长）。
var __CX_MAX_QUESTIONS = 60;

// ───────────────────────── 网络封装 ─────────────────────────

/// 发一个 GET，**不抛异常**：失败与 pending 都编码成 `{ok:false,...}`。
///
/// 为什么吞掉异常：插件要在"统一检查"阶段区分 pending 与真失败，
/// 抛异常会打断"先批量登记、再统一检查"的写法。
function __cx_get(url, headers) {
  try {
    return ctx.http.get(url, headers);
  } catch (e) {
    return { ok: false, error: String((e && e.message) || e), thrown: true };
  }
}

/// 统一检查一个响应；有问题就返回"可重试/不可重试"的失败对象，否则返回 null。
///
/// `pending` 也走这里返回错误对象——这是**有意的**：宿主只看待办列表，
/// 插件返回什么它都会重放；而"提前返回"正是让每轮只推进一层的机制。
function __cx_check(resp, what) {
  if (!resp || resp.ok !== true) {
    var err = (resp && resp.error) || 'unknown';
    if (err === 'pending') {
      // 本轮还没发出去，宿主马上会补上并重放。
      return { error: what + '：等待请求返回', retryable: true };
    }
    return __cx_netFail(what + '失败：' + err);
  }
  if (resp.status === 202 || __cx_isBlocked(resp.body)) {
    return {
      error: what + '被学习通风控拦截（【9010】操作异常）。' +
        '请先在浏览器里打开学习通过一次验证码，然后减少一次抓取的课程数再试。'
    };
  }
  if (resp.status !== 200) {
    var msg = what + '失败：HTTP ' + resp.status;
    if (resp.status >= 500) return __cx_netFail(msg);
    return { error: msg + '（Cookie 可能已过期，请重新登录）' };
  }
  return null;
}

/// 构造"网络层失败"的返回对象（Phase 4.3 契约）。
function __cx_netFail(message) {
  var kind = '';
  try { kind = ctx.lastHttpError || ''; } catch (e) { kind = ''; }
  return { error: message, retryable: true, errorKind: kind };
}

/// 未登录。
function __cx_authError() {
  return { error: '未登录：Cookie 为空，请先点「登录」完成学习通登录' };
}

/// 是不是风控拦截页。
function __cx_isBlocked(html) {
  if (!html) return false;
  return html.indexOf('9010') >= 0 ||
    html.indexOf('antispider') >= 0 ||
    html.indexOf('请输入图片中的验证码') >= 0;
}

// ───────────────────────── 通用解析工具 ─────────────────────────

/// 取正则第一个捕获组；无匹配返回 `null`。
function __cx_pick(text, re) {
  if (!text) return null;
  var m = text.match(re);
  return m && m.length > 1 ? m[1] : null;
}

/// 去掉所有标签、压缩空白，并做实体反转义。
function __cx_text(html) {
  if (!html) return '';
  var s = String(html)
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<[^>]*>/g, ' ');
  return __cx_unescape(s).replace(/[ \t\u00a0]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n').replace(/^\s+|\s+$/g, '');
}

/// HTML 实体反转义（只处理常见的几种）。
function __cx_unescape(s) {
  if (!s) return '';
  return String(s)
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&ldquo;/g, '“')
    .replace(/&rdquo;/g, '”')
    .replace(/&mdash;/g, '—')
    .replace(/&hellip;/g, '…')
    .replace(/&amp;/g, '&');
}

/// 按 `<li>` 切块，返回每块（**保留 `<li ...>` 起始标签**——课程/作业的识别
/// 关键 class 就写在标签上，丢掉标签会导致一个都匹配不到）。
///
/// 为什么不用一条大正则去匹配 `<li ...>...</li>`：非贪婪匹配在"某个 `<li>`
/// 内部没有目标 class"时会**跨块吞并**，把两条记录粘成一条。
///
/// 标签正则必须是 `<li(?:\s[^>]*)?>`：`<li[^>]*>` 会**误匹配 `<link ...>`**
/// （`<li` 是 `<link` 的前缀），把整页样式表也切成一块。
function __cx_splitLi(html) {
  if (!html) return [];
  var parts = html.split(/(<li(?:\s[^>]*)?>)/i);
  var out = [];
  for (var i = 1; i < parts.length; i += 2) {
    var tag = parts[i];
    var rest = parts[i + 1] === undefined ? '' : parts[i + 1];
    var end = rest.indexOf('</li>');
    out.push(tag + (end >= 0 ? rest.substring(0, end) : rest));
  }
  return out;
}

/// `YYYY-MM-DD HH:mm` → `YYYY-MM-DDTHH:mm:00`（Dart `DateTime.parse` 按本地时间解析）。
function __cx_iso(local) {
  if (!local) return null;
  var t = String(local).replace(/^\s+|\s+$/g, '');
  if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(t)) return null;
  return t.replace(' ', 'T') + ':00';
}

/// 截断过长文本。
function __cx_clip(s, max) {
  if (!s) return '';
  var t = String(s);
  var limit = max || __CX_MAX_TEXT;
  return t.length > limit ? t.substring(0, limit) + '…' : t;
}

// ───────────────────────── 课程列表 ─────────────────────────

/// 解析课程列表 HTML；结构不符返回 `null`（调用方据此报"登录可能已过期"）。
function __cx_parseCourseList(html) {
  if (!html || html.indexOf('courseItem') < 0) return null;

  var courses = [];
  var chunks = __cx_splitLi(html);
  for (var i = 0; i < chunks.length; i++) {
    var li = chunks[i];
    if (li.indexOf('courseItem') < 0) continue;

    var courseId = __cx_pick(li, /name="courseId"\s+value="([^"]*)"/i);
    var classId = __cx_pick(li, /name="classId"\s+value="([^"]*)"/i);
    var name = __cx_pick(li, /class="courseName"[^>]*title="([^"]*)"/i);
    var cpi = __cx_pick(li, /cpi=(\d+)/);
    if (!courseId || !classId) continue;

    // 教师 / 班级：`<p title="...">` 序列里第一个和最后一个非空值。
    var ps = [];
    var re = /<p\s+title="([^"]*)">/gi;
    var m;
    while ((m = re.exec(li)) !== null) {
      if (m[1] && m[1].replace(/\s/g, '') !== '') ps.push(__cx_unescape(m[1]).replace(/^\s+|\s+$/g, ''));
    }

    courses.push({
      id: String(courseId) + '_' + String(classId),
      courseId: String(courseId),
      classId: String(classId),
      cpi: cpi ? String(cpi) : '',
      name: __cx_clip(__cx_unescape(name || ''), 200),
      teacher: ps.length ? ps[0] : '',
      className: ps.length > 1 ? ps[ps.length - 1] : ''
    });
  }
  return courses.length ? courses : null;
}

// ───────────────────────── 作业 ─────────────────────────

/// 从课程主页 HTML 抠出作业入口（**不要自己拼参数**：会漏掉 openc 而被判无权限）。
function __cx_extractWorkEntry(html) {
  var url = __cx_pick(html, /data="([^"]*\/work\/getAllWork[^"]*)"/i);
  if (!url) return null;
  return { workUrl: __cx_unescape(url) };
}

/// 从考试课程主页 HTML 抠出考试入口。
function __cx_extractExamEntry(html) {
  var url = __cx_pick(html, /data="([^"]*\/exam-ans\/exam\/test[^"]*)"/i);
  if (!url) return null;
  return { examUrl: __cx_unescape(url) };
}

/// 作业列表页里内嵌的 `enc`（**与课程主页那个 enc 不同**，是打开正文要用的）。
function __cx_extractWorkEnc(html) {
  return __cx_pick(html, /enc=([0-9a-f]{16,})&workSystem=0/i);
}

/// 解析作业列表。
function __cx_parseWorkList(html) {
  var out = [];
  var chunks = __cx_splitLi(html);
  for (var i = 0; i < chunks.length; i++) {
    var li = chunks[i];
    if (li.indexOf('class="inspectTask"') < 0) continue;

    var workId = __cx_pick(li, /class="inspectTask"[^>]*data="(\d+)"/i);
    if (!workId) continue;

    out.push({
      workId: String(workId),
      title: __cx_clip(__cx_unescape(__cx_pick(li, /class="inspectTask"[^>]*title="([^"]*)"/i) || ''), 300),
      startTime: __cx_pick(li, /开始时间：<\/span>\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2})/),
      deadline: __cx_pick(li, /截止时间：<\/span>\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2})/),
      status: __cx_unescape(__cx_pick(li, /作业状态：<\/span>\s*<strong>\s*([^<]*?)\s*<\/strong>/i) || '')
    });
  }
  return out;
}

/// `isExpire` 的 JSON 里取 `standardEnc`。
function __cx_parseStandardEnc(body) {
  if (!body) return null;
  var m = body.match(/"standardEnc"\s*:\s*"([0-9a-f]{16,})"/i);
  return m ? m[1] : null;
}

/// 拼作业正文地址（`enc` 用作业列表页那个，`standardEnc` 来自 isExpire）。
function __cx_buildWorkDetailUrl(work, standardEnc) {
  var c = work.course;
  return __CX_HOST + '/mooc-ans/work/doHomeWorkNew?courseId=' +
    encodeURIComponent(c.courseId) + '&classId=' + encodeURIComponent(c.classId) +
    '&workId=' + encodeURIComponent(work.workId) + '&workAnswerId=0' +
    '&isdisplaytable=2&mooc=1&enc=' + encodeURIComponent(work.workEnc || '') +
    '&workSystem=0&cpi=' + encodeURIComponent(c.cpi) +
    '&openc=' + encodeURIComponent(__cx_pick(work.entry.workUrl, /openc=([0-9a-f]+)/i) || '') +
    '&standardEnc=' + encodeURIComponent(standardEnc);
}

/// 解析作业正文页的题量与题目。
///
/// 返回 `{ amount, fullScore, text }`；解析不出题目时返回 `null`。
function __cx_parseWorkContent(html) {
  if (!html || html.indexOf('class="TiMu') < 0) return null;

  var amount = __cx_pick(html, /题量：\s*(\d+)/);
  var fullScore = __cx_pick(html, /满分：[\s\S]{0,60}?([\d.]+)\s*分/);

  // 大题分组：`<div class="Cy_TItle1"><h2>一.简答题<em>（共3 题,65.0分）</em></h2></div>`
  // 与题目按文档顺序交错，这里按出现位置切片，把题目归到所属大题下。
  var sections = [];
  var reSec = /class="Cy_TItle1"[\s\S]*?<h2>([\s\S]*?)<\/h2>/gi;
  var m;
  while ((m = reSec.exec(html)) !== null) {
    sections.push({ at: m.index, title: __cx_text(m[1]) });
  }

  var questions = [];
  var parts = html.split(/<div class="TiMu/);
  var offset = html.indexOf('<div class="TiMu');
  for (var i = 1; i < parts.length; i++) {
    var at = offset + 1;
    offset += parts[i].length + '<div class="TiMu'.length;
    var chunk = parts[i];
    var no = __cx_pick(chunk, /<i class="fl">\s*([^<]*?)\s*<\/i>/i);
    var stem = __cx_pick(chunk, /class="[^"]*fontLabel[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
    var text = __cx_text(stem || '');
    if (!text) continue;
    questions.push({ at: at, no: no || String(questions.length + 1), text: text });
    if (questions.length >= __CX_MAX_QUESTIONS) break;
  }
  if (!questions.length) return null;

  // 组装成纯文本：大题标题 + 题目。
  var lines = [];
  if (amount) lines.push('题量：' + amount + (fullScore ? '　满分：' + fullScore + ' 分' : ''));
  var si = -1;
  for (var q = 0; q < questions.length; q++) {
    while (si + 1 < sections.length && sections[si + 1].at < questions[q].at) {
      si++;
      lines.push('');
      lines.push(sections[si].title);
    }
    lines.push(questions[q].no + '. ' + questions[q].text);
  }

  return {
    amount: amount ? Number(amount) : 0,
    fullScore: fullScore ? Number(fullScore) : 0,
    text: __cx_clip(lines.join('\n'))
  };
}

/// 作业 → 内核 Homework JSON。
function __cx_finishHomeworks(works, warnings, withContent) {
  var out = [];
  for (var i = 0; i < works.length; i++) out.push(__cx_toHomeworkJson(works[i], withContent));
  ctx.log.info('学习通：解析出 ' + out.length + ' 份作业' +
    (withContent ? '（含正文）' : '（仅元信息）'));
  return { homeworks: out, warnings: warnings };
}

function __cx_toHomeworkJson(w, withContent) {
  var c = w.course;
  var status = w.status || '';
  var done = status.indexOf('已完成') >= 0 || status.indexOf('已批阅') >= 0 ||
    status.indexOf('已交') >= 0;

  var desc = w.content ? w.content.text : '';
  if (!desc && w.startTime) desc = '开始时间：' + w.startTime;

  return {
    id: 'chaoxing:' + w.workId,
    title: w.title || '（未命名作业）',
    description: __cx_clip(desc),
    courseName: c.name || '',
    courseId: c.courseId ? ('chaoxing:' + c.courseId) : '',
    deadline: __cx_iso(w.deadline),
    publishTime: __cx_iso(w.startTime),
    completed: done,
    submitStatus: status,
    attachments: [],
    sourcePluginId: 'chaoxing',
    remindMinutesBefore: 0
  };
}

// ───────────────────────── 考试 ─────────────────────────

/// 解析考试列表。
function __cx_parseExamList(html) {
  var out = [];
  var chunks = __cx_splitLi(html);
  for (var i = 0; i < chunks.length; i++) {
    var li = chunks[i];
    if (li.indexOf('goTest(') < 0) continue;

    var rel = __cx_pick(li, /goTest\('[^']*',\s*(\d+)/);
    var name = __cx_pick(li, /goTest\([^)]*\)[^>]*title="([^"]*)"/i) ||
      __cx_pick(li, /title="([^"]*)"/i);
    var times = li.match(/考试时间：<\/span>\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s*至\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2})/);
    if (!rel || !times) continue;

    out.push({
      relationId: String(rel),
      name: __cx_clip(__cx_unescape(name || ''), 300),
      startTime: times[1],
      endTime: times[2],
      condition: __cx_unescape(__cx_pick(li, /考试条件：([^<]*)/) || '').replace(/^\s+|\s+$/g, ''),
      status: __cx_unescape(__cx_pick(li, /考试状态：<\/span>\s*<strong>\s*([^<]*?)\s*<\/strong>/i) || '')
    });
  }
  return out;
}

/// 考试 → 内核 Exam JSON。
function __cx_toExamJson(e) {
  var c = e.course;
  var note = [];
  if (e.status) note.push(e.status);
  if (e.condition) note.push(e.condition);

  return {
    id: 'chaoxing:' + e.relationId,
    name: e.name || '（未命名考试）',
    startTime: __cx_iso(e.startTime),
    endTime: __cx_iso(e.endTime),
    location: '',
    seatNumber: '',
    examType: '',
    unit: 0,
    durationMinutes: 0,
    courseId: c.courseId ? ('chaoxing:' + c.courseId) : '',
    courseName: c.name || '',
    sourcePluginId: 'chaoxing',
    remindMinutesBefore: 0,
    note: note.join(' · ')
  };
}
