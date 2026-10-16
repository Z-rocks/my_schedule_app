// 探测作业详情相关：/work/isExpire 返回什么；作业列表页里是否藏着作业说明
const http = require('http');
const fs = require('fs');
const path = require('path');

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
  // 1) isExpire
  const isExpire = await evalJs(
    `(async()=>{const r=await fetch('/mooc-ans/work/isExpire?classId=156498244&workRelationId=57058627&cpi=344942005&courseId=267787514',{credentials:'include'});return await r.text()})()`
  );
  console.log('=== /work/isExpire ===');
  console.log(isExpire.slice(0, 800));

  // 2) 作业列表页里是否有隐藏的作业说明
  const h = fs.readFileSync(path.join(__dirname, 'shots', '05-work-page.html'), 'utf8');
  console.log('\n=== 作业列表页里的隐藏块 / 说明 ===');
  for (const k of ['display:none', '作业说明', 'wrap-answer', 'CyAnswer', 'titOper', 'tipWin']) {
    const i = h.indexOf(k);
    console.log(`  ${k}: ${i >= 0 ? 'FOUND@' + i : 'not found'}`);
  }
  const i = h.indexOf('class="titOper"');
  if (i >= 0) {
    console.log('\n--- titOper 片段 ---');
    console.log(h.slice(i - 100, i + 800).replace(/\s+/g, ' '));
  }
  const j = h.indexOf('class="titTxt"');
  const j2 = h.indexOf('</div>', h.indexOf('作业状态', j));
  console.log('\n--- 第一条作业完整块 ---');
  console.log(h.slice(j - 60, j2 + 400).replace(/\s+/g, ' '));
})();
