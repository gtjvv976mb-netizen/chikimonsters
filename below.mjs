import { chromium } from 'playwright';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' }).catch(() => chromium.launch());
const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
await p.goto('http://localhost:4321/', { waitUntil: 'networkidle' });
await p.waitForTimeout(2500);
const sceneH = await p.evaluate(() => document.querySelector('[data-scene]').offsetHeight);
for (const [name, y] of [['5-start', sceneH + 40], ['6-faq', sceneH + 900], ['7-cta', sceneH + 1750]]) {
  await p.evaluate((y) => window.scrollTo(0, y), y);
  await p.waitForTimeout(700);
  await p.screenshot({ path: `shots/${name}.png` });
}
await b.close();
