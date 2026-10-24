#!/usr/bin/env node
'use strict';
// Two actual, isolated browser clients of the deployed export. Test-only socket
// instrumentation sends ordinary paid protocol orders; it never changes game
// objects, resources, snapshots, clocks or terminal outcomes. Lobby and extra
// keyboard actions remain real browser input, controlled through localhost HTTP.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const os = require('node:os');
const {startLocalRuntime, digest, verifyTree} = require('./local_browser_runtime.cjs');
const {civilization,resultExpectation,paidVillagerRecruitment} = require('./live_browser_receipts.cjs');
const {nativeTap,createBeta2Controller} = require('./live_browser_beta2_ui.cjs');
const {createGarrisonController}=require('./live_browser_garrison.cjs');
const {createMarchController} = require('./live_browser_march.cjs');

function installWitness(configuration = {}) {
  const Native = window.WebSocket;
  const sockets = [];
  const state = {room: null, matched: null, last: null, ended: null, startedWall: null,
    messages: [], sends: [], counters: {}, ready: false, routes: [], commandSerial: 0};
  let policySending = false;
  const expectedEndpoint = 'wss://game.4mn.org/match';
  if (configuration.local) {
    const target = new URL(configuration.matchUrl);
    if (target.protocol !== 'ws:' || target.hostname !== '127.0.0.1' || !target.port || target.pathname !== '/match' || target.username || target.password || target.search || target.hash) throw new Error('Local witness requires an exact loopback /match URL');
  }
  function witnessEvent(event) {
    if (typeof window.__pocketHarnessEvent === 'function') window.__pocketHarnessEvent(event).catch(() => {});
  }
  function parse(data) {
    try { return JSON.parse(typeof data === 'string' ? data : new TextDecoder().decode(data)); }
    catch (_) { return null; }
  }
  class WitnessSocket extends Native {
    constructor(...args) {
      const requested = String(args[0]);
      if (configuration.local) {
        const allowed = requested === expectedEndpoint || requested === configuration.matchUrl;
        const route = {requested, resolved:allowed ? configuration.matchUrl : null, blocked:!allowed, unix:Date.now()};
        state.routes.push(route); if(state.routes.length > 64)state.routes.shift();
        witnessEvent({kind:'socket_route',...route});
        if (!allowed) throw new Error('Local witness blocked an unapproved WebSocket endpoint');
        args[0] = configuration.matchUrl;
      }
      super(...args); this.witnessSequence = 0; this.witnessMatch = null;
      if (!String(args[0]).includes('/match')) return;
      sockets.push(this);
      this.addEventListener('message', event => {
        const packet = parse(event.data); if (!packet) return;
        state.counters[packet.op] = (state.counters[packet.op] || 0) + 1;
        if (packet.op === 'room') state.room = packet;
        if (packet.op === 'matched') {
          state.matched = packet; this.witnessMatch = packet.match;
          this.witnessSequence = 0; state.ended = null; state.last = null;
        }
        if (packet.op === 'started') { state.startedWall = performance.now(); state.ready = true; }
        if (packet.op === 'snapshot') state.last = packet;
        if (packet.op === 'ended') { state.ended = packet; state.ready = false; }
        if (packet.op !== 'snapshot') {
          state.messages.push({wall: performance.now(), packet});
          if (state.messages.length > 300) state.messages.shift();
        }
      });
    }
    send(data) {
      const packet = parse(data);
      if (packet?.op === 'command') {
        const originalSequence = packet.sequence;
        packet.sequence = ++this.witnessSequence;
        const encoded = JSON.stringify(packet);
        data = typeof data === 'string' ? encoded : new TextEncoder().encode(encoded);
        const event = {serial:++state.commandSerial,wall: performance.now(), originalSequence, packet, source:policySending ? 'paid_policy' : 'game_ui_or_engine'};
        state.sends.push(event);
        witnessEvent({kind:'command_origin',...event});
        if (state.sends.length > 500) state.sends.shift();
      }
      return super.send(data);
    }
  }
  window.WebSocket = WitnessSocket;
  window.__aoemLiveWitness = {
    state,
    sendCommand(command, payload = {}) {
      const allowed = ['allocate', 'train', 'place', 'age', 'research', 'attack_move', 'move', 'delete'];
      if (!allowed.includes(command) || !state.ready || !state.matched || state.ended) return false;
      const socket = sockets.find(s => s.witnessMatch === state.matched.match && s.readyState === Native.OPEN);
      if (!socket) return false;
      policySending = true;
      try {socket.send(JSON.stringify({...payload, op: 'command', command, sequence: 0, match: state.matched.match}));}
      finally {policySending = false;}
      return true;
    },
  };
}

async function configureLocalGuards(context, matchUrl, pageUrl, record) {
  if(typeof context.routeWebSocket!=='function')throw new Error('Local mode requires Playwright routeWebSocket for a second fail-closed socket guard');
  await context.routeWebSocket('**/*',route=>{
    const permitted=route.url()===matchUrl;
    record({unix:Date.now(),url:route.url(),allowed:permitted});
    if(permitted)route.connectToServer();else route.close({code:1008,reason:'Local witness blocks nonlocal sockets'});
  });
  await context.route('**/*',route=>new URL(route.request().url()).origin===new URL(pageUrl).origin?route.continue():route.abort('blockedbyclient'));
}

const unitCosts = {0:{food:50},1:{food:50,wood:20},2:{food:25,wood:45},3:{food:90,wood:30},4:{food:40,gold:10},5:{wood:150,gold:100}};
const buildingCosts = {1:{wood:50},2:{wood:120},3:{wood:120},4:{wood:120},5:{wood:75},8:{wood:300,gold:100},9:{wood:120}};
const footprints = {0:4,1:2,2:3,3:3,4:3,5:2,6:2,8:3,9:2,10:1};
const techs = [{id:'forging',cost:{food:100,gold:50}},{id:'scale_mail',cost:{food:100,gold:50}},
  {id:'wheelbarrow',cost:{food:175,wood:50}},{id:'loom',cost:{gold:50}}];
