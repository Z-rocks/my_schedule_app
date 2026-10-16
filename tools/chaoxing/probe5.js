// 正确姿势：从课程主页 HTML 里直接抠出「作业 / 考试」的完整地址（含 enc/cpi/openc），
// 而不是自己拼参数。
const http = require('http');

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

const script = `
(async () => {
  const courses = [
    { courseId: '267787514', classId: '156498244', cpi: '344942005', name: '综合评价方法' },
    { courseId: '267126809', classId: '155325476', cpi: '344942005', name: '软件工程C-2026' },
    { courseId: '232896455', classId: '141025835', cpi: '344942005', name: '软件架构与设计模式' },
    { courseId: '240974645', classId: '140258368', cpi: '344942005', name: '机器学习' },
  ];
  const diag = (t) => ({ len: t.length, err3003: t.includes('3003'), noContent: t.includes('暂无内容') });
  const out = [];
  for (const c of courses) {
    const rec = { name: c.name, workUrl: null, examUrl: null, work: null, exam: null };
    const midHtml = await (await fetch('/visit/stucoursemiddle?courseid=' + c.courseId + '&clazzid=' + c.classId + '&vc=1&cpi=' + c.cpi, { credentials: 'include' })).text();
    const dec = (s) => s.replace(/&amp;/g, '&');
    const wm = midHtml.match(/data="([^"]*\\/work\\/getAllWork[^"]*)"/);
    const em = midHtml.match(/data="([^"]*\\/exam-ans\\/exam\\/test[^"]*)"/);
    rec.workUrl = wm ? dec(wm[1]) : null;
    rec.examUrl = em ? dec(em[1]) : null;

    if (rec.workUrl) {
      const t = await (await fetch(rec.workUrl, { credentials: 'include' })).text();
      rec.work = { ...diag(t), items: (t.match(/class="inspectTask"/g) || []).length };
    }
    if (rec.examUrl) {
      const t = await (await fetch(rec.examUrl, { credentials: 'include' })).text();
      rec.exam = { ...diag(t) };
      if (!diag(t).err3003) rec.examRawHead = t.slice(0, 4000);
    }
    out.push(rec);
  }
  return JSON.stringify(out, null, 1);
})()
`;

(async () => {
  const r = await evalJs(script);
  console.log(r);
})();
