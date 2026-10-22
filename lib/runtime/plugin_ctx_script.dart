// Phase 3.6：插件运行上下文的 **JS 侧契约**。
//
// 本文件是"宿主 ↔ 插件"之间 ctx 的唯一定义处：JS 侧的 `ctx` 对象、
// 它依赖的内部 primitive、以及宿主每轮注入状态 / 读回副作用用的两段脚本。
//
// ## 为什么 ctx 全部用 JS 实现（没有 `__dart_*` Dart 通道）
//
// 任务书原本设想"Dart 暴露 `__dart_http_get(url, headers) → responseJson`"，
// 但那在当前架构下**不可能**：
//   - 沙箱跑在**独立 isolate**，Dart 通道回调是在子 isolate 里执行的闭包，
//     而 dio / Hive / secure_storage 都在主 isolate——闭包跨不了 isolate；
//   - 就算能跨，`sendMessage` 通道要求 Dart 侧**同步**返回，而 dio 是异步的；
//     JS 又无法挂起（本库唯一的异步路径走 `callFunction`，而 QuickJS 后端
//     该方法是 `UnimplementedError`，Phase 3.2a 已实测）。
//
// 所以 ctx 采用 **"登记待办 + 宿主重放"**（Phase 3.6 决策 B）：
//   1. 宿主每轮先把"本轮可用的 HTTP 响应缓存 / storage 快照 / cookie"用
//      [buildCtxStateScript] 注入成 JS 全局；
//   2. 插件函数照常写 `var r = ctx.http.get(url)`——**命中缓存就同步拿到响应**；
//   3. 未命中时 `ctx.http.get` 只是把请求登记进待办列表并返回
//      `{ok:false,error:'pending'}`（或按插件习惯抛错），**不发任何网络**；
//   4. 宿主用 [kCtxDumpScript] 读回本轮待办与副作用；
//   5. 有待办 → 用 dio 取回（真超时）→ 并入缓存 → **重放**插件函数；
//   6. 没有待办的那一轮就是最终轮：只提交**最终轮**的 storage / log / notify 副作用，
//      并把它返回给调用方。
//
// 这样插件作者写的是自然同步代码，而网络仍由宿主用 dio 发（可超时、可审计）。
//
// ## 已知约束（写进文档）
// - 插件函数会被**执行多次**，因此它必须是"幂等的纯计算"：副作用只在最终轮生效，
//   中间轮次对 `ctx.storage` 的修改会被丢弃（每轮都从同一快照开始）。
// - 顶层（`__plugin` 定义处）调用 `ctx.*` 没有意义——那时还没有"轮"，
//   副作用不会被提交。ctx 只应在入口函数里用。
import 'dart:convert';

