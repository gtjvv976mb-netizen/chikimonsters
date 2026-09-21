import { chromium } from 'playwright';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' }).catch(() => chromium.launch());
const p = await b.newPage({ viewport: { width: 1280, height: 860 } });
const errs = [];
p.on('pageerror', e => errs.push(String(e)));
await p.goto('http://localhost:4321/', { waitUntil: 'networkidle' });
await p.waitForTimeout(1800);
const H = 860;
const stops = [['1-hero', 0], ['2-act1', H * 1.2], ['3-act2', H * 2.3], ['4-act3', H * 3.4], ['5-cards', H * 4.6], ['6-start', H * 5.6], ['7-cta', H * 7.0]];
for (const [name, y] of stops) {
  await p.evaluate(y => window.scrollTo(0, y), y);
  await p.waitForTimeout(1100);
  await p.screenshot({ path: `shots/${name}.png` });
}
console.log('page errors:', errs.length ? errs.slice(0,3) : 'none');
await b.close();
