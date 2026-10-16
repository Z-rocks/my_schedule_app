// 插件测试台：在 Node 里**忠实复刻宿主的重放机制**，跑 assets/plugins/chaoxing.js
// 的真实逻辑，网络经浏览器会话代理（真实站点、真实 Cookie）。
//
// 复刻的关键点（与 lib/runtime/plugin_ctx_script.dart + plugin_context.dart 对齐）：
//   - 同一套 `ctx` 实现（含 pending 语义、去重键、storage 快照）；
//   - 每轮重置状态 → 执行入口函数 → 读回 pending → 宿主取数 → 重放；
//   - 没有 pending 的那一轮即最终轮，轮数上限 8。
// 这样可以提前发现"轮数超限"这类只有真实宿主才会暴露的问题。
const vm = require('vm');
const fs = require('fs');
const path = require('path');
const http = require('http');

const PLUGIN = path.resolve(__dirname, '..', '..', 'assets', 'plugins', 'chaoxing.js');
const MAX_ROUNDS = 8;

// ── 与 plugin_ctx_script.dart 的 kPluginCtxScript 等价的 ctx 实现 ──
const CTX_SCRIPT = `
var __ctx_http_cache = {};
var __ctx_http_pending = [];
var __ctx_storage = {};
var __ctx_storage_touched = {};
var __ctx_logs = [];
var __ctx_notifies = [];
var __ctx_cookie = '';
var __ctx_http_errors = [];

function __ctx_request_key(method, url, body, headersJson) {
  var b = (body === undefined || body === null) ? '' : String(body);
  return method + '|' + String(url) + '|' + b + '|' + String(headersJson || '{}');
}
function __ctx_note_http_error(responseJson) {
  var r;
  try { r = JSON.parse(responseJson); } catch (e) { return; }
  if (!r || r.ok) return;
  if (r.error && r.error !== 'pending') { __ctx_http_errors.push(String(r.error)); }
}
function __ctx_http(method, url, body, headersJson) {
  var key = __ctx_request_key(method, url, body, headersJson);
  if (Object.prototype.hasOwnProperty.call(__ctx_http_cache, key)) {
    var cached = __ctx_http_cache[key];
    __ctx_note_http_error(cached);
    return cached;
  }
  for (var i = 0; i < __ctx_http_pending.length; i++) {
    if (__ctx_http_pending[i].key === key) {
      return JSON.stringify({ ok: false, error: 'pending' });
    }
  }
  var headers = {};
  try { headers = JSON.parse(headersJson || '{}'); } catch (e) { headers = {}; }
  __ctx_http_pending.push({
    method: method, url: String(url),
    body: (body === undefined || body === null) ? null : String(body),
    headers: headers, key: key
  });
  return JSON.stringify({ ok: false, error: 'pending' });
}
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
var ctx = {
  http: {
    get: function (url, headers) {
      var r = JSON.parse(__ctx_http('GET', url, null, JSON.stringify(headers || {})));
      if (!r.ok && r.error !== 'pending') { throw new Error(r.error); }
      return r;
    },
    post: function (url, body, headers) {
      var payload = (body === undefined || body === null) ? null : body;
      if (payload !== null && typeof payload !== 'string') { payload = JSON.stringify(payload); }
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
    schedule: function (title, body, triggerAtIso) {
      __ctx_notifies.push({ title: String(title), body: String(body), triggerAtIso: String(triggerAtIso) });
    }
  },
  get cookie() { return __ctx_cookie; },
  get lastHttpError() {
    return __ctx_http_errors.length > 0 ? __ctx_http_errors[__ctx_http_errors.length - 1] : '';
  }
};
`;

