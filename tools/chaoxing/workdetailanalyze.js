// 分析作业正文页结构：作业说明 / 题目
const fs = require('fs');
const path = require('path');

const h = fs.readFileSync(path.join(__dirname, 'out', 'work-detail.html'), 'utf8');
console.log('len =', h.length);

const strip = (s) => s.replace(/<script[\s\S]*?<\/script>/g, ' ').replace(/<style[\s\S]*?<\/style>/g, ' ');

// 关键词定位
for (const k of ['作业说明', '题目', 'ZiTi', 'question', 'TiMu', '题干', '作业要求', '作答', 'workTitle', 'workName', '第1题']) {
  const i = h.indexOf(k);
  console.log(`${k.padEnd(12)} ${i >= 0 ? 'FOUND@' + i : '-'}`);
}

// 找 title 附近
const t = h.match(/<title>([^<]*)<\/title>/);
console.log('\ntitle =', t && t[1]);

// 找作业名出现的位置
const nameIdx = h.indexOf('第一章作业');
console.log('\n=== 作业名上下文 ===');
console.log(strip(h.slice(Math.max(0, nameIdx - 800), nameIdx + 600)).replace(/\s+/g, ' '));

// 找题目容器
for (const sel of ['class="TiMu"', 'class="Cy_TItle"', 'class="questionLi"', 'id="questionList"', 'class="mark_item"']) {
  const i = h.indexOf(sel);
  if (i >= 0) {
    console.log(`\n=== ${sel} @${i} ===`);
    console.log(strip(h.slice(i, i + 1500)).replace(/\s+/g, ' '));
  }
}
