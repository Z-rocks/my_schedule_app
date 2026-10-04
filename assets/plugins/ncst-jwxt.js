// NCST 教务系统插件（华北理工大学）
//
// ⚠️ 这是**第一个真实插件**，也是唯一允许出现 NCST 具体 URL 的地方
//    （CONTEXT 3.1：内核不得硬编码任何学校 URL / 字段名 / 接口路径）。
//
// ## 幂等约定（CONTEXT 3.6，必读）
// `fetchCourses` 会被宿主**执行多次**：`ctx.http` 用"登记待办 + 宿主重放"实现，
// 命中缓存才拿得到响应，未命中时只排队并返回 `{ok:false,error:'pending'}`。
// 因此本函数：
//   - 只做**纯计算**，副作用仅限 `ctx.storage.set`（宿主保证只在最终轮提交）；
//   - 不做自增 / 累加 / 发消息这类重复执行会出错的写操作；
//   - 中间轮次里 HTTP 拿到的是 `pending`，宿主会带着真响应重放，无需自己处理。
//
// ## 返回约定
// 成功：`{ courses: [<Course JSON>...], sectionTimes: N, allUnits: X, warnings: [...] }`
// 失败：`{ error: '人话原因' }` —— **宁可报错也不静默返回空数组**，
//       空数组会被上层误当成"这学期没课"，比报错危险得多。
//
// ## Phase 4.3：网络类失败要标 `retryable: true`
// 宿主只知道"插件返回了一句 error"，无法分辨"校园网抖了一下（重试就好）"
// 和"Cookie 过期了（重试一百次也没用）"。所以插件要把**网络层**失败
// 显式标出来，宿主才会自动重试（见 `CourseSyncService`）。
// 用 `__ncst_netFail()` 统一构造，避免漏标。
//
// ⚠️ 判断依据是 `ctx.lastHttpError`（宿主给的错误短标识：timeout /
//    connection / bad_response / bad_certificate / ...），**不是**响应正文。
//    因此这里依然没有解析任何教务系统的字段结构。
var __plugin = {
  id: 'ncst-jwxt',
  name: '华北理工大学教务系统',
  version: '1.0.0',
  author: 'MySchedule',
  description: '从 NCST 教务系统拉取本学期课表（需先在详情页登录）',
  capabilities: ['timetable'],
  school: '华北理工大学',
  loginUrl: 'https://xjw1.ncst.edu.cn/',
  checkUrl: 'https://xjw1.ncst.edu.cn/student/courseSelect/courseSelectResult/index',

  // ───────────────────────── 主入口 ─────────────────────────
  fetchCourses: function (args) {
    var cookie = ctx.cookie;
    if (!cookie) {
      return { error: '未登录：Cookie 为空，请先点「登录」完成教务系统登录' };
    }

    var base = 'https://xjw1.ncst.edu.cn';
    var referer = base + '/student/courseSelect/courseSelectResult/index';
    var commonHeaders = {
      'Cookie': cookie,
      'Referer': referer,
      'X-Requested-With': 'XMLHttpRequest'
    };
    var warnings = [];

    // ── 1. 课程列表 ──
    var listResp;
    try {
      listResp = ctx.http.get(
        base + '/student/courseSelect/thisSemesterCurriculum/callback',
        commonHeaders
      );
    } catch (e) {
      // ctx.http 在真失败时抛错，消息就是宿主的错误短标识（timeout / connection…）
      return __ncst_netFail('拉取课程列表失败：' + String(e.message || e));
    }
    if (!listResp.ok) {
      return __ncst_netFail('拉取课程列表失败：' + listResp.error);
    }
    if (listResp.status !== 200) {
      // 5xx 是服务端临时故障 → 值得重试；4xx 多为权限/路径问题 → 不重试。
      // 注意：这里只按**状态码**分类，不解析响应正文。
      var msg = '拉取课程列表失败：HTTP ' + listResp.status +
          '（Cookie 可能已过期，请重新登录）';
      if (listResp.status >= 500) {
        return __ncst_netFail(msg);
      }
      return { error: msg };
    }

    var data;
    try {
      data = JSON.parse(listResp.body);
    } catch (e) {
      // 登录过期时教务系统常返回登录页 HTML，这里给出可诊断的提示
      return { error: '课程列表不是合法 JSON（多半是登录已过期，请重新登录）' };
    }

    // 结构校验：宁可报错也不静默返回空数组
    if (!data || typeof data !== 'object') {
      return { error: '响应结构异常：顶层不是对象' };
    }
    if (Object.prototype.toString.call(data) === '[object Array]') {
      // 注意 `typeof [] === 'object'`，数组要单独拦（否则会落到"缺少 dateList"）
      return { error: '响应结构异常：顶层不是对象（是数组）' };
    }
    if (!Object.prototype.hasOwnProperty.call(data, 'dateList')) {
      return { error: '响应结构异常：缺少 dateList' };
    }
    if (Object.prototype.toString.call(data.dateList) !== '[object Array]') {
      return { error: '响应结构异常：dateList 不是数组' };
    }
    for (var d = 0; d < data.dateList.length; d++) {
      var plan = data.dateList[d];
      if (!plan || typeof plan !== 'object') {
        return { error: '响应结构异常：dateList[' + d + '] 不是对象' };
      }
      if (!Object.prototype.hasOwnProperty.call(plan, 'selectCourseList')) {
        return { error: '响应结构异常：dateList[' + d + '] 缺少 selectCourseList' };
      }
      if (Object.prototype.toString.call(plan.selectCourseList) !== '[object Array]') {
        return { error: '响应结构异常：dateList[' + d + '].selectCourseList 不是数组' };
      }
    }

    // ── 2. 节次时间（失败不影响课程，只记 warning） ──
    var sectionTimes = 0;
    try {
      var stResp = ctx.http.post(
        base + '/ajax/student/getSectionAndTime',
        'planNumber=&ff=f&xqh=009',
        {
          'Cookie': cookie,
          'Referer': referer,
          'Origin': base,
          'X-Requested-With': 'XMLHttpRequest',
          'Content-Type': 'application/x-www-form-urlencoded'
        }
      );
      if (stResp.ok && stResp.status === 200) {
        var stOuter = JSON.parse(stResp.body);
        if (stOuter && stOuter.data && stOuter.data.sectionTime) {
          // data.sectionTime 是 **JSON 字符串**，要二次解析
          var list = JSON.parse(stOuter.data.sectionTime);
          var map = {};
          for (var s = 0; s < list.length; s++) {
            var item = list[s];
            var name = String(item.sessionName);
            map[name] = __ncst_formatTime(item.startTime) +
                '-' + __ncst_formatTime(item.endTime);
          }
          sectionTimes = list.length;
          ctx.storage.set('section_times', JSON.stringify(map));
        } else {
          warnings.push('节次时间响应结构异常：缺少 data.sectionTime');
        }
      } else {
        warnings.push('节次时间获取失败：' +
            (stResp.ok ? 'HTTP ' + stResp.status : stResp.error));
      }
    } catch (e) {
      warnings.push('节次时间获取异常：' + String(e.message || e));
    }

    // ── 3. 转换成内核的 Course JSON ──
    var courses = [];
    var skipped = 0;
    for (var p = 0; p < data.dateList.length; p++) {
      var courseList = data.dateList[p].selectCourseList;
      for (var c = 0; c < courseList.length; c++) {
        var raw = courseList[c];
        if (!raw || !raw.id || !raw.id.coureNumber) {
          skipped++;
          continue;   // 没有课程号就无法生成稳定 id，跳过并计数
        }
        var courseId = String(raw.id.coureNumber) + '_' +
            String(raw.id.coureSequenceNumber === undefined ? '' : raw.id.coureSequenceNumber);

        var rawPlaces = Object.prototype.toString.call(raw.timeAndPlaceList) === '[object Array]'
            ? raw.timeAndPlaceList
            : [];
        var places = [];
        for (var t = 0; t < rawPlaces.length; t++) {
          var tp = rawPlaces[t];
          if (!tp) { continue; }
          var rawWeeks = tp.weekDescription === undefined || tp.weekDescription === null
              ? ''
              : String(tp.weekDescription);
          places.push({
            day: __ncst_toInt(tp.classDay, 1),
            startSession: __ncst_toInt(tp.classSessions, 1),
            length: __ncst_toInt(tp.continuingSession, 1),
            room: tp.classroomName === undefined || tp.classroomName === null
                ? '' : String(tp.classroomName),
            weeks: __ncst_parseWeeks(rawWeeks),
            rawWeeksText: rawWeeks,
            weekType: __ncst_parseWeekType(rawWeeks)
          });
        }

        var units = Number(raw.unit);
        courses.push({
          id: courseId,
          name: raw.courseName === undefined || raw.courseName === null
              ? '' : String(raw.courseName),
          teacher: raw.attendClassTeacher === undefined || raw.attendClassTeacher === null
              ? '' : String(raw.attendClassTeacher).replace(/^\s+|\s+$/g, ''),
          unit: isNaN(units) ? 0 : units,
          category: raw.courseCategoryName === undefined || raw.courseCategoryName === null
              ? '' : String(raw.courseCategoryName),
          timePlaces: places,
          sourcePluginId: 'ncst-jwxt'
        });
      }
    }

    if (skipped > 0) {
      warnings.push('有 ' + skipped + ' 条课程因缺少课程号被跳过');
    }
    ctx.log.info('NCST 同步：解析出 ' + courses.length + ' 门课程，' +
        '节次时间 ' + sectionTimes + ' 条');

    return {
      courses: courses,
      sectionTimes: sectionTimes,
      allUnits: data.allUnits,
      warnings: warnings
    };
  }
};

