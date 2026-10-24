'use strict';
// Bounded HTTP infrastructure checks; no browser, Godot, or game runtime.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {sealedHost}=require('./test_match_background_export.cjs');
const {digest}=require('./local_browser_runtime.cjs');

(async()=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'pocket-export-host-test-'));
  const output=path.join(root,'evidence');fs.mkdirSync(output);
  const content=Buffer.from('sealed fixture bytes');fs.writeFileSync(path.join(root,'index.html'),content);
  const receipt={};let host;
  try {
    host=await sealedHost({root,files:{'index.html':digest(content)}},output,receipt);
    let response=await fetch(host.url);
    assert.equal(response.status,200);assert.equal(response.headers.get('x-pocket-artifact-sha256'),digest(content));assert.equal(response.headers.get('content-length'),String(content.length));assert.equal(await response.text(),content.toString());
    response=await fetch(host.url+'not-in-manifest');assert.equal(response.status,404);
    response=await fetch(host.url,{method:'PUT'});assert.equal(response.status,405);
    const body=JSON.stringify({session_id:'private-fixture',report_id:'local-only',events:[]});
    response=await fetch(host.url+'api/playtest-diagnostics',{method:'POST',body});assert.deepEqual(await response.json(),{stored:true,report_id:'local-only'});
    assert.equal(receipt.collector.length,1);assert.equal(fs.readFileSync(path.join(output,receipt.collector[0].file),'utf8'),body);
    response=await fetch(host.url+'api/playtest-diagnostics',{method:'POST',body:'broken'});assert.equal(response.status,400);
    response=await fetch(host.url+'api/playtest-diagnostics',{method:'POST',body:'[]'});assert.equal(response.status,400);
    response=await fetch(host.url+'api/playtest-diagnostics',{method:'POST',body:' '.repeat(256*1024+1)});assert.equal(response.status,413);
    assert.equal(receipt.collector.length,1);
    fs.writeFileSync(path.join(root,'index.html'),'changed');
    response=await fetch(host.url);assert.equal(response.status,409);assert.equal(receipt.served.length,1);
    console.log(JSON.stringify({passed:true,scope:'Infrastructure only: exact served bytes/headers, unknown files/methods rejected, bounded local JSON receipt, mutated artifact fails closed'}));
  } finally {
    if(host)await host.stop();
    assert.equal(path.dirname(path.resolve(root)),path.resolve(os.tmpdir()));assert(path.basename(root).startsWith('pocket-export-host-test-'));
    fs.rmSync(root,{recursive:true,force:true});
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
