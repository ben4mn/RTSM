'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {installWitness,configureLocalGuards,planPolicy}=require('./run_live_browser_multiplayer.cjs');
const {digest,manifestEntries,verifyTree,verifyPair}=require('./local_browser_runtime.cjs');

function witness(configuration={}) {
  const constructed=[],events=[];
  class Socket extends EventTarget {
    static OPEN=1;
    constructor(...args){super();constructed.push(args);this.readyState=1;this.wire=[];}
    send(data){this.wire.push(JSON.parse(typeof data==='string'?data:new TextDecoder().decode(data)));}
  }
  const sandbox={window:{WebSocket:Socket,__pocketHarnessEvent:async event=>events.push(event)},URL,Date,TextDecoder,TextEncoder,performance,EventTarget,configuration};
  vm.runInNewContext(`(${installWitness.toString()})(configuration)`,sandbox);
  return {sandbox,constructed,events};
}

function packet(socket,data) {const event=new Event('message');Object.defineProperty(event,'data',{value:JSON.stringify(data)});socket.dispatchEvent(event);}

test('local routing changes exactly one endpoint and blocks every unapproved native socket',()=>{
  const target='ws://127.0.0.1:12345/match';
  const {sandbox,constructed,events}=witness({local:true,matchUrl:target});
  const socket=new sandbox.window.WebSocket('wss://game.4mn.org/match',['json']);
  assert.equal(constructed[0][0],target);assert.deepEqual(constructed[0][1],['json']);
  new sandbox.window.WebSocket(target);
  for(const url of ['wss://game.4mn.org/match?x=1','wss://game.4mn.org:443/match','wss://game.4mn.org/other','ws://127.0.0.1:12346/match','ws://localhost:12345/match','wss://example.invalid/match'])assert.throws(()=>new sandbox.window.WebSocket(url),/blocked/);
  assert.equal(constructed.length,2);assert.equal(events.filter(e=>e.blocked).length,6);
  socket.send(JSON.stringify({op:'host',protocol:2,civilization:2,map_archetype:1}));
  assert.deepEqual(socket.wire[0],{op:'host',protocol:2,civilization:2,map_archetype:1});
});

test('invalid local destination fails before any native socket can be created',()=>{
  for(const target of ['wss://game.4mn.org/match','ws://127.0.0.1.evil.invalid:80/match','ws://user@127.0.0.1:80/match','ws://127.0.0.1:80/match?x=1','ws://localhost:80/match'])assert.throws(()=>witness({local:true,matchUrl:target}),/loopback/);
});

test('game UI attack-move is distinguishable from paid policy and survives bounded history rotation',()=>{
  const {sandbox}=witness({local:true,matchUrl:'ws://127.0.0.1:12345/match'});
  const socket=new sandbox.window.WebSocket('wss://game.4mn.org/match');
  packet(socket,{op:'matched',match:7,slot:0});packet(socket,{op:'started'});
  const api=sandbox.window.__aoemLiveWitness;
  for(let i=0;i<501;i++)socket.send(JSON.stringify({op:'command',sequence:1,match:7,command:'move'}));
  const before=api.state.commandSerial;
  assert.equal(api.sendCommand('attack_move',{ids:[1],position:[0,1152]}),true);
  socket.send(JSON.stringify({op:'command',sequence:2,match:7,command:'attack_move',ids:[1],position:[0,1152]}));
  const after=api.state.sends.filter(e=>e.serial>before);
  assert.equal(after.length,2);assert.equal(after[0].source,'paid_policy');assert.equal(after[1].source,'game_ui_or_engine');
  assert.equal(after[1].packet.sequence,503);assert.equal(api.state.sends.length,500);
  assert.equal(api.sendCommand('grant',{food:1000}),false);assert.equal(api.sendCommand('surrender'),false);
});

test('browser guard rejects public sockets even if page wrapper is bypassed',async()=>{
  let socketHandler,httpHandler;const events=[];
  const context={routeWebSocket:async(_pattern,handler)=>{socketHandler=handler;},route:async(_pattern,handler)=>{httpHandler=handler;}};
  await configureLocalGuards(context,'ws://127.0.0.1:12345/match','http://127.0.0.1:54321/',e=>events.push(e));
  for(const [url,allowed] of [['ws://127.0.0.1:12345/match',true],['wss://game.4mn.org/match',false],['ws://127.0.0.1:1/match',false]]){
    let opened=false,closed=false;
    socketHandler({url:()=>url,connectToServer:()=>{opened=true;},close:()=>{closed=true;}});
    assert.equal(opened,allowed);assert.equal(closed,!allowed);
  }
  for(const [url,allowed] of [['http://127.0.0.1:54321/index.pck',true],['https://game.4mn.org/index.pck',false]]){
    let continued=false,aborted=false;httpHandler({request:()=>({url:()=>url}),continue:()=>{continued=true;},abort:()=>{aborted=true;}});
    assert.equal(continued,allowed);assert.equal(aborted,!allowed);
  }
  assert.equal(events.length,3);await assert.rejects(()=>configureLocalGuards({},'ws://127.0.0.1:1/match','http://127.0.0.1:2/',()=>{}),/requires Playwright/);
});

