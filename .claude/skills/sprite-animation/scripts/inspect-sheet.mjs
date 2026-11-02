import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

// Kept browser-compatible so the same measurements can run on decoded Canvas pixels.
export function auditPixels(pixels, width, height, frames, alphaThreshold = 128) {
  if (pixels.length !== width * height * 4) throw new Error('Invalid RGBA dimensions');
  if (!Number.isInteger(alphaThreshold) || alphaThreshold < 0 || alphaThreshold > 254) {
    throw new Error('Alpha threshold must be an integer from 0 to 254');
  }
  let transparentPixels = 0, nonOpaquePixels = 0;
  for (let i = 3; i < pixels.length; i += 4) {
    if (pixels[i] === 0) transparentPixels++;
    if (pixels[i] < 255) nonOpaquePixels++;
  }
  const warnings = transparentPixels ? [] : ['No fully transparent pixels: verify the background is real alpha.'];
  const groups = new Map(), duplicates = [], measured = [];
  for (let index = 0; index < frames.length; index++) {
    const frame = frames[index], r = frame.rect;
    if (!r || ![r.x, r.y, r.w, r.h].every(Number.isInteger) || r.x < 0 || r.y < 0 ||
        r.w < 1 || r.h < 1 || r.x + r.w > width || r.y + r.h > height) {
      throw new Error('Invalid or out-of-bounds rectangle for frame ' + index);
    }
    if (frame.anchor && ![frame.anchor.x, frame.anchor.y].every(Number.isFinite)) {
      throw new Error('Invalid anchor for frame ' + index);
    }
    if (frame.durationMs !== undefined && (!Number.isFinite(frame.durationMs) || frame.durationMs <= 0)) {
      throw new Error('Frame duration must be positive for frame ' + index);
    }
    let left = r.w, top = r.h, right = -1, bottom = -1, opaquePixels = 0, hash = 2166136261;
    const bytes = new Uint8Array(r.w * r.h * 4);
    for (let y = 0; y < r.h; y++) for (let x = 0; x < r.w; x++) {
      const source = ((r.y + y) * width + r.x + x) * 4;
      const target = (y * r.w + x) * 4;
      for (let c = 0; c < 4; c++) {
        bytes[target + c] = pixels[source + c];
        hash = Math.imul(hash ^ bytes[target + c], 16777619) >>> 0;
      }
      if (pixels[source + 3] > alphaThreshold) {
        left = Math.min(left, x); right = Math.max(right, x);
        top = Math.min(top, y); bottom = Math.max(bottom, y); opaquePixels++;
      }
    }
    const id = String(frame.id ?? index), empty = bottom < 0;
    const edges = empty ? [] : [left === 0 && 'left', right === r.w - 1 && 'right',
      top === 0 && 'top', bottom === r.h - 1 && 'bottom'].filter(Boolean);
    if (empty) warnings.push('Frame ' + id + ' is blank at this alpha threshold.');
    if (edges.length) warnings.push('Frame ' + id + ' touches ' + edges.join(', ') + ': inspect possible clipping.');
    const key = r.w + ':' + r.h + ':' + hash, candidates = groups.get(key) ?? [];
    const match = candidates.find(item => item.bytes.every((value, i) => value === bytes[i]));
    if (match) {
      if (match.ids.length === 1) duplicates.push(match.ids);
      match.ids.push(id);
    } else candidates.push({ bytes, ids: [id] });
    groups.set(key, candidates);
    measured.push({ id, rect: r, anchor: frame.anchor ?? null, durationMs: frame.durationMs ?? null,
      alphaBounds: empty ? null : { left, top, right, bottom }, opaquePixels, touchesEdges: edges });
  }
  for (const group of duplicates) warnings.push('Exact duplicate frames: ' + group.join(', ') + '. Check whether this is an intended hold.');
  const bottoms = measured.filter(frame => frame.alphaBounds).map(frame => frame.alphaBounds.bottom);
  return { image: { width, height, transparentPixels, nonOpaquePixels }, alphaThreshold, frames: measured, duplicates,
    alphaBottomSpan: bottoms.length ? Math.max(...bottoms) - Math.min(...bottoms) : null, warnings };
}

