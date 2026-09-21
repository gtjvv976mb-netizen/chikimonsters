import { chromium } from 'playwright';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' }).catch(() => chromium.launch());
const p = await b.newPage({ viewport: { width: 1280, height: 800 } });
const errs = [];
p.on('pageerror', (e) => errs.push(String(e)));
p.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
await p.goto('http://localhost:4321/', { waitUntil: 'networkidle' });
await p.waitForTimeout(2000);
const names = ['1-street', '2-reception', '3-booking', '4-chair'];
for (let i = 0; i < 4; i++) {
  await p.evaluate((n) => window.scrollTo(0, n * window.innerHeight), i);
  await p.waitForTimeout(1600);
  await p.screenshot({ path: `shots/act-${names[i]}.png` });
}
console.log('page errors:', errs.length ? errs.slice(0, 5) : 'none');
await b.close();
