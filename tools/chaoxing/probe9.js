// 作业正文链路：/work/isExpire → /work/doHomeWorkNew
// 注意：单发 + 间隔，避免触发风控。
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
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  // 1) isExpire
  const isExpire = await evalJs(
    `(async()=>{const r=await fetch('/mooc-ans/work/isExpire?classId=156498244&workRelationId=57058627&cpi=344942005&courseId=267787514',{credentials:'include',headers:{'X-Requested-With':'XMLHttpRequest'}});const t=await r.text();return JSON.stringify({status:r.status,ct:r.headers.get('content-type'),len:t.length,body:t.slice(0,600)})})()`
  );
  console.log('=== /work/isExpire ===');
  console.log(isExpire);

  await sleep(1500);

  // 2) doHomeWorkNew（先不带 standardEnc 试一次）
  const workUrl = '/mooc-ans/work/doHomeWorkNew?courseId=267787514&classId=156498244&workId=57058627&workAnswerId=0&isdisplaytable=2&mooc=1&enc=9c352a0888e4b4377759d4657e9ffb07&workSystem=0&cpi=344942005&openc=cc7cb75739bc35908364474874563502&standardEnc=';
  const work = await evalJs(
    `(async()=>{const r=await fetch(${JSON.stringify(workUrl)},{credentials:'include'});const t=await r.text();return JSON.stringify({status:r.status,len:t.length,blocked:t.includes('9010')||t.includes('antispider'),title:(t.match(/<title>([^<]*)<\\/title>/)||[])[1]||null})})()`
  );
  console.log('\n=== /work/doHomeWorkNew ===');
  console.log(work);

  const w = JSON.parse(work);
  if (w.status === 200 && !w.blocked) {
    const html = await evalJs(`(async()=>{const r=await fetch(${JSON.stringify(workUrl)},{credentials:'include'});return await r.text()})()`);
    fs.writeFileSync(path.join(__dirname, 'out', 'work-detail.html'), html, 'utf8');
    console.log('\n已落盘 out/work-detail.html, len=' + html.length);
  }
})();
