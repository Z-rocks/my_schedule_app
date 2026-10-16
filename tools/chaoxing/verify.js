// 轻量验证：单次请求课程列表，确认风控已解除
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
    return JSON.stringify({
      status: r.status,
      len: t.length,
      courseCount: (t.match(/class="courseItem/g)||[]).length,
      blocked: t.includes('9010') || t.includes('antispider'),
    });
  })()`;
  console.log(await evalJs(js));
})();
