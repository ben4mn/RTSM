'use strict';
// Test infrastructure only. Serve verified bytes and run a private copy of the
// matching sealed authority context; never rewrite the production artifact.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const net = require('node:net');
const crypto = require('node:crypto');
const {spawn, spawnSync} = require('node:child_process');
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

function manifestEntries(text) {
  const entries = {}, seen = new Set();
  for (const line of text.trim().split(/\r?\n/)) {
    const match = /^([a-f0-9]{64})  (?:\.\/)?(.+)$/.exec(line);
    if (!match) throw new Error('Invalid SHA-256 manifest row');
    const name = match[2];
    if (name.includes('\\') || name.includes(':') || name.startsWith('/') || name.split('/').some(p => !p || p === '.' || p === '..') || seen.has(name.toLowerCase())) throw new Error('Unsafe or duplicate manifest path: ' + name);
    entries[name] = match[1]; seen.add(name.toLowerCase());
  }
  return entries;
}

function treeFiles(root, relative = '') {
  const files = [];
  for (const entry of fs.readdirSync(path.join(root, relative), {withFileTypes: true})) {
    const name = relative ? relative + '/' + entry.name : entry.name;
    if (entry.isSymbolicLink()) throw new Error('Linked artifact entry: ' + name);
    if (entry.isDirectory()) files.push(...treeFiles(root, name));
    else if (entry.isFile()) files.push(name);
    else throw new Error('Special artifact entry: ' + name);
  }
  return files.sort();
}

function verifyTree(directory) {
  const root = path.resolve(directory);
  if (fs.lstatSync(root).isSymbolicLink()) throw new Error('Artifact root must not be a link');
  const manifest = fs.readFileSync(path.join(root, 'SHA256SUMS.txt'));
  const entries = manifestEntries(manifest.toString('utf8'));
  const actual = treeFiles(root).filter(name => name !== 'SHA256SUMS.txt');
  if (JSON.stringify(actual) !== JSON.stringify(Object.keys(entries).sort())) throw new Error('Artifact file set differs from sealed manifest');
  for (const [name, hash] of Object.entries(entries)) if (digest(fs.readFileSync(path.join(root, name))) !== hash) throw new Error('Artifact hash mismatch: ' + name);
  return {root, manifest_sha256: digest(manifest), files: entries};
}

function verifyPair(artifactDirectory, serverDirectory) {
  const artifact = verifyTree(artifactDirectory), server = verifyTree(serverDirectory);
  const version = JSON.parse(fs.readFileSync(path.join(artifact.root, 'version.json')));
  const authority = JSON.parse(fs.readFileSync(path.join(server.root, 'SERVER_SOURCE.json')));
  if (version.source_dirty !== false || authority.source_dirty !== false || authority.all_committed_runtime_sources_match !== true ||
      typeof version.source_revision !== 'string' || !/^[a-f0-9]{12,40}$/.test(version.source_revision) ||
      typeof authority.source_revision !== 'string' || !/^[a-f0-9]{40}$/.test(authority.source_revision) ||
      !authority.source_revision.startsWith(version.source_revision)) throw new Error('Local paired witness requires matching clean committed client/server sources');
  const sources = manifestEntries(fs.readFileSync(path.join(artifact.root, 'SOURCE_SHA256SUMS.txt'), 'utf8'));
  let compared = 0;
  for (const [name, hash] of Object.entries(sources)) if (/^(scripts|scenes|assets)\//.test(name)) {
    if (authority.committed_source_sha256['runtime/' + name] !== hash) throw new Error('Client/server runtime source mismatch: ' + name);
    compared++;
  }
  if (!compared) throw new Error('No shared runtime inputs in source manifest');
  return {artifact, server, version, authority, shared_runtime_files: compared};
}

async function freePort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}

