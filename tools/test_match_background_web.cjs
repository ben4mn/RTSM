'use strict';
// Executes the exact JS shipped inside the GDScript lifecycle helper. The
// optional browser witness checks real tab visibility, not a forged property.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const os = require('node:os');
const {spawn, spawnSync} = require('node:child_process');
const sourcePath = path.resolve(__dirname, '../scripts/main/match_background_guard.gd');
const source = fs.readFileSync(sourcePath, 'utf8');
const script = /const WEB_LIFECYCLE_SOURCE: String = """\r?\n([\s\S]*?)"""/.exec(source)?.[1];
assert(script, 'Production lifecycle source must be present');

class Target {
  listeners = new Map();
  addEventListener(type, callback) { if (!this.listeners.has(type)) this.listeners.set(type, new Set()); this.listeners.get(type).add(callback); }
  removeEventListener(type, callback) { this.listeners.get(type)?.delete(callback); }
  emit(type) { for (const callback of this.listeners.get(type) || []) callback(); }
}

function unitChecks() {
  const window = new Target(), document = new Target();
  window.visualViewport = new Target();
  document.visibilityState = 'visible';
  let prompt = null;
  document.getElementById = id => id === 'pocket-landscape-prompt' ? prompt : null;
  const context = vm.createContext({window, document, getComputedStyle: element => ({visibility: element.visibility})}); vm.runInContext(script, context);
  const first = [], old = window.PocketMatchLifecycle.create(hidden => first.push(hidden));
  assert.deepEqual(first, [false]);
  window.emit('blur'); document.emit('blur'); window.emit('focus');
  assert.deepEqual(first, [false], 'Focus listeners must not background the match');
  document.visibilityState = 'hidden'; document.emit('visibilitychange');
  assert.deepEqual(first, [false, true]);
  vm.runInContext(script, context); // A restarted Main can overlap its old guard.
  const second = [], current = window.PocketMatchLifecycle.create(hidden => second.push(hidden));
  assert.deepEqual(second, [true], 'New binding must report initial hidden state');
  old.detach();
  document.visibilityState = 'visible'; document.emit('visibilitychange');
  assert.deepEqual(first, [false, true], 'Detached old scene received visibility');
  assert.deepEqual(second, [true, false], 'Old cleanup removed the new scene binding');
  window.emit('pagehide'); window.emit('pageshow');
  assert.deepEqual(second, [true, false, true, false]);
  prompt = {getClientRects: () => [], visibility: 'visible'};
  window.emit('resize'); assert.equal(second.at(-1), false, 'display:none prompt does not interrupt');
  prompt = {getClientRects: () => [{}], visibility: 'hidden'};
  window.visualViewport.emit('resize'); assert.equal(second.at(-1), false, 'visibility:hidden prompt does not interrupt');
  prompt.visibility = 'visible';
  window.emit('resize'); assert.equal(second.at(-1), true, 'Window resize reports the visible blocker');
  document.visibilityState = 'hidden'; prompt = null;
  window.visualViewport.emit('resize'); assert.equal(second.at(-1), true, 'Removing portrait blocker cannot override a hidden document');
  document.visibilityState = 'visible'; prompt = {getClientRects: () => [{}], visibility: 'visible'};
  document.emit('visibilitychange'); assert.equal(second.at(-1), true, 'Foreground remains interrupted while portrait is blocked');
  prompt = null; window.visualViewport.emit('resize'); assert.equal(second.at(-1), false, 'Viewport resize reports available landscape');
  const beforeDetach = second.slice();
  current.detach(); document.emit('visibilitychange'); window.emit('pagehide'); window.emit('pageshow'); window.emit('resize'); window.visualViewport.emit('resize');
  assert.deepEqual(second, beforeDetach, 'Detached binding received a lifecycle or either resize event');
  assert.equal([...window.listeners.values(), ...document.listeners.values(), ...window.visualViewport.listeners.values()].reduce((n, callbacks) => n + callbacks.size, 0), 0);
  window.visualViewport = null;
  const withoutViewport = window.PocketMatchLifecycle.create(() => {}); withoutViewport.detach();
  return {passed: true, scope: 'Exact production listener; initial hidden, ignored blur, pagehide/pageshow, absent/display-none/visibility-hidden prompt, document/portrait union, both resize listeners, restart and detach ownership, absent visualViewport'};
}

