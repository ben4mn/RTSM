'use strict';
// HTML fixture only: real launch/diagnostic/CSS sources, no Godot or game state.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const out = path.resolve(process.argv[2] || 'runtime-recovery-web-evidence');
fs.mkdirSync(out, {recursive: false});
const hashes = Object.fromEntries(['web/pocket_launch.js', 'web/pocket_launch.css', 'web/playtest_diagnostics.js',
    'web/pocket_shell.html', 'tools/test_runtime_recovery_web.cjs'].map(file => [file, hash(fs.readFileSync(path.join(root, file)))]));
function hash(bytes) { return crypto.createHash('sha256').update(bytes).digest('hex'); }
let html = fs.readFileSync(path.join(root, 'web/pocket_shell.html'), 'utf8').split('<script id="pocket-web-shell-script">')[0]
    + '<script src="fixture-error.js?token=fixture-private-query"></script></body></html>';
html = html.replace('$GODOT_HEAD_INCLUDE', '').replace(/\$GODOT_[A-Z_]+/g, 'fixture');
const updateStub = `window.fixtureSafety=[];window.PocketUpdates={init:async()=>{},prepareForPlay:async()=>({ready:true}),setSafeToReload(value){window.fixtureSafety.push(value);return value;}};`;
const requests = [], posts = [], checks = [], inputs = [], pageErrors = [], blocked = [];
let server, browser, context;
const fixtureAssets = {
    'Barlow-Regular.ttf': 'assets/fonts/Barlow-Regular.ttf', 'Barlow-Medium.ttf': 'assets/fonts/Barlow-Medium.ttf',
    'BarlowCondensed-SemiBold.ttf': 'assets/fonts/BarlowCondensed-SemiBold.ttf', 'field_company.png': 'assets/ui/field_company.png',
    'play_dark.svg': 'assets/ui/icons/play_dark.svg',
};
for (const kind of ['primary', 'secondary']) for (const state of ['normal', 'hover', 'pressed']) fixtureAssets[`${kind}_${state}.svg`] = `assets/ui/plates/${kind}_${state}.svg`;
function mime(name) { return name.endsWith('.js') ? 'text/javascript' : name.endsWith('.css') ? 'text/css' : name.endsWith('.svg') ? 'image/svg+xml' : name.endsWith('.json') ? 'application/json' : name.endsWith('.ttf') ? 'font/ttf' : 'image/png'; }
async function check(name, run) { await run(); checks.push(name); console.log('[PASS] ' + name); }
async function error(page, rejection = false) {
    const count = pageErrors.length;
    const original = page.waitForEvent('pageerror');
    await page.evaluate(reject => fixtureError(reject), rejection);
    await original;
    await page.waitForFunction(() => !!document.getElementById('pocket-runtime-recovery'), null, {timeout: 5000});
    assert(pageErrors.length > count, 'original error was suppressed');
}
async function tap(page, cdp, label) {
    const rect = await page.getByRole('button', {name: label, exact: true}).boundingBox();
    assert(rect && rect.width >= 44 && rect.height >= 44, label + ' minimum target');
    const x = rect.x + rect.width / 2, y = rect.y + rect.height / 2;
    await cdp.send('Input.dispatchTouchEvent', {type: 'touchStart', touchPoints: [{id: 0, x, y, radiusX: 2, radiusY: 2, force: 1}]});
    await cdp.send('Input.dispatchTouchEvent', {type: 'touchEnd', touchPoints: []});
    inputs.push({label, contact_id: 0, x, y, released: true});
}
async function boot(page, ready = true) {
    await page.goto(origin, {waitUntil: 'networkidle'});
    await page.getByRole('button', {name: 'Play now', exact: true}).tap();
    await page.evaluate(async ready => {
        await PocketLaunch.ready;
        window.fixtureGameInputs = [];
        for (const name of ['pointerdown','pointerup','pointermove','touchstart','touchend','mousedown','mouseup','click','keydown','keyup','wheel'])
            window.addEventListener(name, event => window.fixtureGameInputs.push({name, target: event.target.id}));
        if (ready) PocketLaunch.engineFinishedLoading();
        // No game callback is installed. Recovery must work with this dead engine stand-in.
    }, ready);
}
let origin;
(async () => {
    server = http.createServer((req, res) => {
        const name = new URL(req.url, 'http://127.0.0.1').pathname.slice(1);
        requests.push({method: req.method, name});
        if (req.method === 'POST' && name === 'api/playtest-diagnostics') {
            let body = ''; req.on('data', chunk => { body += chunk; if (body.length > 300000) req.destroy(); });
            req.on('end', () => { const value = JSON.parse(body); posts.push(value); res.writeHead(202, {'Content-Type':'application/json'}); res.end(JSON.stringify({stored:true, report_id:value.report_id})); }); return;
        }
        if (name === '' || name === 'index.html') { res.writeHead(200, {'Content-Type':'text/html'}); res.end(html); return; }
        if (name === 'pocket_updates.js') { res.writeHead(200, {'Content-Type':'text/javascript'}); res.end(updateStub); return; }
        if (name === 'fixture-error.js') {
            res.writeHead(200, {'Content-Type':'text/javascript'});
            res.end('window.fixtureError = function(reject) { if (reject) Promise.reject(new RangeError("fixture rejection")); else setTimeout(function() { throw new RangeError("fixture Invalid array length"); }, 0); };'); return;
        }
        if (name === 'version.json') { res.writeHead(200, {'Content-Type':'application/json'}); res.end(JSON.stringify({source_revision:'dde16657-fixture',version:'fixture'})); return; }
        if (/^index\.\d+x\d+\.png$/.test(name) || name === 'favicon.ico') { res.writeHead(204); res.end(); return; }
        const file = fixtureAssets[name] || ('web/' + name);
        if (!/^[A-Za-z0-9_.-]+$/.test(name) || !fs.existsSync(path.join(root, file))) { res.writeHead(404); res.end(); return; }
        res.writeHead(200, {'Content-Type':mime(name)}); res.end(fs.readFileSync(path.join(root,file)));
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); origin = `http://127.0.0.1:${server.address().port}/`;
    browser = await chromium.launch({headless:true, executablePath:process.env.CHROME_PATH || undefined});
    context = await browser.newContext({viewport:{width:844,height:390},hasTouch:true,isMobile:true,acceptDownloads:true});
    await context.route('**/*', route => { if (new URL(route.request().url()).origin !== new URL(origin).origin) { blocked.push(route.request().url()); return route.abort(); } return route.continue(); });
    await context.routeWebSocket('**/*', socket => { blocked.push(socket.url()); socket.close(); });
    const page = await context.newPage(), cdp = await context.newCDPSession(page);
    page.on('pageerror', event => pageErrors.push({name:event.name,message:event.message,stack:event.stack}));
    await check('startup/runtime distinction and resource/rejection/warning exclusions', async () => {
        await boot(page, false);
        await page.evaluate(() => { window.dispatchEvent(new ErrorEvent('error',{message:'startup failure'})); window.dispatchEvent(new Event('error')); window.dispatchEvent(new PromiseRejectionEvent('unhandledrejection',{promise:Promise.resolve(),reason:'string rejection'})); console.warn('fixture warning'); });
        assert.equal(await page.locator('#pocket-runtime-recovery').count(),0);
        await page.evaluate(() => PocketLaunch.engineFinishedLoading());
        await page.evaluate(() => { document.createElement('img').dispatchEvent(new Event('error',{bubbles:true})); window.dispatchEvent(new Event('error')); console.error('fixture console-only'); });
        assert.equal(await page.locator('#pocket-runtime-recovery').count(),0);
    });
    await check('real uncaught error creates one nonmodal notice and preserves original exception', async () => {
        await error(page);
        assert.equal(await page.locator('#pocket-runtime-recovery').count(),1);
        assert.equal(await page.locator('#pocket-app').evaluate(node => node.inert),false);
        assert.equal(await page.evaluate(() => fixtureSafety.at(-1)),false);
        const navigation = requests.filter(row => row.name === '').length;
        await error(page,true); await error(page);
        assert.equal(await page.locator('#pocket-runtime-recovery').count(),1);
        assert.equal(requests.filter(row => row.name === '').length,navigation);
        await page.screenshot({path:path.join(out,'landscape-error.png')});
    });
    await check('native Save log works with disabled storage and dead engine, without forwarding input', async () => {
        await page.evaluate(() => { Object.defineProperty(window,'localStorage',{get(){throw new Error('fixture storage unavailable');},configurable:true}); fixtureGameInputs=[]; });
        const nextDownload = page.waitForEvent('download'); await tap(page,cdp,'Save log');
        const download = await nextDownload; await download.saveAs(path.join(out,'saved-log.json'));
        const saved = JSON.parse(fs.readFileSync(path.join(out,'saved-log.json'),'utf8'));
        const failure = saved.events.find(row=>row.kind==='browser_error' && row.fields.error_message.includes('Invalid array length'));
        assert(failure && failure.fields.file==='fixture-error.js' && failure.fields.line>0 && failure.fields.column>0);
        assert(failure.fields.stack.some(frame=>frame.file==='fixture-error.js' && frame.line>0 && frame.column>0));
        assert(!JSON.stringify(saved).includes('fixture-private-query'));
        assert(!JSON.stringify(saved).includes(origin));
        assert(fs.statSync(path.join(out,'saved-log.json')).size <= 240*1024);
        assert.deepEqual(await page.evaluate(()=>fixtureGameInputs),[]);
        assert.equal(await page.locator('#pocket-report').count(),0);
    });
    await check('existing report and update holds keep priority; notice never releases a match update hold', async () => {
        await page.evaluate(() => { PocketLaunch.setUpdateSafe(false); PocketPlaytestDiagnostics.openReport(); });
        assert.equal(await page.locator('#pocket-runtime-recovery').isVisible(),false);
        await page.getByRole('button',{name:'Back to Pause',exact:true}).tap();
        assert.equal(await page.locator('#pocket-runtime-recovery').isVisible(),true);
        await page.evaluate(() => window.dispatchEvent(new CustomEvent('pocket-update-hold',{detail:{held:true}})));
        assert.equal(await page.locator('#pocket-runtime-recovery').evaluate(node=>node.inert),true);
        assert.equal(await page.locator('#pocket-update-blocker').isVisible(),true);
        await page.evaluate(() => window.dispatchEvent(new CustomEvent('pocket-update-hold',{detail:{held:false}})));
        await tap(page,cdp,'Dismiss');
        assert.equal(await page.locator('#pocket-runtime-recovery').isVisible(),false);
        assert.equal(await page.evaluate(()=>fixtureSafety.at(-1)),false);
        await page.evaluate(()=>PocketLaunch.setUpdateSafe(true));
        assert.equal(await page.evaluate(()=>fixtureSafety.at(-1)),true);
        await error(page); assert.equal(await page.locator('#pocket-runtime-recovery').isVisible(),false);
    });
    await check('portrait and notched landscape controls fit and are reachable above portrait prompt', async () => {
        for (const [width,height,left,right,top,bottom] of [[844,390,44,44,12,18],[932,430,44,44,12,18],[390,844,0,0,44,34],[667,375,24,24,8,14]]) {
            await page.setViewportSize({width,height}); await boot(page); await error(page);
            await page.evaluate(([l,r,t,b])=>{for(const[k,v]of Object.entries({left:l,right:r,top:t,bottom:b}))document.documentElement.style.setProperty('--pocket-safe-'+k,v+'px');},[left,right,top,bottom]);
            const bounds = await page.locator('#pocket-runtime-recovery').boundingBox();
            assert(bounds.x>=left && bounds.x+bounds.width<=width-right+1); assert(bounds.y>=top && bounds.y+bounds.height<=height-bottom+1);
            for (const label of ['Save log','Reload game','Dismiss']) { const rect=await page.getByRole('button',{name:label,exact:true}).boundingBox(); assert(rect.height>=44 && rect.width>=44); }
            await page.screenshot({path:path.join(out,`recovery-${width}x${height}.png`)});
            await tap(page,cdp,'Dismiss'); assert.equal(await page.locator('#pocket-runtime-recovery').isVisible(),false);
        }
    });
    await check('only explicit native Reload game navigates away and starts with no stale notice', async () => {
        await boot(page); await error(page,true);
        const before = requests.filter(row=>row.name==='').length;
        await Promise.all([page.waitForEvent('domcontentloaded'),tap(page,cdp,'Reload game')]);
        assert.equal(requests.filter(row=>row.name==='').length,before+1);
        assert.equal(await page.locator('#pocket-runtime-recovery').count(),0);
        assert.equal(await page.locator('#pocket-welcome').isVisible(),true);
    });
    assert.deepEqual(blocked,[]);
})().catch(error => { process.exitCode=1; checks.push({failed:error.stack}); }).finally(async()=>{
    const cleanup=[];
    for(const [name,action] of [['context',()=>context&&context.close()],['browser',()=>browser&&browser.close()],['server',()=>server&&new Promise(resolve=>server.close(resolve))]])try{await action();cleanup.push({name,closed:true});}catch(error){cleanup.push({name,error:String(error)});process.exitCode=1;}
    const unchanged=Object.entries(hashes).every(([file,sha])=>hash(fs.readFileSync(path.join(root,file)))===sha);
    if(!unchanged)process.exitCode=1;
    fs.writeFileSync(path.join(out,'receipt.json'),JSON.stringify({scope:'Synthetic HTML fixture; no Godot, gameplay or physical phone claim',passed:!process.exitCode,hashes,unchanged,checks,inputs,pageErrors,blocked,requests,cleanup},null,2));
});