function write(root,name,bytes){const file=path.join(root,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);}
function seal(root){const entries=[];function visit(dir,relative=''){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){const name=relative?relative+'/'+entry.name:entry.name;if(entry.isDirectory())visit(path.join(dir,entry.name),name);else if(name!=='SHA256SUMS.txt')entries.push([name,digest(fs.readFileSync(path.join(root,name)))]);}}visit(root);write(root,'SHA256SUMS.txt',entries.sort((a,b)=>a[0].localeCompare(b[0])).map(([name,hash])=>hash+'  ./'+name).join('\n')+'\n');}
function fixture(){const root=fs.mkdtempSync(path.join(os.tmpdir(),'pocket-harness-unit-'));const web=path.join(root,'web'),server=path.join(root,'server');const source='extends Node\n',hash=digest(Buffer.from(source));write(web,'index.html','local export');write(web,'version.json',JSON.stringify({source_revision:'abcdef123456',source_dirty:false}));write(web,'SOURCE_SHA256SUMS.txt',hash+'  ./scripts/unit.gd\n');write(server,'runtime/scripts/unit.gd',source);write(server,'runtime/project.godot','[application]\n');write(server,'SERVER_SOURCE.json',JSON.stringify({source_revision:'abcdef1234560000000000000000000000000000',source_dirty:false,all_committed_runtime_sources_match:true,committed_source_sha256:{'runtime/scripts/unit.gd':hash}}));seal(web);seal(server);return {root,web,server};}
function dispose(root){const resolved=path.resolve(root),prefix=path.resolve(os.tmpdir())+path.sep+'pocket-harness-unit-';assert(resolved.startsWith(prefix));fs.rmSync(resolved,{recursive:true});}

test('source binding accepts identical committed inputs and rejects extra, changed or mismatched files',()=>{
  const f=fixture();try{
    const before=fs.readFileSync(path.join(f.web,'index.html'));assert.equal(verifyPair(f.web,f.server).shared_runtime_files,1);assert.deepEqual(fs.readFileSync(path.join(f.web,'index.html')),before);
    write(f.web,'extra.js','extra');assert.throws(()=>verifyTree(f.web),/file set/);fs.unlinkSync(path.join(f.web,'extra.js'));
    write(f.web,'index.html','changed');assert.throws(()=>verifyTree(f.web),/hash mismatch/);write(f.web,'index.html',before);
    const version=JSON.parse(fs.readFileSync(path.join(f.web,'version.json')));version.source_revision='fedcba654321';write(f.web,'version.json',JSON.stringify(version));seal(f.web);assert.throws(()=>verifyPair(f.web,f.server),/matching clean/);
  }finally{dispose(f.root);}
});

test('manifest paths cannot escape the sealed root or alias another file',()=>{
  const hash='0'.repeat(64);
  for(const rows of [hash+'  ../outside',hash+'  ./C:/outside',hash+'  ./a\\b',hash+'  ./a\n'+hash+'  ./A'])assert.throws(()=>manifestEntries(rows),/Unsafe/);
});

test('source binding rejects absent, ambiguous or malformed clean provenance',()=>{
  const f=fixture();
  try {
    const originalWeb=JSON.parse(fs.readFileSync(path.join(f.web,'version.json')));
    const originalServer=JSON.parse(fs.readFileSync(path.join(f.server,'SERVER_SOURCE.json')));
    const cases=[
      ['web','source_dirty',undefined],['web','source_dirty','false'],
      ['server','source_dirty',undefined],['server','source_dirty',0],
      ['server','all_committed_runtime_sources_match','true'],
      ['web','source_revision',''],['web','source_revision','abc'],
      ['web','source_revision',null],['server','source_revision','abcdef123456'],
    ];
    for(const [side,key,value] of cases){
      const web={...originalWeb},server={...originalServer};
      const target=side==='web'?web:server;
      if(value===undefined)delete target[key];else target[key]=value;
      write(f.web,'version.json',JSON.stringify(web));
      write(f.server,'SERVER_SOURCE.json',JSON.stringify(server));
      seal(f.web);seal(f.server);
      assert.throws(()=>verifyPair(f.web,f.server),/matching clean/,`${side}.${key}=${value}`);
    }
  }finally{dispose(f.root);}
});

