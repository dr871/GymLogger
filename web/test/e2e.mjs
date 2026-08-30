// End-to-end tests for GymLogger, driven through a real mobile-sized Chromium.
// Covers the flow that matters: log a session, come back, and see last time's
// numbers and the suggested bump in the right place.
//
//   npm install playwright && npx playwright install chromium
//   node test/e2e.mjs
//
// Set PW_CHROMIUM to use a Chromium you already have.

import { chromium, devices } from 'playwright';
import http from 'http';
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve(new URL('..', import.meta.url).pathname);
const TYPES = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript',
  '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.json': 'application/json' };

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(ROOT, p);
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('nf'); }
  res.writeHead(200, { 'content-type': TYPES[path.extname(f)] || 'application/octet-stream' });
  res.end(fs.readFileSync(f));
});
await new Promise(r => server.listen(8099, r));

const launchOpts = process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {};
const browser = await chromium.launch(launchOpts);
const ctx = await browser.newContext({ ...devices['iPhone 12'] });
const page = await ctx.newPage();

const errors = [];
page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
page.on('console', m => { if (m.type() === 'error') errors.push('CONSOLE: ' + m.text()); });

const SHOTS = path.join(ROOT, 'test', 'screenshots');
fs.mkdirSync(SHOTS, { recursive: true });
const shot = (n) => page.screenshot({ path: path.join(SHOTS, `shot-${n}.png`), fullPage: true });
const T = async (name, fn) => { try { await fn(); console.log('PASS  ' + name); } catch (e) { console.log('FAIL  ' + name + ' :: ' + e.message); process.exitCode = 1; } };

await page.goto('http://localhost:8099/index.html');
await page.waitForTimeout(500);

await T('seeded home shows Full Body', async () => {
  const t = await page.textContent('.big-title');
  if (!t.includes('Full Body')) throw new Error('got ' + t);
});
await shot('01-home');

await T('start session lists 6 exercises', async () => {
  await page.click('[data-act="start"]');
  await page.waitForTimeout(300);
  const n = await page.locator('.card').count();
  if (n !== 6) throw new Error('cards=' + n);
  const names = await page.locator('.ex-name').allTextContents();
  const want = ['Leg press','Chest press','Lat pulldown','Seated cable row','Leg curl','Plank'];
  if (JSON.stringify(names) !== JSON.stringify(want)) throw new Error(names.join(','));
});

await T('leg press rest is 120s, others 90s', async () => {
  const metas = await page.locator('.ex-meta').allTextContents();
  if (!metas[0].includes('120s')) throw new Error(metas[0]);
  if (!metas[1].includes('90s')) throw new Error(metas[1]);
  if (!metas[5].includes('3 × 40')) throw new Error('plank: ' + metas[5]);
});

await T('first session has empty weights, reps prefilled to target', async () => {
  const w = await page.locator('.card').first().locator('.field').first().inputValue();
  const r = await page.locator('.card').first().locator('.field').nth(1).inputValue();
  if (w !== '') throw new Error('weight=' + w);
  if (r !== '12') throw new Error('reps=' + r);
});

await T('note typed during the exercise saves', async () => {
  await page.locator('.card').first().locator('.note').fill('seat 4, handles 2');
  await page.waitForTimeout(300);
});

await T('log session 1 and tick every set', async () => {
  const weights = ['60','40','35','40','30',''];
  for (let c = 0; c < 6; c++) {
    const card = page.locator('.card').nth(c);
    for (let s = 0; s < 3; s++) {
      const row = card.locator('.set').nth(s);
      if (weights[c]) await row.locator('.field').first().fill(weights[c]);
      await row.locator('.tick').click();
      await page.waitForTimeout(60);
    }
  }
  const badges = await page.locator('.badge').allTextContents();
  if (badges.some(b => b !== '3/3')) throw new Error(badges.join(','));
});