// ───────────────────────── 工具函数 ─────────────────────────
//
// 放在 `__plugin` **外面**：运行时用 `Object.keys(__plugin).filter(typeof === 'function')`
// 收集入口函数，把工具函数放在对象里会被误报成入口函数。

/// 构造"网络层失败"的返回对象（Phase 4.3）。
///
/// `retryable: true` 告诉宿主这次失败**值得自动重试**——只有在"请求没成功
/// 到达 / 服务端临时故障"时才这么标。凭证过期、响应结构异常都不该标：
/// 重试只会让用户多等一轮还会得到同样的结果。
///
/// `kind` 取 `ctx.lastHttpError`（宿主给的短标识），空串则退化为不标。
/// 之所以还带上 `kind`：宿主可以据此给出更准的提示
/// （例如 `bad_certificate` → 提示证书问题而不是"检查校园网"）。
function __ncst_netFail(message) {
  var kind = '';
  try { kind = ctx.lastHttpError || ''; } catch (e) { kind = ''; }
  return { error: message, retryable: true, errorKind: kind };
}

/// 周次解析（`TimetableLogic.parseWeeks` 的 JS 复刻）。
///
/// 沙箱里调不到 Dart，所以这里必须有一份等价实现；与 Dart 版的差异必须为零。
/// Phase 5.1 用 **37 组样本逐条对拍**（标准写法 / 全角数字 / 中文数字 /
/// 坏数据 / 超大区间），对拍脚本跑在 Node 上直接调用本文件的这几个函数。
///
/// ⚠️ 归一化规则与 Dart 侧逐条对应，**顺序也是契约**：
///   1. 中文数字 → 阿拉伯数字（含十位组合）
///   2. 全角数字 → 半角
///   3. 标点 / 关系词归一，丢弃修饰字
/// 改一边必须同步改另一边，否则同一门课在"插件解析出的周次"与
/// "内核再解析一次"两条路径上会得到不同的周次，课表就会莫名缺课。
function __ncst_normalizeWeekText(rawText) {
  if (rawText === undefined || rawText === null) { return ''; }
  // Dart 侧先转全角数字再转中文数字；两步互不影响（表里没有全角字符），
  // 但为了逐条对应仍然保持同样的顺序。
  var converted = __ncst_replaceFullWidthDigits(String(rawText));
  converted = __ncst_chineseToArabic(converted);

  var out = '';
  for (var i = 0; i < converted.length; i++) {
    var ch = converted.charAt(i);
    if (ch === '，' || ch === '、' || ch === '；' || ch === ';') { out += ','; continue; }
    if (ch === '－' || ch === '—' || ch === '–' || ch === '~' ||
        ch === '～' || ch === 'ー' || ch === '至' || ch === '到') {
      out += '-';
      continue;
    }
    if (ch === '第' || ch === '周' || ch === '星期') { continue; }
    out += ch;
  }
  return out;
}