function createArtifactServer(artifact, output) {
  const served=[],collector=[],failures=[];
  const mime={'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.ttf':'font/ttf','.pck':'application/octet-stream'};
  const server=http.createServer((req,res)=>{
    let relative;
    try {relative=decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname).slice(1)||'index.html';}
    catch {res.writeHead(400).end();return;}
    if(req.method==='POST'&&relative==='api/playtest-diagnostics') {
      let size=0;const chunks=[];
      req.on('data',chunk=>{size+=chunk.length;if(size<=256*1024)chunks.push(chunk);});
      req.on('end',()=>{
        if(size>256*1024){res.writeHead(413).end();return;}
        const bytes=Buffer.concat(chunks);let payload;
        try{payload=JSON.parse(bytes);}catch{res.writeHead(400).end();return;}
        if(!payload||typeof payload!=='object'||Array.isArray(payload)){res.writeHead(400).end();return;}
        const file='local-diagnostics-'+String(collector.length+1).padStart(4,'0')+'.json';
        fs.writeFileSync(path.join(output,file),bytes);
        collector.push({file,unix:Date.now(),bytes:bytes.length,sha256:digest(bytes),session_id:payload.session_id||null});
        res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'}).end(JSON.stringify({stored:true,report_id:payload.report_id||''}));
      });return;
    }
    if(!['GET','HEAD'].includes(req.method)){res.writeHead(405).end();return;}
    if(!Object.hasOwn(artifact.files,relative)){res.writeHead(404).end();return;}
    let bytes,actual;
    try {bytes=fs.readFileSync(path.join(artifact.root,relative));actual=digest(bytes);if(actual!==artifact.files[relative])throw Error('Artifact hash changed');}
    catch(error){failures.push({unix:Date.now(),file:relative,error:String(error)});res.writeHead(409).end('Artifact changed');return;}
    const request_id=String(served.length+1);
    served.push({request_id,method:req.method,unix:Date.now(),file:relative,sha256:actual,bytes:bytes.length});
    res.writeHead(200,{'Content-Type':mime[path.extname(relative)]||'application/octet-stream','Content-Length':bytes.length,'Cache-Control':'no-store','Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp','X-Pocket-Artifact-SHA256':actual,'X-Pocket-Request-ID':request_id});
    res.end(req.method==='HEAD'?undefined:bytes);
  });
  server.requestTimeout=15000;
  return {server,served,collector,failures};
}

