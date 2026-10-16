// 全量扫描 68 门课程：作业 + 考试，分批复用页面上下文执行（避免单次 evaluate 超时）
const http = require('http');
const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, 'out');
fs.mkdirSync(OUT, { recursive: true });

function evalJs(js, timeoutMs = 120000) {
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
    req.setTimeout(timeoutMs, () => {
      req.destroy(new Error('eval timeout'));
    });
    req.on('error', reject);
  });
}

const batchScript = (courses) => `
(async () => {
  const out = [];
  for (const c of ${JSON.stringify(courses)}) {
    const rec = { courseId: c.courseId, classId: c.classId, name: c.name, teacher: c.teacher, enc: null, works: [], exams: [], err: null, workLen: 0, examLen: 0 };
    try {
      const midHtml = await (await fetch('/visit/stucoursemiddle?courseid=' + c.courseId + '&clazzid=' + c.classId + '&vc=1&cpi=' + c.cpi, { credentials: 'include' })).text();
      const dec = (s) => s.replace(/&amp;/g, '&');
      const wm = midHtml.match(/data="([^"]*\\/work\\/getAllWork[^"]*)"/);
      const em = midHtml.match(/data="([^"]*\\/exam-ans\\/exam\\/test[^"]*)"/);
      const encM = midHtml.match(/[?&]enc=([0-9a-f]{16,})/);
      rec.enc = encM ? encM[1] : null;

      if (wm) {
        const t = await (await fetch(dec(wm[1]), { credentials: 'include' })).text();
        rec.workLen = t.length;
        rec.workErr3003 = t.includes('3003');
        const blocks = t.match(/<li[^>]*>[\\s\\S]*?class="inspectTask"[\\s\\S]*?<\\/li>/g) || [];
        rec.works = blocks.map(b => ({
          workId: (b.match(/class="inspectTask"[^>]*data="(\\d+)"/) || [])[1] || '',
          title: (b.match(/class="inspectTask"[^>]*title="([^"]*)"/) || [])[1] || '',
          start: (b.match(/开始时间：[\\s\\S]{0,60}?(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2})/) || [])[1] || '',
          deadline: (b.match(/截止时间：[\\s\\S]{0,60}?(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2})/) || [])[1] || '',
          status: (b.match(/作业状态：[\\s\\S]{0,80}?<strong>\\s*([^<]*?)\\s*<\\/strong>/) || [])[1] || '',
        }));
      }
      if (em) {
        const t = await (await fetch(dec(em[1]), { credentials: 'include' })).text();
        rec.examLen = t.length;
        rec.examErr3003 = t.includes('3003');
        rec.examHasContent = !/暂无内容/.test(t);
        if (rec.examHasContent) rec.examRaw = t;
      }
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

  const all = [];
  const BATCH = 8;
  for (let i = 0; i < courses.length; i += BATCH) {
    const chunk = courses.slice(i, i + BATCH);
    try {
      const res = JSON.parse(await evalJs(batchScript(chunk), 180000));
      all.push(...res);
      console.log(`  进度 ${Math.min(i + BATCH, courses.length)}/${courses.length}`);
    } catch (e) {
      console.log(`  批次 ${i} 失败: ${e.message}`);
      chunk.forEach((c) => all.push({ ...c, err: 'batch-fail' }));
    }
  }

  fs.writeFileSync(path.join(OUT, 'all-courses-data.json'), JSON.stringify(all, null, 2), 'utf8');

  console.log('\n===== 汇总 =====');
  let withWork = 0, withExam = 0;
  for (const r of all) {
    const w = r.works ? r.works.length : 0;
    const e = r.examHasContent ? 1 : 0;
    if (w) withWork++;
    if (e) withExam++;
    if (w || e) {
      console.log(`\n【${r.name}】 教师:${r.teacher} 作业${w} 考试${e ? '有' : '无'}`);
      (r.works || []).forEach((x) => console.log(`   作业: ${x.title} | 开始 ${x.start} | 截止 ${x.deadline} | ${x.status} | id=${x.workId}`));
      if (e) {
        const f = path.join(OUT, `exam-content-${r.courseId}.html`);
        fs.writeFileSync(f, r.examRaw, 'utf8');
        console.log(`   考试页已落盘: ${path.basename(f)} (len=${r.examRaw.length})`);
      }
    }
  }
  console.log(`\n共 ${all.length} 门课；有作业的 ${withWork} 门；有考试的 ${withExam} 门`);
  const errs = all.filter((r) => r.err || r.workErr3003 || r.examErr3003);
  console.log('异常条目:', errs.length);
  errs.slice(0, 5).forEach((r) => console.log('  ', r.name, r.err || '', 'work3003=' + r.workErr3003, 'exam3003=' + r.examErr3003));
})();
