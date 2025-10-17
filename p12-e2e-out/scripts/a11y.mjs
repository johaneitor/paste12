#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';
import axeSource from 'axe-core/axe.min.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BASE = process.env.BASE || process.argv[2] || 'https://paste12-rmsk.onrender.com';
const OUT = process.env.OUT_DIR || path.join(__dirname, '..', '..', 'p12-e2e-out');
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const runDir = path.join(OUT, stamp, 'a11y');
fs.mkdirSync(runDir, { recursive: true });

(async () => {
  const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox','--disable-dev-shm-usage'] });
  const page = await browser.newPage();
  const url = new URL('/', BASE).toString();
  await page.goto(url, { waitUntil: ['domcontentloaded','networkidle2'] });
  await page.addScriptTag({ content: axeSource });
  const results = await page.evaluate(async () => await axe.run(document, {
    runOnly: ['wcag2a','wcag2aa','wcag21aa']
  }));
  fs.writeFileSync(path.join(runDir, 'a11y.json'), JSON.stringify(results, null, 2));
  await browser.close();
  console.log(runDir);
})();
