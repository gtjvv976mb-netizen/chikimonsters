import { chromium } from 'playwright';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--disable-frame-rate-limit'] }).catch(() => chromium.launch());
const p = await b.newPage({ viewport: { width: 1280, height: 800 } });
p.on('pageerror', e => console.log('PAGEERROR', String(e)));
await p.addInitScript(() => {
  window.__mine = 0; window.__all = 0;
  const raf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (cb) => raf((t) => { window.__all++; return cb(t); });
  const tick = () => { window.__mine++; raf(tick); };   // reference: one chain, unwrapped
  raf(tick);
});
await p.goto('http://localhost:4321/', { waitUntil: 'load' });
await p.waitForTimeout(500);
console.log('webgl ok:', await p.evaluate(() => !!document.createElement('canvas').getContext('webgl2')));
console.log('scene-failed attr:', await p.evaluate(() => document.querySelector('[data-scene]')?.hasAttribute('data-scene-failed')));
await p.evaluate(() => { window.__mine = 0; window.__all = 0; });
await p.waitForTimeout(3000);
console.log('ON SCREEN  ', JSON.stringify(await p.evaluate(() => ({ refFrames: window.__mine, sceneCallbacks: window.__all }))));
await p.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
await p.waitForTimeout(1000);
await p.evaluate(() => { window.__mine = 0; window.__all = 0; });
await p.waitForTimeout(2000);
console.log('SCROLLED OFF', JSON.stringify(await p.evaluate(() => ({ refFrames: window.__mine, sceneCallbacks: window.__all }))));
await p.evaluate(() => window.scrollTo(0, 0));
await p.waitForTimeout(1000);
await p.evaluate(() => { window.__mine = 0; window.__all = 0; });
await p.waitForTimeout(2000);
console.log('BACK ON     ', JSON.stringify(await p.evaluate(() => ({ refFrames: window.__mine, sceneCallbacks: window.__all }))));
await b.close();
