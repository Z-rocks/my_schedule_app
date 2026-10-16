// 提取考试列表的真实 DOM 片段
const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, 'out');
const f = 'exam-content-267126105.html';
const h = fs.readFileSync(path.join(OUT, f), 'utf8');

const i = h.indexOf('id="CyList"');
console.log('CyList 位置:', i);
if (i >= 0) {
  // 往前找最近的 <ul
  const start = h.lastIndexOf('<ul', i);
  const end = h.indexOf('</ul>', i);
  console.log('\n=== CyList 容器 ===');
  console.log(h.slice(start, end + 5).replace(/\s+/g, ' ').slice(0, 4000));
}

console.log('\n=== 关键词定位 ===');
for (const k of ['考试时间', '开考', '进入考试', '查看', 'testId', 'testName', 'class="titTxt"']) {
  const j = h.indexOf(k);
  console.log(`  ${k}: ${j >= 0 ? 'FOUND@' + j : 'not found'}`);
  if (j >= 0 && k !== 'class="titTxt"') {
    console.log('    ...' + h.slice(Math.max(0, j - 250), j + 350).replace(/\s+/g, ' '));
  }
}
