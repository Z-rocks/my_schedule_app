// 第三阶段：读课程页上的 考试 入口真实地址，并验证 enc 从课程页 HTML 提取
const http = require('http');

function call(p) {
  return new Promise((resolve, reject) => {
    http.get('http://127.0.0.1:8899' + p, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(d));
        } catch (e) {
          reject(new Error(d.slice(0, 200)));
        }
      });
    }).on('error', reject);
  });
}
const evalJs = (js) => call('/eval?js=' + encodeURIComponent(js)).then((r) => r.value);

(async () => {
  // 回到第 1 门课的课程主页
  const url = 'https://mooc1-2.chaoxing.com/visit/stucoursemiddle?courseid=267787514&clazzid=156498244&vc=1&cpi=344942005';
  console.log('goto:', (await call('/goto?url=' + encodeURIComponent(url))).url);

  // 读所有导航 data 属性 + 页面里的 host 变量
  const info = await evalJs(`JSON.stringify({
    hostCp2: (typeof _HOST_CP2_ !== 'undefined' ? _HOST_CP2_ : null),
    hostCp1: (typeof _HOST_CP1_ !== 'undefined' ? _HOST_CP1_ : null),
    nav: Array.from(document.querySelectorAll('a[data]')).map(a=>({title:a.getAttribute('title'), data:a.getAttribute('data')})),
    encInHtml: (document.documentElement.innerHTML.match(/enc=([0-9a-f]{16,})/g)||[]).slice(0,3)
  })`);
  console.log('--- 导航与 host ---');
  console.log(info);

  const nav = JSON.parse(info).nav;
  const exam = nav.find((x) => x.title === '考试');
  if (exam) {
    console.log('\n--- 考试 data 属性 ---\n', exam.data);
    for (const base of ['https://mooc1-2.chaoxing.com', 'https://mooc1-2.chaoxing.com/mooc-ans']) {
      const full = base + exam.data;
      const r = await call('/goto?url=' + encodeURIComponent(full));
      console.log('  试:', base, '->', r.url, '| status:', r.ok);
      const probe = await evalJs(`JSON.stringify({title:document.title, len:document.documentElement.outerHTML.length, is404:document.title.includes('404')})`);
      console.log('     ', probe);
      if (!JSON.parse(probe).is404) break;
    }
  }
})();
