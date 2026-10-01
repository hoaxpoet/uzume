// Milkdrop reference harness — deterministic frame SEQUENCE for motion gating (UND.0).
//
// render-gif.js plays the clip in real time and lets butterchurn time itself, so the
// frame rate (and every per-frame spring in a preset) depends on how fast headless
// Chrome happens to run. This script instead injects the audio window and the frame
// time on every call — `render({ audioLevels, elapsedTime })` — so frame i is exactly
// t = i / FPS of the clip at exactly FPS, every run. That makes the output comparable
// frame-for-frame with an Uzume render of the same audio.
//
// Usage: node render-sequence.js <out_dir> <preset.json> <audio> [start_s] [secs] [fps]
// Writes <out_dir>/seq_00000.png … (640×480). Gain 2.0 matches render-gif.js.
// LOG_VARS=a,b,… also writes <out_dir>/vars.csv: those frame-equation variables per frame
// (e.g. bass,treb,bb,tt,q16,y1,y2,ww — the spring state a port is fitted against).
// NO_FRAMES=1 skips the PNGs (log only).
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const puppeteer = require('puppeteer');

const W = 640, H = 480, RATE = 44100, N = 1024, GAIN = 2.0;

(async () => {
  const [outDir, presetPath, audioPath, startS = '8', secs = '12', fpsArg = '60'] = process.argv.slice(2);
  const fps = Number(fpsArg), frames = Math.round(Number(secs) * fps);
  fs.mkdirSync(outDir, { recursive: true });

  // Mono float PCM of the window (plus N samples of lead-in for the first frame's buffer).
  const lead = N / RATE;
  const pcm = execFileSync('ffmpeg', ['-v', 'error', '-ss', String(Math.max(0, Number(startS) - lead)),
    '-t', String(Number(secs) + lead), '-i', audioPath, '-ac', '1', '-ar', String(RATE), '-f', 'f32le', '-'],
    { maxBuffer: 1 << 28 });
  const samples = new Float32Array(pcm.buffer, pcm.byteOffset, pcm.length / 4);

  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
      '--ignore-gpu-blocklist', '--enable-webgl', `--window-size=${W},${H}`],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: W, height: H });
  page.on('pageerror', (e) => console.log('  [page error]', e.message));
  await page.setContent(`<!doctype html><html><body style="margin:0"><canvas id="c" width="${W}" height="${H}"></canvas></body></html>`);
  await page.addScriptTag({ path: path.join(__dirname, 'node_modules/butterchurn/lib/butterchurn.min.js') });
  const preset = JSON.parse(fs.readFileSync(presetPath, 'utf8'));
  const ok = await page.evaluate((w, h, rate, p) => {
    const BC = window.butterchurn.default || window.butterchurn;
    const ac = new AudioContext({ sampleRate: rate });
    window.__viz = BC.createVisualizer(ac, document.getElementById('c'), { width: w, height: h, pixelRatio: 1 });
    window.__viz.loadPreset(p.preset || p, 0.0);
    return 'ok';
  }, W, H, RATE, preset);
  if (ok !== 'ok') { console.log(ok); process.exit(1); }

  const logVars = (process.env.LOG_VARS || '').split(',').filter(Boolean);
  const log = logVars.length ? [['frame', 't', ...logVars].join(',')] : null;
  for (let i = 0; i < frames; i++) {
    const end = N + Math.round((i / fps) * RATE);
    const bytes = new Array(N);
    for (let k = 0; k < N; k++) {
      const s = Math.max(-1, Math.min(1, (samples[end - N + k] || 0) * GAIN));
      bytes[k] = Math.max(0, Math.min(255, Math.round(128 + s * 127)));
    }
    const [url, vars] = await page.evaluate((b, dt, names, wantPNG) => {
      const a = Uint8Array.from(b);
      window.__viz.render({ audioLevels: { timeByteArray: a, timeByteArrayL: a, timeByteArrayR: a }, elapsedTime: dt });
      const f = window.__viz.renderer.presetEquationRunner.mdVSFrame || {};
      return [wantPNG ? document.getElementById('c').toDataURL('image/png') : null, names.map((n) => f[n])];
    }, bytes, 1 / fps, logVars, !process.env.NO_FRAMES);
    if (log) log.push([i, (Number(startS) + i / fps).toFixed(4), ...vars].join(','));
    if (url) fs.writeFileSync(path.join(outDir, `seq_${String(i).padStart(5, '0')}.png`), Buffer.from(url.split(',')[1], 'base64'));
  }
  if (log) fs.writeFileSync(path.join(outDir, 'vars.csv'), log.join('\n') + '\n');
  console.log(`wrote ${frames} frames to ${outDir}`);
  await browser.close();
})();
