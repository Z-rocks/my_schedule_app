// 学习通抓包会话：拉起有界面的 Chrome（独立 profile），全程录制网络请求，
// 并暴露一个只监听 127.0.0.1 的控制 API，供我（AI）远程驱动页面 / 取回数据。
//
// 用法：node tools/chaoxing/session.js
// 控制 API（默认 127.0.0.1:8899）：
//   GET /status                当前 URL / 标题 / 请求数 / 是否已登录
//   GET /goto?url=<url>        跳转
//   GET /shot?name=<name>      截图到 tools/chaoxing/shots/<name>.png
//   GET /dump?name=<name>      保存当前 DOM 到 tools/chaoxing/shots/<name>.html
//   GET /cookies               导出 cookie
//   GET /mark?label=<label>    在抓包流里插一条标记（区分"用户点了什么"）
//   GET /eval?js=<expr>        在页面里求值（只读用途）
//   GET /quit                  关闭浏览器并退出
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright-core');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const ROOT = path.resolve(__dirname);
const PROFILE = path.join(ROOT, '.profile');
const SHOTS = path.join(ROOT, 'shots');
const PORT = 8899;
const STAMP = new Date().toISOString().replace(/[:.]/g, '-');
const NETLOG = path.join(ROOT, `netlog-${STAMP}.jsonl`);

fs.mkdirSync(SHOTS, { recursive: true });
const logStream = fs.createWriteStream(NETLOG, { flags: 'a' });

function rec(obj) {
  try {
    logStream.write(JSON.stringify(obj) + '\n');
  } catch (_) {}
}

// 哪些请求值得记正文：接口调用与文档。
const BODY_TYPES = new Set(['xhr', 'fetch', 'document']);
const TEXTUAL = /json|text|javascript|xml|x-www-form-urlencoded/i;

(async () => {
  const browser = await chromium.launchPersistentContext(PROFILE, {
    headless: false,
    executablePath: CHROME,
    viewport: null,
    args: ['--start-maximized', '--disable-blink-features=AutomationControlled'],
  });

  const pages = browser.pages();
  const page = pages.length ? pages[0] : await browser.newPage();

  page.on('response', async (resp) => {
    try {
      const req = resp.request();
      const type = req.resourceType();
      const entry = {
        t: new Date().toISOString(),
        kind: 'response',
        type,
        method: req.method(),
        status: resp.status(),
        url: resp.url(),
        postData: type === 'xhr' || type === 'fetch' ? req.postData() || null : null,
      };
      if (BODY_TYPES.has(type)) {
        const ct = (resp.headers()['content-type'] || '');
        if (TEXTUAL.test(ct)) {
          const body = await resp.text().catch(() => null);
          if (body != null) entry.body = body.length > 200000 ? body.slice(0, 200000) + '...[truncated]' : body;
        }
      }
      rec(entry);
    } catch (_) {}
  });

  page.on('framenavigated', (f) => {
    if (f === page.mainFrame()) rec({ t: new Date().toISOString(), kind: 'nav', url: f.url() });
  });

  await page.goto('https://passport2.chaoxing.com/login', {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  }).catch((e) => console.log('[session] goto failed:', e.message));

  console.log('[session] netlog =', NETLOG);
  console.log('[session] 请在打开的 Chrome 窗口里登录学习通（扫码或账号密码均可）');

  const server = http.createServer(async (req, res) => {
    const u = new URL(req.url, `http://127.0.0.1:${PORT}`);
    const send = (code, obj) => {
      res.writeHead(code, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify(obj));
    };
    try {
      switch (u.pathname) {
        case '/status': {
          const url = page.url();
          const title = await page.title().catch(() => '');
          const loggedIn = !/passport\d*\.chaoxing\.com|^about:blank/.test(url);
          return send(200, { ok: true, url, title, loggedIn, netlog: NETLOG });
        }
        case '/goto': {
          await page.goto(u.searchParams.get('url'), { waitUntil: 'domcontentloaded', timeout: 60000 });
          return send(200, { ok: true, url: page.url() });
        }
        case '/shot': {
          const name = (u.searchParams.get('name') || 'shot') + '.png';
          const p = path.join(SHOTS, name);
          await page.screenshot({ path: p, fullPage: u.searchParams.get('full') === '1' });
          return send(200, { ok: true, file: p });
        }
        case '/dump': {
          const name = (u.searchParams.get('name') || 'dump') + '.html';
          const p = path.join(SHOTS, name);
          fs.writeFileSync(p, await page.content(), 'utf8');
          return send(200, { ok: true, file: p });
        }
        case '/cookies': {
          const cookies = await browser.cookies();
          return send(200, { ok: true, cookies });
        }
        case '/mark': {
          rec({ t: new Date().toISOString(), kind: 'mark', label: u.searchParams.get('label') || '' });
          return send(200, { ok: true });
        }
        case '/eval': {
          const v = await page.evaluate(u.searchParams.get('js') || '1').catch((e) => 'ERR:' + e.message);
          return send(200, { ok: true, value: v });
        }
        case '/quit': {
          send(200, { ok: true, bye: true });
          rec({ t: new Date().toISOString(), kind: 'quit' });
          setTimeout(async () => {
            await browser.close().catch(() => {});
            process.exit(0);
          }, 300);
          return;
        }
        default:
          return send(404, { ok: false, error: 'unknown path' });
      }
    } catch (e) {
      return send(500, { ok: false, error: String(e && e.message) });
    }
  });

  server.listen(PORT, '127.0.0.1', () => {
    console.log(`[session] control api on http://127.0.0.1:${PORT}`);
  });

  setInterval(async () => {
    const url = page.url();
    console.log(`[hb] ${new Date().toLocaleTimeString()} ${url}`);
  }, 15000);
})().catch((e) => {
  console.error('[session] FATAL:', e && e.stack);
  process.exit(1);
});