function htmlReview(title, data, report) {
  const payload = JSON.stringify({ data, report }).replaceAll('<', '\\u003c');
  const escapedTitle = title.replace(/[&<>"']/g, value => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[value]));
  return `<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapedTitle} sprite review</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#202322;color:#edf0ec;font:14px system-ui,sans-serif}
main{max-width:1050px;margin:auto;padding:24px}h1{font-size:22px;margin:0 0 18px}h2{font-size:16px}
.controls{display:flex;flex-wrap:wrap;align-items:center;gap:16px;margin:18px 0}label{display:flex;align-items:center;gap:6px}
button,input,select{font:inherit}button{min-width:36px;min-height:32px;cursor:pointer}input[type=number]{width:70px}
input[type=range]{width:130px}img{display:block;width:100%;height:auto;background:#404642}
.players{display:grid;grid-template-columns:1fr 1fr;gap:18px}.stage{min-height:310px;padding:12px;display:flex;align-items:end;gap:16px;overflow:auto}
.dark{background:#343b37}.light{background:#d1d8d3}canvas{image-rendering:pixelated;flex-shrink:0}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}
ul{padding-left:20px;line-height:1.6}#frameName{min-width:170px}a{color:#cbd989}@media(max-width:650px){.players{grid-template-columns:1fr}main{padding:16px}}
</style>
<main><h1>${escapedTitle}</h1><img id="sheet" alt="Source sprite sheet">
<div class="controls">
<button id="play" title="Pause playback" aria-label="Pause playback">&#10074;&#10074;</button>
<button id="previous" title="Previous frame" aria-label="Previous frame">&#8592;</button>
<button id="next" title="Next frame" aria-label="Next frame">&#8594;</button>
<label>Frame <input id="frame" type="range" min="0" value="0"></label><span id="frameName"></span>
<label>FPS <input id="fps" type="number" min="1" max="60" value="8" title="Fallback for frames without a duration"></label>
<label>Logical height <input id="size" type="number" min="16" max="256" value="96"></label>
<label><input id="smoothing" type="checkbox">Smooth reduction</label>
</div>
<div class="players"><section><h2>Dark background</h2><div class="stage dark"><canvas id="nativeDark"></canvas><canvas id="largeDark"></canvas></div></section>
<section><h2>Light background</h2><div class="stage light"><canvas id="nativeLight"></canvas><canvas id="largeLight"></canvas></div></section></div>
<h2>Audit findings</h2><ul id="warnings"></ul><pre id="details"></pre></main>
<script>
(() => {
const payload=${payload},frames=payload.data.frames,report=payload.report,sheet=document.getElementById('sheet');
const image=new Image();let playing=true,index=0,last=0;
const canvases=['nativeDark','largeDark','nativeLight','largeLight'].map(id=>document.getElementById(id));
const frameSlider=document.getElementById('frame'),play=document.getElementById('play');
frameSlider.max=frames.length-1;sheet.src=payload.data.source;
document.getElementById('fps').disabled=frames.every(f=>f.durationMs);
const anchor=f=>f.anchor||{x:f.rect.w/2,y:f.rect.h};
const left=Math.max(0,...frames.map(f=>anchor(f).x)),right=Math.max(0,...frames.map(f=>f.rect.w-anchor(f).x));
const top=Math.max(0,...frames.map(f=>anchor(f).y)),bottom=Math.max(0,...frames.map(f=>f.rect.h-anchor(f).y));
const w=Math.ceil(left+right),h=Math.ceil(top+bottom);
for(const canvas of canvases){canvas.width=w;canvas.height=h;}
function render(){const f=frames[index],r=f.rect,a=anchor(f),size=Number(document.getElementById('size').value)||96;
for(const canvas of canvases){const ctx=canvas.getContext('2d');ctx.clearRect(0,0,w,h);ctx.drawImage(image,r.x,r.y,r.w,r.h,left-a.x,top-a.y,r.w,r.h);
const scale=canvas.id.startsWith('large')?3:1;canvas.style.height=(size*scale)+'px';canvas.style.width=(size*scale*w/h)+'px';
canvas.style.imageRendering=document.getElementById('smoothing').checked?'auto':'pixelated';}
frameSlider.value=index;document.getElementById('frameName').textContent=(index+1)+' / '+frames.length+' : '+f.id;
document.getElementById('details').textContent=JSON.stringify(report.frames[index],null,2);}
function setPlaying(value){playing=value;play.innerHTML=value?'&#10074;&#10074;':'&#9654;';play.title=value?'Pause playback':'Play animation';play.setAttribute('aria-label',play.title);last=0;}
play.onclick=()=>setPlaying(!playing);document.getElementById('previous').onclick=()=>{setPlaying(false);index=(index+frames.length-1)%frames.length;render();};
document.getElementById('next').onclick=()=>{setPlaying(false);index=(index+1)%frames.length;render();};
frameSlider.oninput=()=>{setPlaying(false);index=Number(frameSlider.value);render();};
document.getElementById('size').oninput=render;document.getElementById('smoothing').onchange=render;
function tick(time){const duration=frames[index].durationMs||1000/(Number(document.getElementById('fps').value)||8);
if(playing&&time-last>=duration){index=(index+1)%frames.length;last=time;render();}requestAnimationFrame(tick);}
for(const warning of report.warnings){const li=document.createElement('li');li.textContent=warning;document.getElementById('warnings').append(li);}
if(!frames.every(f=>f.anchor)){const li=document.createElement('li');li.textContent='Missing explicit anchors: playback aligns logical cell bottoms. Verify foot positions visually.';document.getElementById('warnings').append(li);}
image.onload=()=>{render();requestAnimationFrame(tick);};image.src=payload.data.source;
})();
</script></html>`;
}

async function run(args) {
  const imagePath = args.shift(), options = {};
  if (!imagePath || imagePath.startsWith('--')) throw new Error('Usage: inspect-sheet.mjs image.png --columns N --rows N [--frames frames.json] [--report file.json] [--preview file.html] [--module-root project] [--chrome executable] [--alpha 128]');
  const allowed = new Set(['columns', 'rows', 'frames', 'report', 'preview', 'module-root', 'chrome', 'alpha']);
  while (args.length) {
    const key = args.shift()?.replace(/^--/, '');
    if (!allowed.has(key) || !args.length) throw new Error('Invalid option: ' + key);
    options[key] = args.shift();
  }
  const require = createRequire(path.join(path.resolve(options['module-root'] ?? process.cwd()), 'package.json'));
  let browserPackage;
  try { browserPackage = require('playwright-core'); }
  catch { try { browserPackage = require('playwright'); } catch { throw new Error('No Playwright package found. Use --module-root for a project with playwright-core or playwright.'); } }
  let executablePath = options.chrome ?? process.env.SPRITE_BROWSER_EXECUTABLE;
  if (!executablePath) for (const candidate of ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome']) {
    try { await fs.access(candidate); executablePath = candidate; break; } catch {}
  }
  const source = 'data:image/png;base64,' + (await fs.readFile(imagePath)).toString('base64');
  const custom = options.frames ? JSON.parse(await fs.readFile(options.frames, 'utf8')) : null;
  const declared = custom ? (Array.isArray(custom) ? custom : custom.frames) : null;
  if (custom && (!Array.isArray(declared) || !declared.length)) throw new Error('Frame manifest must contain a nonempty frames array');
  const browser = await browserPackage.chromium.launch({ headless: true, ...(executablePath ? { executablePath } : {}) });
  try {
    const page = await browser.newPage();
    await page.addScriptTag({ content: 'window.auditPixels = ' + auditPixels.toString() + ';' });
    const result = await page.evaluate(async ({ source, declared, columns, rows, alpha }) => {
      const image = new Image(); image.src = source; await image.decode();
      const width = image.naturalWidth, height = image.naturalHeight;
      let frames = declared;
      if (!frames) {
        if (![columns, rows].every(value => Number.isInteger(value) && value > 0) || width % columns || height % rows) {
          throw new Error('Grid must use positive integers and divide the image exactly. Use an explicit frame manifest for irregular layouts.');
        }
        frames = Array.from({ length: columns * rows }, (_, i) => ({ id: String(i),
          rect: { x: (i % columns) * width / columns, y: Math.floor(i / columns) * height / rows, w: width / columns, h: height / rows } }));
      }
      const canvas = document.createElement('canvas'); canvas.width = width; canvas.height = height;
      const ctx = canvas.getContext('2d', { willReadFrequently: true }); ctx.drawImage(image, 0, 0);
      const pixels = ctx.getImageData(0, 0, width, height).data;
      return { report: window.auditPixels(pixels, width, height, frames, alpha), frames };
    }, { source, declared, columns: Number(options.columns), rows: Number(options.rows ?? 1), alpha: Number(options.alpha ?? 128) });
    if (options.report) await fs.writeFile(options.report, JSON.stringify(result.report, null, 2) + '\n');
    if (options.preview) await fs.writeFile(options.preview, htmlReview(path.basename(imagePath), { source, frames: result.frames }, result.report));
    process.stdout.write(JSON.stringify(result.report, null, 2) + '\n');
  } finally { await browser.close(); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  run(process.argv.slice(2)).catch(error => { process.stderr.write(error.message + '\n'); process.exitCode = 1; });
}
