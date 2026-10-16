// 探针：验证沙箱能否拉起「有界面」的 Chrome 并访问学习通。
// 一次性脚本，验证完即删。
const { chromium } = require('playwright-core');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

(async () => {
  console.log('[probe] launching headed chrome...');
  const browser = await chromium.launch({
    headless: false,
    executablePath: CHROME,
    args: ['--start-maximized'],
  });
  const ctx = await browser.newContext({ viewport: null });
  const page = await ctx.newPage();
  await page.goto('https://passport2.chaoxing.com/login', {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });
  console.log('[probe] url =', page.url());
  console.log('[probe] title =', await page.title());
  await page.screenshot({ path: 'tools/chaoxing/_probe.png', fullPage: false });
  console.log('[probe] screenshot saved');
  await browser.close();
  console.log('[probe] OK');
})().catch((e) => {
  console.error('[probe] FAILED:', e && e.message);
  process.exit(1);
});