async function browserChecks() {
  const moduleArg = process.argv.indexOf('--playwright-module');
  const modulePath = moduleArg >= 0 ? process.argv[moduleArg + 1] : 'playwright';
  const {chromium} = require(modulePath);
  // Playwright normally forces every page to appear focused/visible, even in
  // headed Chrome. A private external browser + noDefaults preserves Chrome's
  // actual tab visibility. Headless works without touching desktop focus.
  const chromeIndex = process.argv.indexOf('--chrome');
  const chrome = chromeIndex >= 0 ? process.argv[chromeIndex + 1] : path.join(process.env.PROGRAMFILES || '', 'Google/Chrome/Application/chrome.exe');
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'pocket-visibility-'));
  const args = ['--remote-debugging-port=0', '--remote-debugging-address=127.0.0.1', '--user-data-dir=' + profile, '--no-first-run', '--no-default-browser-check', '--disable-background-networking', 'about:blank'];
  if (!process.argv.includes('--headed')) args.unshift('--headless=new');
  const child = spawn(chrome, args, {windowsHide: true, stdio: 'ignore'});
  let launchError, browser;
  child.once('error', error => { launchError = error; });
  try {
    const portFile = path.join(profile, 'DevToolsActivePort');
    let port;
    for (let attempt = 0; !port; attempt++) {
      if (launchError) throw launchError;
      if (child.exitCode !== null || attempt >= 100) throw new Error('Private Chrome did not start');
      try {
        const candidate = Number(fs.readFileSync(portFile, 'utf8').split(/\r?\n/)[0]);
        if (Number.isInteger(candidate) && candidate > 0) port = candidate;
      } catch (error) { if (!['ENOENT', 'EBUSY'].includes(error.code)) throw error; }
      if (port) break;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert(Number.isInteger(port) && port > 0);
    browser = await chromium.connectOverCDP('http://127.0.0.1:' + port, {noDefaults: true});
    const context = browser.contexts()[0];
    const page = await context.newPage();
    await page.setViewportSize({width: 932, height: 430});
    await page.setContent('<title>Lifecycle regression</title><input id="first"><button id="second">Another control</button>');
    await page.evaluate(script);
    await page.evaluate(() => { window.events = []; window.binding = window.PocketMatchLifecycle.create(hidden => window.events.push({hidden, visibility: document.visibilityState})); });
    assert.equal(await page.evaluate(() => document.visibilityState), 'visible');
    // Window and visualViewport may both report the initial real resize.
    await page.waitForTimeout(150);
    const beforeFocus = await page.evaluate(() => window.events);
    assert(beforeFocus.every(event => event.hidden === false));
    await page.locator('#first').focus(); await page.locator('#second').focus();
    assert.deepEqual(await page.evaluate(() => window.events), beforeFocus, 'Actual DOM focus changed match visibility');
    const other = await context.newPage();
    await other.setContent('<title>Second private test tab</title>');
    await other.bringToFront();
    await page.waitForFunction(() => document.visibilityState === 'hidden', null, {timeout: 4000, polling: 100});
    assert.equal(await page.evaluate(() => window.events.at(-1).hidden), true);
    await page.bringToFront();
    await page.waitForFunction(() => document.visibilityState === 'visible', null, {timeout: 4000, polling: 100});
    assert.deepEqual(await page.evaluate(() => window.events.map(event => event.hidden).filter((value, index, all) => index === 0 || value !== all[index - 1])), [false, true, false]);
    await page.evaluate(() => {
      const style = document.createElement('style');
      style.textContent = '#pocket-landscape-prompt { display: none; position: fixed; inset: 0; } @media (orientation: portrait) { #pocket-landscape-prompt { display: block; } }';
      document.head.appendChild(style);
      const prompt = document.createElement('div'); prompt.id = 'pocket-landscape-prompt'; prompt.textContent = 'Rotate to landscape'; document.body.appendChild(prompt);
    });
    await page.setViewportSize({width: 390, height: 844});
    await page.waitForFunction(() => document.getElementById('pocket-landscape-prompt').getClientRects().length > 0 && window.events.at(-1).hidden, null, {polling: 100});
    const portrait = await page.evaluate(() => ({visibility: document.visibilityState, blocked: window.events.at(-1).hidden}));
    assert.deepEqual(portrait, {visibility: 'visible', blocked: true});
    await other.bringToFront();
    await page.waitForFunction(() => document.visibilityState === 'hidden', null, {polling:100});
    await page.setViewportSize({width: 932, height: 430});
    await page.waitForFunction(() => document.getElementById('pocket-landscape-prompt').getClientRects().length === 0, null, {polling:100});
    assert.equal(await page.evaluate(() => window.events.at(-1).hidden), true, 'Landscape resize incorrectly clears real tab background');
    await page.bringToFront();
    await page.waitForFunction(() => document.visibilityState === 'visible' && !window.events.at(-1).hidden, null, {polling:100});
    const events = await page.evaluate(() => window.events);
    await page.evaluate(() => window.binding.detach());
    await page.setViewportSize({width: 390, height: 844});
    await other.bringToFront();
    await page.waitForFunction(() => document.visibilityState === 'hidden', null, {timeout: 4000, polling: 100});
    assert.deepEqual(await page.evaluate(() => window.events), events);
    return {passed: true, scope: 'Real Chrome tab hide/show, DOM focus, actual CSS portrait blocker via viewport resize, hidden+portrait union and detached resize/visibility using exact listener; no game exported or mutated; no focus emulation', headless: !process.argv.includes('--headed'), browser: await browser.version(), portrait, events};
  } finally {
    if (browser) {
      try { const session = await browser.newBrowserCDPSession(); await session.send('Browser.close'); } catch (_) { /* The close response can race browser exit. */ }
      await browser.close();
    }
    for (let attempt = 0; child.exitCode === null && !launchError && attempt < 30; attempt++) await new Promise(resolve => setTimeout(resolve, 100));
    if (child.exitCode === null && !launchError) {
      if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], {windowsHide: true, timeout: 10000});
      else child.kill('SIGKILL');
    }
    const resolved = path.resolve(profile), expectedParent = path.resolve(os.tmpdir());
    assert(path.dirname(resolved) === expectedParent && path.basename(resolved).startsWith('pocket-visibility-'));
    fs.rmSync(resolved, {recursive: true, force: true, maxRetries: 5, retryDelay: 100});
  }
}

(async () => {
  const receipt = {source: sourcePath, source_sha256: crypto.createHash('sha256').update(source).digest('hex'), unit: unitChecks()};
  if (process.argv.includes('--browser')) receipt.browser = await browserChecks();
  const outputIndex = process.argv.indexOf('--output');
  if (outputIndex >= 0) fs.writeFileSync(process.argv[outputIndex + 1], JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx'});
  console.log(JSON.stringify(receipt));
})().catch(error => { console.error(error); process.exitCode = 1; });
