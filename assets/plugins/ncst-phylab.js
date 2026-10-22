// NCST 大学物理实验插件（华北理工大学 · 物理实验中心）
//
// 数据源：http://phylab.ncst.edu.cn:8100/  （安徽省科大奥锐「教学信息化管理系统」）
//
// ⚠️ 与 `ncst-jwxt.js` 一样，**这里是唯一允许出现该校具体 URL / 字段名的地方**
//    （CONTEXT 3.1：内核不得硬编码任何学校 URL、字段名、接口路径）。
//
// ## 与教务插件的分工
// 教务系统（ncst-jwxt）给的是**理论课表**；本插件给的是**已经约好的实验场次**。
// 两者都声明 `timetable` 能力，课程靠 `sourcePluginId` 区分，
// `CourseSyncService` 按课程 id 增量落盘、互不覆盖，所以可以同时启用。
//
// ## 幂等约定（CONTEXT 3.6，必读）
// `fetchCourses` 会被宿主**执行多次**：`ctx.http` 用"登记待办 + 宿主重放"实现，
// 命中缓存才拿得到响应，未命中时只排队并返回 `{ok:false,error:'pending'}`。
// 因此本函数只做**纯计算**，不写 `ctx.storage`、不自增、不发消息。
//
// ## 返回约定
// 成功：`{ courses: [<Course JSON>...], warnings: [...] }`
// 失败：`{ error: '人话原因' }` —— **宁可报错也不静默返回空数组**，
//       空数组会被上层当成"这学期没选实验"，比报错危险得多。
//
// ## 登录
// 本系统是 ASP.NET 表单登录：`/BaseInfo/Login/ValidateLogin` 校验账号密码后，
// 还要再调 `/BaseInfo/Login/GetRoleUser` 把角色写进 Session，才算真正进站。
// 密码在浏览器里经 AES-ECB（key 硬编码在 `Login.js`）加密后才提交，
// **沙箱里不做这件事**：登录统一交给内核的 WebView 登录页（用户自己输账号密码），
// 插件只消费登录后落盘的 Cookie（`ctx.cookie`）。
//
// 会话失效的表现：接口不再返回 JSON，而是 **302 到 `/Index/Redirect/`**
// （宿主跟随重定向后拿到一页 HTML），因此"JSON 解析失败"就是"登录过期"。
var __plugin = {
  id: 'ncst-phylab',
  name: '华北理工大学大物实验',
  version: '1.1.0',
  author: 'MySchedule',
  description: '从物理实验中心系统拉取已选实验场次，按实验日期排进课表（需先登录）',
  capabilities: ['timetable'],
  school: '华北理工大学',

  // 登录入口是站点根（`/` 才是账号密码表单页；`/BaseInfo/Index/` 是登录后的壳）。
  loginUrl: 'http://phylab.ncst.edu.cn:8100/',
  // 登录成功判定：`GetRoleUser` 成功后前端 `window.location.href` 到 Index，
  // 这一页只有拿到会话才返回业务壳，用它当成功前缀最稳。
  checkUrl: 'http://phylab.ncst.edu.cn:8100/BaseInfo/Index/',
  // 本系统登录后直接落到 Index，不需要额外导航；留空即"不自动跳转"。
  postLoginUrl: '',

  // ───────────────────────── 主入口 ─────────────────────────
  fetchCourses: function (args) {
    var cookie = ctx.cookie;
    if (!cookie) {
      return { error: '未登录：Cookie 为空，请先点「登录」完成物理实验中心登录' };
    }

    var base = 'http://phylab.ncst.edu.cn:8100';
    // 「我的课程 → 课表查看」的表格数据源。easyui datagrid 的分页参数
    // 是 page / rows，四个筛选条件留空 = 全部。
    // rows 给 1000 而不是默认的 10：一学期的实验最多几十条，
    // 一次取完就不用翻页（每翻一页都是一次"登记待办 + 重放"的往返）。
    var resp;
    try {
      resp = ctx.http.post(
        base + '/XPK/StuCourseElectiveLook/LoadTableInfo',
        'page=1&rows=1000&CourseID=&weeks=&labID=&weekID=',
        {
          'Cookie': cookie,
          'Referer': base + '/XPK/StuCourseElectiveLook',
          'X-Requested-With': 'XMLHttpRequest',
          'Content-Type': 'application/x-www-form-urlencoded'
        }
      );
    } catch (e) {
      // ctx.http 在真失败时抛错，消息就是宿主的错误短标识（timeout / connection…）
      return __phylab_netFail('拉取实验列表失败：' + String(e.message || e));
    }
    if (!resp.ok) {
      return __phylab_netFail('拉取实验列表失败：' + resp.error);
    }
    if (resp.status !== 200) {
      // 5xx 是服务端临时故障 → 值得重试；4xx 多为权限/路径问题 → 不重试。
      var msg = '拉取实验列表失败：HTTP ' + resp.status +
          '（登录可能已过期，请重新登录）';
      if (resp.status >= 500) {
        return __phylab_netFail(msg);
      }
      return { error: msg };
    }

    var data;
    try {
      data = JSON.parse(resp.body);
    } catch (e) {
      // 会话失效时 ASP.NET 会 302 到 /Index/Redirect/，拿到的是 HTML
      return { error: '实验列表不是合法 JSON（登录已过期，请重新登录）' };
    }

    // 结构校验：宁可报错也不静默返回空数组
    if (!data || typeof data !== 'object') {
      return { error: '响应结构异常：顶层不是对象' };
    }
    if (Object.prototype.toString.call(data) === '[object Array]') {
      return { error: '响应结构异常：顶层不是对象（是数组）' };
    }
    if (!Object.prototype.hasOwnProperty.call(data, 'rows')) {
      return { error: '响应结构异常：缺少 rows' };
    }
    if (Object.prototype.toString.call(data.rows) !== '[object Array]') {
      return { error: '响应结构异常：rows 不是数组' };
    }

    var warnings = [];
    var total = parseInt(data.total, 10);
    if (!isNaN(total) && total > data.rows.length) {
      // 不静默截断：告诉用户"还有 N 条没取到"，否则会以为实验就这么多
      warnings.push('共 ' + total + ' 场实验，本次只取到 ' +
          data.rows.length + ' 场（接口分页上限）');
    }
    if (data.rows.length === 0) {
      // 空数组是**合法**结果（还没选实验 / 学期初还没开放），
      // 但必须说出来：否则用户分不清"真没选"和"抓取坏了"。
      warnings.push('实验系统里还没有已选实验，等选完再同步一次');
    }

    // ── 转换成内核的 Course JSON ──
    //
    // 每场实验单独一门课，而不是把 8 场实验塞进一门"大学物理实验-1"：
    // 课表格子里要能一眼看出"这周做哪个实验"，合并成一门就只剩课程名了。
    //
    // ## 周次从哪来（Phase 9.1：以日期为准）
    //
    // 接口同时给了两套时间：`Weeks`/`WeekID`（第几周 / 星期几）和
    // `ClassDate`（`2026/9/14 0:00:00`，具体日期）。
    //
    // **以日期为准**，因为周次是"相对学期第 1 周"的相对量：实验系统的学期
    // 起点和用户课表里配的学期起点只要差一周，整批实验就会整体错周，而且
    // 错了之后看不出错在哪。日期是绝对的，拿用户的学期起点一除就落到
    // 课表正确的那一列（课表每列的日期也是 `startDate + (week-1)*7` 算的）。
    //
    // 学期起点来自 `ctx.semester.startDate`（宿主注入，见 plugin_ctx_script.dart）。
    // 没有配学期 / 日期解析不出来 / 日期落在学期范围外时，退回系统给的
    // `Weeks` + `WeekID`，并记一条 warning —— 不静默降级。
    var courses = [];
    var byId = {};
    var skipped = 0;
    var dateFallbacks = 0;   // 有日期但没能换算成周次（退回系统周次）的条数
    var datedRows = 0;       // 带可用日期的条数（用于"没配学期"的提示）
    var mismatches = [];     // 日期换算的周次 ≠ 系统标注周次 的描述

    var semester = null;
    try { semester = ctx.semester || null; } catch (e) { semester = null; }
    var hasSemester = !!(semester && __phylab_parseDate(semester.startDate));
    var totalWeeks = hasSemester ? parseInt(semester.totalWeeks, 10) : NaN;

    // 预扫描：同一「学期+课程+实验」出现多次时，**每一场**都要带日期后缀。
    // 不能只给"第二次出现"加后缀——接口返回顺序并不保证稳定，
    // 顺序一变 id 就会互换，用户给实验改过的名字/颜色会跟着错位。
    var baseCount = {};
    for (var j = 0; j < data.rows.length; j++) {
      var row = data.rows[j];
      if (!row || typeof row !== 'object') { continue; }
      var baseKey = __phylab_text(row.SemesterID) + '-' +
          __phylab_text(row.CourseID) + '-' + __phylab_text(row.LabID);
      baseCount[baseKey] = (baseCount[baseKey] || 0) + 1;
    }

    for (var i = 0; i < data.rows.length; i++) {
      var raw = data.rows[i];
      if (!raw || typeof raw !== 'object') { skipped++; continue; }

      var labName = __phylab_text(raw.LabName);
      var sysWeeks = parseInt(raw.Weeks, 10);
      var sysDay = parseInt(raw.WeekID, 10);
      var date = __phylab_parseDate(raw.ClassDate);
      if (date) { datedRows++; }

      // 星期几：日期是绝对的，优先用它（系统 WeekID 只在没日期时兜底）。
      var day = date ? __phylab_weekdayOf(date) : sysDay;

      // 周次：优先"日期 ÷ 学期起点"，其次系统 Weeks。
      var weeks = NaN;
      var weekFromDate = false;
      if (date && hasSemester) {
        var fromDate = __phylab_weekOfDate(date, semester.startDate);
        // 落在学期范围外（早于第 1 周 / 超过总周数）就不认，改用系统周次
        if (fromDate >= 1 && (isNaN(totalWeeks) || fromDate <= totalWeeks)) {
          weeks = fromDate;
          weekFromDate = true;
        }
      }
      if (isNaN(weeks) && !isNaN(sysWeeks) && sysWeeks >= 1 && sysWeeks <= 60) {
        weeks = sysWeeks;
        if (date && hasSemester) { dateFallbacks++; }
      }

      // 没有实验名 / 周次 / 星期就无法落到课表格子里，跳过并计数
      if (labName === '' || isNaN(weeks) || isNaN(day) || day < 1 || day > 7) {
        skipped++;
        continue;
      }

      // 日期算出来的周次与系统标注不同 → 记下来，最后汇总成一条 warning。
      // 这正是"两边学期起点不一致"的直接证据，必须让用户看见。
      if (weekFromDate && !isNaN(sysWeeks) && sysWeeks !== weeks) {
        mismatches.push(labName + '（系统第' + sysWeeks + '周 / 日期第' +
            weeks + '周）');
      }

      var courseId = __phylab_text(raw.CourseID);
      var labId = __phylab_text(raw.LabID);
      var semesterId = __phylab_text(raw.SemesterID);
      // id 必须**跨同步稳定**，否则每次同步都会新增一批课程、
      // 用户对实验做的改名/改色会全部丢失。
      // 一门课里同一个实验通常只做一次，「学期+课程+实验」已经唯一；
      // 真出现多场时（预扫描的 baseCount > 1），**全部**追加日期，
      // 这样 id 与接口返回顺序无关。
      var baseId = 'ncst-phylab:' + semesterId + '-' + courseId + '-' + labId;
      var id = baseId;
      if (baseCount[semesterId + '-' + courseId + '-' + labId] > 1) {
        // 没有日期时退回周次——同一周同一实验排两场才会撞，概率极低
        id = baseId + (date ? '-d' + __phylab_ymd(date) : '-w' + weeks);
      }
      if (Object.prototype.hasOwnProperty.call(byId, id)) {
        // 兜底：万一日期也相同（同一天两场），加序号保证不互相覆盖
        id = id + '-' + i;
      }
      byId[id] = true;

      var startTime = __phylab_text(raw.StartTime);
      var endTime = __phylab_text(raw.EndTime);
      var timePart = __phylab_text(raw.TimePartName);
      var session = __phylab_sessionOf(startTime, timePart);
      if (session.warn) { warnings.push(labName + '：' + session.warn); }

      var room = __phylab_text(raw.ClassRoom);
      var seat = __phylab_text(raw.SeatNo);

      // 座位号放 category（详情弹层显示成「0.0 学分 · 大学物理实验-1 · 13号座」），
      // 不放进 room——课表卡片宽度有限，"308 · 13号座"会挤掉课程名。
      var category = __phylab_text(raw.CourseName);
      if (seat !== '') {
        category = (category === '' ? '' : category + ' · ') + seat + '号座';
      }

      // 展示文本：实验的真实钟点是它自己的一套（每段 2h15），
      // 和教务的 45 分钟一节对不齐，所以把真时间也写在这里，
      // 详情弹层会显示「周一 第7-8节 第3周 · 2026-09-14 16:30-18:45」。
      // 该字段在内核里**只用于展示**（不参与周次解析），见 TimePlace。
      var clock = startTime === ''
          ? ''
          : ' · ' + (date ? __phylab_ymd(date) + ' ' : '') + startTime +
              (endTime === '' ? '' : '-' + endTime);
      var rawWeeksText = '第' + weeks + '周' + clock;

      courses.push({
        id: id,
        name: labName,
        teacher: __phylab_text(raw.UserName),
        unit: 0,
        category: category,
        timePlaces: [{
          day: day,
          startSession: session.start,
          length: session.length,
          room: room,
          weeks: [weeks],
          rawWeeksText: rawWeeksText,
          weekType: 'all'
        }],
        sourcePluginId: 'ncst-phylab'
      });
    }

    // ── 降级说明（不静默） ──
    if (!hasSemester && datedRows > 0) {
      // 没配学期就拿不到"第 1 周从哪天开始"，只能信实验系统给的周次。
      // 两个系统的学期起点一旦不同就会整体错周，所以必须提示去配学期。
      warnings.push('未设置学期起始日期，本次按实验系统标注的周次导入；' +
          '到「设置 → 学期配置」填好开学日期后重新同步，才能按实验日期精确对齐');
    }
    if (dateFallbacks > 0) {
      warnings.push('有 ' + dateFallbacks + ' 场实验的日期不在学期范围内，' +
          '已改用实验系统标注的周次');
    }
    if (mismatches.length > 0) {
      // 只列前 3 条，其余给个数——warning 太长会把页面淹掉
      var shown = mismatches.slice(0, 3).join('、');
      warnings.push('日期换算的周次与系统标注不一致（已按日期排）：' + shown +
          (mismatches.length > 3 ? ' 等 ' + mismatches.length + ' 场' : ''));
    }
    if (skipped > 0) {
      warnings.push('有 ' + skipped + ' 条实验因缺少实验名/周次/星期被跳过');
    }
    ctx.log.info('大物实验同步：解析出 ' + courses.length + ' 场实验' +
        (warnings.length === 0 ? '' : '，警告 ' + warnings.length + ' 条'));

    return { courses: courses, warnings: warnings };
  }
};