async function startLocalRuntime({artifactDirectory, serverDirectory, godot, output}) {
  if (!artifactDirectory || !serverDirectory || !godot) throw new Error('--local requires --artifact-dir, --server-context and --godot');
  const pair = verifyPair(artifactDirectory, serverDirectory);
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'pocket-local-browser-'));
  const runtime = path.join(temp, 'runtime');
  fs.cpSync(path.join(pair.server.root, 'runtime'), runtime, {recursive: true});
  const project = path.join(runtime, 'project.godot');
  const userDir = 'pocket-local-browser/' + crypto.randomUUID();
  let config = fs.readFileSync(project, 'utf8').split(/\r?\n/).filter(line => !/^(config\/use_custom_user_dir|config\/custom_user_dir_name)=/.test(line)).join('\n');
  config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + userDir + '"');
  fs.writeFileSync(project, config);
  const projectHash = digest(Buffer.from(config));
  const port = await freePort(), matchUrl = `ws://127.0.0.1:${port}/match`;
  const authorityLog = path.join(output, 'local-authority.log');
  const log = fs.openSync(authorityLog, 'w');
  const command = ['--headless', '--path', runtime, 'res://scenes/network/server_lobby.tscn', '--', '--aoem-server'];
  const child = spawn(path.resolve(godot), command, {cwd: runtime, env: {...process.env, AOEM_MATCH_PORT: String(port), GODOT_AUDIO_DRIVER: 'Dummy'}, stdio: ['ignore', log, log], windowsHide: true, detached: process.platform !== 'win32'});
  let spawnError;
  child.once('error', error => { spawnError = error; });
  const {server:web,served,collector,failures:artifactFailures}=createArtifactServer(pair.artifact,output);
  let stopped = false;
  const initial = {scope:'Harness-owned local authority and byte-verified production export; private server copy/preferences; no production writes',match_url:matchUrl,server_pid:child.pid,server_command:[path.resolve(godot),...command],godot_sha256:digest(fs.readFileSync(path.resolve(godot))),private_runtime:runtime,private_user_dir:userDir,private_project_sha256:projectHash,...pair};
  fs.writeFileSync(path.join(output,'local-source-initial.json'),JSON.stringify(initial,null,2)+'\n');
  async function stop() {
    if (stopped) return; stopped = true;
    let cleanupError;
    try {
    if (child.exitCode === null && !spawnError) {
      if (process.platform === 'win32') {
        const killed=spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,timeout:15000});
        if(killed.status!==0&&child.exitCode===null)throw new Error('Cannot terminate owned local authority PID '+child.pid);
      }
      else { try { process.kill(-child.pid,'SIGKILL'); } catch (error) { if (error.code !== 'ESRCH') throw error; } }
      await Promise.race([new Promise(resolve => child.once('exit',resolve)),pause(5000)]);
    }
    } catch(error) {cleanupError=String(error);}
    if (web.listening) await new Promise(resolve => {web.close(resolve);web.closeAllConnections();});
    fs.closeSync(log);
    let final;
    try {
      const checked = verifyPair(pair.artifact.root,pair.server.root);
      let runtimeUnchanged = digest(fs.readFileSync(project)) === projectHash;
      for (const [name, hash] of Object.entries(pair.authority.committed_source_sha256)) if (name.startsWith('runtime/') && name !== 'runtime/project.godot') runtimeUnchanged &&= digest(fs.readFileSync(path.join(temp,name))) === hash;
      const terminated=!!spawnError||child.exitCode!==null||child.signalCode!==null;
      final={completed:!cleanupError&&terminated&&!artifactFailures.length,owned_server_terminated:terminated,cleanup_error:cleanupError||null,production_artifacts_unchanged:checked.artifact.manifest_sha256===pair.artifact.manifest_sha256&&checked.server.manifest_sha256===pair.server.manifest_sha256,private_runtime_unchanged:runtimeUnchanged,served,collector,artifact_failures:artifactFailures};
    } catch(error) { final={completed:false,error:String(error),served,collector,artifact_failures:artifactFailures}; }
    fs.writeFileSync(path.join(output,'local-source-final.json'),JSON.stringify(final,null,2)+'\n');
    // Keep the private source copy for a source-bound, independently inspectable receipt.
    if(cleanupError)throw new Error(cleanupError);
  }
  try {
    for(let attempt=0;attempt<150;attempt++) {
      if(spawnError)throw spawnError;
      if(child.exitCode!==null)throw new Error('Local authority exited before ready');
      if(fs.readFileSync(authorityLog,'utf8').includes('AOEM_MATCH_SERVER_READY'))break;
      if(attempt===149)throw new Error('Local authority did not become ready');
      await pause(100);
    }
    await new Promise((resolve,reject)=>{web.once('error',reject);web.listen(0,'127.0.0.1',resolve);});
    const ready=/AOEM_MATCH_SERVER_READY port=(\d+) protocol=(\d+)/.exec(fs.readFileSync(authorityLog,'utf8'));
    if(!ready||Number(ready[1])!==port||Number(ready[2])!==2)throw new Error('Authority ready endpoint/protocol does not match the protocol2 witness');
    fs.writeFileSync(path.join(output,'local-authority-ready.json'),JSON.stringify({unix:Date.now(),match_url:matchUrl,pid:child.pid,port:Number(ready[1]),protocol:Number(ready[2]),source_revision:pair.authority.source_revision,private_project_sha256:projectHash},null,2)+'\n');
    return {url:`http://127.0.0.1:${web.address().port}/`,matchUrl,source:initial,stop};
  } catch(error) {await stop();throw error;}
}

module.exports={digest,manifestEntries,verifyTree,verifyPair,createArtifactServer,startLocalRuntime};