/// 预置的 ctx 脚本：定义全局 `ctx` 与它依赖的内部 primitive。
///
/// 加载插件时由 `PluginRuntime` 注入一次；之后每轮由 [buildCtxStateScript]
/// 重置本轮状态（缓存 / 快照 / 待办 / 日志）。
const String kPluginCtxScript = r'''
// —— 本轮状态（每轮由宿主重置）——
var __ctx_http_cache = {};
var __ctx_http_pending = [];
var __ctx_storage = {};
var __ctx_storage_touched = {};
var __ctx_logs = [];
var __ctx_notifies = [];
var __ctx_cookie = '';
var __ctx_http_errors = [];
var __ctx_semester = null;

// 请求去重键：同方法 + 同 URL + 同 body + 同请求头 → 只发一次。
function __ctx_request_key(method, url, body, headersJson) {
  var b = (body === undefined || body === null) ? '' : String(body);
  return method + '|' + String(url) + '|' + b + '|' + String(headersJson || '{}');
}

// Phase 4.3：把"某次 HTTP 真失败"记进本轮错误列表。
//
// 用途：插件把失败包装成 `{error: '人话原因'}` 后，宿主**无法**从中分辨
// "网络超时（可以重试）"和"凭证过期（重试没用）"。这里保留宿主自己的
// 错误短标识（timeout / connection / bad_certificate / ...），宿主读回后
// 就能按错误类别决定要不要重试。
// 注意：**不解析 body**（"5xx 响应里写着 error 字段"不算网络失败），
// 只看响应信封的 ok 标志。
function __ctx_note_http_error(responseJson) {
  var r;
  try { r = JSON.parse(responseJson); } catch (e) { return; }
  if (!r || r.ok) return;
  if (r.error && r.error !== 'pending') {
    __ctx_http_errors.push(String(r.error));
  }
}

// HTTP primitive：命中缓存直接返回；未命中只登记待办，绝不发网络。
function __ctx_http(method, url, body, headersJson) {
  var key = __ctx_request_key(method, url, body, headersJson);
  if (Object.prototype.hasOwnProperty.call(__ctx_http_cache, key)) {
    var cached = __ctx_http_cache[key];
    // Phase 4.3：把缓存里记下的失败类别也登记一遍。
    // 否则"重放后从缓存命中失败响应"这一轮的 __ctx_http_errors 会是空的，
    // 宿主就看不到真实失败原因（首轮登记过，但那是上一轮的状态）。
    __ctx_note_http_error(cached);
    return cached;
  }
  // 同一轮内对同一 key 重复请求 → 只登记一次（否则会重复发同一个请求）。
  // 缓存只在"轮与轮之间"填充，所以这里必须再对**待办列表**去重。
  for (var i = 0; i < __ctx_http_pending.length; i++) {
    if (__ctx_http_pending[i].key === key) {
      return JSON.stringify({ ok: false, error: 'pending' });
    }
  }
  var headers = {};
  try { headers = JSON.parse(headersJson || '{}'); } catch (e) { headers = {}; }
  __ctx_http_pending.push({
    method: method,
    url: String(url),
    body: (body === undefined || body === null) ? null : String(body),
    headers: headers,
    key: key
  });
  return JSON.stringify({ ok: false, error: 'pending' });
}
// storage 只操作本轮的内存快照；最终轮由宿主提交到 Hive。
function __ctx_storage_get(key) {
  var k = String(key);
  return Object.prototype.hasOwnProperty.call(__ctx_storage, k) ? __ctx_storage[k] : '';
}
function __ctx_storage_set(key, value) {
  var k = String(key);
  __ctx_storage[k] = String(value);
  __ctx_storage_touched[k] = true;
}
function __ctx_storage_remove(key) {
  var k = String(key);
  delete __ctx_storage[k];
  __ctx_storage_touched[k] = true;
}

/// 插件可用的上下文对象。
var ctx = {
  http: {
    /// 命中缓存返回 {ok:true,status,body,headers}；真失败抛 Error。
    /// 未命中时返回 {ok:false,error:'pending'} 并由宿主重放——
    /// 插件**不需要**知道重放的存在（抛错也不会破坏重放，宿主只看待办列表）。
    get: function (url, headers) {
      var r = JSON.parse(__ctx_http('GET', url, null, JSON.stringify(headers || {})));
      if (!r.ok && r.error !== 'pending') { throw new Error(r.error); }
      return r;
    },
    post: function (url, body, headers) {
      var payload = (body === undefined || body === null) ? null : body;
      if (payload !== null && typeof payload !== 'string') {
        payload = JSON.stringify(payload);
      }
      var r = JSON.parse(__ctx_http('POST', url, payload, JSON.stringify(headers || {})));
      if (!r.ok && r.error !== 'pending') { throw new Error(r.error); }
      return r;
    }
  },
  storage: {
    get: function (key) { return __ctx_storage_get(key); },
    set: function (key, value) { __ctx_storage_set(key, value); },
    remove: function (key) { __ctx_storage_remove(key); }
  },
  log: {
    info: function (msg) { __ctx_logs.push({ level: 'info', msg: String(msg) }); },
    error: function (msg) { __ctx_logs.push({ level: 'error', msg: String(msg) }); }
  },
  notify: {
    // 本阶段只登记；宿主最终轮用 debugPrint 输出（Phase 7 接真实通知）。
    schedule: function (title, body, triggerAtIso) {
      __ctx_notifies.push({
        title: String(title),
        body: String(body),
        triggerAtIso: String(triggerAtIso)
      });
    }
  },
  // 凭证：宿主每轮预先注入（Phase 4 由 WebView 登录写入）。
  get cookie() { return __ctx_cookie; },

  // 学期配置：`{ startDate: 'YYYY-MM-DD', totalWeeks: n }`，未配置学期时为 null。
  //
  // 用途（Phase 9）：有些系统的课表接口给的是**具体日期**而不是周次，
  // 插件必须知道"第 1 周从哪天开始"才能把日期换算成课表要的
  // `(week, day)`。这个换算只有拿到 startDate 才做得出来，而学期是
  // 用户在内核里配的，插件无从得知 —— 所以由宿主注入。
  //
  // 约定：`startDate` 是**第 1 周周一**（与 `SemesterConfig` 一致），
  // 字符串形式固定 `YYYY-MM-DD`，插件侧用 `new Date(s)` 解析时不会带时区坑
  // （JS 规范里 `YYYY-MM-DD` 按 UTC 解析，只取年月日时不受影响）。
  get semester() { return __ctx_semester; },

  // Phase 4.3：本轮最后一次"真失败"的短标识（timeout / connection /
  // bad_certificate / bad_response / cancelled / unknown），没有失败则为空串。
  //
  // 插件用它把 `{error:...}` 区分为**可重试**与**不可重试**：
  // 网络类失败（timeout / connection / bad_response）返回 `retryable: true`，
  // 宿主据此自动重试。**不解析任何响应正文**，所以与"内核不认识学校字段"
  // 的约束无关（这里只有宿主自己的错误枚举）。
  get lastHttpError() {
    return __ctx_http_errors.length > 0
        ? __ctx_http_errors[__ctx_http_errors.length - 1]
        : '';
  }
};
''';

