// 带 standardEnc 拉作业正文页
const http = require('http');
const fs = require('fs');
const path = require('path');

function evalJs(js, timeoutMs = 60000) {
  return new Promise((resolve, reject) => {
    const req = http.get('http://127.0.0.1:8899/eval?js=' + encodeURIComponent(js), (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => {
        try {
          const o = JSON.parse(d);
          if (!o.ok) return reject(new Error(JSON.stringify(o)));
          resolve(o.value);
        } catch (e) {
          reject(new Error(d.slice(0, 300)));
        }
      });
    });
    req.setTimeout(timeoutMs, () => req.destroy(new Error('timeout')));
    req.on('error', reject);
  });
}

const STD = '98c69cf1536938a94c3ee43e65117dbd';
const url =
  '/mooc-ans/work/doHomeWorkNew?courseId=267787514&classId=156498244&workId=57058627&workAnswerId=0' +
  '&isdisplaytable=2&mooc=1&enc=9c352a0888e4b4377759d4657e9ffb07&workSystem=0&cpi=344942005' +
  '&openc=cc7cb75739bc35908364474874563502&standardEnc=' + STD;

(async () => {
  const r = await evalJs(
    `(async()=>{const r=await fetch(${JSON.stringify(url)},{credentials:'include'});const t=await r.text();return JSON.stringify({status:r.status,len:t.length,blocked:t.includes('9010')||t.includes('antispider'),title:(t.match(/<title>([^<]*)<\\/title>/)||[])[1]||null})})()`
  );
  console.log('探测:', r);
  const info = JSON.parse(r);
  if (info.status === 200 && info.len > 2000) {
    const html = await evalJs(`(async()=>{const r=await fetch(${JSON.stringify(url)},{credentials:'include'});return await r.text()})()`);
    fs.writeFileSync(path.join(__dirname, 'out', 'work-detail.html'), html, 'utf8');
    console.log('已落盘 out/work-detail.html len=' + html.length);
  }
})();
