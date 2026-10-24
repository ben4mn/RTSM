'use strict';
// Exported-PCK integration, separate from CUA play and the listener unit test.
// Only real browser/canvas inputs and read-only DOM/localStorage observations.
// Default: private verified host. --url permits exploratory external-host
// baselines, which cannot pass the owned-server provenance assertions.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const assert = require('node:assert/strict');
const {spawn, spawnSync} = require('node:child_process');
const {verifyTree, digest} = require('./local_browser_runtime.cjs');
const arg = (name, fallback) => {const i = process.argv.indexOf('--' + name); return i < 0 ? fallback : process.argv[i + 1];};
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const runtimeModules = path.join(process.env.USERPROFILE || '', '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules');
const moduleFrom = name => require(require.resolve(name, {paths: [runtimeModules, __dirname]}));
const {PNG} = moduleFrom('pngjs');

function regionHash(file, rect) {
  const image = PNG.sync.read(fs.readFileSync(file));
  assert(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= image.width && rect.y + rect.height <= image.height);
  const bytes = Buffer.alloc(rect.width * rect.height * 4);
  for (let y = 0; y < rect.height; y++) image.data.copy(bytes, y * rect.width * 4, ((rect.y + y) * image.width + rect.x) * 4, ((rect.y + y) * image.width + rect.x + rect.width) * 4);
  return digest(bytes);
}

async function sealedHost(artifact, output, receipt) {
  const mime = {'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.ttf':'font/ttf','.pck':'application/octet-stream'};
  receipt.served = []; receipt.collector = [];
  const server = http.createServer((request, response) => {
    let relative;
    try { relative = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname).slice(1) || 'index.html'; }
    catch { response.writeHead(400).end(); return; }
    if (request.method === 'POST' && relative === 'api/playtest-diagnostics') {
      const chunks = []; let size = 0;
      request.on('data', chunk => {size += chunk.length;if(size <= 256*1024) chunks.push(chunk);});
      request.on('end', () => {
        if(size > 256*1024) {response.writeHead(413).end();return;}
        const bytes = Buffer.concat(chunks); let payload;
        try {payload=JSON.parse(bytes);} catch {response.writeHead(400).end();return;}
        if(!payload || typeof payload !== 'object' || Array.isArray(payload)) {response.writeHead(400).end();return;}
        const filename = 'collector-' + String(receipt.collector.length+1).padStart(3,'0') + '.json';
        fs.writeFileSync(path.join(output, filename), bytes);
        receipt.collector.push({file:filename,bytes:bytes.length,sha256:digest(bytes),unix:Date.now()});
        response.writeHead(200, {'Content-Type':'application/json','Cache-Control':'no-store'}).end(JSON.stringify({stored:true,report_id:payload.report_id || ''}));
      }); return;
    }
    if(!['GET','HEAD'].includes(request.method)) {response.writeHead(405).end();return;}
    if(!Object.hasOwn(artifact.files,relative)) {response.writeHead(404).end();return;}
    const bytes=fs.readFileSync(path.join(artifact.root,relative)); const sha256=digest(bytes);
    if(sha256!==artifact.files[relative]) {response.writeHead(409).end('Sealed artifact changed');return;}
    receipt.served.push({method:request.method,file:relative,sha256,bytes:bytes.length,unix:Date.now()});
    response.writeHead(200,{'Content-Type':mime[path.extname(relative)]||'application/octet-stream','Content-Length':bytes.length,'Cache-Control':'no-store','Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp','X-Pocket-Artifact-SHA256':sha256});
    response.end(request.method==='HEAD'?undefined:bytes);
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  return {url:'http://127.0.0.1:'+server.address().port+'/',stop:()=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections();})};
}

