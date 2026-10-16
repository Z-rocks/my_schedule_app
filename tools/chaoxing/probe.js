// 通过控制接口批量探测页面内的 fetch 行为，避免 shell 引号转义问题。
// 用法：node tools/chaoxing/probe.js
const http = require('http');

const Q = 'classId=156498244&courseId=267787514&isdisplaytable=2&mooc=1';
const ENC = '8c5bde376a4b26d43ff853b6ab4ec6ca';
const CPI = '344942005';
const OPENC = 'cc7cb75739bc35908364474874563502';
const BASE = '/mooc-ans/work/getAllWork?' + Q;

const probes = [
  ['A 完全照抄原 URL', `${BASE}&ut=s&enc=${ENC}&cpi=${CPI}&openc=${OPENC}`],
  ['B 只带 cpi', `${BASE}&ut=s&cpi=${CPI}`],
  ['C 带 cpi+openc', `${BASE}&ut=s&cpi=${CPI}&openc=${OPENC}`],
  ['D 不带 ut', `${BASE}&enc=${ENC}&cpi=${CPI}&openc=${OPENC}`],
  ['E 只带 openc', `${BASE}&ut=s&openc=${OPENC}`],
  ['F 裸参数（对照）', BASE],
];

function evalJs(js) {
  return new Promise((resolve, reject) => {
    const url = 'http://127.0.0.1:8899/eval?js=' + encodeURIComponent(js);
    http.get(url, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(d).value);
        } catch (e) {
          reject(new Error(d));
        }
      });
    }).on('error', reject);
  });
}

(async () => {
  for (const [name, path] of probes) {
    const js = `(async()=>{const r=await fetch(${JSON.stringify(path)},{credentials:'include'});const t=await r.text();return JSON.stringify({status:r.status,len:t.length,inspectTask:t.includes('inspectTask'),hasTitle:t.includes('第一章作业'),finalUrl:r.url})})()`;
    try {
      console.log(`--- ${name}`);
      console.log('   ', await evalJs(js));
    } catch (e) {
      console.log('    ERR', String(e.message).slice(0, 200));
    }
  }
})();
