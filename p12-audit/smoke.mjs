import fs from 'node:fs/promises';
import path from 'node:path';
import puppeteer from 'puppeteer';

const BASE_URL = process.env.BASE_URL || process.argv[2] || 'https://paste12-rmsk.onrender.com';
const OUT_DIR = path.resolve('/workspace/p12-e2e-out');
await fs.mkdir(OUT_DIR, { recursive: true });

function nowTs(){ return new Date().toISOString(); }

const blockedMethods = new Set(['POST','PUT','PATCH','DELETE']);
const blockedPathRe = /\/api\//;

const result = {
  baseUrl: BASE_URL,
  ts: nowTs(),
  pages: {}
};

async function auditPage(browser, url, name){
  const page = await browser.newPage();
  const consoleMsgs = [];
  const errors = [];
  const network = [];
  await page.setRequestInterception(true);
  page.on('request', req => {
    const u = req.url();
    const m = req.method();
    if (blockedMethods.has(m) && blockedPathRe.test(u)) {
      return req.abort('blockedbyclient');
    }
    req.continue();
  });
  page.on('console', msg => {
    consoleMsgs.push({ type: msg.type(), text: msg.text() });
  });
  page.on('pageerror', err => { errors.push(String(err)); });
  page.on('requestfailed', req => {
    network.push({ type: 'fail', url: req.url(), method: req.method(), failure: req.failure()?.errorText || 'unknown' });
  });
  page.on('response', res => {
    const headers = res.headers();
    network.push({ type: 'resp', url: res.url(), status: res.status(), fromServiceWorker: res.fromServiceWorker(), ct: headers['content-type'] || '' });
  });

  const nav = { url, domContentLoadedMs: null, loadMs: null };
  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'networkidle2', timeout: 45000 }).catch(e => errors.push('goto_error:' + e.message));
  try {
    const perf = await page.evaluate(() => {
      const nav = performance.getEntriesByType('navigation')[0];
      if (nav) {
        return {
          dcl: nav.domContentLoadedEventEnd,
          load: nav.loadEventEnd,
          start: nav.startTime
        };
      }
      const t = performance.timing;
      return {
        dcl: t.domContentLoadedEventEnd - t.navigationStart,
        load: t.loadEventEnd - t.navigationStart,
        start: 0
      };
    });
    nav.domContentLoadedMs = Math.round(perf.dcl - perf.start);
    nav.loadMs = Math.round(perf.load - perf.start);
  } catch (e) {
    errors.push('perf_eval_error:' + e.message);
    nav.domContentLoadedMs = null;
    nav.loadMs = null;
  }

  // Basic DOM checks
  const dom = await page.evaluate(() => ({
    hasMain: !!document.querySelector('main'),
    hasHeader: !!document.querySelector('header'),
    hasFooter: !!document.querySelector('footer'),
    title: document.title || '',
    metas: Array.from(document.querySelectorAll('meta[name], meta[property]')).map(m => ({name: m.getAttribute('name') || m.getAttribute('property'), content: m.getAttribute('content')||''})),
    links: Array.from(document.querySelectorAll('link[rel]')).map(l => ({rel: l.rel, href: l.href})),
    scripts: Array.from(document.scripts).map(s => s.src || '[inline]')
  }));

  result.pages[name] = { url, nav, console: consoleMsgs, errors, network, dom };
  await page.close();
}

const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox','--disable-setuid-sandbox'] });
try {
  await auditPage(browser, BASE_URL + '/', 'home');
  await auditPage(browser, BASE_URL + '/notes', 'notes');
} finally {
  await browser.close();
}

await fs.writeFile(path.join(OUT_DIR, 'puppeteer-smoke.json'), JSON.stringify(result, null, 2));

// Also write concise text summaries
function summarize(){
  const lines = [];
  for (const [name, p] of Object.entries(result.pages)){
    lines.push(`# ${name} ${p.url}`);
    lines.push(`- DCL: ${p.nav.domContentLoadedMs} ms, Load: ${p.nav.loadMs} ms`);
    const errs = p.errors.length + p.console.filter(m => m.type === 'error').length;
    lines.push(`- Errors: ${errs}, Requests: ${p.network.filter(n=>n.type==='resp').length}, Failures: ${p.network.filter(n=>n.type==='fail').length}`);
  }
  return lines.join('\n');
}
await fs.writeFile(path.join(OUT_DIR, 'puppeteer-smoke.txt'), summarize() + '\n');
console.log('Smoke complete:', path.join(OUT_DIR, 'puppeteer-smoke.json'));
