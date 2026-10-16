// 分析作业正文页的题目 DOM 结构
const fs = require('fs');
const path = require('path');

const h = fs.readFileSync(path.join(__dirname, 'shots', '08-work-detail.html'), 'utf8');
console.log('len =', h.length);

// 统计关键 class 出现次数
for (const k of ['TiMu', 'Zy_TItle', 'Cy_TItle', 'mark_item', 'questionLi', 'fl TiMu', 'answerList', '分）', '填空题', '简答题']) {
  const n = (h.match(new RegExp(k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g')) || []).length;
  console.log(`  ${k.padEnd(14)} x${n}`);
}

const i = h.indexOf('TiMu');
if (i >= 0) {
  console.log('\n=== 第一处 TiMu 起 4000 字符 ===');
  console.log(h.slice(i - 200, i + 4000).replace(/\s+/g, ' '));
}
