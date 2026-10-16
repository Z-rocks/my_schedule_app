// 分析抓包产物：课程列表 HTML 里是否含 enc / cpi / openc 等参数
const fs = require('fs');
const path = require('path');

const dir = path.resolve(__dirname);
const h = fs.readFileSync(path.join(dir, 'raw-courses-study.html'), 'utf8');

for (const k of ['enc=', 'cpi=', 'openc=', 'stucoursemiddle', 'ut=s']) {
  const re = new RegExp('[^"\'\\s]{0,50}' + k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '[^"\'\\s]{0,60}', 'g');
  const m = h.match(re) || [];
  console.log(`=== ${k} 出现 ${m.length} 次 ===`);
  m.slice(0, 4).forEach((x) => console.log('   ', x));
}

console.log('\n=== 第一个 courseItem 的完整 li ===');
const i = h.indexOf('courseItem');
const j = h.indexOf('</li>', i);
console.log(h.slice(Math.max(0, i - 40), j + 6).replace(/\s+/g, ' '));

console.log('\n=== 统计 courseItem 数量 ===');
console.log((h.match(/class="courseItem/g) || []).length);
