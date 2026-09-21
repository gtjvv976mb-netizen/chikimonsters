import { chromium } from 'playwright';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'] }).catch(() => chromium.launch());
const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
const p = await ctx.newPage();
await p.addInitScript(() => {
  window.__all = 0; window.__mine = 0;
  const raf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (cb) => raf((t) => { window.__all++; return cb(t); });
  const tick = () => { window.__mine++; raf(tick); }; raf(tick);
});
await p.goto('http://localhost:4321/', { waitUntil: 'load' });
// settle into the single-chain state: scroll off and back
await p.evaluate(() => window.scrollTo(0, document.body.scrollHeight)); await p.waitForTimeout(800);
await p.evaluate(() => window.scrollTo(0, 0)); await p.waitForTimeout(800);
const measure = async (label) => {
  await p.evaluate(() => { window.__all = 0; window.__mine = 0; });
  await p.waitForTimeout(2000);
  const r = await p.evaluate(() => ({ frames: window.__mine, sceneCbs: window.__all }));
  console.log(label, JSON.stringify(r), 'chains≈', (r.sceneCbs / Math.max(r.frames,1)).toFixed(2));
};
await measure('baseline      ');
const other = await ctx.newPage();
await other.goto('about:blank');
for (let i = 1; i <= 3; i++) {
  await other.bringToFront(); await p.waitForTimeout(700);
  console.log('  hidden state seen by page:', await p.evaluate(() => document.visibilityState).catch(()=>'?'));
  await p.bringToFront(); await p.waitForTimeout(700);
  await measure(`after ${i} hide/show`);
}
await b.close();