// ───────────────────────── 工具函数 ─────────────────────────
//
// 放在 `__plugin` **外面**：运行时用 `Object.keys(__plugin).filter(typeof === 'function')`
// 收集入口函数，把工具函数放在对象里会被误报成入口函数。

/// 构造"网络层失败"的返回对象（Phase 4.3 约定）。
///
/// `retryable: true` 告诉宿主这次失败**值得自动重试**——只有"请求没成功
/// 到达 / 服务端临时故障"时才这么标。凭证过期、响应结构异常都不该标。
function __phylab_netFail(message) {
  var kind = '';
  try { kind = ctx.lastHttpError || ''; } catch (e) { kind = ''; }
  return { error: message, retryable: true, errorKind: kind };
}

/// 安全转字符串并去掉首尾空白。
function __phylab_text(value) {
  if (value === undefined || value === null) { return ''; }
  return String(value).replace(/^\s+|\s+$/g, '');
}

// ── 日期工具（Phase 9.1）──
//
// 全程只用 `{y, m, d}` 三个整数 + `Date.UTC`，**不碰本地时区**：
// 沙箱所在设备的时区、夏令时都会让 `new Date('2026/9/14').getTime()`
// 差出几小时，除以 7 天一旦不是整数倍就会算错一周。

/// `"2026/9/14 0:00:00"` / `"2026-09-14"` → `{y:2026, m:9, d:14}`；认不出返回 null。
function __phylab_parseDate(value) {
  var m = /^(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})/.exec(__phylab_text(value));
  if (!m) { return null; }
  var y = parseInt(m[1], 10);
  var mo = parseInt(m[2], 10);
  var d = parseInt(m[3], 10);
  if (y < 1900 || y > 2200 || mo < 1 || mo > 12 || d < 1 || d > 31) {
    return null;
  }
  return { y: y, m: mo, d: d };
}

