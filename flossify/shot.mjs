import { chromium } from 'playwright';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' }).catch(() => chromium.launch());
const p = await b.newPage({ viewport: { width: 1280, height: 880 } });
const errs = [];
p.on('pageerror', e => errs.push(String(e)));
await p.goto('http://localhost:4321/', { waitUntil: 'networkidle' });
await p.waitForTimeout(1800);
const stops = [['1-hero',0],['2-product',900],['3-services',1900],['4-audiences',2950],['5-cta',4100]];
for (const [n,y] of stops) { await p.evaluate(y=>scrollTo(0,y), y); await p.waitForTimeout(900); await p.screenshot({path:`shots/${n}.png`}); }
// Check the tabs actually switch.
await p.evaluate(()=>scrollTo(0,900)); await p.waitForTimeout(500);
const tabs = await p.$$('[role="tab"]');
await tabs[2].click(); await p.waitForTimeout(800);
await p.screenshot({ path: 'shots/6-tab3.png' });
console.log('errors:', errs.length ? errs.slice(0,3) : 'none');
await b.close();