await T('rest timer bar is running', async () => {
  if (await page.locator('#timerbar').isHidden()) throw new Error('timer hidden');
  const t = await page.textContent('#timer-time');
  if (!/^\d:\d\d$/.test(t)) throw new Error('time=' + t);
});
await T('filled note stays visible on a collapsed card', async () => {
  const card = page.locator('.card').first();
  if (!(await card.evaluate(el => el.classList.contains('complete')))) throw new Error('card not collapsed');
  if (await card.locator('.note').isHidden()) throw new Error('note hidden on collapsed card');
  if (await card.locator('.sets').isVisible()) throw new Error('sets should collapse');
});

await T('empty note collapses away on a completed card', async () => {
  const card = page.locator('.card').nth(1);
  if (await card.locator('.note').isVisible()) throw new Error('empty note still shown');
});
await shot('02-session-1');

await T('finish session returns home with history', async () => {
  await page.click('[data-act="finish"]');
  await page.waitForTimeout(300);
  const rows = await page.locator('.row').count();
  if (rows < 1) throw new Error('no history row');
  const sub = await page.textContent('.row-sub');
  if (!sub.includes('18 sets')) throw new Error(sub);
});

// ---- second session: the whole point of the app ----
await T('session 2 shows last session as target', async () => {
  await page.click('[data-act="start"]');
  await page.waitForTimeout(300);
  const lasts = await page.locator('.card').first().locator('.last').allTextContents();
  if (lasts[0] !== '60kg × 12') throw new Error('last col: ' + lasts[0]);
});

await T('session 2 prefills the +2.5 suggestion', async () => {
  const w = await page.locator('.card').first().locator('.field').first().inputValue();
  if (w !== '62.5') throw new Error('prefill=' + w);
  const s = await page.locator('.card').first().locator('.suggest').textContent();
  if (!s.includes('62.5')) throw new Error('banner: ' + s);
});

await T('note persists into session 2', async () => {
  const n = await page.locator('.card').first().locator('.note').inputValue();
  if (n !== 'seat 4, handles 2') throw new Error('note=' + n);
});

await T('plank got no weight suggestion (bodyweight)', async () => {
  const card = page.locator('.card').nth(5);
  const w = await card.locator('.field').first().inputValue();
  if (w !== '') throw new Error('plank weight prefilled: ' + w);
  if (await card.locator('.suggest').count() !== 0) throw new Error('plank got a weight suggestion');
});
await shot('03-session-2-targets');

await T('ignoring the suggestion falls back to last weight', async () => {
  await page.locator('.card').first().locator('[data-act="ignore-suggest"]').click();
  await page.waitForTimeout(200);
  const w = await page.locator('.card').first().locator('.field').first().inputValue();
  if (w !== '60') throw new Error('after ignore=' + w);
});

await T('log session 2 heavier and finish', async () => {
  const weights = ['65','42.5','37.5','42.5','32.5',''];
  for (let c = 0; c < 6; c++) {
    const card = page.locator('.card').nth(c);
    for (let s = 0; s < 3; s++) {
      const row = card.locator('.set').nth(s);
      if (weights[c]) await row.locator('.field').first().fill(weights[c]);
      await row.locator('.tick').click();
      await page.waitForTimeout(50);
    }
  }
  await page.click('[data-act="finish"]');
  await page.waitForTimeout(300);
});

await T('progress chart plots two points', async () => {
  await page.click('[data-tab="progress"]');
  await page.waitForTimeout(300);
  const dots = await page.locator('.chart .dot').count();
  if (dots !== 2) throw new Error('dots=' + dots);
  const title = await page.textContent('.chart-title');
  if (!title.includes('kg')) throw new Error(title);
});
await shot('04-progress');

await T('plank chart falls back to reps', async () => {
  await page.locator('.chips .chip', { hasText: 'Plank' }).click();
  await page.waitForTimeout(300);
  const title = await page.textContent('.chart-title');
  if (!title.includes('reps')) throw new Error('plank title: ' + title);
});

