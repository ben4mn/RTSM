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
  document.visibilityState = 'visible';
  const context = vm.createContext({window, document}); vm.runInContext(script, context);
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
  current.detach(); document.emit('visibilitychange'); window.emit('pagehide'); window.emit('pageshow');
  assert.deepEqual(second, [true, false, true, false]);
  assert.equal([...window.listeners.values(), ...document.listeners.values()].reduce((n, callbacks) => n + callbacks.size, 0), 0);
  return {passed: true, scope: 'Production listener lifecycle, synthetic EventTargets; initial hidden, ignored blur, pagehide/pageshow and restart ownership'};
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
    for (let attempt = 0; !fs.existsSync(portFile); attempt++) {
      if (launchError) throw launchError;
      if (child.exitCode !== null || attempt >= 100) throw new Error('Private Chrome did not start');
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    const port = Number(fs.readFileSync(portFile, 'utf8').split(/\r?\n/)[0]);
    assert(Number.isInteger(port) && port > 0);
    browser = await chromium.connectOverCDP('http://127.0.0.1:' + port, {noDefaults: true});
    const context = browser.contexts()[0];
    const page = await context.newPage();
    await page.setContent('<title>Lifecycle regression</title><input id="first"><button id="second">Another control</button>');
    await page.evaluate(script);
    await page.evaluate(() => { window.events = []; window.binding = window.PocketMatchLifecycle.create(hidden => window.events.push({hidden, visibility: document.visibilityState})); });
    assert.equal(await page.evaluate(() => document.visibilityState), 'visible');
    await page.locator('#first').focus(); await page.locator('#second').focus();
    assert.deepEqual(await page.evaluate(() => window.events.map(event => event.hidden)), [false], 'Actual DOM focus changed match visibility');
    const other = await context.newPage();
    await other.setContent('<title>Second private test tab</title>');
    await other.bringToFront();
    await page.waitForFunction(() => document.visibilityState === 'hidden', null, {timeout: 4000, polling: 100});
    assert.equal(await page.evaluate(() => window.events.at(-1).hidden), true);
    await page.bringToFront();
    await page.waitForFunction(() => document.visibilityState === 'visible', null, {timeout: 4000, polling: 100});
    const events = await page.evaluate(() => window.events);
    assert.deepEqual(events.map(event => event.hidden), [false, true, false]);
    await page.evaluate(() => window.binding.detach());
    await other.bringToFront();
    await page.waitForFunction(() => document.visibilityState === 'hidden', null, {timeout: 4000, polling: 100});
    assert.deepEqual(await page.evaluate(() => window.events), events);
    return {passed: true, scope: 'Real Chrome tab hide/show and DOM control focus using exact production listener; no game exported or mutated; no focus emulation', headless: !process.argv.includes('--headed'), browser: await browser.version(), events};
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
