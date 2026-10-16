// 检查关键接口响应的 Content-Type / 字符集（决定插件里 dio 能否正确解码中文）
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

const script = `
(async () => {
  const targets = [
    ['课程列表', 'https://mooc1-2.chaoxing.com/visit/courses/study'],
    ['课程主页(跳转后)', 'https://mooc1-2.chaoxing.com/visit/stucoursemiddle?courseid=267787514&clazzid=156498244&vc=1&cpi=344942005'],
    ['作业列表', 'https://mooc1-2.chaoxing.com/mooc-ans/work/getAllWork?classId=156498244&courseId=267787514&isdisplaytable=2&mooc=1&enc=8c5bde376a4b26d43ff853b6ab4ec6ca&cpi=344942005&openc=cc7cb75739bc35908364474874563502'],
  ];
  const out = [];
  for (const [name, url] of targets) {
    const r = await fetch(url, { credentials: 'include' });
    const buf = await r.arrayBuffer();
    const bytes = new Uint8Array(buf);
    // 用 TextDecoder 以 utf-8 严格解码，失败说明不是 utf-8
    let utf8ok = true, utf8err = '';
    try { new TextDecoder('utf-8', { fatal: true }).decode(bytes); } catch (e) { utf8ok = false; utf8err = String(e.message); }
    const head = new TextDecoder('utf-8').decode(bytes.slice(0, 600));
    out.push({
      name,
      status: r.status,
      contentType: r.headers.get('content-type'),
      bytes: bytes.length,
      utf8ok,
      utf8err,
      metaCharset: (head.match(/charset=["']?([\\w-]+)/i) || [])[1] || null,
    });
  }
  return JSON.stringify(out, null, 1);
})()
`;

(async () => {
  console.log(await evalJs(script));
})();
