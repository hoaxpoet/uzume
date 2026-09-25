// ncase_capture.js — FF.0 artifact 1+2: run Nicky Case's *Fireflies* (CC0,
// github.com/ncase/fireflies @ 165d16c) headless and capture frames.
// rAF does not fire headless (tools/milkdrop-render/README.md), so the PIXI
// ticker is stopped and every firefly is stepped by hand in a setTimeout-free
// evaluate loop, one 30 fps tick (delta = 2 in PIXI's 60-based units) per frame.
//
//   python3 -m http.server 8765 -d <ncase checkout> &
//   NODE_PATH=<dir with playwright> node ncase_capture.js <out_dir> [seconds] [seed] [skip_s]
//   skip_s: simulate this many seconds before the first captured frame (SHOTS=0 → order.csv only).
//
// Writes f_00001.png… plus order.csv (t, R = |mean e^{2πi·clock}|, flashes).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  const out = process.argv[2];
  const secs = Number(process.argv[3] || 20);
  const seed = Number(process.argv[4] || 1);
  const skip = Number(process.argv[5] || 0);
  const shots = process.env.SHOTS !== '0';
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 600 } });
  // Seeded Math.random so the "random start" is reproducible.
  await page.addInitScript((s) => {
    let x = s >>> 0 || 1;
    Math.random = () => ((x = (x * 1664525 + 1013904223) >>> 0) / 4294967296);
  }, seed);
  await page.goto('http://localhost:8765/index.html');
  await page.waitForFunction(() => window.fireflies && window.fireflies.length > 0, null, { timeout: 30000 });
  await page.evaluate(() => {
    app.ticker.stop();
    FLY_SYNC = true;                       // "Nudge thy neighbor: ON", default pull/radius
    const w = document.querySelector('#words'); if (w) w.style.display = 'none';
    Howler && Howler.mute && Howler.mute(true);
  });
  const rows = ['t,R,flashes'];
  for (let i = -skip * 30; i < secs * 30; i++) {
    const stat = await page.evaluate(() => {
      const before = fireflies.map(f => f.clock);
      for (const f of fireflies) f.update(2);
      app.renderer.render(app.stage);
      let c = 0, s = 0, fl = 0;
      fireflies.forEach((f, k) => {
        c += Math.cos(2 * Math.PI * f.clock); s += Math.sin(2 * Math.PI * f.clock);
        if (f.clock < before[k]) fl++;
      });
      return [Math.hypot(c, s) / fireflies.length, fl];
    });
    rows.push(`${(i / 30).toFixed(3)},${stat[0].toFixed(4)},${stat[1]}`);
    if (i < 0 || !shots) continue;
    await page.locator('canvas').screenshot({ path: path.join(out, `f_${String(i + 1).padStart(5, '0')}.png`) });
  }
  fs.writeFileSync(path.join(out, 'order.csv'), rows.join('\n') + '\n');
  await browser.close();
})();
