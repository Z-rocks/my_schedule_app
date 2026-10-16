// 查看 202 拦截页的正文文案
const http = require('http');

function evalJs(js) {
  return new Promise((resolve, reject) => {
    http.get('http://127.0.0.1:8899/eval?js=' + encodeURIComponent(js), (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => {
        try {
          const o = JSON.parse(d);
          if (!o.ok) return reject(new Error(JSON.stringify(o)));
          resolve(o.value);
        } catch (e) {
          reject(new Error(d.slice(0, 200)));
        }
      });
    }).on('error', reject);
  });
}

(async () => {
  const js = `(async()=>{
    const r = await fetch('/visit/courses/study', {credentials:'include'});
    const t = await r.text();
    const i = t.indexOf('<body');
    const body = i >= 0 ? t.slice(i) : t;
    const text = body
      .replace(/<script[\\s\\S]*?<\\/script>/g, ' ')
      .replace(/<style[\\s\\S]*?<\\/style>/g, ' ')
      .replace(/<[^>]+>/g, ' ')
      .replace(/\\s+/g, ' ')
      .trim();
    return JSON.stringify({ status: r.status, text: text.slice(0, 500) });
  })()`;
  console.log(await evalJs(js));
})();
