// 验证「session 当前课程」机制：作业/考试接口是否要求先"进入"该课程
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
  ];
  const diag = (t) => ({ len: t.length, err3003: t.includes('3003'), noContent: t.includes('暂无内容') });
  const out = [];
  for (const c of courses) {
    const rec = { name: c.name, steps: [] };
    const mid = await fetch('/visit/stucoursemiddle?courseid=' + c.courseId + '&clazzid=' + c.classId + '&vc=1&cpi=' + c.cpi, { credentials: 'include' });
    const midHtml = await mid.text();
    const enc = (midHtml.match(/[?&]enc=([0-9a-f]{16,})/) || [])[1] || '';
    rec.enc = enc;
    rec.steps.push({ step: 'stucoursemiddle', ...diag(midHtml) });

    // ① 先请求作业，再请求考试（同一课程上下文）
    const w1 = await (await fetch('/mooc-ans/work/getAllWork?classId=' + c.classId + '&courseId=' + c.courseId + '&isdisplaytable=2&mooc=1&enc=' + enc, { credentials: 'include' })).text();
    rec.steps.push({ step: 'work(1st)', ...diag(w1), works: (w1.match(/class="inspectTask"/g) || []).length });

    const e1 = await (await fetch('/exam-ans/exam/test?classId=' + c.classId + '&courseId=' + c.courseId + '&ut=s&enc=' + enc + '&cpi=' + c.cpi, { credentials: 'include' })).text();
    rec.steps.push({ step: 'exam', ...diag(e1) });

    // ② 再请求一次作业（看是否被考试请求影响）
    const w2 = await (await fetch('/mooc-ans/work/getAllWork?classId=' + c.classId + '&courseId=' + c.courseId + '&isdisplaytable=2&mooc=1&enc=' + enc, { credentials: 'include' })).text();
    rec.steps.push({ step: 'work(2nd)', ...diag(w2), works: (w2.match(/class="inspectTask"/g) || []).length });

    out.push(rec);
  }
  return JSON.stringify(out, null, 1);
})()
`;

(async () => {
  console.log(await evalJs(script));
})();