function evalInPage(js) {
  return new Promise((resolve, reject) => {
    const req = http.get('http://127.0.0.1:8899/eval?js=' + encodeURIComponent(js), (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => {
        try {
          const o = JSON.parse(d);
          if (!o.ok) return reject(new Error(JSON.stringify(o).slice(0, 300)));
          resolve(o.value);
        } catch (e) {
          reject(new Error(d.slice(0, 300)));
        }
      });
    });
    req.setTimeout(180000, () => req.destroy(new Error('eval timeout')));
    req.on('error', reject);
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 把一批请求交给浏览器页面上下文发出去（浏览器会自动带上 Cookie，
// 因此这里**不能**透传 Cookie 头——fetch 禁止设置该头）。
async function performRequests(requests) {
  const jobs = requests.map((r) => {
    const headers = {};
    Object.keys(r.headers || {}).forEach((k) => {
      if (k.toLowerCase() === 'cookie') return;
      headers[k] = r.headers[k];
    });
    return { key: r.key, method: r.method, url: r.url, headers };
  });
  const js = `(async () => {
    const jobs = ${JSON.stringify(jobs)};
    const out = [];
    for (const j of jobs) {
      try {
        const r = await fetch(j.url, { method: j.method, headers: j.headers, credentials: 'include' });
        const body = await r.text();
        const hs = {};
        r.headers.forEach((v, k) => { hs[k] = v; });
        out.push({ key: j.key, ok: true, status: r.status, body: body, headers: hs });
      } catch (e) {
        out.push({ key: j.key, ok: false, error: String(e && e.message) });
      }
    }
    return JSON.stringify(out);
  })()`;
  const raw = await evalInPage(js);
  const list = JSON.parse(raw);
  const cache = {};
  for (const item of list) {
    cache[item.key] = JSON.stringify(
      item.ok
        ? { ok: true, status: item.status, body: item.body, headers: item.headers }
        : { ok: false, error: item.error }
    );
  }
  return cache;
}

async function runEntry(context, pluginSource, entry, args, cookie) {
  // 载入插件（每轮都会重放，但定义只做一次即可——宿主也是顶层只求值一次）
  const sandbox = { console, JSON, Math, Number, String, Object, Array, RegExp, parseInt, parseFloat, isNaN, encodeURIComponent, decodeURIComponent, Date, Error };
  const ctxObj = vm.createContext(sandbox);
  vm.runInContext(CTX_SCRIPT, ctxObj);
  vm.runInContext(pluginSource, ctxObj);

  const httpCache = {};
  const storage = {};
  const logs = [];
  const fnLiteral = JSON.stringify(entry);
  const argsLiteral = JSON.stringify(JSON.stringify(args || {}));

  for (let round = 0; round < MAX_ROUNDS; round++) {
    const preamble =
      `var __ctx_http_cache = ${JSON.stringify(httpCache)};\n` +
      `var __ctx_http_pending = [];\n` +
      `var __ctx_storage = ${JSON.stringify(storage)};\n` +
      `var __ctx_storage_touched = {};\n` +
      `var __ctx_logs = [];\n` +
      `var __ctx_notifies = [];\n` +
      `var __ctx_cookie = ${JSON.stringify(cookie)};\n` +
      `var __ctx_http_errors = [];\n`;
    vm.runInContext(preamble, ctxObj);

    const call = `(function () {
      var __f = __plugin[${fnLiteral}];
      if (typeof __f !== 'function') { throw new Error('entry function not found: ' + ${fnLiteral}); }
      var __r = __f(JSON.parse(${argsLiteral}));
      return (__r === undefined) ? 'null' : JSON.stringify(__r);
    })()`;

    let resultStr;
    try {
      resultStr = vm.runInContext(call, ctxObj);
    } catch (e) {
      resultStr = JSON.stringify({ error: 'JS 抛错：' + String(e && e.message) });
    }

    const dumpRaw = vm.runInContext(
      `JSON.stringify({ pending: __ctx_http_pending, storage: __ctx_storage, touched: Object.keys(__ctx_storage_touched), logs: __ctx_logs, httpErrors: __ctx_http_errors })`,
      ctxObj
    );
    const dump = JSON.parse(dumpRaw);
    dump.logs.forEach((l) => logs.push(l));
    Object.keys(dump.storage).forEach((k) => (storage[k] = dump.storage[k]));

    if (!dump.pending.length) {
      return { result: JSON.parse(resultStr), rounds: round + 1, logs, storage, httpErrors: dump.httpErrors };
    }
    console.log(`    [round ${round + 1}] 登记 ${dump.pending.length} 个请求，取回后重放`);
    Object.assign(httpCache, await performRequests(dump.pending));
    await sleep(400); // 限速，避免触发风控
  }
  return { result: { error: `重放轮数超过上限 ${MAX_ROUNDS}` }, rounds: MAX_ROUNDS, logs, storage, httpErrors: [] };
}

module.exports = { runEntry };

// ───────────────────────── 直接运行：端到端验证 ─────────────────────────
if (require.main === module) {
  (async () => {
    const source = fs.readFileSync(PLUGIN, 'utf8');
    // 真实请求由浏览器代理发出（Cookie 由浏览器自动带上，且 JSESSIONID 是 HttpOnly，
    // document.cookie 取不到）。这里给一个非空占位值，只为绕过插件的"未登录"前置检查。
    const cookie = 'proxied-by-browser-session';

    console.log('=== 1. fetchCourseList ===');
    const r1 = await runEntry(null, source, 'fetchCourseList', {}, cookie);
    console.log('轮数:', r1.rounds, '| logs:', r1.logs.map((l) => l.msg).join('; '));
    if (r1.result.error) {
      console.log('错误:', r1.result.error);
    } else {
      const cs = r1.result.courses || [];
      console.log('课程数:', cs.length);
      cs.slice(0, 3).forEach((c) => console.log('  ', c.name, '|', c.teacher, '|', c.className, '|', c.id));
    }

    if (r1.result.error) return;
    // 选有作业的那门 + 有考试的那门
    const pick = (r1.result.courses || []).filter((c) =>
      ['267787514', '267126105'].includes(c.courseId)
    );
    console.log('\n选中课程:', pick.map((c) => c.name).join(', '));

    console.log('\n=== 2. fetchHomeworks（含正文）===');
    const r2 = await runEntry(null, source, 'fetchHomeworks', { courses: pick, withContent: true }, cookie);
    console.log('轮数:', r2.rounds, '| logs:', r2.logs.map((l) => l.msg).join('; '));
    console.log(JSON.stringify(r2.result, null, 1).slice(0, 3000));

    console.log('\n=== 3. fetchExams ===');
    const r3 = await runEntry(null, source, 'fetchExams', { courses: pick }, cookie);
    console.log('轮数:', r3.rounds, '| logs:', r3.logs.map((l) => l.msg).join('; '));
    console.log(JSON.stringify(r3.result, null, 1).slice(0, 2000));
  })().catch((e) => console.error('FATAL', e));
}