async function main() {
  const artifact = verifyTree(arg('artifact-dir', path.join(__dirname, '../build/mobile-polish-c323e88-web')));
  const version = JSON.parse(fs.readFileSync(path.join(artifact.root, 'version.json')));
  const revision = arg('revision', 'c323e885bbc208e93061ccf0600924f16e0041c5');
  assert(/^[a-f0-9]{40}$/.test(revision) && /^[a-f0-9]{12,40}$/.test(version.source_revision) && version.source_dirty === false && revision.startsWith(version.source_revision));
  let url = arg('url', 'http://127.0.0.1:8790/');
  assert(new URL(url).hostname === '127.0.0.1', 'Fixture is restricted to the local sealed export');
  const output = path.resolve(arg('output', 'output/background-export-' + Date.now()));
  fs.mkdirSync(output, {recursive: true});
  assert.equal(fs.readdirSync(output).length, 0, 'Use a fresh output directory');
  const receipt = {scope: 'Automated exported-PCK browser fixture; native canvas clicks, real tab hide/show, read-only stored diagnostics. Separate from root CUA play; no physical-device claim.', harness_sha256:digest(fs.readFileSync(__filename)), revision, artifact, version, url, viewport: {width:932,height:430}, inputs:[], captures:[], observations:[], responses:[], errors:[], warnings:[], checks:[], passed:false};
  const write = (name, data) => fs.writeFileSync(path.join(output, name), JSON.stringify(data, null, 2) + '\n');
  const check = (condition, label) => {receipt.checks.push({label, passed:!!condition}); assert(condition, label);};
  let host;
  if(!process.argv.includes('--url')||process.argv.includes('--serve-local')) {host=await sealedHost(artifact,output,receipt);url=host.url;receipt.url=url;receipt.host_scope='Fixture-owned byte-verified static server and local-only bounded diagnostics collector; artifact files unchanged';}
  const {chromium} = moduleFrom('playwright');
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'pocket-export-background-'));
  const chrome = arg('chrome', path.join(process.env.PROGRAMFILES || '', 'Google/Chrome/Application/chrome.exe'));
  const child = spawn(chrome, ['--headless=new','--remote-debugging-port=0','--remote-debugging-address=127.0.0.1','--user-data-dir='+profile,'--no-first-run','--no-default-browser-check','--disable-background-networking','about:blank'], {windowsHide:true,stdio:'ignore'});
  receipt.process = {pid:child.pid, profile, executable:chrome, noDefaults:true};
  let browser, page, launchError;
  child.once('error', error => {launchError=error;});
  const deadline=Date.now()+150000;
  try {
    const portFile=path.join(profile,'DevToolsActivePort');
    let port;
    while(!port) {if(launchError)throw launchError;if(child.exitCode!==null||Date.now()>deadline)throw Error('Private Chrome startup failed');try{const candidate=Number(fs.readFileSync(portFile,'utf8').split(/\r?\n/)[0]);if(Number.isInteger(candidate)&&candidate>0)port=candidate;}catch(error){if(!['ENOENT','EBUSY'].includes(error.code))throw error;}if(!port)await delay(100);}
    browser=await chromium.connectOverCDP('http://127.0.0.1:'+port,{noDefaults:true});
    receipt.browser=await browser.version();
    const context=browser.contexts()[0];
    await context.route('**/*',route=>new URL(route.request().url()).origin===new URL(url).origin?route.continue():route.abort('blockedbyclient'));
    await context.routeWebSocket('**/*',route=>route.close({code:1008,reason:'Offline exported lifecycle fixture'}));
    page=await context.newPage();
    await page.setViewportSize(receipt.viewport);
    page.on('console',message=>{const item={type:message.type(),text:message.text(),unix:Date.now()};if(item.type==='error')receipt.errors.push(item);if(item.type==='warning')receipt.warnings.push(item);});
    page.on('pageerror',error=>receipt.errors.push({type:'pageerror',text:String(error),unix:Date.now()}));
    page.on('response',response=>{
      const name=new URL(response.url()).pathname.slice(1)||'index.html';
      if(['index.html','index.js','index.wasm','index.pck','version.json'].includes(name)) {const headers=response.headers();receipt.responses.push({name,status:response.status(),content_length:headers['content-length'],server_sha256:headers['x-pocket-artifact-sha256']||null,unix:Date.now()});}
    });
    const read = async label => {
      const value=await page.evaluate(()=>({url:location.href,visibility:document.visibilityState,focused:document.hasFocus(),canvas:Array.from(document.querySelectorAll('canvas')).map(c=>({id:c.id,width:c.width,height:c.height,rect:c.getBoundingClientRect().toJSON()})),stored:JSON.parse(localStorage.getItem('pocket.playtest.v1')||'null')}));
      const item={label,unix:Date.now(),...value};receipt.observations.push(item);write(label+'.json',item);return item;
    };
    const capture = async label => {const filename=path.join(output,label+'.png');await page.screenshot({path:filename});receipt.captures.push({label,path:filename,sha256:digest(fs.readFileSync(filename))});console.log('CAPTURE '+filename);return filename;};
    const click = async (label,x,y) => {receipt.inputs.push({label,x,y,unix:Date.now(),method:'page.mouse.click'});await page.mouse.click(x,y);await delay(300);};
    const samples = observation => (observation.stored?.latest?.events||[]).filter(e=>e.kind==='game_sample');
    await page.goto(url,{waitUntil:'domcontentloaded'});
    await page.getByRole('button',{name:'Play now',exact:true}).click({timeout:20000});
    receipt.inputs.push({label:'Play now',method:'semantic HTML button',unix:Date.now()});
    await delay(7000);await capture('01-home');
    await click('New Game',747,288);await capture('02-setup');
    await click('Start solo match',827,392);await delay(5000);await capture('03-started');
    await click('Base selects Town Center',778,305);await capture('04-before-paid-training');
    await click('Paid Villager one',638,375);await click('Paid Villager two',638,375);
    await click('Economy',837,298);await click('Train producer page',331,109);await capture('05-paid-queue');
    const before=await read('before-hide');
    check(before.visibility==='visible','Game page is truly visible before background');
    check(samples(before).length>0,'Exported game produced existing game_sample diagnostics');
    const other=await context.newPage();await other.goto('about:blank');await other.bringToFront();
    await page.waitForFunction(()=>document.visibilityState==='hidden',null,{timeout:5000,polling:100});
    const hidden=await read('actually-hidden');
    check(hidden.visibility==='hidden','Real second tab makes the game document hidden');
    await delay(10000);
    await page.bringToFront();
    await page.waitForFunction(()=>document.visibilityState==='visible',null,{timeout:5000,polling:100});
    await delay(500);
    const pausedFirst=await capture('06-returned-pause');const returned=await read('returned-pause');
    await delay(6000);
    const pausedLater=await capture('07-still-paused');const held=await read('still-paused');
    check(JSON.stringify(samples(returned))===JSON.stringify(samples(held)),'No new playing-clock samples during six visible paused seconds');
    const regions={header:{x:0,y:0,width:932,height:48},selection_and_queue:{x:0,y:355,width:932,height:70},pause_menu:{x:310,y:90,width:312,height:240}};
    receipt.pixel_regions=regions;
    for(const [name,rect] of Object.entries(regions))check(regionHash(pausedFirst,rect)===regionHash(pausedLater,rect),name+' pixels remain exactly frozen while foregrounded');
    let resume={x:Number(arg('resume-x',466)),y:Number(arg('resume-y',170))};
    if(process.argv.includes('--review-resume')) {
      console.log('WAITING_FOR_RESUME_COORDINATES '+path.join(output,'resume.json'));
      while(!fs.existsSync(path.join(output,'resume.json'))){if(Date.now()>deadline)throw Error('Resume review exceeded total scenario bound');await delay(100);}
      resume=JSON.parse(fs.readFileSync(path.join(output,'resume.json'),'utf8'));
    }
    check(Number.isFinite(resume.x)&&Number.isFinite(resume.y),'Resume uses an explicit observed canvas location');
    const resumeAt=Date.now();await click('Explicit Resume',resume.x,resume.y);
    const lastHeld=samples(held).at(-1);
    // The shipped shell persists on a ten-second cadence. Read only; never
    // invoke its record/flush API or synthesize a lifecycle event to force it.
    await page.waitForFunction(previous=>{const stored=JSON.parse(localStorage.getItem('pocket.playtest.v1')||'null');return (stored?.latest?.events||[]).filter(e=>e.kind==='game_sample').at(-1)?.fields.game_seconds>previous+2;},lastHeld?.fields.game_seconds,{timeout:20000,polling:250});
    const resumedImage=await capture('08-after-resume');const resumed=await read('after-resume');
    const lastResumed=samples(resumed).at(-1);receipt.resume_wall_seconds=(Date.now()-resumeAt)/1000;
    check(lastResumed&&lastHeld&&lastResumed.fields.game_seconds>lastHeld.fields.game_seconds+2,'Game clock advances only after explicit Resume');
    check(lastResumed.fields.game_seconds-lastHeld.fields.game_seconds<receipt.resume_wall_seconds+3,'Resumed simulation excludes ten hidden plus six paused wall seconds');
    check(regionHash(pausedLater,regions.selection_and_queue)!==regionHash(resumedImage,regions.selection_and_queue),'Paid selection/queue pixels change after Resume');
    for(const name of ['index.js','index.wasm','index.pck'])check(receipt.responses.some(r=>r.name===name&&r.status===200&&r.server_sha256===artifact.files[name])&&receipt.served?.some(r=>r.file===name&&r.method==='GET'&&r.sha256===artifact.files[name]),'Actual loaded '+name+' matches bytes hashed by owned server');
    check(receipt.errors.length===0,'No browser or runtime errors');
    const knownWarning='<meta name="apple-mobile-web-app-capable" content="yes"> is deprecated. Please include <meta name="mobile-web-app-capable" content="yes">';
    receipt.known_browser_warnings=receipt.warnings.filter(item=>item.text===knownWarning);
    check(receipt.warnings.every(item=>item.text===knownWarning),'No unexpected browser warnings; exact existing metadata deprecation retained');
    receipt.browser_clean=receipt.warnings.length===0;
    receipt.automated_checks_passed=true;
    receipt.passed=false; // Human image inspection must verify paid queue + Pause/Resume text.
    receipt.visual_review_required=['04-before-paid-training','05-paid-queue','06-returned-pause','07-still-paused','08-after-resume'];
  } catch(error) {
    receipt.failure=String(error.stack||error);console.error(receipt.failure);process.exitCode=1;
    if(page)try{await page.screenshot({path:path.join(output,'failure.png')});}catch{}
  } finally {
    if(browser){try{await(await browser.newBrowserCDPSession()).send('Browser.close');}catch{}try{await browser.close();}catch{}}
    for(let i=0;child.exitCode===null&&!launchError&&i<30;i++)await delay(100);
    if(child.exitCode===null&&!launchError){if(process.platform==='win32')spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,timeout:10000});else child.kill('SIGKILL');await delay(200);}
    receipt.cleanup={owned_pid:child.pid,exit_code:child.exitCode,terminated:child.exitCode!==null||!!child.signalCode};
    if(host)await host.stop();
    const final=verifyTree(artifact.root);receipt.artifact_unchanged=final.manifest_sha256===artifact.manifest_sha256;
    const resolved=path.resolve(profile);assert(path.dirname(resolved)===path.resolve(os.tmpdir())&&path.basename(resolved).startsWith('pocket-export-background-'));
    fs.rmSync(resolved,{recursive:true,force:true,maxRetries:5,retryDelay:100});
    write('receipt.json',receipt);console.log('RECEIPT '+path.join(output,'receipt.json'));
  }
}

if(require.main===module)main().catch(error=>{console.error(error);process.exitCode=1;});
module.exports={regionHash,sealedHost};
