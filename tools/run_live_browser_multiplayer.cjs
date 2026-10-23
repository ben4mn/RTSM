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

function installWitness() {
  const Native = window.WebSocket;
  const sockets = [];
  const state = {room: null, matched: null, last: null, ended: null, startedWall: null,
    messages: [], sends: [], counters: {}, ready: false};
  function parse(data) {
    try { return JSON.parse(typeof data === 'string' ? data : new TextDecoder().decode(data)); }
    catch (_) { return null; }
  }
  class WitnessSocket extends Native {
    constructor(...args) {
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
        state.sends.push({wall: performance.now(), originalSequence, packet});
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
      socket.send(JSON.stringify({...payload, op: 'command', command, sequence: 0, match: state.matched.match}));
      return true;
    },
  };
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
  const army=own.filter(a=>a.kind==='unit'&&a.type!==0).map(a=>a.id);
  const buildings=own.filter(a=>a.kind==='building'), active=t=>buildings.find(a=>a.type===t&&a.state===2);
  const count=t=>buildings.filter(a=>a.type===t).length, queued=a=>a?.queue?.items?.length||0;
  const bank={...d.bank}, commands=[], send=(command,payload={})=>commands.push({command,payload});
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
    else if(count(5)<(t>700?6:2)&&t>100)type=5;
    else if(!count(3)&&d.player.age>=2)type=3;
    else if(!count(4)&&d.player.age>=2)type=4;
    else if(!count(8)&&d.player.age>=3)type=8;
    if(type>=0&&afford(bank,buildingCosts[type])) {
      const candidate=placementCandidate(d,m.slot,town,type,client.rejectedPlacements);
      if(candidate) {send('place',{type,ids:[workers[0].id],position:candidate.position});spend(bank,buildingCosts[type]);
        client.pendingPlace={...candidate,type,time:t};client.lastBuild=t;}
    }
  }
  const ageCost=d.player.age===1?{food:250,gold:125}:d.player.age===2?{food:600,gold:300}:null;
  if(ageCost&&afford(bank,ageCost)){send('age');spend(bank,ageCost);}
  const smith=active(9);
  if(smith)for(const tech of techs)if(!d.research.includes(tech.id)&&afford(bank,tech.cost)){send('research',{target:smith.id,research:tech.id});spend(bank,tech.cost);break;}
  const reserve=d.player.age>=3||t<180?0:d.player.age===1?260:620;
  const emergency=t<180||d.player.age>=3?3:0;
  if(army.length<12&&(bank.food>reserve||army.length<emergency))for(const [buildingType,unitType] of [[2,1],[3,2],[4,3],[8,5]]) {
    const b=active(buildingType);if(b&&queued(b)<1&&afford(bank,unitCosts[unitType])) {send('train',{target:b.id,type:unitType});spend(bank,unitCosts[unitType]);}
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
  if(!process.argv.includes('--allow-public'))throw new Error('Root must explicitly launch with --allow-public after deployment readiness.');
  let modulePath=arg('playwright-module');
  if(!modulePath){try{modulePath=require.resolve('playwright');}catch(_){
    const cache=path.join(process.env.HOME,'.npm/_npx');
    modulePath=fs.readdirSync(cache).map(n=>path.join(cache,n,'node_modules/playwright')).find(p=>fs.existsSync(path.join(p,'package.json')));
  }}
  const {chromium}=require(modulePath);
  const out=path.resolve(arg('output')||'output/playwright/live-multiplayer');
  fs.mkdirSync(out,{recursive:true});if(fs.existsSync(path.join(out,'invocation.json')))throw new Error('Use a new output directory.');
  const url=arg('url')||'https://game.4mn.org/',port=Number(arg('port')||8876),clients={};
  const browser=await chromium.launch({channel:'chrome',headless:false,args:['--disable-background-timer-throttling','--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding']});
  const save=(name,value)=>fs.writeFileSync(path.join(out,name),JSON.stringify(value,null,2)+'\n');
  const append=(name,value)=>fs.appendFileSync(path.join(out,name),JSON.stringify(value)+'\n');
  const objectiveOnly=process.argv.includes('--objective-only');
  save('invocation.json',{url,port,started:new Date().toISOString(),headless:false,scenario:objectiveOnly?'objective':'full',harness_sha256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex'),browser_version:browser.version(),scope:'Two isolated actual deployed-browser contexts; UI lobby/keyboard actions plus disclosed test-only ordinary paid WebSocket policy. Only command sequence is normalized. No direct gameplay state, grants, time changes or forced result.'});
  for(const role of ['host','guest']) {
    const context=await browser.newContext({viewport:{width:Number(arg('width')||1600),height:Number(arg('height')||900)},deviceScaleFactor:1});
    await context.addInitScript(installWitness);const page=await context.newPage();
    const client=clients[role]={role,page,context,objectiveOnly,policy:false,last:null,matched:null,room:null,ended:null,started:0,
      errors:[],warnings:[],rejections:[],lastBuild:-10,lastArmy:-60,demolished:false,rejectedPlacements:new Set(),pendingPlace:null,uiChecks:[]};
    page.on('console',message=>{const entry={type:message.type(),text:message.text(),unix:Date.now()};append(role+'-console.jsonl',entry);if(entry.type==='error')client.errors.push(entry);if(entry.type==='warning')client.warnings.push(entry);});
    page.on('pageerror',error=>{const entry={type:'pageerror',text:String(error),unix:Date.now()};client.errors.push(entry);append(role+'-console.jsonl',entry);});
    page.on('response',response=>{if(response.status()>=400)append(role+'-http-errors.jsonl',{url:response.url(),status:response.status()});
      if(/\.(pck|wasm|js)(\?|$)|\/build-info\.json(\?|$)/.test(response.url()))append(role+'-assets.jsonl',{url:response.url(),status:response.status(),unix:Date.now(),from_service_worker:response.fromServiceWorker(),headers:response.headers()});});
    page.on('requestfinished',request=>{if(/\.(pck|wasm|js)(\?|$)/.test(request.url()))append(role+'-asset-finished.jsonl',{url:request.url(),unix:Date.now()});});
    page.on('framenavigated',frame=>{if(frame===page.mainFrame())append(role+'-navigation.jsonl',{url:frame.url(),unix:Date.now()});});
    page.on('requestfailed',request=>append(role+'-request-failures.jsonl',{url:request.url(),error:request.failure(),unix:Date.now()}));
    page.on('websocket',socket=>{
      append(role+'-transport.jsonl',{event:'open',url:socket.url(),unix:Date.now()});
      socket.on('framesent',event=>{let packet;try{packet=JSON.parse(String(event.payload));}catch(_){return;}append(role+'-sent.jsonl',{unix:Date.now(),packet});});
      socket.on('framereceived',event=>{let packet;try{packet=JSON.parse(String(event.payload));}catch(_){return;}
        if(packet.op==='snapshot') {client.last=packet;if(packet.tick%10===0)append(role+'-snapshots.jsonl',{unix:Date.now(),wall:(performance.now()-client.started)/1000,packet});}
        else {append(role+'-transport.jsonl',{event:'packet',unix:Date.now(),packet});if(packet.op==='room')client.room=packet;
          if(packet.op==='matched')client.matched=packet;if(packet.op==='started')client.started=performance.now();
          if(packet.op==='ended'){client.ended={...packet,match_wall_seconds:(performance.now()-client.started)/1000};client.policy=false;save(role+'-terminal.json',{matched:client.matched,ended:client.ended,last:client.last});}
          if(packet.op==='rejected'){client.rejections.push(packet);if(client.pendingPlace&&/clear|reach|Outside/.test(packet.reason)){client.rejectedPlacements.add(client.pendingPlace.key);client.pendingPlace=null;}}}
      });
      socket.on('close',()=>append(role+'-transport.jsonl',{event:'close',unix:Date.now()}));
      socket.on('socketerror',error=>{client.errors.push({type:'socketerror',text:String(error)});append(role+'-transport.jsonl',{event:'error',error:String(error),unix:Date.now()});});
    });
    await page.goto(url,{waitUntil:'domcontentloaded'});
  }
  let running=false;
  const timer=setInterval(async()=>{if(running)return;running=true;try{for(const c of Object.values(clients))for(const cmd of planPolicy(c)) {
    const sent=await c.page.evaluate(({command,payload})=>window.__aoemLiveWitness.sendCommand(command,payload),cmd);
    append(c.role+'-policy.jsonl',{unix:Date.now(),game_seconds:c.last?.time,...cmd,sent});
  }}catch(error){append('controller-errors.jsonl',{unix:Date.now(),error:String(error)});}finally{running=false;}},2000);
  const status=()=>Object.fromEntries(Object.values(clients).map(c=>[c.role,{room:c.room,matched:c.matched,ended:c.ended,
    game_seconds:c.last?.time,wall:c.started?(performance.now()-c.started)/1000:0,bank:c.last?.bank,player:c.last?.player,stats:c.last?.stats,
    policy:c.policy,errors:c.errors,warnings:c.warnings.slice(-8),rejections:c.rejections.length,pendingPlace:c.pendingPlace,uiChecks:c.uiChecks}]));
  const server=http.createServer(async(req,res)=>{try{
    let body='';for await(const chunk of req)body+=chunk;const data=body?JSON.parse(body):{};const c=clients[data.role||'host'];let result;
    if(req.url==='/state')result=status();
    else if(req.url==='/viewport'){await c.page.setViewportSize({width:Number(data.width),height:Number(data.height)});append(c.role+'-browser-input.jsonl',{unix:Date.now(),kind:'viewport',...data});result={resized:true};}
    else if(req.url==='/page')result=await c.page.evaluate(()=>({url:location.href,title:document.title,text:document.body.innerText,canvases:Array.from(document.querySelectorAll('canvas')).map(e=>({id:e.id,width:e.width,height:e.height,rect:e.getBoundingClientRect().toJSON()})),buttons:Array.from(document.querySelectorAll('button')).map(e=>({text:e.innerText,id:e.id,disabled:e.disabled,rect:e.getBoundingClientRect().toJSON()}))}));
    else if(req.url==='/capture'){const label=String(data.label||'capture').replace(/[^a-zA-Z0-9_-]/g,'_');const filename=path.join(out,`${c.role}-${label}.png`);await c.page.screenshot({path:filename});result={path:filename};}
    else if(req.url==='/input') {if(data.kind==='click')await c.page.mouse.click(data.x,data.y,{button:data.button||'left'});
      else if(data.kind==='press')await c.page.keyboard.press(data.key);else if(data.kind==='type')await c.page.keyboard.type(data.text);
      else if(data.kind==='scroll')await c.page.mouse.wheel(data.x||0,data.y||0);else throw new Error('Unknown input kind');append(c.role+'-browser-input.jsonl',{unix:Date.now(),...data});result={sent:true};}
    else if(req.url==='/start-policy'){if(!Object.values(clients).every(c=>c.matched&&c.last&&!c.ended))throw new Error('Both real UI-created clients must be playing first');Object.values(clients).forEach(c=>c.policy=true);result={started:true};}
    else if(req.url==='/stop-policy'){Object.values(clients).forEach(c=>c.policy=false);result={stopped:true};}
    else if(req.url==='/ui-check'){c.uiChecks.push({...data,unix:Date.now(),scope:'Operator screenshot/input verification'});result={recorded:true};}
    else if(req.url==='/save'){save('controller-state.json',status());result={saved:true};}
    else if(req.url==='/shutdown'){Object.values(clients).forEach(c=>c.policy=false);save('controller-state.json',status());clearInterval(timer);await browser.close();result={closed:true};setImmediate(()=>server.close());}
    else throw new Error('Unknown endpoint');
    res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(result));
  }catch(error){res.writeHead(400,{'Content-Type':'application/json'});res.end(JSON.stringify({error:String(error)}));}});
  await new Promise(resolve=>server.listen(port,'127.0.0.1',resolve));
  console.log(JSON.stringify({ready:true,controller:`http://127.0.0.1:${port}`,output:out,scope:'No match or policy starts automatically. Use actual browser inputs for the lobby.'}));
  process.on('SIGTERM',async()=>{clearInterval(timer);save('controller-state.json',status());await browser.close();server.close();});
}

if(require.main===module)main().catch(error=>{console.error(error);process.exitCode=1;});
module.exports={installWitness,planPolicy,placementCandidate};
