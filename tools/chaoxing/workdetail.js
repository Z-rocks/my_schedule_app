// 分析作业列表页 HTML：inspectTask 点击后如何加载作业详情（作业内容）
const fs = require('fs');
const path = require('path');

const h = fs.readFileSync(path.join(__dirname, 'shots', '05-work-page.html'), 'utf8');

function show(label, idx, before, after) {
  if (idx < 0) return console.log(`=== ${label}: 未找到 ===`);
  console.log(`\n=== ${label} ===`);
  console.log(h.slice(Math.max(0, idx - before), idx + after).replace(/\s+/g, ' '));
}

show('inspectTask 定义', h.indexOf('inspectTask'), 100, 900);

// 找「做作业」按钮
const btn = h.match(/<a[^>]*>[^<]*做作业[^<]*<\/a>/g);
console.log('\n=== 做作业按钮 ===');
console.log(btn ? btn.slice(0, 3).join('\n') : '未找到');

// 找 workId 相关的 JS 调用
for (const key of ['getWorkInfo', 'workInfo', 'workId', 'toWork', 'work/getWork']) {
  const i = h.indexOf(key);
  if (i >= 0) {
    console.log(`\n=== 含 ${key} 的片段 ===`);
    console.log(h.slice(Math.max(0, i - 300), i + 400).replace(/\s+/g, ' '));
  }
}

// 列出页面里所有 ajax url
const urls = [...h.matchAll(/url\s*:\s*["']([^"']+)["']/g)].map((m) => m[1]);
console.log('\n=== 页面内 ajax url ===');
console.log([...new Set(urls)].join('\n'));