const world = ([x,y]) => [(x-y)*32,(x+y)*16];
const tile = actor => [Math.round(actor.x/64+actor.y/32),Math.round(actor.y/32-actor.x/64)];
const afford = (bank,cost) => cost && Object.entries(cost).every(([key,value]) => (bank[key]||0)>=value);
const spend = (bank,cost) => Object.entries(cost).forEach(([key,value]) => bank[key]-=value);

function placementCandidate(data, slot, town, type, rejected) {
  const origin = tile(town), size = footprints[type];
  const occupied = data.actors.filter(a=>a.kind==='building').map(a=>({tile:tile(a),size:footprints[a.type]||2}));
  const resources = new Set(data.resources.filter(r=>r[2]>0).map(r=>`${r[0]},${r[1]}`));
  for (let radius=4;radius<15;radius++) for (let dx=-radius;dx<=radius;dx++) for (const dy of [-radius,radius]) {
    const x=origin[0]+dx,y=origin[1]+dy,key=`${type}:${x},${y}`;
    if (x<0||y<0||x+size>72||y+size>72||rejected.has(key)) continue;
    if (occupied.some(b=>x<=b.tile[0]+b.size && x+size>=b.tile[0] && y<=b.tile[1]+b.size && y+size>=b.tile[1])) continue;
    let blocked=false;
    for (let xx=x;xx<x+size;xx++) for (let yy=y;yy<y+size;yy++) if(resources.has(`${xx},${yy}`)) blocked=true;
    if (!blocked) return {key,position:world([x,y])};
  }
  return null;
}

function planPolicy(client) {
  const d=client.last,m=client.matched;
  if (!d||!m||client.ended||!client.policy) return [];
  const own=d.actors.filter(a=>a.owner===m.slot), workers=own.filter(a=>a.kind==='unit'&&a.type===0);
  const army=own.filter(a=>a.kind==='unit'&&a.type!==0&&(!client.beta2||[1,2,3,5].includes(a.type))).map(a=>a.id);
  const saving=client.beta2&&!client.beta2SiegeDone&&d.player.age>=2;
  const buildings=own.filter(a=>a.kind==='building'), active=t=>buildings.find(a=>a.type===t&&a.state===2);
  const count=t=>buildings.filter(a=>a.type===t).length, queued=a=>a?.queue?.items?.length||0;
  const bank={...d.bank}, commands=[], send=(command,payload={})=>commands.push({command,payload,...(command==='train'?{expected_cost:{...unitCosts[payload.type]},bank_before:{...bank}}:{})});
  const town=active(0), t=d.time;
  if (!town) return [];
  if(client.objectiveOnly) {
    if(!army.length&&queued(town)<1&&afford(bank,unitCosts[4]))send('train',{target:town.id,type:4});
    if(workers.some(w=>!w.work&&!w.recovering))send('allocate',{source:'idle',destination:'food'});
    if(client.role==='host'&&army.length&&t-client.lastArmy>=15) {
      send('attack_move',{ids:army,position:[0,1152]});client.lastArmy=t;
    }
    return commands;
  }
  if(client.pendingPlace) {
    const p=client.pendingPlace;
    if(buildings.some(b=>b.type===p.type&&Math.abs(b.x-p.position[0])<1&&Math.abs(b.y-p.position[1])<1))client.pendingPlace=null;
    else if(t-p.time>4) {client.rejectedPlacements.add(p.key);client.pendingPlace=null;}
  }
  if(workers.length<12&&queued(town)<1&&afford(bank,unitCosts[0])) {send('train',{target:town.id,type:0});spend(bank,unitCosts[0]);}
  const tasks={food:0,wood:0,gold:0};workers.forEach(w=>{if(w.work in tasks)tasks[w.work]++;});
  if(workers.some(w=>!w.work&&!w.recovering))send('allocate',{source:'idle',destination:tasks.wood<4?'wood':tasks.gold<3?'gold':'food'});
  if(workers.length&&!buildings.some(a=>a.state!==2)&&!client.pendingPlace&&t-client.lastBuild>=3) {
    let type=-1;
    if(d.player.population_cap<30&&d.player.population+(d.player.population_reserved||0)>=d.player.population_cap-2)type=1;
    else if(t>260&&!client.demolished&&count(1)<2)type=1;
    else if(!count(2))type=2;
    else if(!count(9)&&t>55)type=9;
    // Ordinary paid capacity for this script's own planned/observed food jobs.
    // Five food workers need five one-worker Farms once berries are exhausted.
    else if(count(5)<Math.min(6,Math.max(2,tasks.food,workers.length-7))&&t>100)type=5;
    else if(!count(3)&&d.player.age>=2)type=3;
    else if(!count(4)&&d.player.age>=2)type=4;
    else if(!count(8)&&d.player.age>=3&&!client.beta2)type=8;
    if(type>=0&&afford(bank,buildingCosts[type])) {
      const candidate=placementCandidate(d,m.slot,town,type,client.rejectedPlacements);
      if(candidate) {send('place',{type,ids:[workers[0].id],position:candidate.position});spend(bank,buildingCosts[type]);
        client.pendingPlace={...candidate,type,time:t};client.lastBuild=t;}
    }
  }
  const ageCost=d.player.age===1?{food:250,gold:125}:d.player.age===2?{food:600,gold:300}:null;
  if(ageCost&&afford(bank,ageCost)){send('age');spend(bank,ageCost);}
  const smith=active(9);
  if(smith&&!saving)for(const tech of techs)if(!d.research.includes(tech.id)&&afford(bank,tech.cost)){send('research',{target:smith.id,research:tech.id});spend(bank,tech.cost);break;}
  const reserve=d.player.age>=3||t<180?0:d.player.age===1?260:620;
  const emergency=t<180||d.player.age>=3?3:0;
  if(!saving&&army.length<12&&(bank.food>reserve||army.length<emergency))for(const [buildingType,unitType] of [[2,1],[3,2],[4,3],[8,5]]) {
    const b=active(buildingType);if((!client.beta2||client.beta2SiegeDone||unitType!==5)&&b&&queued(b)<1&&afford(bank,unitCosts[unitType])) {send('train',{target:b.id,type:unitType});spend(bank,unitCosts[unitType]);}
  }
  if(army.length&&t-client.lastArmy>=24){
    const position=t>650?(client.role==='host'?[0,1152]:[town.x,town.y]):[0,1536];
    send('attack_move',{ids:army,position});client.lastArmy=t;
  }
  if(t>300&&!client.demolished&&count(1)>=2){const house=active(1);if(house){send('delete',{target:house.id});client.demolished=true;}}
  return commands;
}