/// 把日期对象规范成 `"2026-09-14"`（用于展示）。
function __phylab_ymd(date) {
  var mm = date.m < 10 ? '0' + date.m : '' + date.m;
  var dd = date.d < 10 ? '0' + date.d : '' + date.d;
  return date.y + '-' + mm + '-' + dd;
}

/// 该日期是星期几，1=周一 … 7=周日（与内核 `TimePlace.day` 一致）。
function __phylab_weekdayOf(date) {
  var jsDay = new Date(Date.UTC(date.y, date.m - 1, date.d)).getUTCDay();
  return (jsDay + 6) % 7 + 1;
}

/// 该日期落在"第几周"：以 [startYmd]（学期第 1 周周一）为基准。
///
/// 返回值可能 <= 0（早于学期开始）或大于总周数，由调用方判断是否可用。
function __phylab_weekOfDate(date, startYmd) {
  var start = __phylab_parseDate(startYmd);
  if (!start) { return 0; }
  var a = Date.UTC(start.y, start.m - 1, start.d);
  var b = Date.UTC(date.y, date.m - 1, date.d);
  // 用 UTC 毫秒差做整数除法：同一天 → 0，下一周同一天 → 7
  return Math.floor((b - a) / 86400000 / 7) + 1;
}

/// 实验时间段 → 课表节次区间。
///
/// 实验系统用的是自己的一套时段（每段 2 小时 15 分，与教务的 45 分钟一节
/// 对不齐）。实测：
///   上午   10:15-12:30
///   下午一 14:00-16:15
///   下午二 16:30-18:45
/// 对应到 NCST 教务的节次大致是 3-4 / 5-6 / 7-8，所以按 **时间段名** 优先、
/// **开始时刻** 兜底来定位起始节次，长度固定 2 节。
///
/// 返回 `{start, length, warn?}`；认不出时给一个保守的 5-6 节并带 warning，
/// 让用户能在详情里看到"这条时间没认出来"，而不是悄悄排错格子。
function __phylab_sessionOf(startTime, timePartName) {
  var byName = {
    '上午': 3, '上午一': 1, '上午二': 3,
    '下午一': 5, '下午二': 7,
    '晚上': 9, '晚上一': 9, '晚上二': 11
  };
  if (Object.prototype.hasOwnProperty.call(byName, timePartName)) {
    return { start: byName[timePartName], length: 2 };
  }

  var minutes = __phylab_minutesOf(startTime);
  if (minutes >= 0) {
    if (minutes < 9 * 60) { return { start: 1, length: 2 }; }        // 08:00 档
    if (minutes < 12 * 60) { return { start: 3, length: 2 }; }       // 10:15 档
    if (minutes < 16 * 60 + 20) { return { start: 5, length: 2 }; }  // 14:00 档
    if (minutes < 19 * 60) { return { start: 7, length: 2 }; }       // 16:30 档
    return { start: 9, length: 2 };                                  // 19:00 之后
  }

  return {
    start: 5,
    length: 2,
    warn: '认不出上课时段（' + timePartName + ' ' + startTime + '），暂按第 5-6 节排'
  };
}

/// `"16:30"` → 990（当天第几分钟）；格式不认识返回 -1。
function __phylab_minutesOf(text) {
  var m = /^(\d{1,2}):(\d{2})$/.exec(__phylab_text(text));
  if (!m) { return -1; }
  return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
}
