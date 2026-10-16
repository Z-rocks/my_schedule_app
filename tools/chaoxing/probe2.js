// 第二阶段探测：
//  1) 解析课程列表 HTML，列出全部课程（courseId / classId / 课程名 / 教师 / 班级 / cpi）
//  2) 验证 enc 是否账号级通用（用同一 enc 请求另一门课的作业列表）
//  3) 拉取考试页，观察结构
const http = require('http');
const fs = require('fs');
const path = require('path');

const ENC = '8c5bde376a4b26d43ff853b6ab4ec6ca';

function evalJs(js) {
  return new Promise((resolve, reject) => {
    http.get('http://127.0.0.1:8899/eval?js=' + encodeURIComponent(js), (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => {
        try {
          const v = JSON.parse(d).value;
          resolve(v);
        } catch (e) {
          reject(new Error(d.slice(0, 300)));
        }
      });
    }).on('error', reject);
  });
}

(async () => {
  // 1) 课程列表
  const coursesHtml = await evalJs(
    `(async()=>{const r=await fetch('/visit/courses/study',{credentials:'include'});return await r.text()})()`
  );
  fs.writeFileSync(path.join(__dirname, 'raw-courses-study.html'), coursesHtml, 'utf8');

  const liRe = /<li[^>]*class="courseItem[^"]*"[\s\S]*?<\/li>/g;
  const items = coursesHtml.match(liRe) || [];
  const courses = items.map((li) => {
    const courseId = (li.match(/name="courseId"\s+value="([^"]*)"/) || [])[1] || '';
    const classId = (li.match(/name="classId"\s+value="([^"]*)"/) || [])[1] || '';
    const name = (li.match(/class="courseName"[^>]*title="([^"]*)"/) || [])[1] || '';
    const cpi = (li.match(/cpi=(\d+)/) || [])[1] || '';
    const ps = [...li.matchAll(/<p title="([^"]*)">/g)].map((m) => m[1]).filter((s) => s.trim());
    return { courseId, classId, name, cpi, teacher: ps[0] || '', className: ps[ps.length - 1] || '' };
  });
  console.log('=== 课程总数：' + courses.length + ' ===');
  courses.slice(0, 12).forEach((c, i) =>
    console.log(`  ${i + 1}. ${c.name} | 教师:${c.teacher} | 班级:${c.className} | courseId=${c.courseId} classId=${c.classId} cpi=${c.cpi}`)
  );
  fs.writeFileSync(path.join(__dirname, 'courses.json'), JSON.stringify(courses, null, 2), 'utf8');

  // 2) enc 是否通用：拿第 2 门课试作业列表
  const c2 = courses[1];
  if (c2) {
    const js = `(async()=>{const r=await fetch('/mooc-ans/work/getAllWork?classId=${c2.classId}&courseId=${c2.courseId}&isdisplaytable=2&mooc=1&enc=${ENC}',{credentials:'include'});const t=await r.text();return JSON.stringify({len:t.length,ok:t.includes('inspectTask'),title:(t.match(/class="inspectTask"[^>]*title="([^"]*)"/)||[])[1]||null})})()`;
    console.log(`\n=== enc 通用性测试（第2门课 ${c2.name}）===`);
    console.log('   ', await evalJs(js));
  }

  // 3) 考试页
  const c1 = courses[0];
  if (c1) {
    const js = `(async()=>{const r=await fetch('/mooc-ans/exam-ans/exam/test?classId=${c1.classId}&courseId=${c1.courseId}&ut=s&enc=${ENC}&cpi=${c1.cpi}',{credentials:'include'});const t=await r.text();return t})()`;
    const examHtml = await evalJs(js);
    fs.writeFileSync(path.join(__dirname, 'raw-exam-list.html'), examHtml, 'utf8');
    console.log(`\n=== 考试页（第1门课 ${c1.name}）len=${examHtml.length} ===`);
    const idx = examHtml.indexOf('考试');
    console.log(examHtml.slice(Math.max(0, idx - 200), idx + 1200).replace(/\s+/g, ' '));
  }
})();
