'use strict';
// Real Web Crypto/Blob/Response bytes; no browser or device claim.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {webcrypto, createHash} = require('node:crypto');
const vm = require('node:vm');
const html = readFileSync(require('node:path').join(__dirname, '../web/pocket_shell.html'), 'utf8');
const script = html.match(/<script id="pocket-audio-modules-script">([\s\S]*?)<\/script>/)[1];
const names = ['index.audio.worklet.js', 'index.audio.position.worklet.js'];
function fixture(options = {}) {
    const base = 'https://game.example/sub/';
    const source = new Map(names.map(name => [name, '/* ' + name + ' */ registerProcessor("fixture", class {});']));
    const blobs = new Map(), imports = [], fetches = [], events = [], handlers = new Map(), revoked = [];
    class TestURL extends URL {
        static createObjectURL(blob) { const id = 'blob:https://game.example/' + blobs.size; blobs.set(id, blob); return id; }
        static revokeObjectURL(id) { revoked.push(id); }
    }
    class AudioWorklet {
        addModule(url, opts) {
            imports.push({receiver:this,url,opts});
            // Model the reported Safari failure of URL imports; blob imports work.
            return options.importFailure || !String(url).startsWith('blob:')
                ? Promise.reject(new Error('Importing a module script failed.')) : Promise.resolve();
        }
    }
    const original = AudioWorklet.prototype.addModule;
    const w = {AudioWorklet, URL:TestURL, Blob, AbortController, setTimeout, clearTimeout, crypto:webcrypto, document:{baseURI:base},
        POCKET_RELEASE:{audio_worklets:Object.fromEntries([...source].map(([name,bytes])=>[name,createHash('sha256').update(bytes).digest('hex')]))},
        fetch:async (url,opts)=>{
            fetches.push({url,opts});
            if(options.stall) return new Promise((_,reject)=>opts.signal.addEventListener('abort',()=>reject(new Error('aborted'))));
            const name = new URL(url).pathname.split('/').pop();
            return new Response(options.corrupt ? 'wrong release' : source.get(name), {status:options.httpFailure ? 503 : 200});
        },
        CustomEvent:class {constructor(type,data) {this.type=type;Object.assign(this,data);}},
        dispatchEvent:event=>events.push(event), addEventListener:(type,fn)=>handlers.set(type,fn)};
    const context = vm.createContext({window:w,Uint8Array,Map,Error,Object,Array});
    vm.runInContext(script,context);
    if(options.stall) w.PocketAudioModules=context.createPocketAudioModules(w,20);
    return {w,api:w.PocketAudioModules,source,blobs,imports,fetches,events,handlers,revoked,original};
}
test('page-bound, exact-hash worklets import as blobs with native receiver/options',async()=>{
    const f=fixture();
    const worklet=new f.w.AudioWorklet();
    await assert.rejects(worklet.addModule('index.audio.worklet.js'),/Importing/);
    f.imports.length=0;
    await Promise.all([f.api.prepare(),f.api.prepare()]);
    assert.equal(f.fetches.length,2);
    for(const name of names) {
        await worklet.addModule(name,{credentials:'same-origin'});
        const call=f.imports.at(-1);
        assert.equal(call.receiver,worklet);
        assert.equal(call.opts.credentials,'same-origin');
        assert.equal(await f.blobs.get(call.url).text(),f.source.get(name));
    }
    assert.equal(f.events.filter(e=>e.detail.kind==='audio_module_ready').length,2);
    assert(f.fetches.every(r=>r.url.startsWith('https://game.example/sub/') && r.opts.redirect==='error'));
});
test('HTTP failure or different release bytes stop preparation before modifying import behavior',async()=>{
    for(const options of [{httpFailure:true},{corrupt:true}]) {
        const f=fixture(options);
        await assert.rejects(f.api.prepare(),/Sound files/);
        assert.equal(f.w.AudioWorklet.prototype.addModule,f.original);
        assert.equal(f.imports.length,0);
    }
});
test('native module errors remain rejected and other modules retain original handling',async()=>{
    const f=fixture({importFailure:true}); await f.api.prepare();
    await assert.rejects(new f.w.AudioWorklet().addModule(names[0]),/Importing/);
    assert.equal(f.events.at(-1).detail.kind,'audio_module_failed');
    await assert.rejects(new f.w.AudioWorklet().addModule('unrelated.js'),/Importing/);
    assert.equal(f.imports.at(-1).url,'unrelated.js');
    await assert.rejects(new f.w.AudioWorklet().addModule('https://['),/Importing/);
    assert.equal(f.imports.at(-1).url,'https://[');
});
test('blob lifetime supports multiple audio contexts and back-forward restoration',async()=>{
    const f=fixture(); await f.api.prepare();
    for(let i=0;i<2;i++) await new f.w.AudioWorklet().addModule(names[0]);
    f.handlers.get('pagehide')({persisted:true}); assert.equal(f.revoked.length,0);
    f.handlers.get('pagehide')({persisted:false}); assert.equal(f.revoked.length,2);
});
test('engines without AudioWorklet keep the native unsupported/fallback behavior',async()=>{
    const f=fixture(); delete f.w.AudioWorklet; await f.api.prepare(); assert.equal(f.fetches.length,0);
});
test('stalled module download has a bounded, recoverable startup failure',async()=>{
    const f=fixture({stall:true}); await assert.rejects(f.api.prepare(),/took too long/);
    assert.equal(f.w.AudioWorklet.prototype.addModule,f.original);
});
