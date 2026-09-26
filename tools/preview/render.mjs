// node tools/preview/render.mjs <dir-with-town.json> [view names...]
// Renders preview shots of the generated town with three.js in headless Chromium.
import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require('playwright'); } catch { playwright = require('/opt/node22/lib/node_modules/playwright'); }
const { chromium } = playwright;

const here = path.dirname(fileURLToPath(import.meta.url));
const dataDir = path.resolve(process.argv[2] || path.join(here, 'out'));
const only = process.argv.slice(3);
const shotsDir = path.join(dataDir, 'shots');
fs.mkdirSync(shotsDir, { recursive: true });
const viewsFile = process.env.VIEWS || path.join(here, 'views.json');
const views = JSON.parse(fs.readFileSync(viewsFile, 'utf8')).filter(v => only.length === 0 || only.includes(v.name));

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.route('http://preview.local/**', async (route) => {
  const url = new URL(route.request().url());
  const p = decodeURIComponent(url.pathname);
  const file = p.startsWith('/out/') ? path.join(dataDir, p.slice(5)) : path.join(here, p);
  if (!fs.existsSync(file)) return route.fulfill({ status: 404, body: 'not found' });
  const type = file.endsWith('.html') ? 'text/html' : file.endsWith('.js') ? 'application/javascript' : file.endsWith('.json') ? 'application/json' : 'application/octet-stream';
  await route.fulfill({ body: fs.readFileSync(file), contentType: type });
});
page.on('pageerror', (e) => console.log('[pageerror]', e.message));
page.on('console', (m) => { if (m.type() === 'error') console.log('[console]', m.text()); });
const t0 = Date.now();
await page.goto('http://preview.local/viewer.html');
const ready = await page.waitForFunction(() => window.PREVIEW_READY, null, { timeout: 300000 });
console.log('scene ready', JSON.stringify(await ready.jsonValue()), ((Date.now() - t0) / 1000).toFixed(1) + 's');
for (const view of views) {
  const t = Date.now();
  await page.evaluate((v) => window.renderView(v), view);
  await page.screenshot({ path: path.join(shotsDir, view.name + '.png') });
  console.log('rendered', view.name, ((Date.now() - t) / 1000).toFixed(1) + 's');
}
await browser.close();
