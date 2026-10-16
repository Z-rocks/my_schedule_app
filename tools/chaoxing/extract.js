// 完整提取流程验证（这段逻辑将直接成为插件核心）：
//   1. /visit/courses/study            → 全部课程
//   2. /visit/stucoursemiddle?...      → 跟随跳转后的课程主页，从中取 enc
//   3. /mooc-ans/work/getAllWork?...   → 作业列表（HTML）
//   4. /exam-ans/exam/test?...         → 考试列表（HTML）
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

const OUT = path.join(__dirname, 'out');
fs.mkdirSync(OUT, { recursive: true });

// 在页面里跑一段"抓取+解析"的 JS，返回结构化结果
const grabScript = (courses) => `
(async () => {
  const out = [];
  for (const c of ${JSON.stringify(courses)}) {
    const rec = { courseId: c.courseId, classId: c.classId, name: c.name, enc: null, works: [], exams: [], err: null };
    try {
      const mid = await fetch('/visit/stucoursemiddle?courseid=' + c.courseId + '&clazzid=' + c.classId + '&vc=1&cpi=' + c.cpi, { credentials: 'include' });
      const midHtml = await mid.text();
      const m = midHtml.match(/[?&]enc=([0-9a-f]{16,})/);
      rec.enc = m ? m[1] : null;
      if (!rec.enc) { rec.err = 'no-enc'; out.push(rec); continue; }

      const w = await fetch('/mooc-ans/work/getAllWork?classId=' + c.classId + '&courseId=' + c.courseId + '&isdisplaytable=2&mooc=1&enc=' + rec.enc, { credentials: 'include' });
      const wHtml = await w.text();
      const wBlocks = wHtml.match(/<li[^>]*>[\\s\\S]*?class="inspectTask"[\\s\\S]*?<\\/li>/g) || [];
      rec.works = wBlocks.map(b => ({
        workId: (b.match(/class="inspectTask"[^>]*data="(\\d+)"/) || [])[1] || '',
        title: (b.match(/class="inspectTask"[^>]*title="([^"]*)"/) || [])[1] || '',
        start: (b.match(/开始时间：[\\s\\S]{0,40}?(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2})/) || [])[1] || '',
        deadline: (b.match(/截止时间：[\\s\\S]{0,40}?(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2})/) || [])[1] || '',
        status: (b.match(/作业状态：[\\s\\S]{0,60}?<strong>\\s*([^<]*?)\\s*<\\/strong>/) || [])[1] || '',
      }));

      const e = await fetch('/exam-ans/exam/test?classId=' + c.classId + '&courseId=' + c.courseId + '&ut=s&enc=' + rec.enc + '&cpi=' + c.cpi, { credentials: 'include' });
      const eHtml = await e.text();
      rec.examHtmlLen = eHtml.length;
      rec.examHasContent = !/暂无内容/.test(eHtml);
      if (rec.examHasContent) rec.examRaw = eHtml.slice(0, 20000);
    } catch (err) {
      rec.err = String(err && err.message);
    }
    out.push(rec);
  }
  return JSON.stringify(out);
})()
`;

(async () => {
  const coursesHtml = await evalJs(
    `(async()=>{const r=await fetch('/visit/courses/study',{credentials:'include'});return await r.text()})()`
  );
  const items = coursesHtml.match(/<li[^>]*class="courseItem[^"]*"[\s\S]*?<\/li>/g) || [];
  const courses = items.map((li) => ({
    courseId: (li.match(/name="courseId"\s+value="([^"]*)"/) || [])[1] || '',
    classId: (li.match(/name="classId"\s+value="([^"]*)"/) || [])[1] || '',
    name: (li.match(/class="courseName"[^>]*title="([^"]*)"/) || [])[1] || '',
    cpi: (li.match(/cpi=(\d+)/) || [])[1] || '',
  }));
  console.log('课程总数:', courses.length);

  const batch = courses.slice(0, 8);
  const res = JSON.parse(await evalJs(grabScript(batch)));
  for (const r of res) {
    console.log(`\n=== ${r.name} (courseId=${r.courseId}) enc=${r.enc} err=${r.err} ===`);
    console.log(`  作业 ${r.works.length} 条:`);
    r.works.forEach((w) => console.log(`    · ${w.title} | 开始 ${w.start} | 截止 ${w.deadline} | ${w.status} | id=${w.workId}`));
    console.log(`  考试: htmlLen=${r.examHtmlLen} 有内容=${r.examHasContent}`);
    if (r.examRaw) {
      fs.writeFileSync(path.join(OUT, `exam-${r.courseId}.html`), r.examRaw, 'utf8');
      console.log('    → 已落盘 exam-' + r.courseId + '.html');
    }
  }
})();