/// 构造"本轮状态"脚本：由宿主在每轮执行插件函数**之前**求值。
///
/// 各参数都是"宿主已经算好的值"，全部以 JSON 字面量嵌入——
/// Dart ↔ JS 边界只传字符串（CONTEXT/本阶段约束）。
/// 同时把待办与日志清空，保证每轮都是干净的一轮。
///
/// [semester] 是学期摘要（`{startDate, totalWeeks}`）；`null` 表示用户还没
/// 配学期，此时 `ctx.semester` 为 `null`，插件应退回"不用日期"的路径。
String buildCtxStateScript({
  required Map<String, String> httpCache,
  required Map<String, String> storage,
  required String cookie,
  Map<String, Object?>? semester,
}) {
  return 'var __ctx_http_cache = ${_jsonLiteral(httpCache)};\n'
      'var __ctx_http_pending = [];\n'
      'var __ctx_storage = ${_jsonLiteral(storage)};\n'
      'var __ctx_storage_touched = {};\n'
      'var __ctx_logs = [];\n'
      'var __ctx_notifies = [];\n'
      'var __ctx_cookie = ${_jsonLiteral(cookie)};\n'
      'var __ctx_semester = ${semester == null ? 'null' : _jsonLiteral(semester)};\n'
      // Phase 4.3：错误列表必须每轮清空，否则上一轮的失败会污染本轮判定。
      'var __ctx_http_errors = [];\n';
}

/// 读回本轮副作用的脚本：返回
/// `{pending, storage, touched, logs, notifies, httpErrors}` 的 JSON。
///
/// `touched` 只列**本轮改动过的键**，宿主据此决定写哪些键、删哪些键
/// （避免把整个命名空间重写一遍）。
const String kCtxDumpScript = r'''
JSON.stringify({
  pending: __ctx_http_pending,
  storage: __ctx_storage,
  touched: Object.keys(__ctx_storage_touched),
  logs: __ctx_logs,
  notifies: __ctx_notifies,
  httpErrors: __ctx_http_errors
})
''';

/// 把 Dart 值编码成可安全嵌进 JS 的 JSON 字面量。
///
/// JSON 的字符串转义是 JS 字符串字面义的子集，因此 `jsonEncode` 的输出
/// 可以直接当 JS 字面量用（Phase 3.2b.1 起沿用同一手法）。
String _jsonLiteral(Object? value) => jsonEncode(value);