/// 全角数字 → 半角数字（与 Dart 的 `_replaceFullWidthDigits` 对应）。
function __ncst_replaceFullWidthDigits(text) {
  var out = '';
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i);
    if (code >= 0xFF10 && code <= 0xFF19) {
      out += String.fromCharCode(0x30 + (code - 0xFF10));
    } else {
      out += text.charAt(i);
    }
  }
  return out;
}

/// 十位组合的中文数字 → 阿拉伯数字（与 Dart 的 `chineseToArabic` 对应）。
///
/// ⚠️ **不能逐字替换**：`"十"` 在中文里是位权而不是"10"这个值，
/// 逐字替换会让 `"十六"` 变成 `"1"+"10"+"6"` = `"106"`（冲出 60 → 解析成空）。
///
/// 逐字符扫描，扫描点永远落在"可能是一个数字的开头"，
/// 所以 `"第十六周"` 里的 `'第'` 会被原样跳过，随后从 `'十'` 正确识别出 16。
/// 只支持 1–99：周次不可能超过 60，「百 / 千」不值得为此实现。
function __ncst_chineseToArabic(text) {
  var length = text.length;
  var out = '';
  var i = 0;

  while (i < length) {
    var ch = text.charAt(i);
    var current = Object.prototype.hasOwnProperty.call(__NCST_CN_DIGITS, ch)
        ? __NCST_CN_DIGITS[ch] : null;

    // 情形 1：当前字是 "十" —— 位权
    if (ch === '十') {
      var tail = (i + 1 < length &&
          Object.prototype.hasOwnProperty.call(__NCST_CN_DIGITS, text.charAt(i + 1)))
          ? __NCST_CN_DIGITS[text.charAt(i + 1)] : null;
      if (tail !== null) { out += String(10 + tail); i += 2; }
      else { out += '10'; i += 1; }
      continue;
    }

    // 情形 2：当前字是个位数字
    if (current !== null) {
      if (i + 1 < length && text.charAt(i + 1) === '十') {
        var base = current * 10;
        var tail2 = (i + 2 < length &&
            Object.prototype.hasOwnProperty.call(__NCST_CN_DIGITS, text.charAt(i + 2)))
            ? __NCST_CN_DIGITS[text.charAt(i + 2)] : null;
        if (tail2 !== null) { out += String(base + tail2); i += 3; }
        else { out += String(base); i += 2; }
        continue;
      }
      out += String(current);
      i += 1;
      continue;
    }

    // 情形 3：不是中文数字，原样保留
    out += ch;
    i += 1;
  }
  return out;
}