async function main() {
  const arg=name=>{const index=process.argv.indexOf('--'+name);return index<0?null:process.argv[index+1];};
  if(process.argv.includes('--self-test')) {
    assert.deepEqual(world([36,36]),[0,1152]);assert.deepEqual(tile({x:-1760,y:1136}),[8,63]);
    assert(afford({food:250,gold:125},{food:250,gold:125}));assert(!afford({wood:25},{wood:75}));
    const vm=require('node:vm');class Socket extends EventTarget {static OPEN=1;constructor(){super();this.readyState=1;this.wire=[];}send(d){this.wire.push(JSON.parse(d));}}
    const sandbox={window:{WebSocket:Socket},TextDecoder,TextEncoder,performance,EventTarget};vm.runInNewContext(`(${installWitness.toString()})()`,sandbox);
    const socket=new sandbox.window.WebSocket('wss://example.invalid/match');
    socket.send(JSON.stringify({op:'command',sequence:1,match:7,command:'train'}));socket.send(JSON.stringify({op:'command',sequence:1,match:7,command:'train'}));
    assert.deepEqual(socket.wire.map(p=>p.sequence),[1,2]);console.log('Witness sequence normalization and paid-policy arithmetic checks passed. No browser or network launched.');return;
  }
  const localMode=process.argv.includes('--local');
  const inputMode=process.argv.includes('--touch')?'touch':'mouse';
  const beta2=process.argv.includes('--beta2');
  const cohesion=process.argv.includes('--cohesion');
  const garrison=process.argv.includes('--garrison');
  if(garrison&&!cohesion)throw Error('--garrison requires --cohesion --beta2 --touch');
  if(cohesion&&!beta2)throw Error('--cohesion requires the paid --beta2 --touch acceptance');
  if(beta2&&(inputMode!=='touch'||process.argv.includes('--objective-only')))throw Error('--beta2 requires --touch and the full scenario');
  if(beta2&&((arg('width')&&Number(arg('width'))!==844)||(arg('height')&&Number(arg('height'))!==390)))throw Error('--beta2 acceptance requires two844x390 touch viewports');
  const expectations={host:civilization(arg('host-civilization')||1),guest:civilization(arg('guest-civilization')||2)};
  const expectedIds=[expectations.host.id,expectations.guest.id];
  if(localMode && (process.argv.includes('--allow-public') || arg('url')))throw new Error('--local owns both verified endpoints; do not combine it with --allow-public or --url.');
  if(!localMode && !process.argv.includes('--allow-public'))throw new Error('Use --local for sealed local artifacts, or --allow-public only after deployment readiness.');
  const publicProof=!localMode ? {artifact:verifyTree(arg('artifact-dir')),postflight:JSON.parse(fs.readFileSync(arg('public-postflight'),'utf8')),postflight_sha256:digest(fs.readFileSync(arg('public-postflight')))} : null;
  if(publicProof){assert.equal(publicProof.postflight.status,'PASS_READ_ONLY_POSTFLIGHT');for(const [name,hash] of Object.entries(publicProof.artifact.files))assert.equal(publicProof.postflight.public_files[name]?.sha256,hash,'Public postflight does not match sealed file '+name);}
  const versionPath=path.join(path.resolve(arg('artifact-dir')),'version.json');
  const sealedVersionBytes=fs.readFileSync(versionPath),sealedVersion=JSON.parse(sealedVersionBytes);
  const expectedProtocol=sealedVersion.network_protocol;
  if(expectedProtocol!==3)throw Error('Live acceptance requires sealed network_protocol3; historical2 reports remain analyzer-only');
  if(publicProof&&publicProof.postflight.request?.protocol!==expectedProtocol)throw Error('Public postflight protocol differs from sealed release');
  let modulePath=arg('playwright-module');
  if(!modulePath){try{modulePath=require.resolve('playwright');}catch(_){
    const candidates=[path.join(os.homedir(),'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright')];
    for(const cache of [path.join(os.homedir(),'.npm/_npx'),path.join(os.homedir(),'AppData/Local/npm-cache/_npx')])if(fs.existsSync(cache))candidates.push(...fs.readdirSync(cache).map(n=>path.join(cache,n,'node_modules/playwright')));
    modulePath=candidates.find(p=>fs.existsSync(path.join(p,'package.json')));
  }}
  const {chromium}=require(modulePath);
  const out=path.resolve(arg('output')||'output/playwright/live-multiplayer');
  fs.mkdirSync(out,{recursive:true});if(fs.existsSync(path.join(out,'invocation.json')))throw new Error('Use a new output directory.');
  if(localMode&&fs.readdirSync(out).length)throw new Error('Local witness output must be empty so failed receipts cannot be overwritten.');
  const local=localMode ? await startLocalRuntime({artifactDirectory:arg('artifact-dir'),serverDirectory:arg('server-context'),godot:arg('godot')||process.env.GODOT_BIN,output:out}) : null;
  const url=local?.url||arg('url')||'https://game.4mn.org/',port=Number(arg('port')||8876),clients={};
  let browser,controllerTimer,controllerServer;
  try {
  browser=await chromium.launch({channel:'chrome',headless:false,args:['--disable-background-timer-throttling','--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding']});
  const save=(name,value)=>fs.writeFileSync(path.join(out,name),JSON.stringify(value,null,2)+'\n');
  if(publicProof)save('public-source.json',publicProof);
  fs.writeFileSync(path.join(out,'sealed-version.json'),sealedVersionBytes);
  const append=(name,value)=>fs.appendFileSync(path.join(out,name),JSON.stringify(value)+'\n');
  const objectiveOnly=process.argv.includes('--objective-only');
  save('invocation.json',{url,port,started:new Date().toISOString(),headless:false,input_mode:inputMode,acceptance_profile:beta2?'beta2-mobile':'legacy',cohesion_acceptance:cohesion,garrison_acceptance:garrison,garrison_tool_sha256:garrison?digest(fs.readFileSync(require.resolve('./live_browser_garrison.cjs'))):null,garrison_policy_scope:garrison?'After both strict paid purchase and march journeys, hold both scripts; each paid Scout claims an otherwise unguarded Site, observe two advancing game seconds with frozen180s hold, then actual UI Move brings existing fighters for two seconds of ticking. Guest then host; gathering and simulation continue. Return to disclosed terminal policy afterward; no human pacing claim.':null,march_tool_sha256:cohesion?{'live_browser_march.cjs':digest(fs.readFileSync(require.resolve('./live_browser_march.cjs')))}:null,beta2_tool_sha256:beta2?Object.fromEntries(['live_browser_beta2_ui.cjs','live_browser_beta2_receipts.cjs'].map(name=>[name,digest(fs.readFileSync(path.join(__dirname,name)))])):null,civilization_expectations:expectations,protocol:expectedProtocol,expected_protocol:expectedProtocol,scenario:objectiveOnly?'objective':'full',mode:localMode?'local-sealed':'public',match_url:local?.matchUrl||'wss://game.4mn.org/match',source_revision:local?.source.version.source_revision||JSON.parse(fs.readFileSync(path.join(publicProof.artifact.directory||arg('artifact-dir'),'version.json'),'utf8')).source_revision,harness_sha256:digest(fs.readFileSync(__filename)),local_runtime_helper_sha256:digest(fs.readFileSync(require.resolve('./local_browser_runtime.cjs'))),receipt_helper_sha256:digest(fs.readFileSync(require.resolve('./live_browser_receipts.cjs'))),browser_version:browser.version(),beta2_policy_scope:beta2?'Ordinary-cost saving policy: after reaching Feudal, defer research and military purchases until actual touch Workshop construction and Siege birth are witnessed. Essential paid workers, houses, farms, Range, Stable and ages continue. Both policies are explicitly held for isolated UI transactions; gathering and simulation continue. Scout is paid through UI and excluded from automatic army commands. The disclosed650s terminal schedule is retained, not a pacing average.':null,policy_scope:'Ordinary paid scripted policy: grow to12 workers;4wood/3gold/restfood;paid Farms after100s follow own planned/observed food-worker demand, minimum2/cap6; train mixed stable-ID troops; central skirmish until650s then host takes Sacred while guest returns home. Paid house demolition tests destruction. Natural server terminal is policy-scheduled, not human pacing or an11-14 minute balance average. No camp coverage.',scope:localMode?'Automated browser fixture using two fresh contexts of a byte-verified export and matching local authority. Canvas inputs and disclosed ordinary paid protocol policy are separate from root CUA play. Exact endpoint redirected to loopback; command sequence normalized; no state, grants, time or result injected.':'Two isolated actual deployed-browser contexts; UI lobby/keyboard actions plus disclosed test-only ordinary paid WebSocket policy. Only command sequence is normalized. No direct gameplay state, grants, time changes or forced result.'});
  const capture=async(c,label)=>{const name=c.role+'-'+String(label).replace(/[^a-zA-Z0-9_-]/g,'_')+'.png',filename=path.join(out,name);if(fs.existsSync(filename))throw Error('Capture already exists; use a new label');await c.page.screenshot({path:filename});const receipt={name,path:filename,sha256:digest(fs.readFileSync(filename)),unix:Date.now()};c.captures.push(receipt);append(c.role+'-captures.jsonl',receipt);return receipt;};
  const canvasInput=async(c,point,purpose)=>{const viewport=c.page.viewportSize();if(!point||!Number.isFinite(point.x)||!Number.isFinite(point.y)||point.x<0||point.y<0||point.x>=viewport.width||point.y>=viewport.height)throw Error('Supply observed canvas coordinates inside the current viewport');let receipt;if(beta2){receipt=await nativeTap(c.touchCDP,point,purpose,viewport);}else{if(inputMode==='touch')await c.page.touchscreen.tap(point.x,point.y);else await c.page.mouse.click(point.x,point.y);receipt={unix:Date.now(),kind:inputMode==='touch'?'tap':'click',purpose,x:point.x,y:point.y};}c.browserInputs.push(receipt);append(c.role+'-browser-input.jsonl',receipt);return receipt;};
  const identityMatches=c=>c.matched&&c.last&&c.matched.protocol===expectedProtocol&&c.room?.protocol===expectedProtocol&&JSON.stringify(c.matched.civilizations)===JSON.stringify(expectedIds)&&JSON.stringify(c.last.civilizations)===JSON.stringify(expectedIds)&&c.last.player?.civilization===expectations[c.role].id&&c.matched.civilizations[c.matched.slot]===expectations[c.role].id&&c.room?.players===2&&JSON.stringify(c.room.civilizations)===JSON.stringify(expectedIds)&&c.lobbyRequests.some(p=>['host','join','search'].includes(p.op)&&p.protocol===expectedProtocol)&&c.lobbyRequests.at(-1)?.civilization===expectations[c.role].id;
  const assetTasks=[];
  for(const role of ['host','guest']) {
    const context=await browser.newContext({viewport:{width:Number(arg('width')||((localMode||beta2)?844:1600)),height:Number(arg('height')||((localMode||beta2)?390:900))},deviceScaleFactor:1,hasTouch:inputMode==='touch',...(localMode?{serviceWorkers:'block'}:{})});
    if(localMode) {
      await configureLocalGuards(context,local.matchUrl,url,event=>append(role+'-endpoint-guard.jsonl',event));
    }
    await context.exposeBinding('__pocketHarnessEvent',(_source,event)=>{if(['socket_route','command_origin'].includes(event.kind))append(role+'-'+event.kind+'.jsonl',event);});
    await context.addInitScript(installWitness,{local:localMode,matchUrl:local?.matchUrl});const page=await context.newPage();
    if(!localMode){const cdp=await context.newCDPSession(page);await cdp.send('Network.enable',{maxTotalBufferSize:268435456,maxResourceBufferSize:134217728});}
    const client=clients[role]={role,page,context,touchCDP:beta2?await context.newCDPSession(page):null,beta2,beta2SiegeDone:false,beta2Reviewed:false,objectiveOnly,policy:false,last:null,matched:null,room:null,ended:null,started:0,
      errors:[],warnings:[],rejections:[],lastBuild:-10,lastArmy:-60,demolished:false,rejectedPlacements:new Set(),pendingPlace:null,uiChecks:[],captures:[],browserInputs:[],recruitAttempts:[],paidRecruitReviewed:false,policyEver:false,civilizationSelection:null,lobbyRequests:[],endedAt:null};
    page.on('console',message=>{const entry={type:message.type(),text:message.text(),unix:Date.now()};append(role+'-console.jsonl',entry);if(entry.type==='error')client.errors.push(entry);if(entry.type==='warning')client.warnings.push(entry);});
    page.on('pageerror',error=>{const entry={type:'pageerror',text:String(error),unix:Date.now()};client.errors.push(entry);append(role+'-console.jsonl',entry);});
    page.on('response',response=>{if(response.status()>=400)append(role+'-http-errors.jsonl',{url:response.url(),status:response.status()});
      if(/\.(pck|wasm|js)(\?|$)|\/(build-info|version)\.json(\?|$)/.test(response.url())) {
        append(role+'-assets.jsonl',{url:response.url(),status:response.status(),unix:Date.now(),from_service_worker:response.fromServiceWorker(),headers:response.headers()});
        if(localMode&&response.status()===200){const headers=response.headers();append(role+'-asset-server-proof.jsonl',{url:response.url(),file:decodeURIComponent(new URL(response.url()).pathname).slice(1),status:200,request_id:headers['x-pocket-request-id'],sha256:headers['x-pocket-artifact-sha256'],bytes:Number(headers['content-length']),proof:'Browser response headers correlated with owned server exact-byte log; distinct from CDP response.body hash'});}
        if(response.status()===200)assetTasks.push(response.body().then(bytes=>{
          const name=decodeURIComponent(new URL(response.url()).pathname).slice(1),sha256=digest(bytes),expected=(local?.source.artifact||publicProof.artifact).files[name];
          const record={unix:Date.now(),url:response.url(),file:name,bytes:bytes.length,sha256,expected,match:sha256===expected};
          append(role+'-asset-bytes.jsonl',record);if(expected&&!record.match)client.errors.push({type:'artifact-bytes',...record});
        }).catch(error=>append(role+'-asset-body-failures.jsonl',{unix:Date.now(),url:response.url(),error:String(error)})));
      }});
    page.on('requestfinished',request=>{if(/\.(pck|wasm|js)(\?|$)/.test(request.url()))append(role+'-asset-finished.jsonl',{url:request.url(),unix:Date.now()});});
    page.on('framenavigated',frame=>{if(frame===page.mainFrame())append(role+'-navigation.jsonl',{url:frame.url(),unix:Date.now()});});
    page.on('requestfailed',request=>append(role+'-request-failures.jsonl',{url:request.url(),error:request.failure(),unix:Date.now()}));
    page.on('websocket',socket=>{
      append(role+'-transport.jsonl',{event:'open',url:socket.url(),unix:Date.now()});
      socket.on('framesent',event=>{let packet;try{packet=JSON.parse(String(event.payload));}catch(_){return;}append(role+'-sent.jsonl',{unix:Date.now(),packet});if(['host','join','search','room_civilization'].includes(packet.op))client.lobbyRequests.push(packet);});
      socket.on('framereceived',event=>{let packet;try{packet=JSON.parse(String(event.payload));}catch(_){return;}
        if(packet.op==='snapshot') {client.last=packet;if(beta2)append(role+'-authority-full.jsonl',{unix:Date.now(),packet});if(packet.tick%10===0)append(role+'-snapshots.jsonl',{unix:Date.now(),wall:(performance.now()-client.started)/1000,packet});}
        else {append(role+'-transport.jsonl',{event:'packet',unix:Date.now(),packet});if(packet.op==='room')client.room=packet;
          if(packet.op==='matched'){client.matched=packet;client.beta2SiegeDone=false;client.beta2Reviewed=false;}if(packet.op==='started')client.started=performance.now();
          if(packet.op==='ended'){client.endedAt=Date.now();client.ended={...packet,match_wall_seconds:(performance.now()-client.started)/1000};client.policy=false;save(role+'-terminal.json',{received_unix:client.endedAt,matched:client.matched,ended:client.ended,last:client.last});}
          if(packet.op==='rejected'){client.rejections.push(packet);if(client.pendingPlace&&/clear|reach|Outside/.test(packet.reason)){client.rejectedPlacements.add(client.pendingPlace.key);client.pendingPlace=null;}}}
      });
      socket.on('close',()=>append(role+'-transport.jsonl',{event:'close',unix:Date.now()}));
      socket.on('socketerror',error=>{client.errors.push({type:'socketerror',text:String(error)});append(role+'-transport.jsonl',{event:'error',error:String(error),unix:Date.now()});});
    });
    await page.goto(url,{waitUntil:'domcontentloaded'});
    save(role+'-browser-capabilities.json',await page.evaluate(()=>({width:innerWidth,height:innerHeight,max_touch_points:navigator.maxTouchPoints,coarse_pointer:matchMedia('(pointer: coarse)').matches,scope:'Read-only browser capabilities; no physical-device claim'})));
  }
  let running=false,uiBusy=false;
  const beta2Controller=createBeta2Controller({clients,capture,input:canvasInput,append,policyBusy:()=>running});
  const marchController=createMarchController({clients,capture,input:canvasInput,append,policyBusy:()=>running,output:out});
  const garrisonController=createGarrisonController({clients,capture,input:canvasInput,append,policyBusy:()=>running,output:out});
  const timer=controllerTimer=setInterval(async()=>{if(running||uiBusy)return;running=true;try{for(const c of Object.values(clients)){const phase=c.beta2?(c.beta2SiegeDone?'normal-paid-policy':c.last?.player?.age>=2?'saving-for-touch-workshop-and-siege':'normal-paid-opening'):null;if(phase&&phase!==c.beta2PolicyPhase){append('beta2-policy-phases.jsonl',{unix:Date.now(),role:c.role,game_seconds:c.last?.time,phase});c.beta2PolicyPhase=phase;}for(const cmd of planPolicy(c)) {
    const sent=await c.page.evaluate(({command,payload})=>window.__aoemLiveWitness.sendCommand(command,payload),cmd);
    append(c.role+'-policy.jsonl',{unix:Date.now(),game_seconds:c.last?.time,...cmd,sent});
  }}}catch(error){append('controller-errors.jsonl',{unix:Date.now(),error:String(error)});}finally{running=false;}},2000);
  const status=()=>Object.fromEntries(Object.values(clients).map(c=>[c.role,{room:c.room,matched:c.matched,ended:c.ended,
    game_seconds:c.last?.time,wall:c.started?(performance.now()-c.started)/1000:0,bank:c.last?.bank,player:c.last?.player,stats:c.last?.stats,battle:c.last?.battle,
    civilizations:c.last?.civilizations,civilization_selection:c.civilizationSelection,expected_civilization:expectations[c.role],policy:c.policy,policy_ever:c.policyEver,paid_recruit_reviewed:c.paidRecruitReviewed,beta2_siege_done:c.beta2SiegeDone,beta2_reviewed:c.beta2Reviewed,errors:c.errors,warnings:c.warnings.slice(-8),rejections:c.rejections.length,pendingPlace:c.pendingPlace,uiChecks:c.uiChecks,captures:c.captures}]));
  const server=controllerServer=http.createServer(async(req,res)=>{try{
    let body='';for await(const chunk of req)body+=chunk;const data=body?JSON.parse(body):{};if(uiBusy&&!['/state','/page'].includes(req.url))throw Error('Wait for the isolated beta2 UI step');const c=clients[data.role||'host'];let result;
    if(req.url==='/state')result=status();
    else if(req.url==='/garrison'){if(!garrison)throw Error('Use --garrison for postpurchase objective acceptance');if(uiBusy)throw Error('Another UI step is in flight');uiBusy=true;try{result=await garrisonController.handle(c,data);}finally{uiBusy=false;}}
    else if(req.url==='/march'){if(!cohesion)throw Error('Use --cohesion for the optional paid march acceptance');if(uiBusy)throw Error('Another UI step is in flight');uiBusy=true;try{result=await marchController.handle(c,data);}finally{uiBusy=false;}}
    else if(req.url==='/beta2'){if(!beta2)throw Error('Use --beta2 for these acceptance steps');if(uiBusy)throw Error('Another UI step is in flight');uiBusy=true;try{result=await beta2Controller.handle(c,data);}finally{uiBusy=false;}}
    else if(req.url==='/viewport'){await c.page.setViewportSize({width:Number(data.width),height:Number(data.height)});append(c.role+'-browser-input.jsonl',{unix:Date.now(),kind:'viewport',...data});result={resized:true};}
    else if(req.url==='/page')result=await c.page.evaluate(()=>({url:location.href,title:document.title,text:document.body.innerText,canvases:Array.from(document.querySelectorAll('canvas')).map(e=>({id:e.id,width:e.width,height:e.height,rect:e.getBoundingClientRect().toJSON()})),buttons:Array.from(document.querySelectorAll('button')).map(e=>({text:e.innerText,id:e.id,disabled:e.disabled,rect:e.getBoundingClientRect().toJSON()}))}));
    else if(req.url==='/capture')result=await capture(c,data.label||'capture');
    else if(req.url==='/input') {if(uiBusy)throw Error('A beta2 UI proof is in flight');if(data.kind==='click'||data.kind==='tap'){if(data.kind==='tap'&&inputMode!=='touch')throw Error('Native browser taps require --touch');if(inputMode==='touch'&&data.button&&data.button!=='left')throw Error('Touch mode has no mouse right-click');if(beta2){result=await canvasInput(c,data,data.purpose||'operator_tap');}else if(inputMode==='touch')await c.page.touchscreen.tap(data.x,data.y);else await c.page.mouse.click(data.x,data.y,{button:data.button||'left'});data.kind=inputMode==='touch'?'tap':'click';}
      else if(data.kind==='press')await c.page.keyboard.press(data.key);else if(data.kind==='type')await c.page.keyboard.type(data.text);
      else if(data.kind==='scroll'){if(inputMode==='touch')throw Error('Mouse wheel is not a touch gesture; do not claim a touch path with mouse fallback');await c.page.mouse.wheel(data.x||0,data.y||0);}else throw new Error('Unknown input kind');if(!result){const input={...data,unix:Date.now()};c.browserInputs.push(input);append(c.role+'-browser-input.jsonl',input);result={sent:true};}}
    else if(req.url==='/civilization-ui') {
      if(c.matched||c.policy)throw Error('Choose the kingdom in the real menu/lobby before matching');
      const selected=civilization(data.civilization);assert.equal(selected.id,expectations[c.role].id,'Picker selection must match this invocation expectation');
      const label='civilization-'+Date.now(),images=[];
      images.push(await capture(c,label+'-before'));
      await canvasInput(c,data.open,'civilization_picker_open');await c.page.waitForTimeout(150);
      await canvasInput(c,data.choice,'civilization_picker_choice');await c.page.waitForTimeout(150);images.push(await capture(c,label+'-choice'));
      await canvasInput(c,data.confirm,'civilization_picker_confirm');await c.page.waitForTimeout(150);images.push(await capture(c,label+'-confirmed'));
      result=c.civilizationSelection={selected,input_mode:inputMode,unix:Date.now(),performed:true,received_identity_verified:false,captures:images};append(c.role+'-civilization-ui.jsonl',result);
    }
    else if(req.url==='/civilization-check'){if(!c.civilizationSelection||!identityMatches(c))throw Error('Actual matching-protocol lobby/matched/snapshot identities do not confirm the observed picker choice');if(data.reviewed!==true||data.observed_name!==expectations[c.role].name)throw Error('Inspect the captured picker and transcribe its selected kingdom name');result={passed:true,reviewed:true,observed_name:data.observed_name,selected:expectations[c.role],slot:c.matched.slot,room:c.room,matched:c.matched,snapshot_civilizations:c.last.civilizations,own_civilization:c.last.player.civilization};c.civilizationIdentityReviewed=true;append(c.role+'-civilization-identity.jsonl',result);}
    else if(req.url==='/recruit-ui') {
      if(Object.values(clients).some(client=>client.policy||client.policyEver)||!c.matched||!c.last||c.ended)throw Error('Paid recruitment witness must precede the first policy start on both clients');
      const attempt='recruit-'+Date.now(),images=[];
      images.push(await capture(c,attempt+'-before'));
      const before=structuredClone(c.last),start=await c.page.evaluate(()=>window.__aoemLiveWitness.state.commandSerial);
      append(c.role+'-recruit-snapshots.jsonl',{attempt,stage:'before',packet:before});
      const input=await canvasInput(c,data.button,'paid_recruit_villager');
      let evidence,proof,after,error='No matching UI train command or accepted paid queue';
      for(let retry=0;retry<80;retry++) {
        const commands=await c.page.evaluate(serial=>window.__aoemLiveWitness.state.sends.filter(e=>e.serial>serial),start);
        if(commands.length>1){error='Concurrent commands make this one-purchase witness ambiguous';break;}
        evidence=commands[0];after=structuredClone(c.last);
        try {proof=paidVillagerRecruitment(before,after,c.matched.slot,evidence);break;} catch(failure){error=String(failure.message);}
        await new Promise(resolve=>setTimeout(resolve,50));
      }
      append(c.role+'-recruit-snapshots.jsonl',{attempt,stage:'after',packet:after});
      images.push(await capture(c,attempt+'-after'));
      result={attempt,passed:!!proof,unix:Date.now(),input_mode:inputMode,policy_ever:false,slot:c.matched.slot,input,evidence,proof,before,after,captures:images,error:proof?null:error,scope:'Actual native browser input, passive authority queue/reservation/bank receipts; normal deposits are accounted for, never injected'};
      c.recruitAttempts.push(result);append(c.role+'-recruit-ui.jsonl',result);
      if(!proof)throw Error('Paid UI recruitment witness failed: '+error);
    }
    else if(req.url==='/recruit-review') {
      const attempt=c.recruitAttempts.find(row=>row.attempt===data.attempt);
      if(data.reviewed!==true||!attempt?.passed||c.policyEver)throw Error('Review the successful before-policy recruitment captures first');
      for(const image of attempt.captures)assert.equal(digest(fs.readFileSync(image.path)),image.sha256,'Recruitment capture changed');
      const observed=data.observed||{};
      assert.equal(observed.unit,'Villager');assert.equal(observed.cost_food,50);assert.equal(observed.queue_count,1);
      for(const resource of ['food','wood','gold']) {assert.equal(observed.before_bank?.[resource],attempt.before.bank[resource],'Transcribe the actual pre-tap bank');assert.equal(observed.after_bank?.[resource],attempt.after.bank[resource],'Transcribe the actual post-tap bank');}
      result={check:'paid_recruit_review',attempt:attempt.attempt,passed:true,reviewed:true,unix:Date.now(),input_mode:inputMode,observed,captures:attempt.captures};
      c.paidRecruitReviewed=true;c.uiChecks.push(result);append(c.role+'-recruit-reviews.jsonl',result);
    }
    else if(req.url==='/attack-ui') {
      if(Object.values(clients).some(client=>client.policy)||!c.matched||c.ended)throw new Error('Stop paid policy and select a living armed unit before the Attack HUD check');
      for(const point of [data.button,data.destination])if(!point||!Number.isFinite(point.x)||!Number.isFinite(point.y))throw new Error('Supply observed Attack-button and ground coordinates');
      const before=await c.page.evaluate(()=>window.__aoemLiveWitness.state.commandSerial);
      const label='attack-hud-'+Date.now();
      await c.page.screenshot({path:path.join(out,c.role+'-'+label+'-before.png')});
      await canvasInput(c,data.button,'observed_attack_hud_button');
      await c.page.screenshot({path:path.join(out,c.role+'-'+label+'-armed.png')});
      await canvasInput(c,data.destination,'attack_move_ground_destination');
      let evidence;
      for(let retry=0;retry<60;retry++) {
        evidence=await c.page.evaluate(start=>window.__aoemLiveWitness.state.sends.find(e=>e.serial>start&&e.source==='game_ui_or_engine'&&e.packet.command==='attack_move'),before);
        if(evidence)break;await new Promise(resolve=>setTimeout(resolve,50));
      }
      await c.page.screenshot({path:path.join(out,c.role+'-'+label+'-after.png')});
      const receipt={check:'attack_hud',passed:!!evidence,unix:Date.now(),input_mode:inputMode,scope:'Automated browser native canvas input at observed HUD/ground coordinates; actual game-generated command verified; distinct from root CUA play',evidence,screenshots:[c.role+'-'+label+'-before.png',c.role+'-'+label+'-armed.png',c.role+'-'+label+'-after.png']};
      c.uiChecks.push(receipt);append(c.role+'-attack-ui.jsonl',receipt);
      if(!evidence)throw new Error('HUD clicks produced no game-generated attack_move command; A key or ordinary movement is not accepted');
      result=receipt;
    }
    else if(req.url==='/start-policy'){if(uiBusy||running)throw Error('Wait for the current UI/policy operation');if(beta2&&(!data.reason||String(data.reason).trim().length<12))throw Error('Disclose the reason for starting/resuming the scripted policy');if(!Object.values(clients).every(c=>c.matched&&c.last&&!c.ended&&c.civilizationSelection&&c.civilizationIdentityReviewed&&identityMatches(c)))throw new Error('Both reviewed real picker choices and matching-protocol room/matched/snapshot civilizations must agree before paid policy');if(inputMode==='touch'&&!Object.values(clients).every(c=>c.paidRecruitReviewed))throw Error('Touch acceptance requires reviewed real tap recruitment with paid bank/queue proof on both clients before policy');Object.values(clients).forEach(c=>{c.policy=true;c.policyEver=true;});append('policy-starts.jsonl',{unix:Date.now(),input_mode:inputMode,roles:Object.keys(clients),reason:data.reason||null,game_seconds:Object.fromEntries(Object.values(clients).map(c=>[c.role,c.last?.time]))});result={started:true};}
    else if(req.url==='/stop-policy'){if(beta2&&(!data.reason||String(data.reason).trim().length<12))throw Error('Disclose the reason for this ordinary-policy pause');Object.values(clients).forEach(c=>c.policy=false);const deadline=Date.now()+5000;while(running&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,25));if(running)throw Error('Policy send loop has not quiesced');const row={unix:Date.now(),reason:data.reason||null,game_seconds:Object.fromEntries(Object.values(clients).map(c=>[c.role,c.last?.time])),scope:'Stops scripted commands only; simulation, harvesting and paid queues continue'};append('policy-pauses.jsonl',row);result={stopped:true,...row};}
    else if(req.url==='/ui-check'){c.uiChecks.push({...data,unix:Date.now(),scope:'Operator screenshot/input verification'});result={recorded:true};}
    else if(req.url==='/review-screen') {
      if(data.reviewed!==true||!c.ended)throw Error('Review an actual captured post-terminal screen first');
      const image=c.captures.find(item=>item.name===data.capture);if(!image||image.unix<c.endedAt||digest(fs.readFileSync(image.path))!==image.sha256)throw Error('Review needs an unchanged captured image after this terminal');
      const observed=data.observed||{};let expected;
      if(data.kind==='result') {expected=resultExpectation(c);assert.equal(observed.result,expected.result);assert.equal(observed.reason,expected.reason);assert.deepEqual(observed.counts,expected.counts);assert.equal(observed.lesson_status,expected.lesson.status);assert.equal(String(observed.lesson_text??'').replace(/\s+/g,' ').trim(),expected.lesson.text);}
      else if(data.kind==='menu') {assert(c.uiChecks.some(check=>check.check==='result_review'&&check.passed));assert(Array.isArray(observed.actions)&&['New Game','Join a friend'].every(text=>observed.actions.includes(text)),'Record the actual visible Home actions');}
      else throw Error('Review kind must be result or menu');
      result={check:data.kind==='result'?'result_review':'menu_return',passed:true,scope:'Operator inspected actual captured pixels and transcribed visible text/counts; checked against recipient authority facts',image,observed,expected,unix:Date.now()};c.uiChecks.push(result);append(c.role+'-screen-reviews.jsonl',result);
    }
    else if(req.url==='/save'){await Promise.allSettled(assetTasks);save('controller-state.json',status());result={saved:true};}
    else if(req.url==='/shutdown'){Object.values(clients).forEach(c=>c.policy=false);await Promise.allSettled(assetTasks);save('controller-state.json',status());clearInterval(timer);await browser.close();if(local)await local.stop();result={closed:true};setImmediate(()=>server.close());}
    else throw new Error('Unknown endpoint');
    res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(result));
  }catch(error){res.writeHead(400,{'Content-Type':'application/json'});res.end(JSON.stringify({error:String(error)}));}});
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',resolve);});
  console.log(JSON.stringify({ready:true,controller:`http://127.0.0.1:${port}`,output:out,scope:'No match or policy starts automatically. Use actual browser inputs for the lobby.'}));
  let stopping=false;
  const stop=async()=>{if(stopping)return;stopping=true;clearInterval(timer);save('controller-state.json',status());await browser.close();server.close();if(local)await local.stop();};
  process.on('SIGTERM',stop);process.on('SIGINT',stop);
  } catch(error) {if(controllerTimer)clearInterval(controllerTimer);if(controllerServer?.listening)controllerServer.close();if(browser)await browser.close();if(local)await local.stop();throw error;}
}

if(require.main===module)main().catch(error=>{console.error(error);process.exitCode=1;});
module.exports={installWitness,planPolicy,placementCandidate,configureLocalGuards};