test('paid policy never emits grant, speed, result or raw object mutations',()=>{
  const client={role:'host',policy:true,ended:null,matched:{slot:0},lastBuild:-10,lastArmy:-60,demolished:false,rejectedPlacements:new Set(),pendingPlace:null,last:{time:120,actors:[{id:1,kind:'building',type:0,owner:0,state:2,x:0,y:0,queue:{items:[]}},{id:2,kind:'unit',type:0,owner:0,work:'food'}],bank:{food:600,wood:600,gold:600},player:{age:1,population:4,population_reserved:0,population_cap:10},research:[],resources:[]}};
  const commands=planPolicy(client);assert(commands.length>0);assert(commands.every(c=>['allocate','train','place','age','research','attack_move','move','delete'].includes(c.command)));
});

test('real Chromium transport uses loopback and blocks a bypassed public socket', {skip:process.env.POCKET_BROWSER_SMOKE!=='1',timeout:20000}, async()=>{
  // A tiny loopback handshake fixture, not Godot or a played match.
  const http=require('node:http'),crypto=require('node:crypto');
  const modulePath=process.env.PLAYWRIGHT_MODULE||path.join(os.homedir(),'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
  const {chromium}=require(modulePath),connections=[],sockets=new Set(),guard=[],sentFrames=[],receivedFrames=[],serverCommands=[];
  const server=http.createServer((_req,res)=>res.writeHead(200,{'Content-Type':'text/html'}).end('<title>Local socket guard fixture</title>'));
  server.on('upgrade',(req,socket)=>{
    connections.push(req.url);sockets.add(socket);socket.on('close',()=>sockets.delete(socket));
    const accept=crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n');
    const greeting=Buffer.from(JSON.stringify({op:'snapshot',match:7,tick:1,actors:[]}));
    socket.write(Buffer.concat([Buffer.from([0x81,greeting.length]),greeting]));
    let pending=Buffer.alloc(0);
    socket.on('data',chunk=>{
      pending=Buffer.concat([pending,chunk]);
      while(pending.length>=6){
        const length=pending[1]&127;if(length>=126||pending.length<6+length)return;
        const opcode=pending[0]&15,mask=pending.subarray(2,6),body=Buffer.from(pending.subarray(6,6+length));
        for(let i=0;i<body.length;i++)body[i]^=mask[i%4];pending=pending.subarray(6+length);
        if(opcode===1||opcode===2)serverCommands.push(JSON.parse(body.toString()));
        if(opcode===8){socket.write(Buffer.from([0x88,0]));socket.end();}
      }
    });
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  let browser;
  try {
    const port=server.address().port,url=`http://127.0.0.1:${port}/`,matchUrl=`ws://127.0.0.1:${port}/match`;
    browser=await chromium.launch({channel:'chrome',headless:true});
    const context=await browser.newContext({serviceWorkers:'block'});
    await configureLocalGuards(context,matchUrl,url,event=>guard.push(event));
    await context.addInitScript(({configuration,source})=>{window.__rawSocket=window.WebSocket;new Function('configuration','('+source+')(configuration)')(configuration);},{configuration:{local:true,matchUrl},source:installWitness.toString()});
    const page=await context.newPage();
    page.on('websocket',socket=>{socket.on('framesent',event=>sentFrames.push(String(event.payload)));socket.on('framereceived',event=>receivedFrames.push(String(event.payload)));});
    await page.goto(url);
    const actual=await page.evaluate(()=>new Promise((resolve,reject)=>{const socket=new WebSocket('wss://game.4mn.org/match');socket.onopen=()=>socket.send(JSON.stringify({op:'command',match:7,sequence:1,command:'train',type:1}));socket.onmessage=event=>{socket.close();resolve({url:socket.url,packet:JSON.parse(event.data)});};socket.onerror=()=>reject(Error('Local socket failed'));}));
    assert.equal(actual.url,matchUrl);assert.equal(actual.packet.op,'snapshot');assert.deepEqual(connections,['/match']);
    assert(sentFrames.some(frame=>JSON.parse(frame).command==='train'));
    assert(receivedFrames.some(frame=>JSON.parse(frame).op==='snapshot'));
    assert.equal(serverCommands[0].command,'train');
    const blocked=await page.evaluate(()=>new Promise(resolve=>{const socket=new window.__rawSocket('wss://game.4mn.org/match');socket.onclose=event=>resolve(event.code);setTimeout(()=>resolve('timeout'),3000);}));
    assert.equal(blocked,1008);assert.deepEqual(connections,['/match']);
    assert.equal(guard.length,2);assert.equal(guard[0].allowed,true);assert.equal(guard[1].allowed,false);
  } finally {
    if(browser)await browser.close();for(const socket of sockets)socket.destroy();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
  }
});