await T('history detail opens', async () => {
  await page.click('[data-tab="history"]');
  await page.waitForTimeout(250);
  await page.locator('.row').first().click();
  await page.waitForTimeout(250);
  const cards = await page.locator('.card').count();
  if (cards !== 6) throw new Error('cards=' + cards);
});
await shot('05-history-detail');

await T('template editor reorders exercises', async () => {
  await page.click('[data-tab="settings"]');
  await page.waitForTimeout(250);
  await page.locator('.row').first().click();
  await page.waitForTimeout(250);
  const before = await page.locator('.ex-name').allTextContents();
  await page.locator('[data-act="move-down"]').first().click();
  await page.waitForTimeout(250);
  const after = await page.locator('.ex-name').allTextContents();
  if (after[0] !== before[1] || after[1] !== before[0]) throw new Error(after.join(','));
});
await shot('06-template-editor');

await T('export produces valid JSON with 2 sessions', async () => {
  await page.click('[data-tab="settings"]');
  await page.waitForTimeout(250);
  const dl = page.waitForEvent('download');
  await page.click('[data-act="export"]');
  const d = await dl;
  const p = await d.path();
  const j = JSON.parse(fs.readFileSync(p, 'utf8'));
  if (j.sessions.length !== 2) throw new Error('sessions=' + j.sessions.length);
  if (!/^gymlogger-\d{4}-\d{2}-\d{2}\.json$/.test(d.suggestedFilename())) throw new Error(d.suggestedFilename());
});

await T('data survives a reload', async () => {
  await page.goto('http://localhost:8099/index.html');
  await page.waitForTimeout(400);
  await page.click('[data-tab="history"]');
  await page.waitForTimeout(250);
  const n = await page.locator('.row').count();
  if (n !== 2) throw new Error('rows after reload=' + n);
});

await T('service worker registers', async () => {
  const ok = await page.evaluate(() => navigator.serviceWorker.getRegistration().then(r => !!r));
  if (!ok) throw new Error('no SW registration');
});

await T('all tap targets are >= 44px', async () => {
  const bad = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('button, input').forEach(el => {
      const r = el.getBoundingClientRect();
      if (r.height > 0 && r.height < 44) out.push(el.className + ':' + Math.round(r.height));
    });
    return out;
  });
  if (bad.length) throw new Error(bad.join(' | '));
});

await T('no horizontal page scroll', async () => {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  if (over > 0) throw new Error('overflow ' + over + 'px');
});

const secs = (t) => { const [m, s] = t.split(':').map(Number); return m * 60 + s; };

await T('rest timer keeps counting across a reload', async () => {
  await page.click('[data-tab="home"]');
  await page.waitForTimeout(250);
  await page.click('[data-act="start"]');
  await page.waitForTimeout(300);
  // Locate by name: an earlier test reordered the template.
  const legPress = page.locator('.card').filter({ hasText: 'Leg press' }).first();
  await legPress.locator('.tick').first().click();
  await page.waitForTimeout(200);
  const before = secs(await page.textContent('#timer-time'));
  if (before < 115 || before > 120) throw new Error('leg press rest should start near 120s, got ' + before);
  await page.waitForTimeout(3000);
  await page.reload();
  await page.waitForTimeout(700);
  if (await page.locator('#timerbar').isHidden()) throw new Error('timer gone after reload');
  const after = secs(await page.textContent('#timer-time'));
  if (before - after < 2) throw new Error(`clock did not advance: ${before} -> ${after}`);
  if (before - after > 9) throw new Error(`clock advanced too far: ${before} -> ${after}`);
});

