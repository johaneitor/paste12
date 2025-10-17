#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BASE = process.env.BASE || process.argv[2] || 'https://paste12-rmsk.onrender.com';
const ROUTE = process.env.ROUTE || process.argv[3] || '/';

const outDir = process.env.OUT_DIR || path.join(__dirname, '..', '..', 'p12-e2e-out');
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const runDir = path.join(outDir, stamp, 'remote-smoke');
fs.mkdirSync(runDir, { recursive: true });

const navUrl = new URL(ROUTE, BASE).toString();

const result = {
  base: BASE,
  url: navUrl,
  startedAt: new Date().toISOString(),
  timings: {},
  console: [],
  pageErrors: [],
  requests: [],
  responses: [],
  failedRequests: [],
  mainResponseHeaders: null,
  status: 'UNKNOWN'
};

function save(file, data) {
  fs.writeFileSync(path.join(runDir, file), typeof data === 'string' ? data : JSON.stringify(data, null, 2));
}

(async () => {
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-dev-shm-usage']
  });
  try {
    const page = await browser.newPage();
    page.setDefaultNavigationTimeout(30000);

    page.on('console', msg => {
      const entry = {
        type: msg.type(),
        text: msg.text()
      };
      result.console.push(entry);
    });

    page.on('pageerror', err => {
      result.pageErrors.push({ message: String(err?.message || err), stack: String(err?.stack || '') });
    });

    page.on('requestfailed', req => {
      result.failedRequests.push({ url: req.url(), method: req.method(), failure: req.failure() });
    });

    page.on('response', async (res) => {
      const url = res.url();
      const headers = res.headers();
      const status = res.status();
      const req = res.request();
      const entry = { url, status, headers, method: req.method(), resourceType: req.resourceType() };
      result.responses.push(entry);
      if (url === navUrl) {
        result.mainResponseHeaders = headers;
      }
    });

    const start = Date.now();
    const resp = await page.goto(navUrl, { waitUntil: ['domcontentloaded', 'load', 'networkidle0'] });
    const end = Date.now();

    result.statusCode = resp?.status();

    // Performance timings
    const perfNav = await page.evaluate(() => {
      const nav = performance.getEntriesByType('navigation')[0];
      const t = performance.timing || {};
      return {
        type: nav?.entryType || 'navigation',
        startTime: nav?.startTime ?? 0,
        duration: nav?.duration ?? 0,
        domContentLoaded: nav?.domContentLoadedEventEnd ?? (t.domContentLoadedEventEnd - t.navigationStart),
        loadEventEnd: nav?.loadEventEnd ?? (t.loadEventEnd - t.navigationStart),
        transferSize: nav?.transferSize ?? 0,
        encodedBodySize: nav?.encodedBodySize ?? 0,
        decodedBodySize: nav?.decodedBodySize ?? 0
      };
    });
    result.timings = perfNav;
    result.elapsedMs = end - start;

    // Screenshot and HTML
    const html = await page.content();
    save('root.html', html);
    await page.screenshot({ path: path.join(runDir, 'screenshot.png'), fullPage: true });

    // Extract asset URLs
    const assets = await page.evaluate(() => {
      const links = Array.from(document.querySelectorAll('link[rel="stylesheet"]')).map(l => l.href);
      const scripts = Array.from(document.scripts).map(s => s.src).filter(Boolean);
      return { css: links, js: scripts };
    });
    result.assets = assets;

    result.status = 'OK';
  } catch (err) {
    result.status = 'ERROR';
    result.error = String(err?.stack || err);
  } finally {
    await browser.close();
    result.endedAt = new Date().toISOString();
    save('result.json', result);
    console.log(path.relative(process.cwd(), runDir));
  }
})();