/// 中文数字字符 → 数值（与 Dart 的 `_kChineseDigitValue` 对应）。
///
/// `十` 也映射成 10：它既是位权（"十六"的十位），也可以是独立值（"第十周"）。
var __NCST_CN_DIGITS = {
  '〇': 0, '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
  '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10
};

function __ncst_parseWeeks(rawText) {
  if (rawText === undefined || rawText === null) { return []; }
  var cleaned = __ncst_normalizeWeekText(rawText)
    .replace(/\([^)]*\)/g, '')   // 去掉 "(单)" / "(双)"
    .replace(/^\s+|\s+$/g, '');
  if (cleaned === '') { return []; }

  var weeks = {};
  var fragments = cleaned.split(',');
  for (var i = 0; i < fragments.length; i++) {
    var part = fragments[i].replace(/^\s+|\s+$/g, '');
    if (part === '') { continue; }

    // 单个数字（允许前导负号，交由 __ncst_addWeek 的范围判断丢弃）
    if (/^-?\d+$/.test(part)) {
      __ncst_addWeek(weeks, parseInt(part, 10));
      continue;
    }

    var bounds = part.split('-');
    if (bounds.length !== 2) { continue; }  // "1-2-3" 之类视为无效
    var startText = bounds[0].replace(/^\s+|\s+$/g, '');
    var endText = bounds[1].replace(/^\s+|\s+$/g, '');
    if (!/^-?\d+$/.test(startText) || !/^-?\d+$/.test(endText)) { continue; }
    var start = parseInt(startText, 10);
    var end = parseInt(endText, 10);
    if (start > end) { continue; }          // 反向区间视为无效
    var last = end > 60 ? 60 : end;         // 与 kMaxWeekNumber 对齐
    for (var w = start; w <= last; w++) { __ncst_addWeek(weeks, w); }
  }

  var result = [];
  for (var key in weeks) {
    if (Object.prototype.hasOwnProperty.call(weeks, key)) { result.push(Number(key)); }
  }
  result.sort(function (a, b) { return a - b; });
  return result;
}

/// 单双周（`TimetableLogic.parseWeekType` 的 JS 复刻）：同时含"单""双" → all。
function __ncst_parseWeekType(rawText) {
  if (rawText === undefined || rawText === null || rawText === '') { return 'all'; }
  var text = String(rawText);
  var hasOdd = text.indexOf('单') >= 0;
  var hasEven = text.indexOf('双') >= 0;
  if (hasOdd && hasEven) { return 'all'; }
  if (hasOdd) { return 'odd'; }
  if (hasEven) { return 'even'; }
  return 'all';
}

/// 只在 1..60 范围内才收进集合（与 TimetableLogic._addWeek 对齐）。
function __ncst_addWeek(weeks, week) {
  if (week < 1 || week > 60) { return; }
  weeks[week] = true;
}

/// 安全取整数；非法值回落 fallback（与 Dart 侧 _asInt 的兜底思路一致）。
function __ncst_toInt(value, fallback) {
  var n = parseInt(value, 10);
  return isNaN(n) ? fallback : n;
}

/// 教务系统给的是 `"0830"` 这种紧凑格式，转成 `"08:30"`。
function __ncst_formatTime(raw) {
  var text = (raw === undefined || raw === null) ? '' : String(raw);
  if (text.length === 4) { return text.substring(0, 2) + ':' + text.substring(2); }
  if (text.length === 3) { return '0' + text.substring(0, 1) + ':' + text.substring(1); }
  return text;
}