await T('rest time edited mid-session applies to the next set', async () => {
  const legPress = page.locator('.card').filter({ hasText: 'Leg press' }).first();
  await legPress.locator('.card-title').click();
  await page.waitForTimeout(300);
  await page.locator('[data-field="restSec"]').fill('3');
  await page.waitForTimeout(300);
  await page.click('.back');
  await page.waitForTimeout(300);
  const meta = await page.locator('.card').filter({ hasText: 'Leg press' }).first().locator('.ex-meta').textContent();
  if (!meta.includes('rest 3s')) throw new Error('meta still says: ' + meta);
});

await T('timer fires and reads done once it expires', async () => {
  const legPress = page.locator('.card').filter({ hasText: 'Leg press' }).first();
  await legPress.locator('.tick').nth(1).click();
  await page.waitForTimeout(200);
  if (secs(await page.textContent('#timer-time')) > 3) throw new Error('did not pick up the 3s rest');
  await page.waitForTimeout(3400);
  const t = await page.textContent('#timer-time');
  if (t !== 'Rest done') throw new Error('shows ' + t);
});

await T('an expired timer still reads done after a restart', async () => {
  await page.reload();
  await page.waitForTimeout(700);
  const t = await page.textContent('#timer-time');
  if (t !== 'Rest done') throw new Error('after reload shows ' + t);
});

await T('cancelling the timer hides the bar', async () => {
  await page.click('[data-act="timer-cancel"]');
  await page.waitForTimeout(250);
  if (await page.locator('#timerbar').isVisible()) throw new Error('bar still visible');
});

await T('un-ticking a set is possible (mis-tap recovery)', async () => {
  const first = page.locator('.card').filter({ hasText: 'Leg press' }).first().locator('.set').first();
  if (!(await first.evaluate(el => el.classList.contains('done')))) throw new Error('set not done');
  await first.locator('.tick').click();
  await page.waitForTimeout(200);
  if (await page.locator('.card').filter({ hasText: 'Leg press' }).first().locator('.set').first()
        .evaluate(el => el.classList.contains('done'))) throw new Error('still done');
});
await shot('07-session-tick-affordance');

await T('discarding cleans up', async () => {
  page.once('dialog', d => d.accept());
  await page.click('[data-act="discard"]');
  await page.waitForTimeout(400);
  const n = await page.evaluate(() => JSON.parse(localStorage.getItem('gymlogger.v1')).sessions.length);
  if (n !== 2) throw new Error('sessions=' + n);
});

await T('works fully offline once installed', async () => {
  // Give the SW a beat to finish caching the shell, then kill the network.
  await page.waitForTimeout(800);
  await ctx.setOffline(true);
  await page.goto('http://localhost:8099/index.html');
  await page.waitForTimeout(800);
  const title = await page.textContent('.big-title');
  if (!title.includes('Full Body')) throw new Error('offline home shows: ' + title);
  await page.click('[data-tab="history"]');
  await page.waitForTimeout(300);
  const n = await page.locator('.row').count();
  if (n !== 2) throw new Error('offline history rows=' + n);
  const styled = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  if (styled === 'rgba(0, 0, 0, 0)') throw new Error('stylesheet did not load offline');
  await ctx.setOffline(false);
});
await shot('08-offline');

await T('last-session column is never truncated', async () => {
  await page.goto('http://localhost:8099/index.html#/home');
  await page.waitForTimeout(500);
  await page.click('[data-act="start"]');
  await page.waitForTimeout(400);
  const clipped = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('.last').forEach(el => {
      if (el.scrollWidth > el.clientWidth + 1) out.push(el.textContent.trim());
    });
    return out;
  });
  if (clipped.length) throw new Error('clipped: ' + clipped.join(' | '));
  page.once('dialog', d => d.accept());
  await page.click('[data-act="discard"]');
  await page.waitForTimeout(400);
});
await shot('09-final-session');

const real = errors.filter((e) => !e.includes('navigator.vibrate'));
if (real.length) { console.log('\nJS ERRORS:\n' + real.join('\n')); process.exitCode = 1; }
else console.log('\nno JS errors');

await browser.close();
server.close();
