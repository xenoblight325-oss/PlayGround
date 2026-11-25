#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_URL="${CAPTURE_URL:?Set CAPTURE_URL to the exact preview URL}"
CAPTURE_DIR="${CAPTURE_DIR:?Set CAPTURE_DIR to an evidence output directory}"
RUNTIME_DIR="${RUNTIME_DIR:-/home/runner/work/_temp/omgithub-runtime}"
PLAYWRIGHT_ROOT="$HOME/.local/share/omgithub-playwright"

/usr/bin/time -p mkdir -p "$CAPTURE_DIR"
/usr/bin/time -p test -f "$PLAYWRIGHT_ROOT/linux.json"
/usr/bin/time -p node - "$CAPTURE_URL" "$CAPTURE_DIR" "$PLAYWRIGHT_ROOT" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const [url, outputDir, playwrightRoot] = process.argv.slice(2);
const require = createRequire(path.join(playwrightRoot, 'package.json'));
const { chromium } = require('playwright');
const config = JSON.parse(fs.readFileSync(path.join(playwrightRoot, 'linux.json'), 'utf8'));
let browser;
let exitCode = 0;
const fail = (message, code = 1) => { console.error(message); exitCode = code; };
(async () => {
  try {
    try {
      browser = await chromium.launch({ ...config.browser.launchOptions, timeout: 30000 });
    } catch (error) {
      fail(`Browser infrastructure failure: ${error.message}`, 75);
      return;
    }
    for (const [name, width, height] of [['desktop', 1280, 900], ['mobile', 390, 844]]) {
      let page;
      try {
        page = await browser.newPage({ viewport: { width, height } });
        page.setDefaultTimeout(30000);
        const pageErrors = [];
        page.on('pageerror', error => pageErrors.push(error.message));
        let response;
        try {
          response = await page.goto(url, { waitUntil: 'load', timeout: 45000 });
        } catch (error) {
          fail(`Temporary navigation failure (${name}): ${error.message}`, 75);
          return;
        }
        if (!response) {
          fail(`Temporary navigation failure (${name}): no response`, 75);
          return;
        }
        if (response.status() >= 500) {
          fail(`Temporary preview response HTTP ${response.status()} (${name})`, 75);
          return;
        }
        if (!response.ok()) {
          fail(`Preview returned HTTP ${response.status()} (${name})`);
          return;
        }
        try {
          await page.locator('body').waitFor({ state: 'visible' });
          await page.waitForFunction(() => document.fonts.status === 'loaded');
          await page.waitForFunction(() => document.querySelectorAll('#board .sq').length === 64, null, { timeout: 15000 });
        } catch (error) {
          fail(`Rendered app defect (${name}): chess board did not become ready: ${error.message}`);
          return;
        }
        if (pageErrors.length) {
          fail(`Rendered app defect (${name}): ${pageErrors.join('; ')}`);
          return;
        }
        await page.waitForTimeout(500);
        await page.screenshot({ path: path.join(outputDir, `final-${name}.png`), timeout: 30000 });
        await page.close();
      } catch (error) {
        fail(`Capture script/rendering defect (${name}): ${error.stack || error.message}`);
        return;
      } finally {
        if (page && !page.isClosed()) await page.close().catch(() => {});
      }
    }
  } finally {
    if (browser) await browser.close().catch(error => fail(`Browser close failure: ${error.message}`, 75));
  }
})().then(() => { process.exitCode = exitCode; }).catch(error => { console.error(error.stack || error); process.exitCode = 1; });
NODE
